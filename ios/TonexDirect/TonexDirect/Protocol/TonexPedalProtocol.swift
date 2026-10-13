import Foundation

/// Protocolo del **Tonex Pedal** (el grande, USB 0x1963:0x0068) por su puerto CDC
/// "ToneX Control VCOM". Port de `source/main/usb_tonex.c` de TonexOneController
/// (Greg Smith, Apache 2.0; parte del protocolo viene de github.com/vit3k/tonex_controller).
///
/// Todos los mensajes salientes son payloads *sin* framing: `TonexFraming.frame` los envuelve.
enum TonexPedal {
    static let vendorID = 0x1963
    static let productID = 0x0068
    static let maxPresets = 150
    static let nameLength = 32

    // MARK: Peticiones

    static let hello: [UInt8] = [0xB9, 0x03, 0x00, 0x82, 0x04, 0x00, 0x80, 0x10, 0x01, 0xB9, 0x02, 0x02, 0x10]

    static let requestState: [UInt8] = [0xB9, 0x03, 0x00, 0x82, 0x06, 0x00, 0x80, 0x10, 0x03,
                                        0xB9, 0x02, 0x81, 0x01, 0x02, 0x10]

    static let requestGlobalConfig: [UInt8] = [0xB9, 0x03, 0x00, 0x82, 0x06, 0x00, 0x80, 0x10, 0x03,
                                               0xB9, 0x02, 0x81, 0x06, 0x02, 0x10]

    /// `full = false` pide el resumen (~2 KB: nombre + parámetros). El completo (~30 KB) no hace falta.
    static func requestPresetDetails(_ preset: Int, full: Bool = false) -> [UInt8] {
        var m: [UInt8] = [0xB9, 0x03, 0x81, 0x00, 0x02, 0x82, 0x06, 0x00, 0x80, 0x10, 0x03,
                          0xB9, 0x04, 0x10, 0x01]
        appendPresetIndex(preset, to: &m)
        m.append(full ? 0x01 : 0x00)
        return m
    }

    static func setPreset(_ preset: Int) -> [UInt8] {
        var m: [UInt8] = [0xB9, 0x03, 0x81, 0x01, 0x02, 0x82, 0x04, 0x00, 0x80, 0x10, 0x03, 0xB9, 0x02]
        appendPresetIndex(preset, to: &m)
        m.append(0x00)
        return m
    }

    /// Cambia un parámetro del preset activo (índices 0..<`TonexParam.paramLast`).
    /// Requiere el firmware del pedal que trajo soporte para el editor.
    static func setParameter(_ index: Int, value: Float) -> [UInt8] {
        let header: [UInt8] = [0xB9, 0x03, 0x81, 0x07, 0x02, 0x82, 0x0A, 0x00, 0x80, 0x10, 0x03]
        let payload: [UInt8] = [0xB9, 0x04, 0x02, 0x00, UInt8(clamping: index), 0x88] + TonexBytes.bytes(of: value)
        return header + payload
    }

    /// Reenvía la configuración global completa (con los cambios aplicados en `config`).
    ///
    /// El encabezado se copia tal cual del firmware, incluido el 0x7E inicial dentro del
    /// payload (al enmarcar queda escapado como 7D 5E). Así es como funciona con el pedal
    /// hoy; no lo "corrijas" sin probarlo en el hardware.
    static func sendGlobalConfig(_ config: GlobalConfig) -> [UInt8] {
        let header: [UInt8] = [0x7E, 0xB9, 0x03, 0x81, 0x06, 0x02, 0x82, 0xF0, 0x0D, 0x80, 0x10, 0x03,
                               0xB9, 0x01, 0xB9, 0x02, 0xBA, 0x16]
        return header + config.raw[config.startOffset...]
    }

    /// Presets ≥ 128 llevan un 0x80 delante del índice.
    private static func appendPresetIndex(_ preset: Int, to m: inout [UInt8]) {
        let p = UInt8(clamping: preset)
        if preset >= 128 { m.append(0x80) }
        m.append(p)
    }

    // MARK: Mensajes entrantes

    struct PresetDetails {
        var name: String?
        /// Solo viene cuando el preset cambia en el pedal, no durante la sincronización.
        var presetIndex: Int?
        /// Valores de los parámetros 0..<paramLast, en orden. Puede venir incompleto o vacío.
        var params: [Float]
    }

    /// Bloque de configuración global tal cual lo manda el pedal. Se guarda entero
    /// porque para cambiar un global hay que reenviarlo completo.
    struct GlobalConfig {
        var raw: [UInt8]
        /// Posición del primer float (después del marcador B9 02 BA 16).
        var startOffset: Int

        /// Orden de los floats dentro del bloque (cada uno = 0x88 + 4 bytes).
        enum Slot: Int {
            case presetNaming = 2, userMode = 3, midiChannel = 7, inputTrim = 9, mainVolume = 10
            case cabSimBypass = 15, tuningReference = 17, bpm = 18, tempoSource = 19
            static let count = 22
        }

        func value(_ slot: Slot) -> Float? {
            let i = startOffset + slot.rawValue * 5
            guard i < raw.count, raw[i] == 0x88 else { return nil }
            return TonexBytes.float(raw, at: i + 1)
        }

        mutating func set(_ slot: Slot, _ v: Float) -> Bool {
            let i = startOffset + slot.rawValue * 5
            guard i < raw.count, raw[i] == 0x88 else { return false }
            return TonexBytes.write(v, into: &raw, at: i + 1)
        }

