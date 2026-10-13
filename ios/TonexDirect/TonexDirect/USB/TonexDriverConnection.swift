import Foundation
// IOKit llega por TonexDirect-Bridging-Header.h (no hay módulo IOKit en iPadOS).

/// Conexión IOKit con el user client del driver `TonexDriver` (dext embebido en la app).
/// Los selectores replican `DriverSource/TonexShared.h (TonexDriver/ en el proyecto)`.
final class TonexDriverConnection: @unchecked Sendable {
    enum Selector: UInt32 {
        case write = 0
        case read = 1
        case status = 2
    }

    /// Nombre con el que se registra la interfaz de datos del driver.
    static let serviceName = "TonexDataInterface"
    /// Menor que el límite en banda de IOKit (4096) para que nunca use memoria fuera de banda.
    static let maxTransfer = 2048
    static let statusCount = 12

    struct Status {
        let ready: Bool
        let vendorID: Int
        let productID: Int
        let droppedBytes: UInt64
        /// Valores crudos (ver kTonexStatus* en TonexShared.h).
        let raw: [UInt64]

        private func code(_ i: Int) -> String {
            let v = UInt32(truncatingIfNeeded: raw[i])
            return v == 0xFFFF_FFFF ? "—" : "0x" + String(v, radix: 16)
        }

        /// Resumen para el registro de diagnóstico.
        var driverReport: String {
            let ep = raw[10]
            return "escrituras=\(raw[5]) últimaEscritura=\(code(4)) reintento=\(code(11)) lecturas=\(raw[7]) últimaLectura=\(code(6)) lineCoding=\(code(8)) DTR/RTS=\(code(9)) endpoints IN=0x\(String(ep >> 8, radix: 16)) OUT=0x\(String(ep & 0xFF, radix: 16))"
        }
    }

    enum Failure: Error, CustomStringConvertible {
        case serviceNotFound
        case open(kern_return_t)
        case call(String, kern_return_t)
        case notOpen

        var description: String {
            switch self {
            case .serviceNotFound: return tr("No encuentro el driver del Tonex")
            case .open(let kr): return trf("No pude abrir el driver (%@)", Self.hex(kr))
            case let .call(op, kr): return trf("Falló la %@ con el driver (%@)", tr(op), Self.hex(kr))
            case .notOpen: return tr("El driver no está abierto")
            }
        }

        private static func hex(_ kr: kern_return_t) -> String {
            "0x" + String(UInt32(bitPattern: kr), radix: 16)
        }
    }

    private let lock = NSLock()
    private var connection: io_connect_t = io_connect_t(IO_OBJECT_NULL)

    deinit { close() }

    /// ¿El driver está cargado? Solo corre si el pedal está conectado y el driver está
    /// activado en Ajustes.
    static func serviceAvailable() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching(serviceName))
        guard service != IO_OBJECT_NULL else { return false }
        IOObjectRelease(service)
        return true
    }

    func open() throws {
        close()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching(Self.serviceName))
        guard service != IO_OBJECT_NULL else { throw Failure.serviceNotFound }
        defer { IOObjectRelease(service) }

        var handle = io_connect_t(IO_OBJECT_NULL)
        let kr = IOServiceOpen(service, mach_task_self_, 0, &handle)
        guard kr == KERN_SUCCESS else { throw Failure.open(kr) }
        lock.withLock { connection = handle }
    }

    func close() {
        lock.withLock {
            if connection != IO_OBJECT_NULL {
                IOServiceClose(connection)
                connection = io_connect_t(IO_OBJECT_NULL)
            }
        }
    }

    private func handle() throws -> io_connect_t {
        let c = lock.withLock { connection }
        guard c != IO_OBJECT_NULL else { throw Failure.notOpen }
        return c
    }

    /// Escribe bytes crudos al endpoint bulk OUT (en trozos de 4 KB; es un flujo CDC).
    func write(_ bytes: [UInt8]) throws {
        let c = try handle()
        var offset = 0
        while offset < bytes.count {
            let n = min(Self.maxTransfer, bytes.count - offset)
            let kr = bytes.withUnsafeBytes { raw in
                IOConnectCallStructMethod(c, Selector.write.rawValue, raw.baseAddress! + offset, n, nil, nil)
            }
            guard kr == KERN_SUCCESS else { throw Failure.call("escritura", kr) }
            offset += n
        }
    }

    /// Lo que el driver tenga acumulado (puede ser vacío).
    func read() throws -> [UInt8] {
        let c = try handle()
        var count: UInt64 = 0
        var scalarCount: UInt32 = 1
        var buffer = [UInt8](repeating: 0, count: Self.maxTransfer)
        var size = Self.maxTransfer

        let kr = buffer.withUnsafeMutableBytes { raw in
            IOConnectCallMethod(c, Selector.read.rawValue,
                                nil, 0, nil, 0,
                                &count, &scalarCount,
                                raw.baseAddress, &size)
        }
        guard kr == KERN_SUCCESS else { throw Failure.call("lectura", kr) }
        let n = min(Int(count), size, buffer.count)
        return n > 0 ? Array(buffer[0..<n]) : []
    }

    func status() throws -> Status {
        let c = try handle()
        var values = [UInt64](repeating: 0, count: Self.statusCount)
        var count = UInt32(Self.statusCount)
        let kr = values.withUnsafeMutableBufferPointer { buf in
            IOConnectCallMethod(c, Selector.status.rawValue,
                                nil, 0, nil, 0,
                                buf.baseAddress, &count,
                                nil, nil)
        }
        guard kr == KERN_SUCCESS else { throw Failure.call("consulta de estado", kr) }
        return Status(ready: values[0] != 0,
                      vendorID: Int(values[1]),
                      productID: Int(values[2]),
                      droppedBytes: values[3],
                      raw: values)
    }
}

