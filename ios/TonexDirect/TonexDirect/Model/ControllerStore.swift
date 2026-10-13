import Foundation
import Observation
import UIKit

enum ConnectionState: Equatable {
    case idle
    case waitingForPedal
    case connecting
    case syncing(done: Int, total: Int)
    case ready
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Desconectado"
        case .waitingForPedal: return "Conecta el Tonex Pedal por USB-C"
        case .connecting: return "Conectando con el pedal…"
        case let .syncing(done, total): return "Leyendo presets \(done)/\(total)…"
        case .ready: return "Conectado por USB"
        case .failed(let m): return m
        }
    }

    var isBusy: Bool {
        switch self {
        case .connecting, .syncing: return true
        default: return false
        }
    }
}

struct Preset: Identifiable, Equatable {
    let id: Int          // índice 0-based del pedal
    let number: Int      // número visible (índice + 1)
    var name: String
}

/// Fuente única de verdad. Habla directamente con el Tonex Pedal por USB a través del
/// driver embebido (sin ESP32), repitiendo la secuencia de `usb_tonex.c`.
@MainActor
@Observable
final class ControllerStore {

    // MARK: Estado público (misma API que la versión con ESP32)

    private(set) var state: ConnectionState = .idle
    private(set) var modeller: ModellerType?
    private(set) var maxPresets = 0
    private(set) var startPreset = 1
    private(set) var presets: [Preset] = []
    private(set) var currentPreset: Int?
    private(set) var params: [Int: ParamValue] = [:]

    /// Registro de diagnóstico visible en Ajustes (últimas 300 líneas).
    private(set) var diagnostics: [String] = []
    /// Bytes y tramas recibidas en la conexión actual.
    private(set) var rxBytes = 0
    private(set) var rxFrames = 0
    private(set) var rxBadFrames = 0

    var currentPresetInfo: Preset? {
        guard let c = currentPreset, presets.indices.contains(c) else { return nil }
        return presets[c]
    }

    // MARK: Internos

    private enum Phase: Equatable {
        case idle, hello, state, names(Int), currentDetails, globals, ready
    }

    @ObservationIgnored private var link: TonexUSBLink?
    @ObservationIgnored private var deframer = TonexDeframer()
    @ObservationIgnored private var phase: Phase = .idle
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?
    @ObservationIgnored private var lastProgress = Date()
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var globalConfig: TonexPedal.GlobalConfig?
    @ObservationIgnored private var lastDetailsAt = Date.distantPast
    @ObservationIgnored private var detailsCheckTask: Task<Void, Never>?

    /// Parámetros que el usuario está moviendo: no se sobrescriben con lo que llegue del pedal.
    @ObservationIgnored private var editingUntil: [Int: Date] = [:]
    @ObservationIgnored private var pendingSends: [Int: Double] = [:]
    @ObservationIgnored private var lastSendTime: [Int: Date] = [:]
    @ObservationIgnored private var flushTasks: [Int: Task<Void, Never>] = [:]

    @ObservationIgnored private var lastServiceSeen: Bool?
    @ObservationIgnored private var retryNotBefore = Date.distantPast
    @ObservationIgnored private var lostCount = 0

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func note(_ message: String) {
        let line = "\(Self.timeFormat.string(from: Date()))  \(message)"
        diagnostics.append(line)
        if diagnostics.count > 300 { diagnostics.removeFirst(diagnostics.count - 300) }
        #if DEBUG
        print("Tonex:", line)
        #endif
    }

    func clearDiagnostics() { diagnostics.removeAll() }

    // MARK: Imagen de amp por preset (se guarda en el iPad, como SkinConfig en el ESP32)

    private static let skinsKey = "presetSkins"

    /// índice de preset → índice de `AmpSkins.all`
    private(set) var skinIndexes: [Int: Int] = ControllerStore.loadSkins()

    func skinIndex(for preset: Int) -> Int { skinIndexes[preset] ?? 0 }

