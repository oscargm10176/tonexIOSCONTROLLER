import Foundation

/// Framing del puerto CDC del Tonex: tipo HDLC con flag 0x7E, escape 0x7D y CRC-16/X.25.
/// Port directo de `usb_tonex_common.c` (TonexOneController, Greg Smith, Apache 2.0).
enum TonexFraming {
    static let flag: UInt8 = 0x7E
    static let escape: UInt8 = 0x7D

    enum Failure: Error, Equatable {
        case tooShort
        case badEscape
        case crcMismatch(received: UInt16, calculated: UInt16)
    }

    /// CRC-16 con polinomio invertido 0x8408, inicio 0xFFFF y complemento final.
    static func crc<C: Collection>(_ bytes: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0x8408 : crc >> 1
            }
        }
        return ~crc
    }

    /// Añade flag inicial, byte stuffing, CRC (LSB primero) y flag final.
    static func frame(_ payload: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [flag]
        out.reserveCapacity(payload.count + payload.count / 8 + 6)

        func put(_ b: UInt8) {
            if b == flag || b == escape {
                out.append(escape)
                out.append(b ^ 0x20)
            } else {
                out.append(b)
            }
        }

        payload.forEach(put)
        let c = crc(payload)
        put(UInt8(c & 0xFF))
        put(UInt8(c >> 8))
        out.append(flag)
        return out
    }

    /// Recibe los bytes que hay *entre* los dos flags (aún con stuffing), quita el escape
    /// y verifica el CRC. Devuelve el payload sin CRC.
    static func unframe<C: Collection>(body: C) throws -> [UInt8] where C.Element == UInt8 {
        var out: [UInt8] = []
        out.reserveCapacity(body.count)
        var escaping = false
        for b in body {
            if escaping {
                out.append(b ^ 0x20)
                escaping = false
            } else if b == escape {
                escaping = true
            } else {
                out.append(b)
            }
        }
        if escaping { throw Failure.badEscape }
        guard out.count >= 2 else { throw Failure.tooShort }

        let received = UInt16(out[out.count - 1]) << 8 | UInt16(out[out.count - 2])
        out.removeLast(2)
        let calculated = crc(out)
        guard received == calculated else {
            throw Failure.crcMismatch(received: received, calculated: calculated)
        }
        return out
    }
}

/// Rearma tramas a partir del flujo de bytes del puerto CDC. Una lectura USB puede traer
/// media trama o varias juntas; el firmware del ESP32 asume tramas completas por lectura,
/// aquí no.
struct TonexDeframer {
    /// El preset completo ronda 30 KB (más el escape); se deja margen.
    var maxFrameSize = 256 * 1024

    private var body: [UInt8] = []
    private var inFrame = false

    private(set) var droppedFrames = 0

    /// Devuelve los payloads válidos (sin framing ni CRC) completados con estos bytes.
    mutating func feed<S: Sequence>(_ bytes: S) -> [[UInt8]] where S.Element == UInt8 {
        var frames: [[UInt8]] = []
        for b in bytes {
            if b == TonexFraming.flag {
                if inFrame && !body.isEmpty {
                    if let payload = try? TonexFraming.unframe(body: body) {
                        frames.append(payload)
                    } else {
                        droppedFrames += 1
                    }
                    body.removeAll(keepingCapacity: true)
                }
                // El flag de cierre puede hacer también de apertura de la siguiente trama;
                // si después llega otro 0x7E, el cuerpo vacío se ignora.
                inFrame = true
            } else if inFrame {
                body.append(b)
                if body.count > maxFrameSize {
                    body.removeAll(keepingCapacity: true)
                    inFrame = false
                    droppedFrames += 1
                }
            }
        }
        return frames
    }

    mutating func reset() {
        body.removeAll()
        inFrame = false
    }
}

// MARK: - Utilidades de bytes

enum TonexBytes {
    /// Valor codificado como en `tonex_common_parse_value`: 0x81/0x82 + uint16 LE,
    /// 0x80 + uint8, o un byte suelto.
    static func parseValue(_ m: [UInt8], _ i: inout Int) -> Int? {
        guard i < m.count else { return nil }
        switch m[i] {
        case 0x81, 0x82:
            guard i + 2 < m.count else { return nil }
            let v = Int(m[i + 2]) << 8 | Int(m[i + 1])
            i += 3
            return v
        case 0x80:
            guard i + 1 < m.count else { return nil }
            let v = Int(m[i + 1])
            i += 2
            return v
        default:
            let v = Int(m[i])
            i += 1
            return v
        }
    }

    static func float(_ m: [UInt8], at i: Int) -> Float? {
        guard i >= 0, i + 4 <= m.count else { return nil }
        let bits = UInt32(m[i]) | UInt32(m[i + 1]) << 8 | UInt32(m[i + 2]) << 16 | UInt32(m[i + 3]) << 24
        return Float(bitPattern: bits)
    }

    static func bytes(of value: Float) -> [UInt8] {
        let b = value.bitPattern
        return [UInt8(b & 0xFF), UInt8((b >> 8) & 0xFF), UInt8((b >> 16) & 0xFF), UInt8(b >> 24)]
    }

    static func write(_ value: Float, into m: inout [UInt8], at i: Int) -> Bool {
        guard i >= 0, i + 4 <= m.count else { return false }
        m.replaceSubrange(i..<(i + 4), with: bytes(of: value))
        return true
    }

    /// Equivalente a `memmem`: posición del primer byte de `pattern` en `m`, o nil.
    static func find(_ pattern: [UInt8], in m: [UInt8], from start: Int = 0) -> Int? {
        guard !pattern.isEmpty, m.count >= pattern.count, start <= m.count - pattern.count else { return nil }
        let first = pattern[0]
        var i = start
        while i <= m.count - pattern.count {
            if m[i] == first {
                var match = true
                for k in 1..<pattern.count where m[i + k] != pattern[k] {
                    match = false
                    break
                }
                if match { return i }
            }
            i += 1
        }
        return nil
    }
}
