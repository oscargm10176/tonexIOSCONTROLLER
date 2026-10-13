import Foundation
import CoreMIDI

/// Mensaje MIDI que dispara una acción (lo que manda un botón del pedal de pie).
struct MIDITrigger: Codable, Hashable {
    enum Kind: String, Codable { case programChange, controlChange, note }
    var kind: Kind
    var channel: UInt8      // 0…15
    var number: UInt8       // nº de programa, de CC o de nota

    var label: String {
        let ch = "canal \(channel + 1)"
        switch kind {
        case .programChange: return "PC \(number) · \(ch)"
        case .controlChange: return "CC \(number) · \(ch)"
        case .note: return "Nota \(number) · \(ch)"
        }
    }
}

/// Qué hace un botón del pedal de pie.
enum FootAction: Codable, Hashable {
    case previousPreset, nextPreset
    case previousBank, nextBank
    case slot(Int)                 // A / B / C del banco actual
    case toggle(EffectBlock)       // encender / apagar un bloque
    case tapTempo

    var title: String {
        switch self {
        case .previousPreset: return "Preset anterior"
        case .nextPreset: return "Preset siguiente"
        case .previousBank: return "Banco anterior"
        case .nextBank: return "Banco siguiente"
        case .slot(let i): return "Preset \(["A", "B", "C"][min(max(i, 0), 2)]) del banco"
        case .toggle(let b): return "Encender/apagar \(b.title)"
        case .tapTempo: return "Tap tempo"
        }
    }

    var systemImage: String {
        switch self {
        case .previousPreset: return "chevron.left"
        case .nextPreset: return "chevron.right"
        case .previousBank: return "chevron.left.2"
        case .nextBank: return "chevron.right.2"
        case .slot: return "square.grid.3x1.below.line.grid.1x2"
        case .toggle: return "power"
        case .tapTempo: return "metronome"
        }
    }

    /// Todas las opciones, en el orden del menú.
    static var all: [FootAction] {
        [.previousPreset, .nextPreset, .previousBank, .nextBank, .slot(0), .slot(1), .slot(2)]
            + EffectBlock.allCases.filter { $0.enableIndex != nil }.map { .toggle($0) }
            + [.tapTempo]
    }
}

extension EffectBlock: Codable {}

struct FootBinding: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var trigger: MIDITrigger?
    var action: FootAction
}

/// Pedal de pie por MIDI (Bluetooth o USB), p. ej. iRig BlueBoard.
/// Escucha todas las fuentes MIDI del iPad; cada botón se "aprende" pisándolo.
@MainActor
@Observable
final class FootController {
    private(set) var sources: [String] = []
    private(set) var lastMessage: String?
    private(set) var lastAction: String?
    private(set) var bindings: [FootBinding]
    /// Fila esperando a que pises un botón.
    var learning: UUID?