    func setSkin(_ skin: Int, for preset: Int) {
        guard AmpSkins.all.indices.contains(skin) else { return }
        skinIndexes[preset] = skin
        let stored = Dictionary(uniqueKeysWithValues: skinIndexes.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(stored, forKey: Self.skinsKey)
    }

    /// Flechas de la tarjeta: sin dar la vuelta, igual que control_set_skin_next/previous.
    func stepSkin(_ delta: Int) {
        guard let c = currentPreset else { return }
        let next = skinIndex(for: c) + delta
        if AmpSkins.all.indices.contains(next) { setSkin(next, for: c) }
    }

    private static func loadSkins() -> [Int: Int] {
        guard let stored = UserDefaults.standard.dictionary(forKey: skinsKey) as? [String: Int] else { return [:] }
        var out: [Int: Int] = [:]
        for (k, v) in stored { if let i = Int(k) { out[i] = v } }
        return out
    }

    private let stepTimeout: TimeInterval = 1.5
    private let maxRetries = 3

    // MARK: Conexión

    func connect() {
        wantsConnection = true
        attemptOpen()
        startPolling()
    }

    func disconnect() {
        wantsConnection = false
        pollTask?.cancel(); pollTask = nil
        teardown()
        state = .idle
    }

    /// Al volver a primer plano.
    func resume() {
        guard wantsConnection else { return }
        if link == nil {
            attemptOpen()
        } else if phase == .ready {
            refresh()   // por si el pedal cambió mientras la app estaba suspendida
        }
        startPolling()
    }

    /// Busca el driver cada segundo mientras no haya enlace (pedal desconectado o driver apagado).
    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if self.wantsConnection, self.link == nil { self.attemptOpen() }
            }
        }
    }

    private func attemptOpen() {
        guard wantsConnection, link == nil, Date() >= retryNotBefore else { return }
        let available = TonexDriverConnection.serviceAvailable()
        if available != lastServiceSeen {
            note(available ? "Driver encontrado (TonexDataInterface)" : "Driver no encontrado")
            lastServiceSeen = available
        }
        guard available else {
            if case .failed = state { return }   // deja visible el último error
            state = .waitingForPedal
            return
        }

        let newLink = TonexUSBLink()
        let status: TonexDriverConnection.Status
        do {
            status = try newLink.start()
        } catch {
            note("No pude abrir el driver: \(error)")
            state = .failed("\(error)")
            retryNotBefore = Date().addingTimeInterval(2)
            return
        }
        note("Driver abierto: listo=\(status.ready) VID=0x\(String(status.vendorID, radix: 16)) PID=0x\(String(status.productID, radix: 16)) perdidos=\(status.droppedBytes) · \(status.driverReport)")
        guard status.ready else {
            newLink.stop()
            state = .connecting   // el driver aún no abrió los endpoints; reintenta en 1 s
            return
        }
        guard status.productID == TonexPedal.productID || status.productID == 0 else {
            newLink.stop()
            state = .failed("Modelo USB 0x\(String(status.productID, radix: 16)) aún no soportado (solo Tonex Pedal)")
            return
        }

        newLink.onBytes = { [weak self] bytes in
            MainActor.assumeIsolated { self?.receive(bytes) }
        }
        newLink.onLost = { [weak self] reason in
            MainActor.assumeIsolated { self?.connectionLost(reason) }
        }
        link = newLink
        rxBytes = 0; rxFrames = 0; rxBadFrames = 0
        beginSync()
    }

    private func teardown() {
        watchdogTask?.cancel(); watchdogTask = nil
        detailsCheckTask?.cancel(); detailsCheckTask = nil
        flushTasks.values.forEach { $0.cancel() }
        flushTasks.removeAll()
        pendingSends.removeAll()
        link?.onBytes = nil
        link?.onLost = nil
        link?.stop()
        link = nil
        phase = .idle
        deframer.reset()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func connectionLost(_ reason: String) {
        lostCount += 1
        note("Conexión perdida (#\(lostCount)) en fase \(phase): \(reason). Recibido: \(rxBytes) bytes, \(rxFrames) tramas, \(rxBadFrames) inválidas")
        teardown()
        guard wantsConnection else { state = .idle; return }
        state = .failed("Se cortó la conexión: \(reason)")
        retryNotBefore = Date().addingTimeInterval(3)
    }

    // MARK: Sincronización inicial (como usb_tonex_process_single_message)

    private func beginSync() {
        modeller = .tonexPedal
        maxPresets = TonexPedal.maxPresets
        startPreset = 1
        if presets.count != maxPresets {
            presets = (0..<maxPresets).map { Preset(id: $0, number: $0 + startPreset, name: "Preset \($0 + startPreset)") }
        }
        params = TonexParamTable.defaults()
        globalConfig = nil
        deframer.reset()

        state = .connecting
        go(.hello)
        startWatchdog()
    }

    private func go(_ next: Phase) {
        if next != phase {
            retries = 0
            if case .names(let i) = next, i > 0 { } else { note("Fase → \(next)") }
        }
        phase = next
        sendCurrentStep()
    }

    private func sendCurrentStep() {
        lastProgress = Date()
        switch phase {
        case .hello: send(TonexPedal.hello)
        case .state: send(TonexPedal.requestState)
        case .names(let i): send(TonexPedal.requestPresetDetails(i))
        case .currentDetails: send(TonexPedal.requestPresetDetails(currentPreset ?? 0))
        case .globals: send(TonexPedal.requestGlobalConfig)
        case .idle, .ready: break
        }
    }

    /// Si un paso no responde: reintenta; al agotar reintentos, salta (nombres) o sigue adelante.
    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                self.checkTimeout()
            }
        }
    }

    private func checkTimeout() {
        guard link != nil, phase != .ready, phase != .idle,
              Date().timeIntervalSince(lastProgress) > stepTimeout else { return }

        retries += 1
        note("Sin respuesta en fase \(phase), reintento \(retries)")
        if retries <= maxRetries || phase == .hello || phase == .state {
            sendCurrentStep()
            return
        }
        switch phase {
        case .names(let i): advanceNames(after: i)
        case .currentDetails: go(.globals)
        case .globals: finishSync()
        default: sendCurrentStep()
        }
    }

    private func advanceNames(after i: Int) {
        let next = i + 1
        if next < maxPresets {
            state = .syncing(done: next, total: maxPresets)
            go(.names(next))
        } else {
            go(.currentDetails)
        }
    }

    private func finishSync() {
        note("Sincronización completa")
        phase = .ready
        state = .ready
        UIApplication.shared.isIdleTimerDisabled = true   // pantalla encendida en escenario
    }

    // MARK: Recepción

    private func receive(_ bytes: [UInt8]) {
        if rxBytes == 0 {
            note("Primeros bytes del pedal: \(bytes.prefix(24).map { String(format: "%02X", $0) }.joined(separator: " "))")
        }
        rxBytes += bytes.count
        for payload in deframer.feed(bytes) {
            rxFrames += 1
            do {
                handle(try TonexPedal.parse(payload))
            } catch {
                rxBadFrames += 1
                if rxBadFrames <= 10 {
                    note("Trama ignorada (\(error)): \(payload.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "))")
                }
            }
        }
    }

    private func handle(_ event: TonexPedal.Event) {
        switch event {
        case .hello:
            if phase == .hello { go(.state) }

        case .state(let p):
            if p < maxPresets { currentPreset = p }
            switch phase {
            case .state:
                state = .syncing(done: 0, total: maxPresets)
                go(.names(0))
            case .ready:
                scheduleDetailsCheck()
            default:
                break
            }

        case .presetDetails(let details):
            switch phase {
            case .names(let i):
                if let name = details.name, !name.isEmpty, presets.indices.contains(i) {
                    presets[i].name = name
                }
                advanceNames(after: i)
            case .currentDetails:
                apply(details)
                go(.globals)
            case .ready:
                apply(details)
            default:
                break
            }

        case .paramChanged(let index, let value):
            setFromPedal(index, Double(value))

        case .globalConfig(let config):
            globalConfig = config
            for (i, v) in config.paramValues { setFromPedal(i, Double(v)) }
            if phase == .globals { finishSync() }

        case .presetDetailsFull, .unknown:
            break
        }
    }

    private func apply(_ details: TonexPedal.PresetDetails) {
        lastDetailsAt = Date()
        if let i = details.presetIndex, i < maxPresets { currentPreset = i }
        if let name = details.name, !name.isEmpty, let c = currentPreset, presets.indices.contains(c) {
            presets[c].name = name
        }
        for (i, v) in details.params.enumerated() { setFromPedal(i, Double(v)) }
    }

    private func setFromPedal(_ index: Int, _ value: Double) {
        if let until = editingUntil[index], until > Date() { return }
        params[index]?.value = value
    }

    /// Tras un cambio de preset, el pedal suele mandar los detalles solo; si no llegan en
    /// 400 ms, se piden.
    private func scheduleDetailsCheck() {
        let asked = Date()
        detailsCheckTask?.cancel()
        detailsCheckTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled, self.phase == .ready else { return }
            if self.lastDetailsAt < asked, let c = self.currentPreset {
                self.send(TonexPedal.requestPresetDetails(c))
            }
        }
    }

    // MARK: Envío

    private func send(_ payload: [UInt8]) {
        link?.send(payload)
    }

    func refresh() {
        guard phase == .ready, let c = currentPreset else { return }
        send(TonexPedal.requestPresetDetails(c))
        send(TonexPedal.requestGlobalConfig)
    }

    // MARK: Presets

    func selectPreset(_ id: Int) {
        guard state == .ready, id >= 0, id < maxPresets else { return }
        currentPreset = id      // optimista
        send(TonexPedal.setPreset(id))
        scheduleDetailsCheck()
    }

    func nextPreset() { step(+1) }
    func previousPreset() { step(-1) }

    private func step(_ delta: Int) {
        guard maxPresets > 0 else { return }
        let current = currentPreset ?? 0
        selectPreset((current + delta + maxPresets) % maxPresets)
    }

    // MARK: Parámetros

    /// En el Tonex Pedal el firmware no soporta bypass, direct monitor ni tempo source
    /// (ver `usb_tonex_modify_global`). Los globales necesitan haber leído la config.
    func supports(_ index: Int) -> Bool {
        if [TonexParam.bypass, TonexParam.directMonitor, TonexParam.tempoSource].contains(index) {
            return false
        }
        if index > TonexParam.paramLast {
            return globalConfig != nil && TonexPedal.GlobalConfig.slot(forParam: index) != nil
        }
        return true
    }

    func value(_ index: Int) -> Double { params[index]?.value ?? 0 }
    func isOn(_ index: Int) -> Bool { value(index) >= 0.5 }
    func range(_ index: Int) -> ClosedRange<Double> {
        guard let p = params[index], p.max > p.min else { return 0...1 }
        return p.min...p.max
    }

    func setToggle(_ index: Int, _ on: Bool) { setValue(index, on ? 1 : 0, immediate: true) }

    /// `immediate: false` para sliders: limita la tasa de envío y siempre manda el último valor.
    func setValue(_ index: Int, _ value: Double, immediate: Bool = false) {
        guard state == .ready, supports(index) else { return }
        params[index]?.value = value
        editingUntil[index] = Date().addingTimeInterval(0.8)

        if immediate {
            flushTasks[index]?.cancel()
            flushTasks[index] = nil
            pendingSends[index] = nil
            transmit(index, value)
            return
        }

        // Los globales reenvían ~3.5 KB cada vez: más espaciados.
        let interval: TimeInterval = index > TonexParam.paramLast ? 0.15 : 0.06
        let now = Date()
        if let last = lastSendTime[index], now.timeIntervalSince(last) < interval {
            pendingSends[index] = value
            if flushTasks[index] == nil {
                let wait = interval - now.timeIntervalSince(last)
                flushTasks[index] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(wait))
                    guard let self, !Task.isCancelled else { return }
                    self.flushTasks[index] = nil
                    if let v = self.pendingSends.removeValue(forKey: index) { self.transmit(index, v) }
                }
            }
        } else {
            transmit(index, value)
        }
    }

    /// Al soltar el slider: envía el valor final pase lo que pase.
    func commitValue(_ index: Int, _ value: Double) {
        setValue(index, value, immediate: true)
    }

    private func transmit(_ index: Int, _ value: Double) {
        lastSendTime[index] = Date()
        if index < TonexParam.paramLast {
            send(TonexPedal.setParameter(index, value: Float(value)))
        } else if let slot = TonexPedal.GlobalConfig.slot(forParam: index), var config = globalConfig {
            guard config.set(slot, Float(value)) else { return }
            globalConfig = config
            send(TonexPedal.sendGlobalConfig(config))
        }
    }
}
