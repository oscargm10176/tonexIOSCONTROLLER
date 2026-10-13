import SwiftUI

/// Sección de Ajustes con los setlists.
struct SetlistsSection: View {
    @Environment(SetlistStore.self) private var setlists
    @State private var editing: Setlist?
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        Section {
            ForEach(setlists.setlists) { s in
                Button { editing = s } label: {
                    HStack {
                        Image(systemName: setlists.activeID == s.id ? "music.note.list" : "list.bullet")
                            .foregroundStyle(setlists.activeID == s.id ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        Text(s.name)
                        Spacer()
                        Text(trf("%@ canciones", s.songs.count)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { idx in idx.map { setlists.setlists[$0].id }.forEach(setlists.delete) }
            .onMove { setlists.moveSetlists(from: $0, to: $1) }
            Button { newName = ""; naming = true } label: { Label("Nuevo setlist", systemImage: "plus.circle") }
                // Las hojas van en UNA sola fila fija: si se ponen en la Section, SwiftUI las
                // repite en cada fila y al abrir otra hoja encima (nueva canción) se cierra todo.
                .alert("Nuevo setlist", isPresented: $naming) {
                    TextField("Nombre (p. ej. Show viernes)", text: $newName)
                    Button("Cancelar", role: .cancel) {}
                    Button("Crear") { editing = setlists.create(named: newName.trimmingCharacters(in: .whitespaces)) }
                }
                .sheet(item: $editing) { s in SetlistEditor(setlistID: s.id) }
        } header: {
            Text("Setlists")
        } footer: {
            Text("Tus canciones en orden, cada una con su preset (y tempo, si quieres). En Live eliges el setlist y las flechas o el pedal pasan de canción en canción.")
        }
    }
}

/// Editar un setlist: nombre, canciones (agregar, reordenar, borrar).
struct SetlistEditor: View {
    @Environment(SetlistStore.self) private var setlists
    @Environment(ControllerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let setlistID: UUID
    @State private var draft = Setlist(name: "")
    @State private var songEditing: Song?
    @State private var addingSong = false

    var body: some View {
        NavigationStack {
            List {
                Section("Nombre") {
                    TextField("Nombre", text: $draft.name)
                }
                Section {
                    ForEach(Array(draft.songs.enumerated()), id: \.element.id) { i, song in
                        Button { songEditing = song } label: {
                            HStack(spacing: 12) {
                                Text("\(i + 1)").font(.callout.monospacedDigit().weight(.bold)).foregroundStyle(.tint).frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title).font(.body.weight(.semibold))
                                    Text(presetText(song)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let bpm = song.bpm { Text("\(bpm) BPM").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { draft.songs.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.songs.remove(atOffsets: $0) }
                    Button { addingSong = true } label: { Label("Agregar canción", systemImage: "plus.circle") }
                } header: {
                    Text("Canciones")
                } footer: {
                    Text("Toca “Edit” para reordenar; desliza una canción para borrarla.")
                }
            }
            .navigationTitle(draft.name.isEmpty ? "Setlist" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { draft.name = "Setlist" }
                        setlists.update(draft); dismiss()
                    }
                }
            }
            .onAppear { if draft.songs.isEmpty, draft.name.isEmpty, let s = setlists.setlists.first(where: { $0.id == setlistID }) { draft = s } }
            .interactiveDismissDisabled()   // que un deslizón no tire lo que estás armando
            .sheet(isPresented: $addingSong) {
                SongEditor(song: Song(title: "", slot: store.currentPreset ?? 0, bpm: nil)) { draft.songs.append($0) }
            }
            .sheet(item: $songEditing) { song in
                SongEditor(song: song) { updated in
                    if let i = draft.songs.firstIndex(where: { $0.id == updated.id }) { draft.songs[i] = updated }
                }
            }
        }
    }

    private func presetText(_ s: Song) -> String {
        guard store.presets.indices.contains(s.slot) else { return "Preset \(s.slot + 1)" }
        let p = store.presets[s.slot]
        return "\(p.label) · \(p.name)"
    }
}

/// Una canción: título, preset y tempo opcional.
struct SongEditor: View {
    @Environment(ControllerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var song: Song
    let onSave: (Song) -> Void
    @State private var picking = false
    @State private var useBPM = false
    @State private var bpm = 120

    var body: some View {
        NavigationStack {
            Form {
                Section("Canción") {
                    TextField("Título", text: $song.title)
                }
                Section("Preset") {
                    Button { picking = true } label: {
                        HStack {
                            if store.presets.indices.contains(song.slot) {
                                let p = store.presets[song.slot]
                                Text(p.label).font(.callout.monospaced().weight(.bold)).foregroundStyle(.tint)
                                Text(p.name)
                            } else {
                                Text("Elegir preset")
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Section {
                    Toggle("Fijar tempo al llegar a esta canción", isOn: $useBPM)
                    if useBPM {
                        Stepper(value: $bpm, in: 40...240) {
                            Text("\(bpm) BPM").monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle(song.title.isEmpty ? "Canción" : song.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        if song.title.trimmingCharacters(in: .whitespaces).isEmpty {
                            song.title = store.presets.indices.contains(song.slot) ? store.presets[song.slot].name : "Canción"
                        }
                        song.bpm = useBPM ? bpm : nil
                        onSave(song); dismiss()
                    }
                }
            }
            .onAppear {
                useBPM = song.bpm != nil
                bpm = song.bpm ?? (store.tempoAvailable ? store.bpm : 120)
            }
            .sheet(isPresented: $picking) {
                SlotPickerSheet(title: "Preset para la canción") { song.slot = $0 }
            }
        }
    }
}
