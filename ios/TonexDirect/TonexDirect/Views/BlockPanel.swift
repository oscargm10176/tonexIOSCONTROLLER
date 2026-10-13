import SwiftUI
import UIKit

/// Panel de edición del bloque seleccionado en la cadena (Escenario).
/// Encendido tipo footswitch, tipo/modelo y perillas de lo esencial.
/// La edición completa (VIR, pre/post, subdivisiones…) sigue en la pestaña Efectos.
struct BlockPanel: View {
    @Environment(ControllerStore.self) private var store
    let block: EffectBlock

    /// Alto fijo de la zona de controles: el del bloque más alto (VIR / modulación / delay),
    /// para que al cambiar de bloque solo cambie el contenido y el panel no salte.
    /// (Compacto: las opciones de sync/modo van en la fila de arriba, así queda más espacio al amp.)
    static let controlsHeight: CGFloat = 100
    static let headerHeight: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let i = block.enableIndex {
                    StompSwitch(index: i)
                }
                if let p = block.postIndex {
                    PrePostChip(index: p)
                }
                modelPicker
                headerExtras
                Spacer(minLength: 8)
                Button {
                    store.focus(block.editorSection)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Todos los ajustes")
            }
            .frame(height: Self.headerHeight)

            controls
                .frame(maxWidth: .infinity)
                // el gabinete VIR tiene dos filas: ese caso puede crecer
                .frame(minHeight: Self.controlsHeight, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(store.isBlockOn(block) ? 1 : 0.45)
                .animation(.easeInOut(duration: 0.15), value: store.isBlockOn(block))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08)))
        )
        .id(block)
        .transition(.opacity)
    }

    private func model(_ i: Int) -> Int { Int(store.value(i).rounded()) }

    // MARK: Tipo / modelo

    @ViewBuilder
    private var modelPicker: some View {
        switch block {
        case .amp:
            EmptyView()
        case .cab:
            DropdownParam(index: TonexParam.cabType, options: TonexCatalog.cabinetTypes)
        case .mod:
            DropdownParam(index: TonexParam.modModel, options: TonexCatalog.modulationModels)
        case .delay:
            DropdownParam(index: TonexParam.delayModel, options: TonexCatalog.delayModels)
        case .reverb:
            DropdownParam(index: TonexParam.reverbModel, options: TonexCatalog.reverbModels)
        case .gate, .comp, .eq:
            EmptyView()
        }
    }

    /// Sync al tempo, subdivisión e interruptores del bloque (modo del delay…), en la fila de arriba.
    @ViewBuilder
    private var headerExtras: some View {
        switch block {
        case .mod:
            syncControls(TonexCatalog.modulationParams(model: model(TonexParam.modModel)))
        case .delay:
            syncControls(TonexCatalog.delayParams(model: model(TonexParam.delayModel)))
        default:
            EmptyView()
        }
    }

    private func syncControls(_ b: (sync: Int, subdivision: Int, params: [ParamSpec])) -> some View {
        HStack(spacing: 8) {
            ToggleChip(index: b.sync, label: "Sync", systemImage: "metronome")
            ForEach(b.params.filter { if case .toggle = $0.kind { return true } else { return false } }, id: \.index) { spec in
                ToggleChip(index: spec.index, label: spec.label, systemImage: "switch.2")
            }
            if store.isOn(b.sync) {
                SubdivisionStepper(index: b.subdivision)
            }
        }
    }

    // MARK: Perillas

    @ViewBuilder
    private var controls: some View {
        switch block {
        case .amp:
            KnobRow(specs: Self.ampSpecs)
        case .cab:
            cabControls
        case .gate:
            KnobRow(specs: TonexCatalog.gate)
        case .comp:
            KnobRow(specs: TonexCatalog.comp)
        case .eq:
            KnobRow(specs: TonexCatalog.eq)
        case .mod:
            KnobRow(specs: TonexCatalog.modulationParams(model: model(TonexParam.modModel)).params)
        case .delay:
            KnobRow(specs: TonexCatalog.delayParams(model: model(TonexParam.delayModel)).params)
        case .reverb:
            KnobRow(specs: TonexCatalog.reverbParams(model: model(TonexParam.reverbModel)))
        }
    }

    /// Gabinete: con Tone Model no hay nada que ajustar; con VIR, micrófonos y posición.
    @ViewBuilder
    private var cabControls: some View {
        switch model(TonexParam.cabType) {
        case 1:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    SubdivisionStepper(index: TonexParam.virCabModel, title: "Gabinete VIR")
                    Divider().frame(height: 24)
                    Text("Mic 1").font(.footnote.weight(.semibold)).foregroundStyle(.orange)
                    DropdownParam(index: TonexParam.virMic1, options: TonexCatalog.virMics)
                    Text("Mic 2").font(.footnote.weight(.semibold)).foregroundStyle(.teal)
                    DropdownParam(index: TonexParam.virMic2, options: TonexCatalog.virMics)
                }
                KnobRow(specs: [
                    ParamSpec(index: TonexParam.virMic1X, label: "Mic 1 X", kind: .slider(unit: "", decimals: 1)),
                    ParamSpec(index: TonexParam.virMic1Z, label: "Mic 1 Z", kind: .slider(unit: "", decimals: 1)),
                    ParamSpec(index: TonexParam.virMic2X, label: "Mic 2 X", kind: .slider(unit: "", decimals: 1)),
                    ParamSpec(index: TonexParam.virMic2Z, label: "Mic 2 Z", kind: .slider(unit: "", decimals: 1)),
                    ParamSpec(index: TonexParam.virBlend, label: "Mix mics", kind: .slider(unit: "", decimals: 0)),
                    ParamSpec(index: TonexParam.virReso, label: "Resonance", kind: .slider(unit: "", decimals: 1)),
                ])
            }
        case 2:
            Label("Sin gabinete: la salida va directa (para usar un IR o un gabinete real).", systemImage: "speaker.slash")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
        default:
            Label("Usando el gabinete capturado con el Tone Model.", systemImage: "lock")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
    }

    static let ampSpecs: [ParamSpec] = [
        ParamSpec(index: TonexParam.ampGain, label: "Gain", kind: .slider(unit: "", decimals: 1)),
        ParamSpec(index: TonexParam.eqBass, label: "Bass", kind: .slider(unit: "", decimals: 1)),
        ParamSpec(index: TonexParam.eqMid, label: "Mid", kind: .slider(unit: "", decimals: 1)),
        ParamSpec(index: TonexParam.eqTreble, label: "Treble", kind: .slider(unit: "", decimals: 1)),
        ParamSpec(index: TonexParam.ampPresence, label: "Presence", kind: .slider(unit: "", decimals: 1)),
        ParamSpec(index: TonexParam.ampDepth, label: "Depth", kind: .slider(unit: "", decimals: 1)),
        ParamSpec(index: TonexParam.ampVolume, label: "Volume", kind: .slider(unit: "", decimals: 1)),
        ParamSpec(index: TonexParam.ampMix, label: "Mix", kind: .slider(unit: "%", decimals: 0)),
    ]
}

