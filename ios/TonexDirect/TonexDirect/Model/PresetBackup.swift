import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

/// Tipo de archivo propio: los .tonepreset se ven con el ícono de TONE y se abren con la app
/// (Archivos, AirDrop, Mail…). Por dentro es JSON; los .json viejos también se aceptan.
extension UTType {
    static let tonePreset = UTType(exportedAs: "com.nuttstudios.tone.preset", conformingTo: .json)
}

/// Un preset guardado en un archivo (.tonepreset), con todo lo que el pedal nos da:
/// nombre, posición, valores legibles y los datos crudos completos (incluye el Tone Model),
/// para poder volver a cargarlo el día que conozcamos el comando de escritura.
struct SavedPreset: Codable {
    var format = 1
    var app = "TONE"
    var savedAt: Date
    var pedal: String?
    var slot: Int            // 0-based
    var bank: String         // "01"
    var letter: String       // "B"
    var name: String
    var bpm: Double?
    var params: [SavedParam]
    /// Datos crudos del pedal (base64 en el JSON).
    var raw: Data

    struct SavedParam: Codable {
        var index: Int
        var name: String
        var value: Double
    }

    var fileName: String {
        let safe = name.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" ? $0 : "_" }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespaces)
        return "\(bank)\(letter) \(safe.isEmpty ? "Preset" : safe).\(PresetLibrary.fileExtension)"
    }

    func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }
}

extension ControllerStore {
    /// Lee del pedal un preset y lo empaqueta para guardarlo (no cambia nada en el pedal).
    func makeBackup(of id: Int) async -> SavedPreset? {
        guard let raw = await readFullPreset(id), !raw.isEmpty else { return nil }
        let details = TonexPedal.parsePresetDetails(raw)
        let info = presets.indices.contains(id) ? presets[id] : Preset(id: id, number: id + 1, name: "Preset")

        var values: [(Int, Double)] = details.params.enumerated().map { ($0.offset, Double($0.element)) }
        if values.isEmpty, id == currentPreset {
            values = (0..<TonexParam.paramLast).map { ($0, value($0)) }   // los que tenemos en pantalla
        }
        let names = TonexParamTable.defaults()
        let params = values.map { SavedPreset.SavedParam(index: $0.0, name: names[$0.0]?.name ?? "P\($0.0)", value: $0.1) }

        return SavedPreset(
            savedAt: Date(),
            pedal: modeller?.displayName,
            slot: id,
            bank: info.bankText,
            letter: info.slot,
            name: (details.name?.isEmpty == false ? details.name! : info.name),
            bpm: supports(TonexParam.bpm) ? value(TonexParam.bpm) : nil,
            params: params,
            raw: Data(raw)
        )
    }
}

/// Biblioteca de presets guardados en el iPad (Documentos/Presets).
/// También se ve en Archivos › En mi iPad › TONE › Presets.
@MainActor
@Observable
final class PresetLibrary {
    static let fileExtension = "tonepreset"

