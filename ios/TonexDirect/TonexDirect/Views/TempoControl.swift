import SwiftUI
import UIKit

/// Tap tempo: promedia los últimos toques; si pasan más de 2 s sin tocar, empieza de nuevo.
@MainActor
final class TapTempo {
    private var taps: [Date] = []

    /// Registra un toque y devuelve el BPM calculado (a partir del 2.º toque).
    func tap() -> Double? {
        let now = Date()
        if let last = taps.last, now.timeIntervalSince(last) > 2 { taps.removeAll() }
        taps.append(now)
        if taps.count > 5 { taps.removeFirst(taps.count - 5) }
        guard taps.count >= 2 else { return nil }
        let avg = taps.last!.timeIntervalSince(taps.first!) / Double(taps.count - 1)
        return 60 / avg
    }
}

extension ControllerStore {
    var tempoAvailable: Bool { supports(TonexParam.bpm) }
    var bpm: Int { Int(value(TonexParam.bpm).rounded()) }

    func setBPM(_ v: Double) {
        let r = range(TonexParam.bpm)
        let bounds = r.upperBound > 1 ? r : 40...240
        setValue(TonexParam.bpm, min(max(v.rounded(), bounds.lowerBound), bounds.upperBound), immediate: true)
    }
}

/// Luz que parpadea al tempo actual.
struct TempoBeat: View {
    let bpm: Int
    var size: CGFloat = 10

    var body: some View {
        TimelineView(.animation) { ctx in
            let period = 60 / Double(max(bpm, 1))
            let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let on = phase < 0.18
            Circle()
                .fill(on ? Color.orange : Color(white: 0.28))
                .frame(width: size, height: size)
                .shadow(color: on ? .orange : .clear, radius: size * 0.6)
        }
        .accessibilityHidden(true)
    }
}

/// Tempo en la barra superior, junto a las pestañas: luz al tempo, BPM, − / + y TAP.
struct TempoBar: View {
    @Environment(ControllerStore.self) private var store
    @State private var tapper = TapTempo()

    var body: some View {
        HStack(spacing: 8) {
            TempoBeat(bpm: store.bpm, size: 9)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(store.bpm)")
                    .font(.headline.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
                    .animation(.snappy, value: store.bpm)
                Text("BPM")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 62, alignment: .leading)

            stepButton("minus", -1)
            stepButton("plus", +1)

            Button {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                if let v = tapper.tap() { store.setBPM(v) }
            } label: {
                Text("TAP")
                    .font(.subheadline.weight(.heavy))
                    .frame(width: 48, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .accessibilityHint("Toca al ritmo para fijar el tempo")
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tempo, \(store.bpm) BPM")
    }

    private func stepButton(_ icon: String, _ delta: Double) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            store.setBPM(Double(store.bpm) + delta)
        } label: {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .frame(width: 26, height: 28)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)   // mantener presionado = sube/baja seguido
        .accessibilityLabel(delta < 0 ? "Bajar tempo" : "Subir tempo")
    }
}

/// Footswitch de TAP para el modo Live: grande, con el BPM y la luz al tempo.
struct LiveTapSwitch: View {
    @Environment(ControllerStore.self) private var store
    @State private var tapper = TapTempo()

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            if let v = tapper.tap() { store.setBPM(v) }
        } label: {
            VStack(spacing: 8) {
                TempoBeat(bpm: store.bpm, size: 16)
                Text("TAP")
                    .font(.title3.weight(.bold))
                Text("\(store.bpm) BPM")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.09)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.orange.opacity(0.5), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(LivePressStyle())
        .accessibilityLabel("Tap tempo")
        .accessibilityValue("\(store.bpm) BPM")
    }
}
