import SwiftUI
import UIKit

@main
struct TonexDirectApp: App {
    @State private var store = ControllerStore()
    /// Pedal de pie Bluetooth/USB MIDI (iRig BlueBoard, etc.).
    @State private var foot = FootController()
    /// Presets guardados en el iPad.
    @State private var library = PresetLibrary()
    /// Setlists para Live.
    @State private var setlists = SetlistStore()
    /// Idioma (Español / English), cambia al instante.
    @State private var language = LanguageStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Rehacer toda la interfaz al cambiar de idioma (los datos del pedal se quedan).
                .id(language.code)
                .environment(\.locale, language.locale)
                .environment(language)
                .environment(store)
                .environment(foot)
                .environment(library)
                .environment(setlists)
                .preferredColorScheme(.dark)
                .tint(.orange)
                .onAppear {
                    store.connect()
                    foot.attach(store, setlists: setlists)
                }
                // Un .tonepreset abierto desde Archivos, AirDrop, Mail…: se importa a "Mis presets".
                .onOpenURL { url in
                    library.importFiles([url])
                    library.wantsToShow = true
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.resume() }
        }
    }
}

struct ConnectionBanner: View {
    @Environment(ControllerStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if store.state.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "cable.connector")
                }
                Text(store.state.label)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            if store.state == .waitingForPedal {
                HStack(alignment: .firstTextBaseline) {
                    Text("Si ya está conectado, activa el driver en Ajustes › General › Drivers (o en los ajustes de esta app).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Abrir Ajustes") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.18))
    }
}