/// Botón PRE/POST (posición del efecto respecto al amp).
struct PrePostChip: View {
    @Environment(ControllerStore.self) private var store
    let index: Int

    var body: some View {
        let post = store.isOn(index)
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            store.setToggle(index, !post)
        } label: {
            Text(post ? "POST" : "PRE")
                .font(.subheadline.weight(.bold).monospaced())
                .foregroundStyle(.orange)
                .frame(minWidth: 52)
                .padding(.vertical, 9)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.1)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .disabled(store.state != .ready)
        .accessibilityLabel("Posición")
        .accessibilityValue(post ? "Después del amp" : "Antes del amp")
    }
}

/// Menú desplegable para el tipo/modelo de un bloque.
struct DropdownParam: View {
    @Environment(ControllerStore.self) private var store
    let index: Int
    let options: [String]

    var body: some View {
        let current = min(max(Int(store.value(index).rounded()), 0), options.count - 1)
        Menu {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    store.setValue(index, Double(i), immediate: true)
                } label: {
                    if i == current { Label(options[i], systemImage: "checkmark") } else { Text(options[i]) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(options[current]).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.1)))
        }
        .disabled(store.state != .ready)
    }
}

/// Fila de perillas que se adapta al ancho (grande, chica o en cuadrícula).
struct KnobRow: View {
    let specs: [ParamSpec]