/// Enlace con el pedal: abre el driver, lee en un hilo propio y escribe en una cola serie.
/// Entrega los bytes recibidos en el hilo principal, en orden.
final class TonexUSBLink: @unchecked Sendable {
    let connection = TonexDriverConnection()

    /// En el hilo principal.
    var onBytes: (([UInt8]) -> Void)?
    /// En el hilo principal. Se llama una sola vez.
    var onLost: ((String) -> Void)?

    private let writeQueue = DispatchQueue(label: "tonex.usb.write", qos: .userInitiated)
    private let stateLock = NSLock()
    private var running = false
    private var lostReported = false
    private var reader: Thread?

    func start() throws -> TonexDriverConnection.Status {
        try connection.open()
        let status: TonexDriverConnection.Status
        do {
            status = try connection.status()
        } catch {
            connection.close()
            throw error
        }

        stateLock.withLock {
            running = true
            lostReported = false
        }
        let thread = Thread { [weak self] in self?.readLoop() }
        thread.name = "tonex.usb.read"
        thread.qualityOfService = .userInitiated
        reader = thread
        thread.start()
        return status
    }

    func stop() {
        stateLock.withLock { running = false }
        reader = nil
        writeQueue.sync { }
        connection.close()
    }

    /// Enmarca y envía un payload del protocolo.
    func send(_ payload: [UInt8]) {
        let framed = TonexFraming.frame(payload)
        writeQueue.async { [weak self] in
            guard let self, self.isRunning else { return }
            do {
                try self.connection.write(framed)
            } catch {
                self.reportLost("\(error)")
            }
        }
    }

    private var isRunning: Bool { stateLock.withLock { running } }

    private func readLoop() {
        var idle = 0
        while isRunning {
            do {
                let bytes = try connection.read()
                if bytes.isEmpty {
                    // Sin datos: espera corta, un poco más larga si lleva rato en silencio.
                    idle = min(idle + 1, 50)
                    Thread.sleep(forTimeInterval: idle < 25 ? 0.004 : 0.012)
                } else {
                    idle = 0
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isRunning else { return }
                        self.onBytes?(bytes)
                    }
                }
            } catch {
                reportLost("\(error)")
                return
            }
        }
    }

    private func reportLost(_ reason: String) {
        let first: Bool = stateLock.withLock {
            guard running, !lostReported else { return false }
            lostReported = true
            running = false
            return true
        }
        guard first else { return }
        let report = (try? connection.status())?.driverReport
        DispatchQueue.main.async { [weak self] in
            self?.connection.close()
            self?.onLost?(report.map { "\(reason) · driver: \($0)" } ?? reason)
        }
    }
}
