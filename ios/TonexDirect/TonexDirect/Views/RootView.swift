import SwiftUI
import UIKit

/// Secciones de la columna derecha.
enum AppSection: String, CaseIterable, Identifiable {
    case stage, effects, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .stage: return "Escenario"
        case .effects: return "Efectos"
        case .settings: return "Ajustes"
        }
    }

    var systemImage: String {
        switch self {
        case .stage: return "music.note.list"
        case .effects: return "slider.horizontal.3"
        case .settings: return "gearshape"
        }
    }
}

/// Diseño de iPad: lista de presets a la izquierda, sección activa a la derecha.
/// En vertical la lista se oculta y se abre con el botón de la barra.
struct ContentView: View {
    @Environment(ControllerStore.self) private var store
    @State private var columns: NavigationSplitViewVisibility = .all

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
                        case .stage: StageView()
                        case .effects: EffectsView()
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
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// Columna izquierda: búsqueda y lista de presets con miniatura del amp.
struct PresetSidebar: View {
    @Environment(ControllerStore.self) private var store
    @State private var search = ""

    private var filtered: [Preset] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.presets }
        return store.presets.filter {
            $0.name.localizedCaseInsensitiveContains(q) || String($0.number) == q
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(filtered) { preset in
                PresetRow(preset: preset, isCurrent: preset.id == store.currentPreset)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UISelectionFeedbackGenerator().selectionChanged()
                        store.selectPreset(preset.id)
                    }
                    .listRowBackground(preset.id == store.currentPreset ? Color.orange.opacity(0.22) : Color.clear)
                    .id(preset.id)
            }
            .listStyle(.plain)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar preset")
            .navigationTitle("Presets")
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
            Text("\(preset.number)")
                .font(.callout.monospacedDigit().weight(.bold))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 36, alignment: .trailing)
            Image(AmpSkins.skin(store.skinIndex(for: preset.id)).asset)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 72, height: 26)
            Text(preset.name)
                .font(isCurrent ? .body.weight(.semibold) : .body)
                .lineLimit(1)
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
