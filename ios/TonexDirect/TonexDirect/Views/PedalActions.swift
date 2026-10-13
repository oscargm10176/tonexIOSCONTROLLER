import SwiftUI

/// Elegir una posición del pedal (banco + A/B/C).
struct SlotPickerSheet: View {
    @Environment(ControllerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let title: String
    var exclude: Int? = nil
    let onPick: (Int) -> Void

    private var banks: [(bank: Int, presets: [Preset])] {
        Dictionary(grouping: store.presets, by: \.bank).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(banks, id: \.bank) { group in
                    Section("Banco " + String(format: "%02d", group.bank)) {
                        ForEach(group.presets) { p in
                            Button {
                                dismiss()
                                onPick(p.id)
                            } label: {
                                HStack {
                                    Text(p.slot).font(.callout.monospaced().weight(.bold)).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(p.name)
                                        if let info = store.toneModels[p.id] {
                                            Text(info.amp ?? info.model).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if p.id == store.currentPreset {
                                        Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(p.id == exclude)
                        }
                    }
                }
            }
            .navigationTitle(tr(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}

/// Botón "Guardar en el pedal" (lo que suena ahora queda guardado en su posición).
struct SaveToPedalButton: View {
    @Environment(ControllerStore.self) private var store
    @Environment(PresetLibrary.self) private var library
    @State private var confirming = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Button {
            confirming = true
        } label: {
            if busy { ProgressView() } else { Label("Guardar", systemImage: "square.and.arrow.down") }
        }
        .disabled(store.state != .ready || busy || store.currentPreset == nil)
        .confirmationDialog("¿Guardar en el pedal?", isPresented: $confirming, titleVisibility: .visible) {
            Button(trf("Guardar %@", store.currentPresetInfo.map { "\($0.label) · \($0.name)" } ?? "")) { save() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Los cambios de perillas y efectos de este preset quedan guardados en el pedal. Antes se guarda un respaldo en “Mis presets”.")
        }
        .alert("Guardar en el pedal", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private func save() {
        guard let c = store.currentPreset else { return }
        busy = true
        Task { @MainActor in
            if let backup = await store.makeBackup(of: c) { try? library.save(backup) }
            let r = await store.saveCurrentToPedal()
            library.reload()
            busy = false
            switch r {
            case .done: message = tr("Listo: guardado en el pedal.")
            case .failed(let why): message = why
            }
        }
    }
}
