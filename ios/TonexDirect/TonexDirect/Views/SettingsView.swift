import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(ControllerStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            Form {
                Section {
                    LabeledContent("Estado", value: store.state.label)
                    if let m = store.modeller {
                        LabeledContent("Pedal", value: m.displayName)
                    }
                    if store.maxPresets > 0 {
                        LabeledContent("Presets", value: "\(store.maxPresets)")
                    }
                    if store.state == .ready {
                        Button("Releer preset y globales") { store.refresh() }
                        Button("Desconectar", role: .destructive) { store.disconnect() }
                    } else if store.state == .idle {
                        Button("Conectar") { store.connect() }
                    }
                } header: {
                    Text("Conexión USB")
                } footer: {
                    Text("Conecta el Tonex Pedal al puerto USB-C del iPad (cable USB-C a USB-B, o adaptador). La primera vez, activa el driver en Ajustes › General › Drivers.")
                }

                Section {
                    Button("Abrir los ajustes de la app") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } header: {
                    Text("Driver")
                } footer: {
                    Text("El driver solo se ejecuta mientras el pedal está conectado. Si lo apagas en Ajustes, la app dejará de ver el pedal.")
                }

                if store.state == .ready {
                    Section("Globales del pedal") {
                        ForEach(TonexCatalog.globals.filter { store.supports($0.index) }, id: \.index) {
                            ParamRow(spec: $0)
                        }
                    }
                }

                Section {
                    LabeledContent("Recibido", value: "\(store.rxBytes) bytes · \(store.rxFrames) tramas · \(store.rxBadFrames) inválidas")
                    HStack {
                        Button("Copiar registro") {
                            UIPasteboard.general.string = store.diagnostics.joined(separator: "\n")
                        }
                        Spacer()
                        Button("Borrar", role: .destructive) { store.clearDiagnostics() }
                    }
                    if store.diagnostics.isEmpty {
                        Text("Sin eventos todavía").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(store.diagnostics.suffix(60).enumerated().reversed()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("Diagnóstico")
                } footer: {
                    Text("Si algo falla, toca \"Copiar registro\" y pégalo en el chat.")
                }

                Section {
                    Text("Protocolo USB basado en TonexOneController de Greg Smith (Apache 2.0).")
                    Link("github.com/Builty/TonexOneController",
                         destination: URL(string: "https://github.com/Builty/TonexOneController")!)
                } header: {
                    Text("Créditos")
                } footer: {
                    Text("No está afiliado a IK Multimedia. TONEX es marca registrada de IK Multimedia Production Srl.")
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}
