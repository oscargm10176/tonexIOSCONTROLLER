import SwiftUI
import UniformTypeIdentifiers

/// Exporta una carpeta tal cual (el respaldo completo) a donde elijas: iCloud Drive, En mi iPad…
struct FolderExport: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    let url: URL
    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try FileWrapper(url: url) }
}

/// Respaldo completo del pedal en un toque: los 150 presets (con su Tone Model) en una carpeta.
/// Queda en el iPad (Archivos › En mi iPad › TONE › Respaldos) y se puede guardar en iCloud.
struct FullBackupSheet: View {
    @Environment(ControllerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var running: Task<Void, Never>?
    @State private var done = 0
    @State private var total = 0
    @State private var currentName = ""
    @State private var failed: [String] = []
    @State private var result: URL?
    @State private var backups: [URL] = []
    @State private var exportURL: URL?
    @State private var exporting = false
    @State private var message: String?

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Respaldos", isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if running != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: Double(done), total: Double(max(total, 1))).tint(.orange)
                            Text("Leyendo \(done) de \(total)… \(currentName)")
                                .font(.callout.monospacedDigit())
                                .lineLimit(1)
                            Text("Deja el pedal conectado. Puedes seguir tocando; no se cambia nada en el pedal.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Button("Cancelar", role: .destructive) { running?.cancel() }
                    } else if let result {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Respaldo listo: \(done) presets", systemImage: "checkmark.circle.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text(result.lastPathComponent).font(.caption.monospaced()).foregroundStyle(.secondary)
                            if !failed.isEmpty {
                                Text("No respondieron: " + failed.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Button { export(result) } label: {
                            Label("Guardar en iCloud Drive / Archivos…", systemImage: "icloud.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button { start() } label: {
                            Label("Respaldar los \(store.presets.count) presets", systemImage: "externaldrive.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.state != .ready)
                    }
                } footer: {
                    Text("Cada preset se guarda completo (nombre, perillas y Tone Model) como .tonepreset. La carpeta también queda en este iPad, en Archivos › En mi iPad › TONE › Respaldos. Tarda alrededor de un minuto.")
                }

                if !backups.isEmpty {
                    Section("Respaldos anteriores") {
                        ForEach(backups, id: \.self) { url in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                    Text("\(count(url)) presets").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { export(url) } label: { Image(systemName: "icloud.and.arrow.up") }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Guardar en Archivos")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Respaldo completo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { running?.cancel(); dismiss() }
                }
            }
            .interactiveDismissDisabled(running != nil)
            .onAppear(perform: reloadBackups)
            .fileExporter(isPresented: $exporting, document: exportURL.map(FolderExport.init),
                          contentType: .folder, defaultFilename: exportURL?.lastPathComponent) { r in
                switch r {
                case .success(let url): message = "Guardado en “\(url.deletingLastPathComponent().lastPathComponent)”."
                case .failure(let e): message = "No se guardó: \(e.localizedDescription)"
                }
            }
            .alert("Respaldo", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
    }

    private func export(_ url: URL) {
        exportURL = url
        exporting = true
    }

    private func count(_ url: URL) -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
            .filter { $0.hasSuffix("." + PresetLibrary.fileExtension) }.count
    }

    private func reloadBackups() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        backups = urls.filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func start() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
        let folder = Self.folder.appendingPathComponent("Respaldo TONE \(f.string(from: Date()))", isDirectory: true)
        let ids = store.presets.map(\.id)
        done = 0; total = ids.count; failed = []; result = nil
        running = Task { @MainActor in
            defer { running = nil; reloadBackups() }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                message = "No pude crear la carpeta del respaldo."; return
            }
            var index: [[String: String]] = []
            for id in ids {
                if Task.isCancelled { break }
                currentName = store.presets[id].name
                if let saved = await store.makeBackup(of: id), let data = try? saved.encoded() {
                    let url = folder.appendingPathComponent(saved.fileName)
                    if (try? data.write(to: url, options: .atomic)) != nil {
                        index.append(["posicion": "\(saved.bank) \(saved.letter)", "nombre": saved.name, "archivo": saved.fileName])
                    } else {
                        failed.append(store.presets[id].label)
                    }
                } else {
                    failed.append(store.presets[id].label)
                }
                done += 1
            }
            // Índice legible con lo que hay en cada posición.
            let lines = index.map { "\($0["posicion"]!)\t\($0["nombre"]!)" }.joined(separator: "\n")
            try? ("Respaldo de TONE — \(f.string(from: Date()))\n\n" + lines + "\n")
                .write(to: folder.appendingPathComponent("Indice.txt"), atomically: true, encoding: .utf8)
            if Task.isCancelled {
                message = "Respaldo cancelado. Lo leído hasta ahora (\(index.count) presets) quedó en la carpeta."
            }
            result = folder
            done = index.count
        }
    }
}
