import SwiftUI
import UIKit

/// Perilla tipo amplificador para un parámetro del pedal.
/// - Arrastra hacia arriba/abajo para girarla (sensibilidad fina con el arrastre largo).
/// - Doble toque: vuelve al valor por defecto.
struct Knob: View {
    @Environment(ControllerStore.self) private var store
    let index: Int
    let label: String
    var unit: String = ""
    var decimals: Int = 1
    var size: CGFloat = 72

    @State private var dragStart: Double?
    @State private var lastDetent: Int?

    /// Recorrido de la perilla: de -135° a +135°.
    private let sweep: Double = 270

    var body: some View {
        let range = store.range(index)
        let value = min(max(store.value(index), range.lowerBound), range.upperBound)
        let span = range.upperBound - range.lowerBound
        let fraction = span > 0 ? (value - range.lowerBound) / span : 0
        let enabled = store.state == .ready

        VStack(spacing: 6) {
            ZStack {
                // pista
                Circle()
                    .trim(from: 0, to: sweep / 360)
                    .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(90 + (360 - sweep) / 2))
                // valor
                Circle()
                    .trim(from: 0, to: sweep / 360 * fraction)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(90 + (360 - sweep) / 2))
                // cuerpo
                Circle()
                    .fill(
                        RadialGradient(colors: [Color(white: 0.32), Color(white: 0.10)],
                                       center: .init(x: 0.35, y: 0.3), startRadius: 2, endRadius: size * 0.6)
                    )
                    .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 3)
                    .padding(9)
                // marca
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: size * 0.2)
                    .offset(y: -size * 0.22)
                    .rotationEffect(.degrees(-sweep / 2 + sweep * fraction))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(drag(range: range, span: span, enabled: enabled))
            .onTapGesture(count: 2) { reset() }

            Text(label)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(formatted(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(dragStart == nil ? .secondary : .primary)
        }
        .opacity(enabled ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(formatted(value))
        .accessibilityAdjustableAction { direction in
            let step = span / 20
            let next = direction == .increment ? value + step : value - step
            store.commitValue(index, min(max(next, range.lowerBound), range.upperBound))
        }
    }

    private func drag(range: ClosedRange<Double>, span: Double, enabled: Bool) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                guard enabled, span > 0 else { return }
                if dragStart == nil { dragStart = store.value(index) }
                // 220 pt de arrastre = recorrido completo
                let delta = Double(-g.translation.height) / 220 * span
                let next = min(max((dragStart ?? 0) + delta, range.lowerBound), range.upperBound)
                store.setValue(index, next)
                // un "clic" háptico cada 10 % del recorrido
                let detent = Int(((next - range.lowerBound) / span * 10).rounded())
                if detent != lastDetent {
                    lastDetent = detent
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { _ in
                guard enabled else { return }
                store.commitValue(index, store.value(index))
                dragStart = nil
                lastDetent = nil
            }
    }

    private func reset() {
        guard store.state == .ready, let d = TonexParamTable.defaultValue(index) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.commitValue(index, d)
    }

    private func formatted(_ v: Double) -> String {
        let n = v.formatted(.number.precision(.fractionLength(decimals)))
        return unit.isEmpty ? n : "\(n) \(unit)"
    }
}

/// Panel de perillas del amp (modelo + EQ) del preset activo.
struct AmpPanel: View {
    @Environment(ControllerStore.self) private var store

    private let knobs: [(Int, String, String, Int)] = [
        (TonexParam.ampGain, "Gain", "", 1),
        (TonexParam.eqBass, "Bass", "", 1),
        (TonexParam.eqMid, "Mid", "", 1),
        (TonexParam.eqTreble, "Treble", "", 1),
        (TonexParam.ampPresence, "Presence", "", 1),
        (TonexParam.ampDepth, "Depth", "", 1),
        (TonexParam.ampVolume, "Volume", "", 1),
        (TonexParam.ampMix, "Mix", "%", 0),
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(size: 76)
            row(size: 62)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                ForEach(knobs, id: \.0) { k in Knob(index: k.0, label: k.1, unit: k.2, decimals: k.3, size: 62) }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08)))
        )
    }

    private func row(size: CGFloat) -> some View {
        HStack(spacing: 18) {
            ForEach(knobs, id: \.0) { k in
                Knob(index: k.0, label: k.1, unit: k.2, decimals: k.3, size: size)
            }
        }
    }
}
