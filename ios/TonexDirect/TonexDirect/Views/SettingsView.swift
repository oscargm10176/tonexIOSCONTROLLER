import SwiftUI
import UIKit

struct SettingsView: View {
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    @Environment(ControllerStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var savingPresets = false
    @State private var showingLibrary = false
    @State private var showingFullBackup = false
    @Environment(LanguageStore.self) private var language
    @Environment(PresetLibrary.self) private var library

    var body: some View {
        Group {
            Form {
                Section {
                    Picker(selection: Binding(get: { language.choice }, set: { language.set($0) })) {
                        ForEach(AppLanguage.allCases) { l in Text(l.title).tag(l) }
                    } label: {
                        Label("Idioma", systemImage: "globe")
                    }
                } header: {
                    Text("Idioma")
                }

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
                    Button {
                        savingPresets = true
                    } label: {
                        Label("Guardar presets…", systemImage: "square.and.arrow.down.on.square")
                    }
                    .disabled(store.state != .ready)
                    Button {
                        showingFullBackup = true
                    } label: {
                        Label("Respaldo completo del pedal…", systemImage: "externaldrive.badge.icloud")
                    }
                    .disabled(store.state != .ready)
                    Button {
                        showingLibrary = true
                    } label: {
                        LabeledContent {
                            Text("\(library.entries.count)")
                        } label: {
                            Label("Mis presets", systemImage: "tray.full")
                        }
                    }
                } header: {
                    Text("Respaldo de presets")
                } footer: {
                    Text("Elige uno, un banco o todos y se guardan en este iPad. Solo lee del pedal, no cambia nada. Desde “Mis presets” puedes compartirlos o copiarlos a otra ubicación.")
                }

                FootPedalSection()

                ExpressionPedalSection()

                SetlistsSection()

                BackgroundSettings(.edit)

                BackgroundSettings(.live)

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
                    Button {
                        store.downloadFullPreset()
                    } label: {
                        HStack {
                            Label("Descargar preset completo (el activo)", systemImage: "square.and.arrow.down")
                            Spacer()
                            if store.dumpInProgress != nil { ProgressView() }
                        }
                    }
                    .disabled(store.state != .ready || store.dumpInProgress != nil)

                    ForEach(store.presetDumps, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc.zipper")
                            Text(url.lastPathComponent)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        }
                        .swipeActions {
                            Button("Borrar", role: .destructive) { store.deleteDump(url) }
                        }
                    }
                } header: {
                    Text("Preset completo (investigación)")
                } footer: {
                    Text("Solo lee del pedal, no cambia nada. Descarga dos presets que solo difieran en el amp y compártelos (AirDrop a la Mac o Guardar en Archivos). También aparecen en Archivos › En mi iPad › TONE › PresetDumps.")
                }

                Section {
                    LabeledContent("Recibido", value: trf("%@ bytes · %@ tramas · %@ inválidas", store.rxBytes, store.rxFrames, store.rxBadFrames))
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
                    LabeledContent("Versión", value: Self.appVersion)
                    Link(destination: URL(string: "https://github.com/oscargm10176/tonexIOSCONTROLLER")!) {
                        Label("github.com/oscargm10176/tonexIOSCONTROLLER", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("Acerca de TONE")
                } footer: {
                    Text("No está afiliado a IK Multimedia. TONEX es marca registrada de IK Multimedia Production Srl.")
                }
            }
            .navigationTitle("Ajustes")
            .sheet(isPresented: $savingPresets) { SavePresetsSheet(preselect: store.currentPreset.map { [$0] } ?? []) }
            .sheet(isPresented: $showingLibrary) { PresetLibraryView() }
            .sheet(isPresented: $showingFullBackup) { FullBackupSheet() }
        }
    }
}
