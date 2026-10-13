import SwiftUI
import CoreAudioKit

/// Sección de Ajustes: conectar el pedal de pie (Bluetooth MIDI) y elegir qué hace cada botón.
struct FootPedalSection: View {
    @Environment(FootController.self) private var foot
    @State private var pairing = false

    var body: some View {
        Section {
            Button {
                pairing = true
            } label: {
                Label("Conectar pedal Bluetooth…", systemImage: "dot.radiowaves.left.and.right")
            }

            LabeledContent("Dispositivos MIDI") {
                Text(foot.sources.isEmpty ? "Ninguno" : foot.sources.joined(separator: ", "))
                    .multilineTextAlignment(.trailing)
            }
            if let m = foot.lastMessage {
                LabeledContent("Último botón recibido") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(m).font(.callout.monospaced())
                        if let a = foot.lastAction {
                            Text(a).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ForEach(foot.bindings) { b in
                FootBindingRow(binding: b)
            }
            .onDelete { idx in idx.map { foot.bindings[$0].id }.forEach(foot.remove) }

            Button { foot.add() } label: {
                Label("Agregar botón", systemImage: "plus.circle")
            }
        } header: {
            Text("Pedal de pie (Bluetooth MIDI)")
        } footer: {
            Text("Funciona con iRig BlueBoard y cualquier pedal MIDI. 1) Conéctalo con “Conectar pedal Bluetooth…”. 2) En cada fila toca “Aprender” y pisa el botón del pedal. 3) Elige qué hace. Desliza una fila para borrarla.")
        }
        .sheet(isPresented: $pairing) {
            NavigationStack {
                BluetoothMIDIPairing()
                    .navigationTitle("Pedal Bluetooth")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Listo") { pairing = false; foot.connectSources() }
                        }
                    }
            }
        }
    }
}

struct FootBindingRow: View {
    @Environment(FootController.self) private var foot
    let binding: FootBinding

    private var isLearning: Bool { foot.learning == binding.id }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(binding.name).font(.body.weight(.semibold))
                Text(isLearning ? tr("Pisa el botón del pedal…") : (binding.trigger?.label ?? tr("Sin asignar")))
                    .font(.caption.monospaced())
                    .foregroundStyle(isLearning ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .frame(minWidth: 150, alignment: .leading)

            Spacer()

            Menu {
                ForEach(FootAction.all, id: \.self) { a in
                    Button { foot.setAction(binding.id, a) } label: {
                        Label(a.title, systemImage: a.systemImage)
                    }
                }
            } label: {
                Label(binding.action.title, systemImage: binding.action.systemImage)
                    .font(.callout)
            }

            Button(isLearning ? "Cancelar" : "Aprender") {
                foot.learning = isLearning ? nil : binding.id
            }
            .buttonStyle(.bordered)
            .tint(isLearning ? .orange : nil)

            Button {
                foot.perform(binding.action)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(trf("Probar %@", binding.action.title))
        }
        .contextMenu {
            if binding.trigger != nil {
                Button("Quitar botón asignado", role: .destructive) { foot.clearTrigger(binding.id) }
            }
        }
    }
}

/// Pantalla del sistema para buscar y conectar dispositivos MIDI por Bluetooth.
struct BluetoothMIDIPairing: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDICentralViewController {
        CABTMIDICentralViewController()
    }
    func updateUIViewController(_ vc: CABTMIDICentralViewController, context: Context) {}
}

/// Pedales de expresión (CC continuo): volumen, gain o mix de delay/reverb.
struct ExpressionPedalSection: View {
    @Environment(FootController.self) private var foot

    var body: some View {
        Section {
            ForEach(foot.expressions) { e in
                ExpressionRow(binding: e)
            }
            .onDelete { idx in idx.map { foot.expressions[$0].id }.forEach(foot.removeExpression) }
            Button { foot.addExpression() } label: {
                Label("Agregar pedal de expresión", systemImage: "plus.circle")
            }
        } header: {
            Text("Pedales de expresión")
        } footer: {
            Text("Conecta el pedal de expresión al BlueBoard, toca “Aprender” y muévelo de punta a punta. Si sube al revés, activa “Invertir”.")
        }
    }
}

struct ExpressionRow: View {
    @Environment(FootController.self) private var foot
    let binding: ExpressionBinding
    private var isLearning: Bool { foot.learningExpression == binding.id }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(binding.name).font(.body.weight(.semibold))
                Text(isLearning ? tr("Mueve el pedal de expresión…") : (binding.trigger?.label ?? tr("Sin asignar")))
                    .font(.caption.monospaced())
                    .foregroundStyle(isLearning ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .frame(minWidth: 150, alignment: .leading)
            Spacer()
            Menu {
                ForEach(ExpressionTarget.allCases) { t in
                    Button { foot.setExpression(binding.id, target: t) } label: { Label(t.title, systemImage: t.systemImage) }
                }
            } label: {
                Label(binding.target.title, systemImage: binding.target.systemImage).font(.callout)
            }
            Toggle("Invertir", isOn: Binding(get: { binding.inverted },
                                             set: { foot.setExpression(binding.id, inverted: $0) }))
                .toggleStyle(.button)
                .font(.callout)
            Button(isLearning ? "Cancelar" : "Aprender") {
                foot.learningExpression = isLearning ? nil : binding.id
            }
            .buttonStyle(.bordered)
            .tint(isLearning ? .orange : nil)
        }
    }
}
