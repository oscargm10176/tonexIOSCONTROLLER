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

    /// El pedal agrupa los presets en bancos de 3 (A, B, C), como el editor de IK.
    static let perBank = 3
    var bank: Int { id / Preset.perBank }
    var slot: String { ["A", "B", "C"][id % Preset.perBank] }
    /// "00", "01"…
    var bankText: String { String(format: "%02d", bank) }
    /// "01 B": como lo muestra el pedal.
    var label: String { "\(bankText) \(slot)" }
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
    /// Ya terminó al menos una sincronización completa en esta sesión (oculta la pantalla de carga).
    private(set) var hasBeenReady = false

    /// Sección visible en la columna derecha y bloque al que saltar desde la cadena de efectos.
    var section: AppSection = .edit
    /// Hoja con la edición completa (todos los parámetros).
    var showAdvanced = false
    var focusedBlock: EffectBlock?
    /// Bloque cuyo panel se ve en Escenario (se elige tocando la cadena).
    var stageBlock: EffectBlock = .amp

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

    // MARK: Descarga del preset completo (diagnóstico, solo lectura)

    /// Archivos .bin descargados (Documents/PresetDumps), más reciente primero.
    private(set) var presetDumps: [URL] = ControllerStore.listDumps()
    private(set) var dumpInProgress: Int?

    @ObservationIgnored private var dumpBuffer: [UInt8] = []
    @ObservationIgnored private var dumpFrames = 0
    @ObservationIgnored private var dumpFinishTask: Task<Void, Never>?
    @ObservationIgnored private var dumpTimeoutTask: Task<Void, Never>?
    /// Si alguien espera el preset completo (respaldo), se le entrega en vez de guardarlo aquí.
    @ObservationIgnored private var dumpWaiter: CheckedContinuation<[UInt8]?, Never>?

    private static var dumpsFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("PresetDumps", isDirectory: true)
    }

    private static func listDumps() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dumpsFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "bin" }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
    }

    /// Pide al pedal el preset completo (~30 KB) del preset activo y lo guarda como archivo.
    func downloadFullPreset() {
        guard phase == .ready, dumpInProgress == nil, let c = currentPreset else { return }
        startDump(c)
    }

    /// Lee del pedal el preset completo de cualquier posición (solo lectura, no lo cambia).
    /// Devuelve nil si el pedal no responde o ya hay otra lectura en curso.
    func readFullPreset(_ id: Int, editBuffer: Bool = false) async -> [UInt8]? {
        // Una lectura a la vez: si hay otra en curso (p. ej. la búsqueda de Tone Models), espera.
        var waited = 0
        while dumpInProgress != nil, waited < 300 {
            try? await Task.sleep(for: .milliseconds(50)); waited += 1
        }
        guard phase == .ready, dumpInProgress == nil, presets.indices.contains(id) else { return nil }
        return await withCheckedContinuation { cont in
            dumpWaiter = cont
            startDump(id, editBuffer: editBuffer)
        }
    }

    private func startDump(_ c: Int, editBuffer: Bool = false) {
        dumpBuffer.removeAll()
        dumpFrames = 0
        dumpInProgress = c
        note("Pidiendo preset completo \(c + startPreset)\(editBuffer ? " (búfer de edición)" : "")…")
        send(editBuffer ? TonexPedal.requestEditBufferFull : TonexPedal.requestPresetDetails(c, full: true))
        dumpTimeoutTask?.cancel()
        dumpTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled, self.dumpInProgress != nil, self.dumpFrames == 0 else { return }
            self.note("El pedal no respondió al pedido de preset completo")
            self.dumpInProgress = nil
            self.dumpWaiter?.resume(returning: nil)
            self.dumpWaiter = nil
        }
    }

    private func receiveFullPreset(_ payload: [UInt8]) {
        guard dumpInProgress != nil else {
            note("Llegó un preset completo sin pedirlo (\(payload.count) bytes); lo ignoro")
            return
        }
        dumpBuffer.append(contentsOf: payload)
        dumpFrames += 1
        // Normalmente llega completo en una sola trama: listo de inmediato.
        if TonexPedal.fullPresetBody(dumpBuffer) != nil {
            dumpFinishTask?.cancel()
            finishDump()
            return
        }
        note("Preset completo: trama \(dumpFrames), \(payload.count) bytes")
        // Por si llega en varias tramas: se guarda cuando pasan 800 ms sin más.
        dumpFinishTask?.cancel()
        dumpFinishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled else { return }
            self.finishDump()
        }
    }

    private func finishDump() {
        guard let c = dumpInProgress else { return }
        dumpInProgress = nil
        dumpTimeoutTask?.cancel()
        if let waiter = dumpWaiter {
            dumpWaiter = nil
            let data = dumpBuffer
            dumpBuffer.removeAll()
            waiter.resume(returning: data)
            return
        }
        let name = presets.indices.contains(c) ? presets[c].name : "preset"
        let safe = name.map { $0.isLetter || $0.isNumber ? $0 : "_" }.reduce(into: "") { $0.append($1) }
        let stamp = Self.fileStamp.string(from: Date())
        let url = Self.dumpsFolder.appendingPathComponent("preset_\(c + startPreset)_\(safe)_\(stamp).bin")
        do {
            try FileManager.default.createDirectory(at: Self.dumpsFolder, withIntermediateDirectories: true)
            try Data(dumpBuffer).write(to: url)
            presetDumps = Self.listDumps()
            let texts = TonexPedal.printableRuns(dumpBuffer, minLength: 5).prefix(25).joined(separator: " | ")
            note("Guardado \(url.lastPathComponent) (\(dumpBuffer.count) bytes, \(dumpFrames) tramas). Textos: \(texts)")
        } catch {
            note("No pude guardar el preset completo: \(error.localizedDescription)")
        }
        dumpBuffer.removeAll()
    }

    func deleteDump(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        presetDumps = Self.listDumps()
    }

    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    // MARK: Nombres guardados (la lista aparece al instante y se actualiza al sincronizar)

    private static let namesKey = "presetNames.tonexPedal"

    private func saveNameCache() {
        UserDefaults.standard.set(presets.map(\.name), forKey: Self.namesKey)
    }

    private static func loadNameCache() -> [String] {
        UserDefaults.standard.stringArray(forKey: namesKey) ?? []
    }

    /// Ir a un bloque de efectos (desde la cadena).
    func focus(_ block: EffectBlock) {
        focusedBlock = block
        showAdvanced = true
    }

    // MARK: Imagen de amp por preset (se guarda en el iPad, como SkinConfig en el ESP32)

    private static let skinsKey = "presetSkins"

    /// índice de preset → índice de `AmpSkins.all`
    private(set) var skinIndexes: [Int: Int] = ControllerStore.loadSkins()

    /// Imagen sugerida por palabras clave (nombre del preset / textos internos).
    private(set) var autoSkins: [Int: Int] = [:]

    /// Tone Model y amp real de cada preset (se leen del preset completo y se guardan).
    private(set) var toneModels: [Int: TonexPedal.ToneModelInfo] = ControllerStore.loadToneModels()
    @ObservationIgnored var toneModelNames: [Int: String] = ControllerStore.loadToneModelNames()
    @ObservationIgnored var toneScanTask: Task<Void, Never>?
    static let toneModelsKey = "toneModels.v1"

    /// Lo que se muestra: la elección del usuario o, si no hay, la sugerencia.
    func displaySkin(for preset: Int) -> (index: Int, isAuto: Bool)? {
        if let c = skinIndexes[preset] { return (c, false) }
        if let a = autoSkins[preset] { return (a, true) }
        return nil
    }

    private func updateGuess(for preset: Int, texts: [String] = []) {
        guard presets.indices.contains(preset) else { return }
        // Primero los textos internos (si traen el modelo), luego el nombre.
        // Lo más fiable: el amp real y el nombre del Tone Model que trae el preset.
        let info = toneModels[preset]
        let fromModel = info.flatMap { i in AmpSkins.guess([i.amp ?? ""]) ?? AmpSkins.guess([i.model]) }
        let guess = fromModel ?? (texts.isEmpty ? nil : AmpSkins.guess(texts)) ?? AmpSkins.guess([presets[preset].name])
        if autoSkins[preset] != guess { autoSkins[preset] = guess }
    }

    /// Imagen elegida para el preset, o nil si nunca se eligió una.
    func chosenSkin(for preset: Int) -> Int? { skinIndexes[preset] }
    func skinIndex(for preset: Int) -> Int { skinIndexes[preset] ?? 0 }

    func clearSkin(for preset: Int) {
        skinIndexes[preset] = nil
        let stored = Dictionary(uniqueKeysWithValues: skinIndexes.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(stored, forKey: Self.skinsKey)
    }

    func setSkin(_ skin: Int, for preset: Int) {
        guard AmpSkins.all.indices.contains(skin) else { return }
        skinIndexes[preset] = skin
        let stored = Dictionary(uniqueKeysWithValues: skinIndexes.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(stored, forKey: Self.skinsKey)
    }

    /// Flechas de la tarjeta: sin dar la vuelta, igual que control_set_skin_next/previous.
    func stepSkin(_ delta: Int) {
        guard let c = currentPreset else { return }
        // Sin imagen elegida, la primera flecha arranca en la primera imagen.
        guard let current = displaySkin(for: c)?.index else { setSkin(0, for: c); return }
        let next = current + delta
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
            let cached = Self.loadNameCache()
            presets = (0..<maxPresets).map { i in
                let name = cached.indices.contains(i) && !cached[i].isEmpty ? cached[i] : "Preset \(i + startPreset)"
                return Preset(id: i, number: i + startPreset, name: name)
            }
            for i in presets.indices { updateGuess(for: i) }
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
        saveNameCache()
        phase = .ready
        state = .ready
        hasBeenReady = true
        UIApplication.shared.isIdleTimerDisabled = true   // pantalla encendida en escenario
        for i in presets.indices { updateGuess(for: i) }
        scanToneModels()
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
                    updateGuess(for: i)
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

        case .presetDetailsFull(let payload):
            receiveFullPreset(payload)

        case .unknown:
            break
        }
    }

    @ObservationIgnored private var loggedTextsFor: Set<Int> = []

    private func apply(_ details: TonexPedal.PresetDetails) {
        lastDetailsAt = Date()
        if let c = details.presetIndex ?? currentPreset, !loggedTextsFor.contains(c), !details.texts.isEmpty {
            loggedTextsFor.insert(c)
            note("Textos en el preset \(c + startPreset): " + details.texts.prefix(20).joined(separator: " | "))
        }
        if let i = details.presetIndex, i < maxPresets { currentPreset = i }
        if let name = details.name, !name.isEmpty, let c = currentPreset, presets.indices.contains(c) {
            if presets[c].name != name {
                presets[c].name = name
                if phase == .ready { saveNameCache() }
            }
        }
        if let c = currentPreset { updateGuess(for: c, texts: details.texts) }
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


// MARK: - Renombrar en el pedal

extension ControllerStore {
    enum RenameOutcome: Equatable {
        case done
        case failed(String)
    }

    /// Cambia el nombre del preset en el pedal, igual que TONEX Editor: lee el preset completo,
    /// cambia solo el nombre y lo vuelve a escribir en su posición; luego lo relee para confirmar.
    /// Si es el preset que suena, se usa el búfer de edición (como el Editor), así que los
    /// cambios de perillas que tengas también quedan guardados.
    func renamePreset(_ id: Int, to rawName: String) async -> RenameOutcome {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard phase == .ready, presets.indices.contains(id) else { return .failed("El pedal no está listo.") }

        let isCurrent = id == currentPreset
        guard let raw = await readFullPreset(id, editBuffer: isCurrent),
              let body = TonexPedal.fullPresetBody(raw) else {
            return .failed("El pedal no respondió al leer el preset.")
        }
        // Que el bloque leído sea de verdad este preset.
        let idxAt = 4
        let readIndex = body[idxAt] == 0x80 && body.count > idxAt + 1 ? Int(body[idxAt + 1]) : Int(body[idxAt])
        guard readIndex == id else { return .failed("El pedal devolvió otro preset (\(readIndex + startPreset)); no se cambió nada.") }

        let newBody: [UInt8]
        do {
            newBody = try TonexPedal.renamedBody(body, to: name)
        } catch TonexPedal.RenameError.invalidName {
            return .failed("Usa de 1 a \(TonexPedal.nameLength) letras sin acentos ni ñ (solo caracteres ASCII).")
        } catch TonexPedal.RenameError.unknownLayout(let why) {
            note("Renombrar cancelado, formato inesperado (\(isCurrent ? "búfer" : "guardado"), \(raw.count) bytes): \(why)")
            return .failed("El formato del preset no es el esperado; no se cambió nada.\n\n\(why)")
        } catch {
            return .failed("El formato del preset no es el esperado; no se cambió nada.")
        }

        note("Renombrando preset \(id + startPreset) a “\(name)” (\(newBody.count) bytes)")
        send(TonexPedal.writePreset(body: newBody))
        try? await Task.sleep(for: .milliseconds(700))

        // Confirmar leyendo lo que quedó guardado.
        guard let check = await readFullPreset(id),
              let saved = TonexPedal.fullPresetBody(check) else {
            return .failed("Se envió el nombre pero no pude confirmarlo. Revisa el pedal.")
        }
        let stored = TonexPedal.parsePresetDetails(saved).name ?? ""
        guard stored == name else {
            return .failed("El pedal guardó “\(stored)”. Revisa el preset.")
        }
        presets[id].name = name
        saveNameCache()
        rememberToneModel(saved, for: id)
        note("Preset \(id + startPreset) renombrado a “\(name)”")
        return .done
    }

    // MARK: Guardar / cargar / intercambiar (mismo comando de escritura)

    /// Escribe un cuerpo de preset en su posición y lo relee para confirmar.
    private func writeAndVerify(_ body: [UInt8], slot: Int, expectName: String?) async -> RenameOutcome {
        note("Escribiendo preset en \(slot + startPreset) (\(body.count) bytes)")
        send(TonexPedal.writePreset(body: body))
        try? await Task.sleep(for: .milliseconds(700))
        guard let check = await readFullPreset(slot), let saved = TonexPedal.fullPresetBody(check) else {
            return .failed("Se envió, pero no pude confirmarlo. Revisa el pedal.")
        }
        let stored = TonexPedal.parsePresetDetails(saved).name ?? ""
        if let expectName, stored != expectName {
            return .failed("El pedal tiene “\(stored)” en esa posición. Revisa el preset.")
        }
        if presets.indices.contains(slot), !stored.isEmpty, presets[slot].name != stored {
            presets[slot].name = stored
            saveNameCache()
        }
        rememberToneModel(saved, for: slot)
        return .done
    }

    /// Guarda en el pedal lo que suena ahora (perillas y efectos), como el botón Save del Editor.
    func saveCurrentToPedal() async -> RenameOutcome {
        guard phase == .ready, let c = currentPreset else { return .failed("El pedal no está listo.") }
        guard let raw = await readFullPreset(c, editBuffer: true), let body = TonexPedal.fullPresetBody(raw) else {
            return .failed("El pedal no respondió al leer el preset.")
        }
        guard TonexPedal.slot(ofBody: body) == c else { return .failed("El pedal devolvió otro preset; no se guardó nada.") }
        let name = TonexPedal.parsePresetDetails(body).name ?? presets[c].name
        guard let out = try? TonexPedal.renamedBody(body, to: name) else {
            return .failed("El formato del preset no es el esperado; no se guardó nada.")
        }
        return await writeAndVerify(out, slot: c, expectName: name)
    }

    /// Carga un preset guardado (con su Tone Model) en una posición del pedal, reemplazando lo que haya.
    func loadPreset(_ saved: SavedPreset, into slot: Int) async -> RenameOutcome {
        guard phase == .ready, presets.indices.contains(slot) else { return .failed("El pedal no está listo.") }
        guard let body = TonexPedal.fullPresetBody(Array(saved.raw)),
              let moved = try? TonexPedal.body(body, movedTo: slot),
              (try? TonexPedal.renamedBody(moved, to: saved.name)) != nil else {
            return .failed("Ese archivo no tiene el formato de preset completo; no se cargó nada.")
        }
        let result = await writeAndVerify(moved, slot: slot, expectName: saved.name)
        if result == .done, slot == currentPreset { send(TonexPedal.setPreset(slot)) }   // recargar lo que suena
        return result
    }

    /// Intercambia dos posiciones leyendo ambas y escribiendo cada una en la otra.
    func swapPresets(_ a: Int, _ b: Int) async -> RenameOutcome {
        guard a != b, presets.indices.contains(a), presets.indices.contains(b) else { return .failed("Elige dos posiciones distintas.") }
        guard let ra = await readFullPreset(a), let ba = TonexPedal.fullPresetBody(ra),
              let rb = await readFullPreset(b), let bb = TonexPedal.fullPresetBody(rb),
              TonexPedal.slot(ofBody: ba) == a, TonexPedal.slot(ofBody: bb) == b,
              let toB = try? TonexPedal.body(ba, movedTo: b), let toA = try? TonexPedal.body(bb, movedTo: a) else {
            return .failed("No pude leer las dos posiciones; no se cambió nada.")
        }
        let nameA = TonexPedal.parsePresetDetails(ba).name
        let nameB = TonexPedal.parsePresetDetails(bb).name
        let first = await writeAndVerify(toA, slot: a, expectName: nameB)
        guard first == .done else { return first }
        let second = await writeAndVerify(toB, slot: b, expectName: nameA)
        if second == .done, a == currentPreset || b == currentPreset, let c = currentPreset { send(TonexPedal.setPreset(c)) }
        return second
    }

    // MARK: Tone Models

    func rememberToneModel(_ body: [UInt8], for id: Int) {
        guard presets.indices.contains(id) else { return }
        if let info = TonexPedal.toneModelInfo(body: body) {
            toneModels[id] = info
        } else {
            toneModels[id] = nil
        }
        toneModelNames[id] = presets[id].name
        saveToneModels()
        updateGuess(for: id)
    }

    /// Lee en segundo plano los presets cuyo Tone Model aún no conocemos (≈0.2 s cada uno).
    func scanToneModels() {
        toneScanTask?.cancel()
        toneScanTask = Task { [weak self] in
            guard let self else { return }
            for id in self.presets.indices {
                if Task.isCancelled || self.phase != .ready { return }
                // Ya lo tenemos y el preset no cambió de nombre: no hace falta leerlo.
                if self.toneModelNames[id] == self.presets[id].name { continue }
                guard let raw = await self.readFullPreset(id), let body = TonexPedal.fullPresetBody(raw) else { continue }
                self.rememberToneModel(body, for: id)
            }
            self.note("Tone Models: \(self.toneModels.count) de \(self.presets.count) presets identificados")
        }
    }

    private func saveToneModels() {
        let models = Dictionary(uniqueKeysWithValues: toneModels.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(models) { UserDefaults.standard.set(data, forKey: Self.toneModelsKey) }
        let names = Dictionary(uniqueKeysWithValues: toneModelNames.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(names, forKey: Self.toneModelsKey + ".names")
    }

    static func loadToneModels() -> [Int: TonexPedal.ToneModelInfo] {
        guard let data = UserDefaults.standard.data(forKey: toneModelsKey),
              let d = try? JSONDecoder().decode([String: TonexPedal.ToneModelInfo].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: d.compactMap { k, v in Int(k).map { ($0, v) } })
    }

    static func loadToneModelNames() -> [Int: String] {
        guard let d = UserDefaults.standard.dictionary(forKey: toneModelsKey + ".names") as? [String: String] else { return [:] }
        return Dictionary(uniqueKeysWithValues: d.compactMap { k, v in Int(k).map { ($0, v) } })
    }
}
