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

    /// Preset completo del búfer de edición (lo que suena ahora, con los cambios sin guardar).
    static let requestEditBufferFull: [UInt8] = [0xB9, 0x03, 0x81, 0x00, 0x02, 0x82, 0x06, 0x00, 0x80, 0x10, 0x03,
                                                  0xB9, 0x04, 0x10, 0x00, 0x00, 0x01]

    // MARK: Escritura de presets
    //
    // Capturado de TONEX Editor (macOS) al renombrar un preset, 2026-10-13:
    //   TX  B9 03 81 03 02 82 <len LSB> <len MSB> 80 10 03 + cuerpo (≈30 KB)
    //   RX  B9 03 05 00 10                         (acuse)
    // El cuerpo es el mismo que el pedal devuelve al pedir el preset completo:
    //   B9 04 <01 = guardado | 00 = búfer> 00 <índice> B9 04 B9 04 B9 02 BC 21 <33 bytes nombre> <largo> …
    // Comparando lecturas antes/después: el pedal guarda tal cual la cabecera (nombre,
    // parámetros, etiquetas) y conserva su Tone Model; la cola del bloque es relleno.

    /// Mensaje para guardar un preset completo en su posición (la que va dentro del cuerpo).
    static func writePreset(body: [UInt8]) -> [UInt8] {
        let n = body.count
        return [0xB9, 0x03, 0x81, 0x03, 0x02, 0x82, UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), 0x80, 0x10, 0x03] + body
    }

    /// Cuerpo de una respuesta de preset completo (sin su encabezado).
    static func fullPresetBody(_ m: [UInt8]) -> [UInt8]? {
        guard m.count > 9, m[0] == 0xB9, m[1] == 0x03 else { return nil }
        var i = 2
        guard let type = TonexBytes.parseValue(m, &i), type == 0x0203 || type == 0x0303,
              let size = TonexBytes.parseValue(m, &i),
              TonexBytes.parseValue(m, &i) != nil, m.count - i == size, size > 64 else { return nil }
        return Array(m[i...])
    }

    enum RenameError: Error { case unknownLayout(String), invalidName }

    private static func hex<C: Collection>(_ c: C) -> String where C.Element == UInt8 {
        c.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Devuelve el cuerpo con otro nombre, listo para `writePreset`. Revisa que el formato sea
    /// exactamente el conocido; si algo no cuadra, no toca nada (mejor fallar que dañar el preset).
    static func renamedBody(_ body: [UInt8], to newName: String) throws -> [UInt8] {
        let ascii = Array(newName.utf8)
        guard !ascii.isEmpty, ascii.count <= nameLength, ascii.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else {
            throw RenameError.invalidName
        }
        // B9 04 <flag> 00 <índice (80 xx si ≥128)> …
        guard body.count > 64, body[0] == 0xB9, body[1] == 0x04, body[2] <= 0x01, body[3] == 0x00 else {
            throw RenameError.unknownLayout("inicio: \(hex(body.prefix(16)))")
        }
        guard let marker = TonexBytes.find(presetNameMarker, in: Array(body.prefix(24))) else {
            throw RenameError.unknownLayout("sin marcador de nombre: \(hex(body.prefix(24)))")
        }
        let start = marker + presetNameMarker.count          // 33 bytes de nombre
        let lengthAt = start + nameLength + 1                  // y luego su largo
        guard lengthAt + 1 < body.count else { throw RenameError.unknownLayout("cuerpo corto (\(body.count))") }
        let oldName = body[start..<(start + nameLength + 1)].prefix { $0 != 0 }
        guard Int(body[lengthAt]) == oldName.count, body[lengthAt + 1] == 0xBA else {
            throw RenameError.unknownLayout("largo \(body[lengthAt]) vs \(oldName.count), sigue \(String(format: "%02X", body[lengthAt + 1])); "
                                            + hex(body[marker..<min(body.count, lengthAt + 4)]))
        }

        var out = body
        out[2] = 0x01                                          // guardar en la posición
        for k in 0...nameLength { out[start + k] = k < ascii.count ? ascii[k] : 0 }
        out[lengthAt] = UInt8(ascii.count)
        return out
    }

    /// Mismo cuerpo, pero para guardarlo en otra posición (el índice va dentro del cuerpo).
    static func body(_ body: [UInt8], movedTo slot: Int) throws -> [UInt8] {
        guard body.count > 64, body[0] == 0xB9, body[1] == 0x04, body[2] <= 0x01, body[3] == 0x00 else {
            throw RenameError.unknownLayout("inicio: \(hex(body.prefix(16)))")
        }
        let oldIndexLength = body[4] == 0x80 ? 2 : 1
        var index: [UInt8] = []
        appendPresetIndex(slot, to: &index)
        return [0xB9, 0x04, 0x01, 0x00] + index + body[(4 + oldIndexLength)...]
    }

    /// Posición guardada dentro de un cuerpo de preset.
    static func slot(ofBody body: [UInt8]) -> Int? {
        guard body.count > 6, body[0] == 0xB9, body[1] == 0x04 else { return nil }
        return body[4] == 0x80 ? Int(body[5]) : Int(body[4])
    }

    /// Tone Model que usa el preset y, si lo trae (presets de IK/ToneNET), el amplificador real.
    /// Visto en las capturas: `B9 02 BC 21 <33 bytes nombre del modelo> <largo> <n> BC 81 <largo16>`
    /// y, al inicio de ese bloque, un texto de 43 bytes con el amp ("Diezel VH4", "Vox AC30"…).
    struct ToneModelInfo: Codable, Equatable {
        var model: String
        var amp: String?
    }

    static func toneModelInfo(body b: [UInt8]) -> ToneModelInfo? {
        let field: [UInt8] = [0xB9, 0x02, 0xBC, 0x21]
        var j = 1600
        while let p = TonexBytes.find(field, in: b, from: j), p < min(b.count - 60, 4000) {
            let start = p + 4
            let after = start + nameLength + 1          // byte de largo
            if after + 3 < b.count, b[after + 2] == 0xBC, b[after + 3] == 0x81 {
                let model = cString(b[start..<(start + nameLength + 1)])
                var amp: String?
                let blob = after + 6                    // BC 81 LL LL
                if blob + 50 < b.count, let z = b[blob..<(blob + 8)].firstIndex(of: 0x2B) {
                    let a = cString(b[(z + 1)..<(z + 44)])
                    if a.count >= 3 { amp = a }
                }
                return model.isEmpty ? nil : ToneModelInfo(model: model, amp: amp)
            }
            j = p + 1
        }
        return nil
    }

    private static func cString(_ s: ArraySlice<UInt8>) -> String {
        let bytes = s.prefix { $0 != 0 }.filter { $0 >= 0x20 && $0 < 0x7F }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
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
        /// Cadenas ASCII legibles (≥ 4 letras) dentro del bloque, para diagnóstico.
        var texts: [String] = []
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
        /// Preset completo (~30 KB): payload entero, sin interpretar.
        case presetDetailsFull([UInt8])
        case paramChanged(index: Int, value: Float)
        case globalConfig(GlobalConfig)
        case unknown(type: Int)
    }

    enum ParseError: Error {
        case invalidHeader
        case sizeMismatch(expected: Int, actual: Int)
    }

    // Marcadores (ver usb_tonex.c)
    static let presetNameMarker: [UInt8] = [0xB9, 0x04, 0xB9, 0x02, 0xBC, 0x21]
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
        case 0x0203, 0x0303:
            // Preset completo. En el Tonex Pedal llega como 0x0203 (B9 03 81 03 02 …),
            // visto en la captura de TONEX Editor; 0x0303 queda por si otro firmware lo usa.
            return .presetDetailsFull(m)
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

    static func parsePresetDetails(_ m: [UInt8]) -> PresetDetails {
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
        details.texts = printableRuns(m)
        return details
    }

    /// Secuencias de caracteres imprimibles de 4 o más (como `strings`).
    static func printableRuns(_ m: [UInt8], minLength: Int = 4) -> [String] {
        var out: [String] = []
        var run: [UInt8] = []
        func flush() {
            if run.count >= minLength { out.append(String(decoding: run, as: UTF8.self)) }
            run.removeAll(keepingCapacity: true)
        }
        for b in m {
            if b >= 0x20 && b < 0x7F { run.append(b) } else { flush() }
        }
        flush()
        return out
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
