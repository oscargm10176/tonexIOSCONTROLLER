import SwiftUI

/// Imágenes de amplificadores y pedales ("skins"), en el mismo orden que `enum Skins`
/// de `source/main/control.h`. Igual que en el firmware, el pedal no dice qué imagen usar:
/// se elige por preset y se guarda en el iPad.
///
/// Las imágenes son de IK Multimedia (vienen del repo TonexOneController): solo para uso
/// personal, no las distribuyas.
struct AmpSkin: Identifiable, Hashable {
    let id: Int
    let asset: String
    let name: String
    var isPedal: Bool { asset.hasPrefix("pskin_") }
}

enum AmpSkins {
    static let all: [AmpSkin] = entries.enumerated().map { AmpSkin(id: $0.offset, asset: $0.element.0, name: $0.element.1) }
    static var amps: [AmpSkin] { all.filter { !$0.isPedal } }
    static var pedals: [AmpSkin] { all.filter { $0.isPedal } }

    static func skin(_ index: Int) -> AmpSkin {
        all.indices.contains(index) ? all[index] : all[0]
    }

    private static let entries: [(String, String)] = [
        // Amps
        ("skin_jcm", "JCM"), ("skin_silverface", "Silverface"), ("skin_tonexampblack", "Tonex Amp negro"),
        ("skin_5150", "5150"), ("skin_ampegchrome", "Ampeg Chrome"), ("skin_fendertweedbig", "Tweed"),
        ("skin_fenderhotrod", "Hot Rod"), ("skin_mesaboogiedual", "Dual Rectifier"), ("skin_elegantblue", "Elegant Blue"),
        ("skin_modernwhiteplexi", "Plexi blanco"), ("skin_rolandjazz", "Jazz Chorus"), ("skin_orangeor120", "OR120"),
        ("skin_modernblackplexi", "Plexi negro"), ("skin_fendertwin", "Twin"), ("skin_ba500", "BA500"),
        ("skin_mesamarkwood", "Mark madera"), ("skin_mesamarkv", "Mark V"), ("skin_jtm", "JTM"),
        ("skin_jbdumble1", "Dumble"), ("skin_jetcity", "Jet City"), ("skin_ac30", "AC30"),
        ("skin_evh", "EVH"), ("skin_tonexampred", "Tonex Amp rojo"), ("skin_friedmann", "Friedman"),
        ("skin_supro", "Supro"), ("skin_diezel", "Diezel"), ("skin_whitemodern", "Moderno blanco"),
        ("skin_woodamp", "Madera"),
        // Pedales
        ("pskin_bigmuff", "Big Muff"), ("pskin_bossblack", "Boss negro"), ("pskin_bosssilver", "Boss plata"),
        ("pskin_bossyellow", "Boss amarillo"), ("pskin_fuzzred", "Fuzz rojo"), ("pskin_fuzzsilver", "Fuzz plata"),
        ("pskin_ibanezblue", "Ibanez azul"), ("pskin_ibanezdarkblue", "Ibanez azul oscuro"), ("pskin_ibanezgreen", "Ibanez verde"),
        ("pskin_ibanezred", "Ibanez rojo"), ("pskin_klongold", "Klon"), ("pskin_lifepedal", "Life Pedal"),
        ("pskin_morningglory", "Morning Glory"), ("pskin_mxrdoubleblack", "MXR doble negro"), ("pskin_mxrdoublered", "MXR doble rojo"),
        ("pskin_mxrsingleblack", "MXR negro"), ("pskin_mxrsinglegold", "MXR dorado"), ("pskin_mxrsinglegreen", "MXR verde"),
        ("pskin_mxrsingleorange", "MXR naranja"), ("pskin_mxrsinglewhite", "MXR blanco"), ("pskin_mxrsingleyellow", "MXR amarillo"),
        ("pskin_ratyellow", "RAT"),
    ]
}

// MARK: - Tarjeta del preset actual

