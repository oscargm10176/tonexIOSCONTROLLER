import SwiftUI
import UniformTypeIdentifiers

/// Elegir presets y guardarlos en la ubicación que quieras (Archivos, iCloud, USB…).
/// Solo lee del pedal: no cambia nada.
struct SavePresetsSheet: View {
    @Environment(ControllerStore.self) private var store
    @Environment(PresetLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int>
    @State private var progress: (done: Int, total: Int)?
    @State private var failed: [String] = []
    @State private var result: String?
    @State private var showLibrary = false
    @State private var task: Task<Void, Never>?

    init(preselect: Set<Int> = []) {
        _selected = State(initialValue: preselect)
    }

    private var banks: [(bank: Int, presets: [Preset])] {
        Dictionary(grouping: store.presets, by: \.bank).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        quick("Actual") { store.currentPreset.map { selected = [$0] } }
                        quick("Este banco") {
                            if let c = store.currentPresetInfo {
                                selected = Set(store.presets.filter { $0.bank == c.bank }.map(\.id))
                            }
                        }
                        quick("Todos") { selected = Set(store.presets.map(\.id)) }
                        quick("Ninguno") { selected = [] }
                    }
                    .buttonStyle(.bordered)
                } footer: {
                    Text("Se guardan en este iPad, en “Mis presets” (también en Archivos › En mi iPad › TONE › Presets). Incluye nombre, valores y el Tone Model en crudo. Leer cada preset tarda alrededor de un segundo.")
                }

                ForEach(banks, id: \.bank) { group in
                    Section("Banco " + String(format: "%02d", group.bank)) {
                        ForEach(group.presets) { p in
                            Button {
                                if selected.contains(p.id) { selected.remove(p.id) } else { selected.insert(p.id) }
                            } label: {
                                HStack {
                                    Image(systemName: selected.contains(p.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(p.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                    Text(p.slot).font(.callout.monospaced().weight(.bold)).frame(width: 20)
                                    Text(p.name)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(progress != nil)
                        }
                    }
                }
            }
            .navigationTitle("Guardar presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { task?.cancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.count > 1 ? "Guardar \(selected.count)" : "Guardar") { start() }
                        .disabled(selected.isEmpty || progress != nil || store.state != .ready)
                }
            }
            .safeAreaInset(edge: .bottom) { statusBar }
            .sheet(isPresented: $showLibrary) { PresetLibraryView() }
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if let p = progress {
            VStack(spacing: 6) {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1))).tint(.orange)
                Text("Leyendo del pedal \(p.done) de \(p.total)…").font(.caption.monospacedDigit())
            }
            .padding().background(.bar)
        } else if let result {
            VStack(spacing: 6) {
                Text(result).font(.callout.weight(.semibold))
                Button("Ver mis presets") { showLibrary = true }
                    .buttonStyle(.bordered)
                if !failed.isEmpty {
                    Text("No respondieron: " + failed.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity).padding().background(.bar)
        }
    }

    private func quick(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action).disabled(progress != nil)
    }

    private func start() {
        let ids = selected.sorted()
        failed = []
        result = nil
        progress = (0, ids.count)
        task = Task { @MainActor in
            var saved = 0
            for (n, id) in ids.enumerated() {
                if Task.isCancelled { break }
                if let preset = await store.makeBackup(of: id), (try? library.save(preset)) != nil {
                    saved += 1
                } else if let p = store.presets.first(where: { $0.id == id }) {
                    failed.append(p.label)
                }
                progress = (n + 1, ids.count)
            }
            progress = nil
            library.reload()
            guard !Task.isCancelled else { return }
            result = saved == 0
                ? "El pedal no respondió. Revisa la conexión e intenta de nuevo."
                : (saved == 1 ? "Guardado en Mis presets" : "\(saved) presets guardados en Mis presets")
        }
    }
}

