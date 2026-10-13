import SwiftUI
import UIKit

/// Modo Editar: barra de bloques arriba, franja de controles del bloque elegido
/// y el amp del preset abajo.
struct EditView: View {
    @Environment(ControllerStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if store.state == .ready {
                    BlockBar()
                    BlockPanel(block: store.stageBlock)
                        .animation(.snappy, value: store.stageBlock)
                }
                PresetHeroCard(showChain: false, showPresetArrows: true)
            }
            .padding(16)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Barra superior con un mosaico por bloque, en el orden real de la cadena.
/// Toque: lo selecciona. Toque largo: lo enciende/apaga.
struct BlockBar: View {
    @Environment(ControllerStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.chainOrder(), id: \.self) { block in
                    BlockTile(block: block, selected: store.stageBlock == block)
                        .onTapGesture {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.snappy) { store.stageBlock = block }
                        }
                        .onLongPressGesture(minimumDuration: 0.4) {
                            guard let i = block.enableIndex, store.state == .ready else { return }
                            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                            store.setToggle(i, !store.isOn(i))
                        }
                }
            }
            .padding(4)
        }
        .animation(.snappy, value: store.chainOrder())
    }
}

struct BlockTile: View {
    @Environment(ControllerStore.self) private var store
    let block: EffectBlock
    let selected: Bool

    var body: some View {
        let on = store.isBlockOn(block)
        HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(store.chainIcon(for: block))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)
                Circle()
                    .fill(on ? Color.green : Color(white: 0.3))
                    .frame(width: 8, height: 8)
                    .shadow(color: on ? .green.opacity(0.9) : .clear, radius: 4)
                    .offset(x: 3, y: -3)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(block.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text(store.blockSubtitle(block))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 86, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Color.orange.opacity(0.18) : Color(white: 0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.orange : Color.white.opacity(0.06), lineWidth: selected ? 1.5 : 1)
        )
        .opacity(on ? 1 : 0.6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(block.title), \(store.blockSubtitle(block))")
        .accessibilityValue(on ? "Encendido" : "Apagado")
        .accessibilityHint("Toca para editar. Mantén presionado para encender o apagar.")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Línea pequeña de arriba: posición en la cadena o tipo de bloque.
    private var caption: String {
        if let p = block.postIndex { return store.isOn(p) ? "POST" : "PRE" }
        return block == .amp ? "AMP" : "CAB"
    }
}

/// Edición completa (la antigua pestaña Efectos), en hoja, abierta en el bloque pedido.
struct AdvancedSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EffectsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
                }
        }
    }
}