/// Imagen del amp del preset, número, nombre y cadena de efectos. Las flechas cambian la
/// imagen (como en la pantalla del controlador); tocar la imagen abre la galería.
struct PresetHeroCard: View {
    @Environment(ControllerStore.self) private var store
    @State private var showPicker = false

    var body: some View {
        let skinIndex = store.currentPreset.map { store.skinIndex(for: $0) } ?? 0
        let skin = AmpSkins.skin(skinIndex)

        VStack(spacing: 12) {
            HStack(spacing: 8) {
                skinArrow("chevron.left", enabled: skinIndex > 0) { store.stepSkin(-1) }
                Button { showPicker = true } label: {
                    Image(skin.asset)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: skin.isPedal ? 260 : 620, maxHeight: 210)
                        .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
                        .id(skin.asset)
                        .transition(.opacity)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .disabled(store.currentPreset == nil)
                skinArrow("chevron.right", enabled: skinIndex < AmpSkins.all.count - 1) { store.stepSkin(+1) }
            }
            .animation(.easeInOut(duration: 0.15), value: skin.asset)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(store.currentPresetInfo.map { "\($0.number)" } ?? "–")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(store.currentPresetInfo?.name ?? "Sin preset")
                    .font(.title.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }

            if store.state == .ready {
                EffectsChainView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.06)))
        .animation(.snappy, value: store.currentPreset)
        .sheet(isPresented: $showPicker) {
            SkinPickerSheet()
        }
    }

    private func skinArrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.bold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(!enabled || store.currentPreset == nil)
        .accessibilityLabel(symbol == "chevron.left" ? "Imagen anterior" : "Imagen siguiente")
    }
}

/// Galería para elegir la imagen del preset actual.
struct SkinPickerSheet: View {
    @Environment(ControllerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                section("Amplificadores", AmpSkins.amps)
                section("Pedales", AmpSkins.pedals)
            }
            .navigationTitle(store.currentPresetInfo.map { "Imagen para \($0.number) · \($0.name)" } ?? "Imagen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
    }

