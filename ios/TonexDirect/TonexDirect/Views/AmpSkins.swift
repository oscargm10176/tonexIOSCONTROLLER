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

    /// Sugiere una imagen a partir de textos (nombre del preset y textos internos).
    /// Busca palabras completas, en orden: lo más específico primero, amps antes que pedales.
    static func guess(_ texts: [String]) -> Int? {
        let normalized = " " + texts.joined(separator: " ").lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) } + " "
        for (asset, keywords) in rules {
            for k in keywords where normalized.contains(" \(k) ") {
                return all.firstIndex { $0.asset == asset }
            }
        }
        return nil
    }

    private static let rules: [(String, [String])] = [
        // Amps (de lo más específico a lo más genérico)
        ("skin_evh", ["evh", "5153", "5150 iii"]),
        ("skin_mesamarkv", ["mark v", "mark 5", "mkv"]),
        ("skin_mesamarkwood", ["mark iv", "mark iii", "mark ii", "mark 4", "mark 3", "mark iic", "boogie"]),
        ("skin_mesaboogiedual", ["rectifier", "recto", "dual rec", "triple rec", "mesa"]),
        ("skin_jbdumble1", ["dumble", "ods", "overdrive special"]),
        ("skin_jetcity", ["jet city", "soldano", "slo", "slo 100"]),
        ("skin_friedmann", ["friedman", "be100", "be 100", "dirty shirley", "hbe"]),
        ("skin_diezel", ["diezel", "vh4", "herbert"]),
        ("skin_supro", ["supro"]),
        ("skin_ac30", ["ac30", "ac 30", "ac15", "ac 15", "vox"]),
        ("skin_orangeor120", ["orange", "or120", "or50", "rockerverb", "thunderverb"]),
        ("skin_rolandjazz", ["jazz chorus", "jc120", "jc 120", "roland"]),
        ("skin_ampegchrome", ["ampeg", "svt", "b15"]),
        ("skin_ba500", ["ba500", "ba 500"]),
        ("skin_5150", ["5150", "6505", "peavey"]),
        ("skin_jtm", ["jtm", "jtm45", "jtm 45"]),
        ("skin_modernblackplexi", ["super lead", "slp", "1959"]),
        ("skin_modernwhiteplexi", ["plexi"]),
        ("skin_jcm", ["jcm", "jcm800", "jcm900", "jvm", "marshall", "2203", "brit"]),
        ("skin_fendertweedbig", ["tweed", "bassman", "5e3"]),
        ("skin_fenderhotrod", ["hot rod", "hotrod", "blues jr", "blues junior"]),
        ("skin_fendertwin", ["twin", "deluxe reverb", "blackface", "fender"]),
        ("skin_silverface", ["silverface", "princeton", "vibrolux", "super reverb"]),
        // Pedales
        ("pskin_klongold", ["klon", "centaur"]),
        ("pskin_morningglory", ["morning glory"]),
        ("pskin_bigmuff", ["big muff", "muff"]),
        ("pskin_ibanezgreen", ["tube screamer", "screamer", "ts9", "ts808", "ts 9", "ts 808"]),
        ("pskin_bossyellow", ["sd1", "sd 1", "super overdrive", "bd2", "blues driver"]),
        ("pskin_bossblack", ["hm2", "hm 2", "metal zone", "mt2"]),
        ("pskin_ratyellow", ["rat"]),
        ("pskin_fuzzred", ["fuzz face", "fuzz"]),
        ("pskin_mxrsingleorange", ["mxr", "phase 90"]),
    ]

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
    /// En Editar la cadena va arriba en la barra de bloques.
    var showChain = true
    /// Flechas de preset anterior/siguiente junto al nombre.
    var showPresetArrows = false

    var body: some View {
        let shown = store.currentPreset.flatMap { store.displaySkin(for: $0) }
        let chosen = shown?.index

        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button { showPicker = true } label: {
                    if let chosen {
                        let skin = AmpSkins.skin(chosen)
                        Image(skin.asset)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(maxWidth: skin.isPedal ? 340 : 980, maxHeight: skin.isPedal ? 300 : 340)
                            .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
                            .id(skin.asset)
                            .transition(.opacity)
                            .overlay(alignment: .bottomTrailing) {
                                if shown?.isAuto == true {
                                    Label("Sugerida · toca para cambiar", systemImage: "wand.and.stars")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(.ultraThinMaterial, in: Capsule())
                                        .padding(6)
                                }
                            }
                    } else {
                        // Sin imagen elegida: lo decimos en vez de mostrar un amp que no es.
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 44, weight: .light))
                            Text("Elegir el amp de este preset")
                                .font(.headline)
                            Text("El pedal no informa qué amplificador usa cada preset.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: 980, minHeight: 220)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                                .foregroundStyle(.secondary)
                        )
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .disabled(store.currentPreset == nil)
            }
            .animation(.easeInOut(duration: 0.15), value: chosen)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                if showPresetArrows { presetArrow("chevron.left") { store.previousPreset() } }
                Text(store.currentPresetInfo?.label ?? "–")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(store.currentPresetInfo?.name ?? "Sin preset")
                    .font(.title.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if showPresetArrows { presetArrow("chevron.right") { store.nextPreset() } }
            }

            if showChain, store.state == .ready {
                EffectsChainView(selection: store.stageBlock, onSelect: { store.stageBlock = $0 })
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.06)))
        .animation(.snappy, value: store.currentPreset)
        .sheet(isPresented: $showPicker) {
            if let c = store.currentPreset { SkinPickerSheet(presetID: c) }
        }
    }

    private func presetArrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(store.state != .ready)
        .accessibilityLabel(symbol == "chevron.left" ? "Preset anterior" : "Preset siguiente")
        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 6 }
    }
}