    struct Entry: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let name: String
        let bank: String
        let letter: String
        let savedAt: Date
        let model: String?
        let amp: String?
        let digest: String
    }

    struct ImportReport: Identifiable {
        let id = UUID()
        var added: [Entry] = []
        var duplicates: [String] = []
        var invalid: [String] = []

        var summary: String {
            var parts: [String] = []
            if !added.isEmpty { parts.append(added.count == 1 ? "Se importó “\(added[0].name)”." : "Se importaron \(added.count) presets.") }
            if !duplicates.isEmpty { parts.append("Ya tenías \(duplicates.count == 1 ? "“\(duplicates[0])”" : "\(duplicates.count) de ellos") (no se duplicaron).") }
            if !invalid.isEmpty { parts.append("\(invalid.count == 1 ? "“\(invalid[0])” no es" : "\(invalid.count) archivos no son") un preset de TONE.") }
            return parts.isEmpty ? "No había nada que importar." : parts.joined(separator: " ")
        }
    }

    private(set) var entries: [Entry] = []
    /// Resultado del último import (para mostrarlo, venga de donde venga).
    var lastImport: ImportReport?
    /// Pide abrir "Mis presets" (p. ej. al abrir un archivo desde fuera de la app).
    var wantsToShow = false

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Presets", isDirectory: true)
    }

    init() { reload() }

    private static func decode(_ data: Data) -> SavedPreset? {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(SavedPreset.self, from: data)
    }

    private static func entry(_ url: URL, _ p: SavedPreset) -> Entry {
        let info = TonexPedal.fullPresetBody(Array(p.raw)).flatMap { TonexPedal.toneModelInfo(body: $0) }
        let digest = SHA256.hash(data: p.raw).prefix(12).map { String(format: "%02x", $0) }.joined()
        return Entry(url: url, name: p.name, bank: p.bank, letter: p.letter, savedAt: p.savedAt,
                     model: info?.model, amp: info?.amp, digest: digest)
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        entries = urls.filter { ["json", Self.fileExtension].contains($0.pathExtension.lowercased()) }.compactMap { url in
            guard let data = try? Data(contentsOf: url), let p = Self.decode(data) else { return nil }
            return Self.entry(url, p)
        }
        .sorted { $0.savedAt > $1.savedAt }
    }

    func load(_ entry: Entry) -> SavedPreset? {
        (try? Data(contentsOf: entry.url)).flatMap(Self.decode)
    }

    /// Guarda el preset en la biblioteca. Si ya hay uno con el mismo nombre de archivo, agrega la fecha.
    @discardableResult
    func save(_ preset: SavedPreset) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        var url = Self.folder.appendingPathComponent(preset.fileName)
        if fm.fileExists(atPath: url.path) {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let base = url.deletingPathExtension().lastPathComponent
            url = Self.folder.appendingPathComponent("\(base) \(f.string(from: preset.savedAt)).\(Self.fileExtension)")
        }
        try preset.encoded().write(to: url, options: .atomic)
        return url
    }

    /// Importa archivos o carpetas de fuera de la app (Archivos, AirDrop, arrastrar…).
    /// Evita duplicados: si ya tienes exactamente el mismo preset, no lo copia otra vez.
    @discardableResult
    func importFiles(_ urls: [URL]) -> ImportReport {
        var report = ImportReport()
        var known = Set(entries.map(\.digest))
        func handle(_ url: URL) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                items.filter { ["json", Self.fileExtension].contains($0.pathExtension.lowercased()) }.forEach(handle)
                return
            }
            guard let data = try? Data(contentsOf: url), let p = Self.decode(data) else {
                report.invalid.append(url.deletingPathExtension().lastPathComponent); return
            }
            let probe = Self.entry(url, p)
            if known.contains(probe.digest) { report.duplicates.append(p.name); return }
            guard let saved = try? save(p) else { report.invalid.append(p.name); return }
            known.insert(probe.digest)
            report.added.append(Self.entry(saved, p))
        }
        urls.forEach(handle)
        reload()
        lastImport = report
        return report
    }

    func delete(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
        reload()
    }

    func delete(_ list: [Entry]) {
        list.forEach { try? FileManager.default.removeItem(at: $0.url) }
        reload()
    }
}

/// Para "Guardar en Archivos…": copia los presets elegidos (uno = archivo, varios = carpeta).
struct PresetFilesExport: FileDocument {
    static var readableContentTypes: [UTType] { [.tonePreset, .folder] }
    let urls: [URL]

    init(urls: [URL]) { self.urls = urls }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }

    var contentType: UTType { urls.count == 1 ? .tonePreset : .folder }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if urls.count == 1 { return try FileWrapper(url: urls[0]) }
        var children: [String: FileWrapper] = [:]
        for u in urls {
            let w = try FileWrapper(url: u)
            w.preferredFilename = u.lastPathComponent
            children[u.lastPathComponent] = w
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    var defaultName: String {
        if urls.count == 1 { return urls[0].deletingPathExtension().lastPathComponent }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return "Presets TONE \(f.string(from: Date()))"
    }
}
