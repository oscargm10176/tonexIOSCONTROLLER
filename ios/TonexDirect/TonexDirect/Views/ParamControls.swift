import SwiftUI

/// Dibuja el control adecuado para un parámetro según su `ParamKind`.
struct ParamRow: View {
    @Environment(ControllerStore.self) private var store
    let spec: ParamSpec

    var body: some View {
        switch spec.kind {
        case let .slider(unit, decimals):
            ParamSlider(index: spec.index, label: spec.label, unit: unit, decimals: decimals)
        case .toggle:
            Toggle(spec.label, isOn: Binding(
                get: { store.isOn(spec.index) },
                set: { store.setToggle(spec.index, $0) }
            ))
        case .prePost:
            PrePostPicker(index: spec.index, label: spec.label)
        case .choice(let options):
            ChoicePicker(index: spec.index, label: spec.label, options: options)
        case .stepper:
            let r = store.range(spec.index)
            Stepper(value: Binding(
                get: { Int(store.value(spec.index).rounded()) },
                set: { store.setValue(spec.index, Double($0), immediate: true) }
            ), in: Int(r.lowerBound)...Int(r.upperBound)) {
                HStack {
                    Text(spec.label)
                    Spacer()
                    Text("\(Int(store.value(spec.index).rounded()))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ParamSlider: View {
    @Environment(ControllerStore.self) private var store
    let index: Int
    let label: String
    let unit: String
    let decimals: Int

    var body: some View {
        let range = store.range(index)
        let value = store.value(index)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(formatted(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { min(max(store.value(index), range.lowerBound), range.upperBound) },
                    set: { store.setValue(index, $0) }
                ),
                in: range,
                onEditingChanged: { editing in
                    if !editing { store.commitValue(index, store.value(index)) }
                }
            )
        }
        .padding(.vertical, 2)
    }

    private func formatted(_ v: Double) -> String {
        let n = v.formatted(.number.precision(.fractionLength(decimals)))
        return unit.isEmpty ? n : "\(n) \(unit)"
    }
}

struct PrePostPicker: View {
    @Environment(ControllerStore.self) private var store
    let index: Int
    let label: String

    var body: some View {
        Picker(label, selection: Binding(
            get: { store.isOn(index) ? 1 : 0 },
            set: { store.setToggle(index, $0 == 1) }
        )) {
            Text("Pre").tag(0)
            Text("Post").tag(1)
        }
        .pickerStyle(.segmented)
    }
}

struct ChoicePicker: View {
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
    }
}

/// Cabecera de sección con interruptor de encendido del efecto.
struct EffectHeader: View {
    @Environment(ControllerStore.self) private var store
    let title: String
    let enableIndex: Int?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let i = enableIndex {
                Toggle(title, isOn: Binding(
                    get: { store.isOn(i) },
                    set: { store.setToggle(i, $0) }
                ))
                .labelsHidden()
                .controlSize(.mini)
            }
        }
    }
}
