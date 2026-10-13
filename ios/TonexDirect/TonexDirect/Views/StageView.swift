import SwiftUI
import UIKit

/// Vista principal para tocar en vivo: preset actual grande, botones anterior/siguiente
/// y lista de presets con búsqueda.
struct StageView: View {
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
        NavigationStack {
            VStack(spacing: 16) {
                PresetHeroCard()
                navigationButtons
                presetList
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .navigationTitle(store.modeller?.displayName ?? "Tonex")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.supports(TonexParam.bypass) {
                    ToolbarItem(placement: .topBarTrailing) {
                        BypassButton()
                    }
                }
            }
        }
    }

    private var currentPresetCard: some View {
        VStack(spacing: 4) {
            Text(store.currentPresetInfo.map { "\($0.number)" } ?? "–")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(store.currentPresetInfo?.name ?? "Sin preset")
                .font(.title2.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.06)))
        .animation(.snappy, value: store.currentPreset)
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            BigButton(systemImage: "chevron.left", title: "Anterior") { store.previousPreset() }
            BigButton(systemImage: "chevron.right", title: "Siguiente") { store.nextPreset() }
        }
        .disabled(store.state != .ready)
    }

    private var presetList: some View {
        VStack(spacing: 8) {
            TextField("Buscar preset", text: $search)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            ScrollViewReader { proxy in
                List(filtered) { preset in
                    Button {
                        store.selectPreset(preset.id)
                    } label: {
                        HStack {
                            Text("\(preset.number)")
                                .font(.body.monospacedDigit().weight(.bold))
                                .frame(width: 44, alignment: .leading)
                                .foregroundStyle(.secondary)
                            Image(AmpSkins.skin(store.skinIndex(for: preset.id)).asset)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: 84, height: 28)
                            Text(preset.name)
                                .lineLimit(1)
                            Spacer()
                            if preset.id == store.currentPreset {
                                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(preset.id == store.currentPreset ? Color.orange.opacity(0.18) : nil)
                    .id(preset.id)
                }
                .listStyle(.plain)
                .onChange(of: store.currentPreset) { _, new in
                    guard let new, search.isEmpty else { return }
                    withAnimation { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
    }
}

struct BigButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 30, weight: .bold))
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 88)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 18))
    }
}

struct BypassButton: View {
    @Environment(ControllerStore.self) private var store

    var body: some View {
        let on = store.isOn(TonexParam.bypass)
        Button {
            store.setToggle(TonexParam.bypass, !on)
        } label: {
            Label(on ? "Bypass" : "Activo", systemImage: on ? "power.circle" : "power.circle.fill")
                .labelStyle(.titleAndIcon)
        }
        .tint(on ? .red : .green)
        .disabled(store.state != .ready)
    }
}