    @ObservationIgnored private weak var store: ControllerStore?
    @ObservationIgnored private var client = MIDIClientRef()
    @ObservationIgnored private var port = MIDIPortRef()
    @ObservationIgnored private let tapper = TapTempo()
    /// Último "presionado" de cada CC, para no disparar dos veces con botones momentáneos.
    @ObservationIgnored private var ccPressedAt: [MIDITrigger: Date] = [:]
    private static let key = "footBindings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([FootBinding].self, from: data) {
            bindings = saved
        } else {
            bindings = [
                FootBinding(name: "Botón A", action: .previousPreset),
                FootBinding(name: "Botón B", action: .nextPreset),
                FootBinding(name: "Botón C", action: .toggle(.delay)),
                FootBinding(name: "Botón D", action: .tapTempo),
            ]
        }
    }

    func attach(_ store: ControllerStore) {
        self.store = store
        guard client == 0 else { return }
        MIDIClientCreateWithBlock("TONE" as CFString, &client) { [weak self] notif in
            let id = notif.pointee.messageID
            guard id == .msgSetupChanged || id == .msgObjectAdded || id == .msgObjectRemoved else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.connectSources() } }
        }
        MIDIInputPortCreateWithProtocol(client, "TONE in" as CFString, ._1_0, &port) { [weak self] list, _ in
            let msgs = FootController.parse(list)
            guard !msgs.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { msgs.forEach { self?.handle($0.trigger, value: $0.value) } }
            }
        }
        connectSources()
    }

    func connectSources() {
        guard port != 0 else { return }
        var names: [String] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            MIDIPortDisconnectSource(port, src)
            MIDIPortConnectSource(port, src, nil)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &name)
            names.append((name?.takeRetainedValue() as String?) ?? "MIDI")
        }
        sources = names
    }

    // MARK: Edición de botones

    func add() {
        bindings.append(FootBinding(name: "Botón \(bindings.count + 1)", action: .nextPreset))
        save()
    }

    func remove(_ id: UUID) {
        bindings.removeAll { $0.id == id }
        if learning == id { learning = nil }
        save()
    }

    func setAction(_ id: UUID, _ action: FootAction) {
        guard let i = bindings.firstIndex(where: { $0.id == id }) else { return }
        bindings[i].action = action
        save()
    }

    func clearTrigger(_ id: UUID) {
        guard let i = bindings.firstIndex(where: { $0.id == id }) else { return }
        bindings[i].trigger = nil
        save()
    }

    // MARK: Mensajes entrantes

    private func handle(_ trigger: MIDITrigger, value: UInt8) {
        lastMessage = trigger.kind == .controlChange ? "\(trigger.label) = \(value)" : trigger.label

        if trigger.kind == .controlChange {
            // Momentáneo: 127 al pisar, 0 al soltar → solo cuenta el pisado.
            // Alternado (toggle): cada pisada manda 127 ó 0 → el 0 también cuenta si llega solo.
            let now = Date()
            if value >= 64 {
                ccPressedAt[trigger] = now
            } else if let t = ccPressedAt[trigger], now.timeIntervalSince(t) < 0.6 {
                return
            }
        }

        if let id = learning, let i = bindings.firstIndex(where: { $0.id == id }) {
            for j in bindings.indices where bindings[j].trigger == trigger { bindings[j].trigger = nil }
            bindings[i].trigger = trigger
            learning = nil
            save()
            return
        }

        for b in bindings where b.trigger == trigger { perform(b.action) }
    }

    func perform(_ action: FootAction) {
        guard let store, store.state == .ready, store.maxPresets > 0 else { return }
        let n = store.maxPresets
        let current = store.currentPreset ?? 0
        switch action {
        case .previousPreset: store.previousPreset()
        case .nextPreset: store.nextPreset()
        case .previousBank, .nextBank:
            let step = action == .nextBank ? Preset.perBank : -Preset.perBank
            store.selectPreset(((current + step) % n + n) % n)
        case .slot(let s):
            let target = (current / Preset.perBank) * Preset.perBank + s
            if target < n { store.selectPreset(target) }
        case .toggle(let block):
            guard let i = block.enableIndex else { return }
            store.setToggle(i, !store.isOn(i))
        case .tapTempo:
            if let bpm = tapper.tap() { store.setBPM(bpm) }
        }
        lastAction = action.title
    }

    // MARK: Lectura de MIDI (UMP, MIDI 1.0)

    nonisolated private static func parse(_ list: UnsafePointer<MIDIEventList>) -> [(trigger: MIDITrigger, value: UInt8)] {
        var out: [(MIDITrigger, UInt8)] = []
        for packet in list.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            var words: [UInt32] = []
            withUnsafeBytes(of: packet.pointee.words) { raw in
                words = Array(raw.bindMemory(to: UInt32.self).prefix(count))
            }
            for w in words where w >> 28 == 0x2 {           // mensaje de canal MIDI 1.0
                let status = UInt8((w >> 16) & 0xF0)
                let ch = UInt8((w >> 16) & 0x0F)
                let d1 = UInt8((w >> 8) & 0x7F)
                let d2 = UInt8(w & 0x7F)
                switch status {
                case 0xC0: out.append((MIDITrigger(kind: .programChange, channel: ch, number: d1), 127))
                case 0xB0: out.append((MIDITrigger(kind: .controlChange, channel: ch, number: d1), d2))
                case 0x90 where d2 > 0: out.append((MIDITrigger(kind: .note, channel: ch, number: d1), d2))
                default: break
                }
            }
        }
        return out
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