/// Miniatura de la lista: la imagen elegida o un hueco discreto si no hay.
struct SkinThumbnail: View {
    @Environment(ControllerStore.self) private var store
    let presetID: Int
    var width: CGFloat = 72
    var height: CGFloat = 26

    var body: some View {
        if let shown = store.displaySkin(for: presetID) {
            Image(AmpSkins.skin(shown.index).asset)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: width, height: height)
                .opacity(shown.isAuto ? 0.75 : 1)
                .overlay(alignment: .topTrailing) {
                    if shown.isAuto {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .offset(x: 4, y: -4)
                    }
                }
                .accessibilityLabel(shown.isAuto ? "Imagen sugerida" : "Imagen elegida")
        } else {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.quaternary)
                .frame(width: width, height: height)
                .accessibilityLabel("Sin imagen")
        }
    }
}

/// Galería para elegir la imagen de un preset.
struct SkinPickerSheet: View {
    @Environment(ControllerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let presetID: Int

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    private var preset: Preset? { store.presets.indices.contains(presetID) ? store.presets[presetID] : nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                section("Amplificadores", AmpSkins.amps)
                section("Pedales", AmpSkins.pedals)
            }
            .navigationTitle(preset.map { "Imagen para \($0.label) · \($0.name)" } ?? "Imagen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if store.chosenSkin(for: presetID) != nil {
                        Button("Quitar imagen", role: .destructive) {
                            store.clearSkin(for: presetID)
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
    }

    private func section(_ title: String, _ skins: [AmpSkin]) -> some View {
        let selected = store.displaySkin(for: presetID)?.index
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).padding(.horizontal)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(skins) { skin in
                    Button {
                        store.setSkin(skin.id, for: presetID)
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

    /// Parámetro Pre/Post (0 = antes del amp, 1 = después), si el bloque lo tiene.
    var postIndex: Int? {
        switch self {
        case .gate: return TonexParam.gatePost
        case .comp: return TonexParam.compPost
        case .eq: return TonexParam.eqPost
        case .mod: return TonexParam.modPost
        case .delay: return TonexParam.delayPost
        case .reverb: return TonexParam.reverbPosition
        case .amp, .cab: return nil
        }
    }
}

/// Iconos de la cadena en el orden real (pre/post), como `setEffectIcons()` de la web del firmware.
/// Toque: abre el bloque en Efectos. Toque largo: lo enciende/apaga.
struct EffectsChainView: View {
    @Environment(ControllerStore.self) private var store
    var iconSize: CGFloat = 48
    /// Si se pasa, el toque selecciona en lugar de saltar a la pestaña Efectos (uso en Escenario).
    var selection: EffectBlock? = nil
    var onSelect: ((EffectBlock) -> Void)? = nil

    private func isHighlighted(_ block: EffectBlock) -> Bool {
        if onSelect != nil { return selection == block.editorSection }
        return store.focusedBlock == block.editorSection && store.showAdvanced
    }

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
                            .fill(isHighlighted(block) ? Color.orange.opacity(0.25) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UISelectionFeedbackGenerator().selectionChanged()
                        if let onSelect {
                            withAnimation(.snappy) { onSelect(block.editorSection) }
                        } else {
                            store.focus(block.editorSection)
                        }
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
                    .accessibilityAddTraits(isHighlighted(block) ? .isSelected : [])
                    .accessibilityAddTraits(.isButton)
            }
        }
        .animation(.snappy, value: chain)
    }

    private var chain: [EffectBlock] { store.chainOrder() }
    private func icon(for block: EffectBlock) -> String { store.chainIcon(for: block) }
}

// MARK: - Lógica compartida de la cadena

extension ControllerStore {
    /// Orden real de la cadena (pre/post), como `setEffectIcons()` de la web del firmware.
    func chainOrder() -> [EffectBlock] {
        let gatePost = isOn(TonexParam.gatePost), compPost = isOn(TonexParam.compPost)
        let modPost = isOn(TonexParam.modPost), delayPost = isOn(TonexParam.delayPost)
        let eqPost = isOn(TonexParam.eqPost), reverbPost = isOn(TonexParam.reverbPosition)

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

    private func model(_ i: Int) -> Int { Int(value(i).rounded()) }

    /// ¿Está sonando el bloque? (EQ siempre; gabinete salvo "sin gabinete").
    func isBlockOn(_ block: EffectBlock) -> Bool {
        switch block {
        case .cab: return model(TonexParam.cabType) != 2
        case .eq: return true
        default: return block.enableIndex.map { isOn($0) } ?? true
        }
    }

    /// Texto bajo el nombre del bloque: el tipo/modelo elegido.
    func blockSubtitle(_ block: EffectBlock) -> String {
        func pick(_ list: [String], _ i: Int) -> String {
            let m = model(i)
            return list.indices.contains(m) ? list[m] : "—"
        }
        switch block {
        case .amp:
            if let c = currentPreset, let shown = displaySkin(for: c) { return AmpSkins.skin(shown.index).name }
            return "Tone Model"
        case .cab: return pick(TonexCatalog.cabinetTypes, TonexParam.cabType)
        case .mod: return pick(TonexCatalog.modulationModels, TonexParam.modModel)
        case .delay: return pick(TonexCatalog.delayModels, TonexParam.delayModel)
        case .reverb: return pick(TonexCatalog.reverbModels, TonexParam.reverbModel)
        case .gate, .comp, .eq: return isBlockOn(block) ? "On" : "Off"
        }
    }

    func chainIcon(for block: EffectBlock) -> String {
        switch block {
        case .gate: return isOn(TonexParam.gateEnable) ? "effect_icon_gate_on" : "effect_icon_gate_off"
        case .comp: return isOn(TonexParam.compEnable) ? "effect_icon_comp_on" : "effect_icon_comp_off"
        case .amp: return isOn(TonexParam.ampEnable) ? "effect_icon_amp_on" : "effect_icon_amp_off"
        case .cab: return model(TonexParam.cabType) == 2 ? "effect_icon_cab_off" : "effect_icon_cab_on"
        case .eq: return "effect_icon_eq"
        case .mod:
            guard isOn(TonexParam.modEnable) else { return "effect_icon_mod_off" }
            switch model(TonexParam.modModel) {
            case 1: return "effect_icon_mod_on_tremolo"
            case 2: return "effect_icon_mod_on_phaser"
            case 3: return "effect_icon_mod_on_flanger"
            case 4: return "effect_icon_mod_on_rotary"
            default: return "effect_icon_mod_on_chorus"
            }
        case .delay:
            guard isOn(TonexParam.delayEnable) else { return "effect_icon_delay_off" }
            return model(TonexParam.delayModel) == 1 ? "effect_icon_delay_on_t" : "effect_icon_delay_on_d"
        case .reverb:
            guard isOn(TonexParam.reverbEnable) else { return "effect_icon_reverb_off" }
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