        /// Índice de `TonexParam` (globales 110…117) → slot del bloque. Bypass, direct monitor
        /// y tempo source no están soportados en el Pedal (ver `usb_tonex_modify_global`).
        static func slot(forParam index: Int) -> Slot? {
            switch index {
            case TonexParam.bpm: return .bpm
            case TonexParam.inputTrim: return .inputTrim
            case TonexParam.cabSimBypass: return .cabSimBypass
            case TonexParam.tuningReference: return .tuningReference
            case TonexParam.masterVolume: return .mainVolume
            default: return nil
            }
        }

        /// Globales legibles que la app muestra.
        var paramValues: [Int: Float] {
            var out: [Int: Float] = [:]
            let map: [(Int, Slot)] = [
                (TonexParam.bpm, .bpm), (TonexParam.inputTrim, .inputTrim),
                (TonexParam.cabSimBypass, .cabSimBypass), (TonexParam.tempoSource, .tempoSource),
                (TonexParam.tuningReference, .tuningReference), (TonexParam.masterVolume, .mainVolume),
            ]
            for (param, slot) in map {
                if let v = value(slot) { out[param] = v }
            }
            return out
        }
    }

    enum Event {
        case hello
        case state(currentPreset: Int)
        case presetDetails(PresetDetails)
        case presetDetailsFull
        case paramChanged(index: Int, value: Float)
        case globalConfig(GlobalConfig)
        case unknown(type: Int)
    }

    enum ParseError: Error {
        case invalidHeader
        case sizeMismatch(expected: Int, actual: Int)
    }

    // Marcadores (ver usb_tonex.c)
    private static let presetNameMarker: [UInt8] = [0xB9, 0x04, 0xB9, 0x02, 0xBC, 0x21]
    private static let presetIndexMarker: [UInt8] = [0xB9, 0x04, 0x00, 0x00]
    private static let presetParamsMarker: [UInt8] = [0xBA, 0x03, 0xBA, 0x6D]
    private static let paramChangedMarker: [UInt8] = [0xB9, 0x04, 0x02, 0x00]
    private static let globalConfigMarker: [UInt8] = [0xB9, 0x02, 0xBA, 0x16]

    /// Interpreta un payload ya sin framing.
    ///
    /// Nota: el firmware busca nombre/índice/parámetros en la trama *con* stuffing; aquí se
    /// busca en el payload limpio, que es lo correcto si algún float contiene 0x7D/0x7E.
    static func parse(_ m: [UInt8]) throws -> Event {
        guard m.count >= 5, m[0] == 0xB9, m[1] == 0x03 else { throw ParseError.invalidHeader }
        var i = 2
        guard let type = TonexBytes.parseValue(m, &i),
              let size = TonexBytes.parseValue(m, &i),
              TonexBytes.parseValue(m, &i) != nil else { throw ParseError.invalidHeader }
        guard m.count - i == size else { throw ParseError.sizeMismatch(expected: size, actual: m.count - i) }

        switch type {
        case 0x02:
            return .hello
        case 0x0301, 0x0201:
            // El firmware lee el preset en una posición fija.
            guard m.count > 9 else { throw ParseError.invalidHeader }
            return .state(currentPreset: Int(m[9]))
        case 0x0304, 0x0204:
            return .presetDetails(parsePresetDetails(m))
        case 0x0303:
            return .presetDetailsFull
        case 0x0206:
            if let cfg = parseGlobalConfig(m) { return .globalConfig(cfg) }
            return .unknown(type: type)
        case 0x0207:
            if let change = parseParamChanged(m) { return .paramChanged(index: change.index, value: change.value) }
            return .unknown(type: type)
        default:
            return .unknown(type: type)
        }
    }

    private static func parsePresetDetails(_ m: [UInt8]) -> PresetDetails {
        var details = PresetDetails(name: nil, presetIndex: nil, params: [])

        if let p = TonexBytes.find(presetNameMarker, in: m) {
            let start = p + presetNameMarker.count
            let end = min(start + nameLength, m.count)
            if start < end {
                let raw = m[start..<end].prefix { $0 != 0 }
                let name = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                details.name = name
            }
        }

        if let p = TonexBytes.find(presetIndexMarker, in: m) {
            var i = p + presetIndexMarker.count
            if i < m.count, m[i] == 0x80 { i += 1 }
            if i < m.count { details.presetIndex = Int(m[i]) }
        }

        if let p = TonexBytes.find(presetParamsMarker, in: m) {
            var i = p + presetParamsMarker.count
            var values: [Float] = []
            values.reserveCapacity(TonexParam.paramLast)
            while values.count < TonexParam.paramLast, i < m.count, m[i] == 0x88,
                  let v = TonexBytes.float(m, at: i + 1) {
                values.append(v)
                i += 5
            }
            details.params = values
        }
        return details
    }

    private static func parseParamChanged(_ m: [UInt8]) -> (index: Int, value: Float)? {
        guard let p = TonexBytes.find(paramChangedMarker, in: m) else { return nil }
        let i = p + paramChangedMarker.count
        guard i + 1 < m.count, m[i + 1] == 0x88, let v = TonexBytes.float(m, at: i + 2) else { return nil }
        return (Int(m[i]), v)
    }

    private static func parseGlobalConfig(_ m: [UInt8]) -> GlobalConfig? {
        guard let p = TonexBytes.find(globalConfigMarker, in: m) else { return nil }
        let start = p + globalConfigMarker.count
        guard start < m.count, m[start] == 0x88 else { return nil }
        return GlobalConfig(raw: m, startOffset: start)
    }
}