    private var knobs: [(spec: ParamSpec, unit: String, decimals: Int)] {
        specs.compactMap { s in
            if case let .slider(unit, decimals) = s.kind { return (s, unit, decimals) }
            return nil
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(size: 62)
            row(size: 52)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach(knobs, id: \.spec.index) { k in
                    Knob(index: k.spec.index, label: k.spec.label, unit: k.unit, decimals: k.decimals, size: 52)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(size: CGFloat) -> some View {
        HStack(spacing: 22) {
            ForEach(knobs, id: \.spec.index) { k in
                Knob(index: k.spec.index, label: k.spec.label, unit: k.unit, decimals: k.decimals, size: size)
            }
        }
    }
}

/// Encendido estilo footswitch, con LED.
struct StompSwitch: View {
    @Environment(ControllerStore.self) private var store
    let index: Int

    var body: some View {
        let on = store.isOn(index)
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            store.setToggle(index, !on)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(on ? Color.red : Color(white: 0.3))
                    .frame(width: 10, height: 10)
                    .shadow(color: on ? .red.opacity(0.9) : .clear, radius: 6)
                Text(on ? "ON" : "OFF")
                    .font(.headline.monospaced())
                    .frame(minWidth: 34)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color(white: on ? 0.2 : 0.12)))
            .overlay(Capsule().stroke(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(store.state != .ready)
        .accessibilityLabel("Encendido")
        .accessibilityValue(on ? "Encendido" : "Apagado")
    }
}

/// Selector segmentado para parámetros de tipo/modelo.
struct SegmentedParam: View {
    @Environment(ControllerStore.self) private var store
    let index: Int
    let label: String
    let options: [String]

    var body: some View {
        Picker(label, selection: Binding(
            get: { min(max(Int(store.value(index).rounded()), 0), options.count - 1) },
            set: { store.setValue(index, Double($0), immediate: true) }
        )) {
            ForEach(options.indices, id: \.self) { i in
                Text(options[i]).tag(i)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .disabled(store.state != .ready)
    }
}

/// Interruptor compacto en forma de cápsula.
struct ToggleChip: View {
    @Environment(ControllerStore.self) private var store
    let index: Int
    let label: String
    let systemImage: String

    var body: some View {
        let on = store.isOn(index)
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            store.setToggle(index, !on)
        } label: {
            Label(label, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(on ? Color.orange.opacity(0.3) : Color(white: 0.15)))
                .foregroundStyle(on ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(store.state != .ready)
        .accessibilityValue(on ? "Encendido" : "Apagado")
    }
}

/// Subdivisión de tempo (0…17) con botones − / +.
struct SubdivisionStepper: View {
    @Environment(ControllerStore.self) private var store
    let index: Int
    var title = "Subdivisión"

    var body: some View {
        let r = store.range(index)
        Stepper(value: Binding(
            get: { Int(store.value(index).rounded()) },
            set: { store.setValue(index, Double($0), immediate: true) }
        ), in: Int(r.lowerBound)...Int(r.upperBound)) {
            Text("\(title) \(Int(store.value(index).rounded()))")
                .font(.footnote.monospacedDigit())
        }
        .fixedSize()
    }
}
