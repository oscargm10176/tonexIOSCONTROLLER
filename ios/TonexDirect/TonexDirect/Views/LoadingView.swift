import SwiftUI
import UIKit

/// Pantalla de carga al abrir la app: se muestra hasta que la primera sincronización con
/// el pedal termina, para no enseñar una interfaz vacía ("Sin preset").
/// Después, si la conexión se cae, basta el aviso de arriba (no vuelve a tapar todo).
struct LoadingView: View {
    @Environment(ControllerStore.self) private var store
    @Environment(\.openURL) private var openURL
    /// Permite entrar a la app sin pedal (p. ej. para ver Ajustes o el diagnóstico).
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            // Foto del escenario de fondo, oscurecida para que el texto se lea bien.
            // (overlay sobre Color: la foto llena la pantalla sin agrandar el resto del diseño)
            Color.black
                .overlay {
                    Image("loading_background")
                        .resizable()
                        .scaledToFill()
                        .accessibilityHidden(true)
                }
                .clipped()
                .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.35), .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: store.state.isBusy)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(height: 80)

                VStack(spacing: 10) {
                    Text("TONE")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                }

                progress
                    .frame(width: 420)
                    .frame(height: 50)

                if let hint {
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                if store.state == .waitingForPedal {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Label("Abrir Ajustes del iPad", systemImage: "gear")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Entrar sin pedal", action: onSkip)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 24)
            }
            .padding(24)
            .shadow(color: .black.opacity(0.6), radius: 8)
            .animation(.easeInOut(duration: 0.25), value: store.state)
        }
    }

    private var icon: String {
        switch store.state {
        case .waitingForPedal: return "cable.connector"
        case .failed: return "exclamationmark.triangle"
        default: return "hifispeaker.2"
        }
    }

    private var title: String {
        switch store.state {
        case .idle, .waitingForPedal: return tr("Conecta el Tonex Pedal por USB-C")
        case .connecting: return tr("Conectando con el pedal…")
        case .syncing: return tr("Leyendo tus presets…")
        case .ready: return tr("Listo")
        case .failed(let m): return m
        }
    }

    private var hint: String? {
        switch store.state {
        case .waitingForPedal:
            return tr("Si ya está conectado, activa el driver en Ajustes › General › Drivers (o en los ajustes de esta app).")
        case .failed:
            return tr("Se reintenta solo en unos segundos. Si sigue, desconecta y vuelve a conectar el pedal.")
        default:
            return nil
        }
    }

    @ViewBuilder
    private var progress: some View {
        switch store.state {
        case let .syncing(done, total):
            VStack(spacing: 8) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(.orange)
                Text(trf("%@ de %@", done, total))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .connecting:
            ProgressView().controlSize(.large)
        default:
            Color.clear
        }
    }
}