/// "Mis presets": los guardados en el iPad. Importar de fuera (Archivos, AirDrop, arrastrar),
/// exportar (compartir o guardar en Archivos, uno o varios), cargar al pedal y borrar.
struct PresetLibraryView: View {
    @Environment(PresetLibrary.self) private var library
    @Environment(ControllerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var selecting = false
    @State private var selection: Set<URL> = []
    @State private var importing = false
    @State private var exportDoc: PresetFilesExport?
    @State private var exporting = false
    @State private var loading: PresetLibrary.Entry?
    @State private var confirm: (entry: PresetLibrary.Entry, slot: Int)?
    @State private var confirmDelete: [PresetLibrary.Entry] = []
    @State private var busy = false
    @State private var message: String?
    @State private var dropTargeted = false

    private var filtered: [PresetLibrary.Entry] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return library.entries }
        return library.entries.filter {
            $0.name.localizedCaseInsensitiveContains(q) || ($0.model ?? "").localizedCaseInsensitiveContains(q)
                || ($0.amp ?? "").localizedCaseInsensitiveContains(q) || "\($0.bank)\($0.letter)".localizedCaseInsensitiveContains(q)
        }
    }

    private var selectedEntries: [PresetLibrary.Entry] { library.entries.filter { selection.contains($0.url) } }

    var body: some View {
        NavigationStack {
            List(selection: selecting ? $selection : nil) {
                if let report = library.lastImport {
                    Section {
                        importBanner(report)
                    }
                }
                if library.entries.isEmpty {
                    ContentUnavailableView {
                        Label("Aún no hay presets guardados", systemImage: "tray")
                    } description: {
                        Text("Guarda presets del pedal (mantén presionado uno en la lista › “Guardar preset…”), o trae archivos .tonepreset desde Archivos, AirDrop o arrastrándolos aquí.")
                    } actions: {
                        Button("Importar archivos…") { importing = true }.buttonStyle(.borderedProminent)
                    }
                }
                ForEach(filtered) { e in
                    row(e)
                        .tag(e.url)
                        .contextMenu { menu(for: e) }
                        .swipeActions {
                            Button("Borrar", role: .destructive) { confirmDelete = [e] }
                            ShareLink(item: e.url) { Label("Compartir", systemImage: "square.and.arrow.up") }.tint(.blue)
                        }
                }
            }
            .searchable(text: $search, prompt: "Buscar por nombre, amp o banco")
            .environment(\.editMode, .constant(selecting ? .active : .inactive))
            .navigationTitle("Mis presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .overlay(Label("Suelta aquí para importar", systemImage: "square.and.arrow.down").font(.headline))
                        .padding(8)
                        .allowsHitTesting(false)
                }
                if busy {
                    ProgressView("Cargando en el pedal…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                library.importFiles(urls)
                return true
            } isTargeted: { dropTargeted = $0 }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.tonePreset, .json, .folder],
                          allowsMultipleSelection: true) { r in
                if case .success(let urls) = r { library.importFiles(urls) }
            }
            .fileExporter(isPresented: $exporting, document: exportDoc,
                          contentType: exportDoc?.contentType ?? .tonePreset,
                          defaultFilename: exportDoc?.defaultName) { r in
                switch r {
                case .success(let url): message = "Guardado en “\(url.lastPathComponent)”."
                case .failure(let e): message = "No se guardó: \(e.localizedDescription)"
                }
                exportDoc = nil
                selecting = false; selection = []
            }
            .onAppear { library.reload() }
            .sheet(item: $loading) { e in
                SlotPickerSheet(title: "Cargar “\(e.name)” en…") { slot in confirm = (e, slot) }
            }
            .confirmationDialog("¿Reemplazar este preset del pedal?",
                                isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                                titleVisibility: .visible) {
                if let c = confirm {
                    Button("Reemplazar \(store.presets[c.slot].label) · \(store.presets[c.slot].name)", role: .destructive) {
                        load(c.entry, into: c.slot)
                    }
                }
                Button("Cancelar", role: .cancel) { confirm = nil }
            } message: {
                Text("Se carga el preset completo, con su Tone Model. Lo que hay ahora en esa posición se guarda antes en “Mis presets”.")
            }
            .confirmationDialog(confirmDelete.count == 1 ? "¿Borrar “\(confirmDelete.first?.name ?? "")”?" : "¿Borrar \(confirmDelete.count) presets?",
                                isPresented: Binding(get: { !confirmDelete.isEmpty }, set: { if !$0 { confirmDelete = [] } }),
                                titleVisibility: .visible) {
                Button("Borrar", role: .destructive) {
                    library.delete(confirmDelete); confirmDelete = []
                    selection = []; selecting = false
                }
            } message: { Text("Se borran solo de este iPad; el pedal no cambia.") }
            .alert("Mis presets", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
        }
    }

    // MARK: Partes

    private func row(_ e: PresetLibrary.Entry) -> some View {
        HStack(spacing: 12) {
            Text("\(e.bank) \(e.letter)")
                .font(.callout.monospaced().weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.body.weight(.semibold))
                HStack(spacing: 6) {
                    if let m = e.amp ?? e.model {
                        Text(m).lineLimit(1)
                        Text("·")
                    }
                    Text(e.savedAt.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !selecting {
                Button { loading = e } label: { Label("Cargar al pedal", systemImage: "square.and.arrow.up.on.square") }
                    .buttonStyle(.bordered)
                    .disabled(store.state != .ready || busy)
                ShareLink(item: e.url) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Compartir")
            }
        }
    }

    @ViewBuilder
    private func menu(for e: PresetLibrary.Entry) -> some View {
        Button { loading = e } label: { Label("Cargar al pedal…", systemImage: "square.and.arrow.up.on.square") }
            .disabled(store.state != .ready)
        ShareLink(item: e.url) { Label("Compartir…", systemImage: "square.and.arrow.up") }
        Button { export([e]) } label: { Label("Guardar en Archivos…", systemImage: "folder") }
        Divider()
        Button(role: .destructive) { confirmDelete = [e] } label: { Label("Borrar", systemImage: "trash") }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button { importing = true } label: { Label("Desde Archivos…", systemImage: "folder") }
                Text("También puedes abrir un .tonepreset desde Archivos, AirDrop o Mail, o arrastrarlo a esta lista.")
            } label: {
                Label("Importar", systemImage: "square.and.arrow.down")
            }
        }
        ToolbarItemGroup(placement: .confirmationAction) {
            if !library.entries.isEmpty {
                Button(selecting ? "Cancelar" : "Seleccionar") {
                    selecting.toggle(); selection = []
                }
            }
            if !selecting { Button("Listo") { dismiss() } }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Button(selection.count == library.entries.count ? "Ninguno" : "Todos") {
                selection = selection.count == library.entries.count ? [] : Set(library.entries.map(\.url))
            }
            Spacer()
            Text(selection.isEmpty ? "Elige presets" : "\(selection.count) seleccionados")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            ShareLink(items: selectedEntries.map(\.url)) { Label("Compartir", systemImage: "square.and.arrow.up") }
                .disabled(selection.isEmpty)
            Button { export(selectedEntries) } label: { Label("Guardar en Archivos", systemImage: "folder") }
                .disabled(selection.isEmpty)
            Button(role: .destructive) { confirmDelete = selectedEntries } label: { Image(systemName: "trash") }
                .disabled(selection.isEmpty)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal).padding(.vertical, 10)
        .background(.bar)
    }

    private func importBanner(_ r: PresetLibrary.ImportReport) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: r.added.isEmpty ? "info.circle" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(r.added.isEmpty ? Color.secondary : Color.green)
            VStack(alignment: .leading, spacing: 8) {
                Text(r.summary).font(.callout)
                if r.added.count == 1, let e = r.added.first {
                    Button { loading = e } label: { Label("Cargar al pedal…", systemImage: "square.and.arrow.up.on.square") }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.state != .ready)
                }
            }
            Spacer()
            Button { library.lastImport = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Cerrar aviso")
        }
    }

    private func export(_ list: [PresetLibrary.Entry]) {
        guard !list.isEmpty else { return }
        exportDoc = PresetFilesExport(urls: list.map(\.url))
        exporting = true
    }

    private func load(_ e: PresetLibrary.Entry, into slot: Int) {
        confirm = nil
        guard let saved = library.load(e) else { message = "No pude abrir ese archivo."; return }
        busy = true
        Task { @MainActor in
            if let backup = await store.makeBackup(of: slot) { try? library.save(backup) }
            let r = await store.loadPreset(saved, into: slot)
            library.reload()
            busy = false
            switch r {
            case .done: message = "Listo: “\(saved.name)” quedó en \(store.presets[slot].label)."
            case .failed(let why): message = why
            }
        }
    }
}