    private func section(_ title: String, _ skins: [AmpSkin]) -> some View {
        let selected = store.currentPreset.map { store.skinIndex(for: $0) }
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).padding(.horizontal)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(skins) { skin in
                    Button {
                        if let c = store.currentPreset { store.setSkin(skin.id, for: c) }
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            Image(skin.asset)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(height: 70)
                            Text(skin.name).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(selected == skin.id ? Color.orange.opacity(0.25) : Color.white.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Cadena de efectos

/// Bloques de la cadena del Tonex.
enum EffectBlock: String, CaseIterable, Hashable {
    case gate, comp, mod, delay, eq, amp, cab, reverb

    var title: String {
        switch self {
        case .gate: return "Noise gate"
        case .comp: return "Compresor"
        case .mod: return "Modulación"
        case .delay: return "Delay"
        case .eq: return "EQ"
        case .amp: return "Amplificador"
        case .cab: return "Gabinete"
        case .reverb: return "Reverb"
        }
    }

    /// Parámetro de encendido (nil si el bloque no se puede apagar desde aquí).
    var enableIndex: Int? {
        switch self {
        case .gate: return TonexParam.gateEnable
        case .comp: return TonexParam.compEnable
        case .mod: return TonexParam.modEnable
        case .delay: return TonexParam.delayEnable
        case .amp: return TonexParam.ampEnable
        case .reverb: return TonexParam.reverbEnable
        case .eq, .cab: return nil
        }
    }

    /// Sección de la pestaña Efectos donde se edita (el gabinete está dentro de Amplificador).
    var editorSection: EffectBlock { self == .cab ? .amp : self }
}

/// Iconos de la cadena en el orden real (pre/post), como `setEffectIcons()` de la web del firmware.
/// Toque: abre el bloque en Efectos. Toque largo: lo enciende/apaga.
struct EffectsChainView: View {
    @Environment(ControllerStore.self) private var store
    var iconSize: CGFloat = 48

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(chain.enumerated()), id: \.offset) { i, block in
                if i > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Image(icon(for: block))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(store.focusedBlock == block.editorSection && store.section == .effects
                                  ? Color.orange.opacity(0.25) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UISelectionFeedbackGenerator().selectionChanged()
                        store.focus(block.editorSection)
                    }
                    .onLongPressGesture(minimumDuration: 0.4) {
                        guard let i = block.enableIndex, store.state == .ready else { return }
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        store.setToggle(i, !store.isOn(i))
                    }
                    .accessibilityElement()
                    .accessibilityLabel(block.title)
                    .accessibilityValue(block.enableIndex.map { store.isOn($0) ? "Encendido" : "Apagado" } ?? "")
                    .accessibilityHint("Toca para editar. Mantén presionado para encender o apagar.")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .animation(.snappy, value: chain)
    }

    private var chain: [EffectBlock] {
        let s = store
        let gatePost = s.isOn(TonexParam.gatePost), compPost = s.isOn(TonexParam.compPost)
        let modPost = s.isOn(TonexParam.modPost), delayPost = s.isOn(TonexParam.delayPost)
        let eqPost = s.isOn(TonexParam.eqPost), reverbPost = s.isOn(TonexParam.reverbPosition)

        var out: [EffectBlock] = []
        if !gatePost { out.append(.gate) }
        if !compPost { out.append(.comp) }
        if !modPost { out.append(.mod) }
        if !delayPost { out.append(.delay) }
        if !eqPost { out.append(.eq) }
        out.append(.amp)
        out.append(.cab)
        if eqPost { out.append(.eq) }
        if gatePost { out.append(.gate) }
        if compPost { out.append(.comp) }
        if !reverbPost { out.append(.reverb) }
        if modPost { out.append(.mod) }
        if delayPost { out.append(.delay) }
        if reverbPost { out.append(.reverb) }
        return out
    }

    private func model(_ i: Int) -> Int { Int(store.value(i).rounded()) }

    private func icon(for block: EffectBlock) -> String {
        switch block {
        case .gate: return store.isOn(TonexParam.gateEnable) ? "effect_icon_gate_on" : "effect_icon_gate_off"
        case .comp: return store.isOn(TonexParam.compEnable) ? "effect_icon_comp_on" : "effect_icon_comp_off"
        case .amp: return store.isOn(TonexParam.ampEnable) ? "effect_icon_amp_on" : "effect_icon_amp_off"
        case .cab: return model(TonexParam.cabType) == 2 ? "effect_icon_cab_off" : "effect_icon_cab_on"
        case .eq: return "effect_icon_eq"
        case .mod:
            guard store.isOn(TonexParam.modEnable) else { return "effect_icon_mod_off" }
            switch model(TonexParam.modModel) {
            case 1: return "effect_icon_mod_on_tremolo"
            case 2: return "effect_icon_mod_on_phaser"
            case 3: return "effect_icon_mod_on_flanger"
            case 4: return "effect_icon_mod_on_rotary"
            default: return "effect_icon_mod_on_chorus"
            }
        case .delay:
            guard store.isOn(TonexParam.delayEnable) else { return "effect_icon_delay_off" }
            return model(TonexParam.delayModel) == 1 ? "effect_icon_delay_on_t" : "effect_icon_delay_on_d"
        case .reverb:
            guard store.isOn(TonexParam.reverbEnable) else { return "effect_icon_reverb_off" }
            switch model(TonexParam.reverbModel) {
            case 1: return "effect_icon_reverb_on_s2"
            case 2: return "effect_icon_reverb_on_s3"
            case 3: return "effect_icon_reverb_on_s4"
            case 4: return "effect_icon_reverb_on_r"
            case 5: return "effect_icon_reverb_on_p"
            default: return "effect_icon_reverb_on_s1"
            }
        }
    }
}
