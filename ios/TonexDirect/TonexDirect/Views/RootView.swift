import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Secciones de la columna derecha.
enum AppSection: String, CaseIterable, Identifiable {
    case edit, live, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit: return tr("Editar")
        case .live: return "Live"
        case .settings: return tr("Ajustes")
        }
    }

    var systemImage: String {
        switch self {
        case .edit: return "slider.horizontal.3"
        case .live: return "music.mic"
        case .settings: return "gearshape"
        }
    }
}

/// Diseño de iPad: lista de presets a la izquierda, sección activa a la derecha.
/// En vertical la lista se oculta y se abre con el botón de la barra.
struct ContentView: View {
    @Environment(ControllerStore.self) private var store
    @Environment(PresetLibrary.self) private var library
    @State private var columns: NavigationSplitViewVisibility = .all
    /// El usuario eligió entrar sin esperar al pedal.
    @State private var skippedLoading = false

    private var showLoading: Bool { !store.hasBeenReady && !skippedLoading }

    var body: some View {
        @Bindable var store = store

        NavigationSplitView(columnVisibility: $columns) {
            PresetSidebar()
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
        } detail: {
            NavigationStack {
                VStack(spacing: 0) {
                    if store.state != .ready {
                        ConnectionBanner()
                    }
                    Group {
                        switch store.section {
                        case .edit: EditView()
                        case .live: LiveView()
                        case .settings: SettingsView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Sección", selection: $store.section) {
                            ForEach(AppSection.allCases) { s in
                                Label(s.title, systemImage: s.systemImage).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 380)
                    }
                    if store.section == .edit {
                        ToolbarItem(placement: .topBarLeading) { SaveToPedalButton() }
                    }
                    // Tempo a la altura de las pestañas (en Editar y Live).
                    if store.tempoAvailable && store.section != .settings {
                        ToolbarItem(placement: .topBarTrailing) {
                            TempoBar()
                        }
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        // En Live se esconde la lista de presets para no tocarla por accidente.
        .onAppear { columns = store.section == .live ? .detailOnly : .all }
        .onChange(of: store.section) { _, section in
            withAnimation(.snappy) { columns = section == .live ? .detailOnly : .all }
        }
        .sheet(isPresented: $store.showAdvanced) {
            AdvancedSheet()
        }
        .sheet(isPresented: Bindable(library).wantsToShow) {
            PresetLibraryView()
        }
        // Pantalla de carga hasta la primera sincronización completa.
        .overlay {
            if showLoading {
                LoadingView(onSkip: { skippedLoading = true })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: showLoading)
    }
}

/// Columna izquierda: búsqueda y lista de presets con miniatura del amp.
struct PresetSidebar: View {
    @Environment(ControllerStore.self) private var store
    @State private var search = ""
    @State private var pickingFor: Int?
    @State private var savingFor: Int?
    @Environment(PresetLibrary.self) private var library
    @State private var renamingFor: Int?
    @State private var newName = ""
    @State private var renaming = false
    @State private var renameMessage: String?
    @State private var swappingFrom: Int?
    // Exportar / importar desde el menú del preset
    @State private var exportReady: ExportReady?
    @State private var importTarget: Int?
    @State private var importingFile = false
    @State private var libraryPickFor: Int?
    @State private var pendingLoad: (preset: SavedPreset, slot: Int)?

    private var filtered: [Preset] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.presets }
        let compact = q.replacingOccurrences(of: " ", with: "").uppercased()
        return store.presets.filter {
            $0.name.localizedCaseInsensitiveContains(q) || String($0.number) == q
                || $0.label.replacingOccurrences(of: " ", with: "") == compact   // "01B"
                || String($0.bank) + $0.slot == compact                          // "1B"
        }
    }

    /// Presets agrupados por banco, en orden.
    private var banks: [(bank: Int, presets: [Preset])] {
        Dictionary(grouping: filtered, by: \.bank)
            .sorted { $0.key < $1.key }
            .map { (bank: $0.key, presets: $0.value) }
    }

    private func rename(_ id: Int, to name: String) {
        renaming = true
        Task { @MainActor in
            // Respaldo del preset tal como está, por si acaso.
            if let backup = await store.makeBackup(of: id) { try? library.save(backup) }
            let result = await store.renamePreset(id, to: name)
            library.reload()
            renaming = false
            switch result {
            case .done: renameMessage = trf("Listo: el preset ahora se llama “%@” en el pedal.", name.trimmingCharacters(in: .whitespaces))
            case .failed(let why): renameMessage = why
            }
        }
    }

    /// Lee el preset del pedal y ofrece compartirlo o guardarlo en Archivos.
    private func exportPreset(_ id: Int) {
        renaming = true
        Task { @MainActor in
            defer { renaming = false }
            guard let saved = await store.makeBackup(of: id), let data = try? saved.encoded() else {
                renameMessage = tr("El pedal no respondió; intenta de nuevo."); return
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(saved.fileName)
            do { try data.write(to: url, options: .atomic) } catch {
                renameMessage = tr("No pude preparar el archivo."); return
            }
            try? library.save(saved)            // y una copia en "Mis presets"
            library.reload()
            exportReady = ExportReady(url: url, name: saved.name, label: store.presets[id].label)
        }
    }

    private func importInto(_ p: SavedPreset, slot: Int) {
        pendingLoad = nil
        renaming = true
        Task { @MainActor in
            if let backup = await store.makeBackup(of: slot) { try? library.save(backup) }
            let r = await store.loadPreset(p, into: slot)
            library.reload()
            renaming = false
            switch r {
            case .done: renameMessage = trf("Listo: “%@” quedó en %@.", p.name, store.presets[slot].label)
            case .failed(let why): renameMessage = why
            }
        }
    }

    private func swap(_ a: Int, _ b: Int) {
        renaming = true
        Task { @MainActor in
            for id in [a, b] { if let backup = await store.makeBackup(of: id) { try? library.save(backup) } }
            let result = await store.swapPresets(a, b)
            library.reload()
            renaming = false
            switch result {
            case .done: renameMessage = trf("Listo: se intercambiaron %@ y %@.", store.presets[a].label, store.presets[b].label)
            case .failed(let why): renameMessage = why
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(banks, id: \.bank) { group in
                    Section {
                        ForEach(group.presets) { preset in
                            PresetRow(preset: preset, isCurrent: preset.id == store.currentPreset)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    store.selectPreset(preset.id)
                                }
                                .listRowBackground(preset.id == store.currentPreset ? Color.orange.opacity(0.22) : Color.clear)
                                .contextMenu {
                                    Button { pickingFor = preset.id } label: { Label("Elegir imagen…", systemImage: "photo") }
                                    Section {
                                        Button { exportPreset(preset.id) } label: {
                                            Label("Exportar…", systemImage: "square.and.arrow.up")
                                        }
                                        .disabled(store.state != .ready || renaming)
                                        Menu {
                                            Button {
                                                importTarget = preset.id
                                                importingFile = true
                                            } label: { Label("Desde Archivos…", systemImage: "folder") }
                                            Button { libraryPickFor = preset.id } label: {
                                                Label("Desde Mis presets…", systemImage: "tray.full")
                                            }
                                            .disabled(library.entries.isEmpty)
                                        } label: {
                                            Label("Importar aquí", systemImage: "square.and.arrow.down")
                                        }
                                        .disabled(store.state != .ready || renaming)
                                        Button { savingFor = preset.id } label: { Label("Guardar en Mis presets…", systemImage: "tray.and.arrow.down") }
                                            .disabled(store.state != .ready)
                                    }
                                    Button {
                                        newName = preset.name
                                        renamingFor = preset.id
                                    } label: { Label("Renombrar en el pedal…", systemImage: "character.cursor.ibeam") }
                                        .disabled(store.state != .ready || renaming)
                                    Button { swappingFrom = preset.id } label: {
                                        Label("Intercambiar con…", systemImage: "arrow.left.arrow.right")
                                    }
                                    .disabled(store.state != .ready || renaming)
                                    if store.chosenSkin(for: preset.id) != nil {
                                        Button(role: .destructive) { store.clearSkin(for: preset.id) } label: {
                                            Label("Quitar imagen", systemImage: "trash")
                                        }
                                    }
                                }
                                .id(preset.id)
                        }
                    } header: {
                        BankHeader(bank: group.bank,
                                   isCurrent: store.currentPresetInfo?.bank == group.bank)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar preset")
            .navigationTitle("Presets")
            .sheet(item: Binding(get: { pickingFor.map(PickTarget.init) }, set: { pickingFor = $0?.id })) { target in
                SkinPickerSheet(presetID: target.id)
            }
            .sheet(item: Binding(get: { savingFor.map(PickTarget.init) }, set: { savingFor = $0?.id })) { target in
                SavePresetsSheet(preselect: [target.id])
            }
            .alert("Renombrar en el pedal", isPresented: Binding(get: { renamingFor != nil }, set: { if !$0 { renamingFor = nil } })) {
                TextField("Nombre", text: $newName)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Cancelar", role: .cancel) { renamingFor = nil }
                Button("Renombrar") {
                    if let id = renamingFor { rename(id, to: newName) }
                    renamingFor = nil
                }
            } message: {
                Text(trf("Se guarda directo en el pedal. Antes se hace un respaldo en “Mis presets”. Máximo %@ caracteres, sin acentos ni ñ. Si es el preset que suena, también se guardan los cambios de perillas que tengas.", TonexPedal.nameLength))
            }
            .sheet(item: Binding(get: { swappingFrom.map(PickTarget.init) }, set: { swappingFrom = $0?.id })) { from in
                SlotPickerSheet(title: trf("Intercambiar %@ con…", store.presets[from.id].label), exclude: from.id) { to in
                    swap(from.id, to)
                }
            }
            .sheet(item: $exportReady) { ready in
                ExportReadySheet(ready: ready)
                    .presentationDetents([.height(260)])
            }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.tonePreset, .json]) { r in
                guard case .success(let url) = r, let slot = importTarget else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
                guard let data = try? Data(contentsOf: url), let p = try? d.decode(SavedPreset.self, from: data) else {
                    renameMessage = tr("Ese archivo no es un preset de TONE."); return
                }
                library.importFiles([url])          // también queda en "Mis presets"
                library.lastImport = nil
                pendingLoad = (p, slot)
            }
            .sheet(item: Binding(get: { libraryPickFor.map(PickTarget.init) }, set: { libraryPickFor = $0?.id })) { target in
                LibraryPickerSheet { entry in
                    if let p = library.load(entry) { pendingLoad = (p, target.id) }
                }
            }
            .confirmationDialog("¿Reemplazar este preset del pedal?",
                                isPresented: Binding(get: { pendingLoad != nil }, set: { if !$0 { pendingLoad = nil } }),
                                titleVisibility: .visible) {
                if let pl = pendingLoad {
                    Button(trf("Cargar “%@” en %@", pl.preset.name, store.presets[pl.slot].label), role: .destructive) {
                        importInto(pl.preset, slot: pl.slot)
                    }
                }
                Button("Cancelar", role: .cancel) { pendingLoad = nil }
            } message: {
                if let pl = pendingLoad {
                    Text(trf("Se reemplaza “%@” por el preset completo, con su Tone Model. Lo de ahora se guarda antes en “Mis presets”.", store.presets[pl.slot].name))
                }
            }
            .alert("Renombrar", isPresented: Binding(get: { renameMessage != nil }, set: { if !$0 { renameMessage = nil } })) {
                Button("OK", role: .cancel) { renameMessage = nil }
            } message: {
                Text(renameMessage ?? "")
            }
            .overlay {
                if renaming {
                    ProgressView("Hablando con el pedal…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .onChange(of: store.currentPreset) { _, new in
                guard let new, search.isEmpty else { return }
                withAnimation(.snappy) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }
}

struct PresetRow: View {
    @Environment(ControllerStore.self) private var store
    let preset: Preset
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(preset.slot)
                .font(.callout.monospacedDigit().weight(.bold))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 22, alignment: .center)
            SkinThumbnail(presetID: preset.id)
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name)
                    .font(isCurrent ? .body.weight(.semibold) : .body)
                    .lineLimit(1)
                if let info = store.toneModels[preset.id] {
                    Text(info.amp ?? info.model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Encabezado de cada banco en la lista ("BANCO 01"), fijo arriba al desplazarse.
struct BankHeader: View {
    let bank: Int
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%02d", bank))
                .font(.title3.weight(.heavy).monospacedDigit())
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            Text("BANCO")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trf("Banco %@", bank))
        .accessibilityAddTraits(.isHeader)
    }
}

/// Envoltorio Identifiable para abrir la galería desde la lista.
private struct PickTarget: Identifiable { let id: Int }


/// Archivo listo para salir de la app.
struct ExportReady: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let label: String
}

/// Hoja corta tras exportar: compartir (AirDrop, Mail…) o guardar en Archivos.
struct ExportReadySheet: View {
    @Environment(\.dismiss) private var dismiss
    let ready: ExportReady
    @State private var saving = false
    @State private var savedTo: String?

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.arrow.up").font(.largeTitle).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ready.name).font(.headline)
                    Text("\(ready.label) · \(ready.url.lastPathComponent)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                ShareLink(item: ready.url) {
                    Label("Compartir…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { saving = true } label: {
                    Label("Guardar en Archivos…", systemImage: "folder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            Text(savedTo.map { trf("Guardado en “%@”.", $0) } ?? tr("También quedó una copia en “Mis presets”."))
                .font(.caption).foregroundStyle(.secondary)
            Button("Listo") { dismiss() }
        }
        .padding(24)
        .fileExporter(isPresented: $saving, document: PresetFilesExport(urls: [ready.url]),
                      contentType: .tonePreset, defaultFilename: ready.url.deletingPathExtension().lastPathComponent) { r in
            if case .success(let url) = r { savedTo = url.deletingLastPathComponent().lastPathComponent }
        }
    }
}

/// Elegir un preset de "Mis presets".
struct LibraryPickerSheet: View {
    @Environment(PresetLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    let onPick: (PresetLibrary.Entry) -> Void
    @State private var search = ""

    private var filtered: [PresetLibrary.Entry] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? library.entries : library.entries.filter {
            $0.name.localizedCaseInsensitiveContains(q) || ($0.amp ?? $0.model ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { e in
                Button {
                    dismiss()
                    onPick(e)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.name).font(.body.weight(.semibold))
                        Text([e.amp ?? e.model, e.savedAt.formatted(date: .abbreviated, time: .shortened)]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, prompt: "Buscar")
            .navigationTitle("Elegir de Mis presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}
