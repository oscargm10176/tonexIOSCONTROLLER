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
    // Restaurar
    @State private var restoreCandidate: URL?
    @State private var importingFolder = false
    @State private var mode = "Leyendo"

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
                            Text(trf("%@ %@ de %@…", tr(mode), done, total) + " " + currentName)
                                .font(.callout.monospacedDigit())
                                .lineLimit(1)
                            Text("Deja el pedal conectado. Puedes seguir tocando; no se cambia nada en el pedal.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Button("Cancelar", role: .destructive) { running?.cancel() }
                    } else if let result {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(mode == "Restaurando" ? trf("Restaurados: %@ presets", done) : trf("Respaldo listo: %@ presets", done), systemImage: "checkmark.circle.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text(result.lastPathComponent).font(.caption.monospaced()).foregroundStyle(.secondary)
                            if !failed.isEmpty {
                                Text("No respondieron: " + failed.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        if mode != "Restaurando" {
                            Button { export(result) } label: {
                                Label("Guardar en iCloud Drive / Archivos…", systemImage: "icloud.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button("Listo") { self.result = nil }
                    } else {
                        Button { start() } label: {
                            Label(trf("Respaldar los %@ presets", store.presets.count), systemImage: "externaldrive.badge.plus")
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
                                    Text(trf("%@ presets", count(url))).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { restoreCandidate = url } label: {
                                    Label("Restaurar", systemImage: "arrow.counterclockwise")
                                }
                                .buttonStyle(.bordered)
                                .disabled(store.state != .ready || running != nil)
                                Button { export(url) } label: { Image(systemName: "icloud.and.arrow.up") }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Guardar en Archivos")
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if running == nil {
                    Button { importingFolder = true } label: {
                        Label("Restaurar desde iCloud / Archivos…", systemImage: "folder.badge.gearshape")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.state != .ready)
                    .padding()
                    .background(.bar)
                }
            }
            .fileImporter(isPresented: $importingFolder, allowedContentTypes: [.folder]) { r in
                if case .success(let url) = r { restoreCandidate = url }
            }
            .confirmationDialog("¿Restaurar este respaldo en el pedal?",
                                isPresented: Binding(get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } }),
                                titleVisibility: .visible) {
                if let url = restoreCandidate {
                    Button("Respaldar lo actual y restaurar", role: .destructive) { restore(url, backupFirst: true) }
                    Button("Restaurar sin respaldar", role: .destructive) { restore(url, backupFirst: false) }
                }
                Button("Cancelar", role: .cancel) { restoreCandidate = nil }
            } message: {
                Text("Cada preset del respaldo se escribe en su posición original, con su Tone Model, y reemplaza lo que haya ahí. Recomendado: respaldar antes lo que tiene el pedal ahora (tarda un minuto más).")
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
                case .success(let url): message = trf("Guardado en “%@”.", url.deletingLastPathComponent().lastPathComponent)
                case .failure(let e): message = trf("No se guardó: %@", e.localizedDescription)
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

    /// Escribe en el pedal todos los presets de una carpeta de respaldo, cada uno en su posición.
    private func restore(_ folder: URL, backupFirst: Bool) {
        restoreCandidate = nil
        // Leer todo primero (la carpeta puede venir de iCloud con acceso temporal).
        let access = folder.startAccessingSecurityScopedResource()
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["json", PresetLibrary.fileExtension].contains($0.pathExtension.lowercased()) }
        let presets = files.compactMap { (try? Data(contentsOf: $0)).flatMap { try? d.decode(SavedPreset.self, from: $0) } }
            .filter { store.presets.indices.contains($0.slot) }
            .sorted { $0.slot < $1.slot }
        if access { folder.stopAccessingSecurityScopedResource() }
        guard !presets.isEmpty else { message = tr("Esa carpeta no tiene presets de TONE."); return }

        running = Task { @MainActor in
            defer { running = nil; reloadBackups() }
            if backupFirst {
                mode = "Respaldando lo actual"
                await runBackup()
                if Task.isCancelled { return }
            }
            mode = "Restaurando"
            done = 0; total = presets.count; failed = []
            for p in presets {
                if Task.isCancelled { break }
                currentName = "\(p.bank) \(p.letter) · \(p.name)"
                if await store.loadPreset(p, into: p.slot) != .done { failed.append("\(p.bank)\(p.letter)") }
                done += 1
            }
            result = folder
            if Task.isCancelled { message = trf("Restauración detenida: se escribieron %@ de %@.", done, total) }
        }
    }

    private func start() {
        mode = "Leyendo"
        running = Task { @MainActor in
            defer { running = nil; reloadBackups() }
            await runBackup()
        }
    }

    /// Lee los 150 presets a una carpeta nueva de Respaldos.
    @MainActor private func runBackup() async {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
        let folder = Self.folder.appendingPathComponent("Respaldo TONE \(f.string(from: Date()))", isDirectory: true)
        let ids = store.presets.map(\.id)
        done = 0; total = ids.count; failed = []; result = nil
        do {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                message = tr("No pude crear la carpeta del respaldo."); return
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
            try? (trf("Respaldo de TONE — %@", f.string(from: Date())) + "\n\n" + lines + "\n")
                .write(to: folder.appendingPathComponent("Indice.txt"), atomically: true, encoding: .utf8)
            if Task.isCancelled {
                message = trf("Respaldo cancelado. Lo leído hasta ahora (%@ presets) quedó en la carpeta.", index.count)
            }
            result = folder
            done = index.count
        }
    }
}
