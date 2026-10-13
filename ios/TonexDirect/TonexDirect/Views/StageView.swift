import SwiftUI
import UIKit

/// Columna derecha en "Escenario": amp del preset, nombre, cadena de efectos,
/// perillas y botones grandes de anterior/siguiente.
struct StageView: View {
    @Environment(ControllerStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PresetHeroCard()
                if store.state == .ready {
                    AmpPanel()
                }
                navigationButtons
            }
            .padding(16)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            BigButton(systemImage: "chevron.left", title: "Anterior") { store.previousPreset() }
            BigButton(systemImage: "chevron.right", title: "Siguiente") { store.nextPreset() }
        }
        .disabled(store.state != .ready)
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
