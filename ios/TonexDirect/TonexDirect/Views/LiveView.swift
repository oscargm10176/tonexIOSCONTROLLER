import SwiftUI
import UIKit

/// Modo Live: para tocar. Todo grande, legible de lejos y a un toque.
/// - Preset actual (amp, número y nombre) al centro; desliza para cambiar.
/// - Botones laterales enormes con el nombre del preset anterior/siguiente.
/// - Fila de footswitches para encender/apagar los efectos.
struct LiveView: View {
    @Environment(ControllerStore.self) private var store
    @Environment(SetlistStore.self) private var setlists
    /// Candado: bloquea la pantalla para que un roce no cambie nada (el pedal de pie sigue funcionando).
    @AppStorage("live.locked") private var locked = false
    @State private var lockHint = false
    @State private var editingSetlists = false

    private let switches: [EffectBlock] = [.gate, .comp, .mod, .delay, .reverb]

    private func step(_ d: Int) {
        if setlists.active != nil {
            if d < 0 { setlists.previous(store: store) } else { setlists.next(store: store) }
        } else {
            if d < 0 { store.previousPreset() } else { store.nextPreset() }
        }
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 10) {
                topBar
                VStack(spacing: 14) {
                HStack(spacing: 14) {
                    LivePresetButton(direction: -1)
                        .frame(width: max(110, geo.size.width * 0.12))
                    presetDisplay(height: geo.size.height)
                    LivePresetButton(direction: +1)
                        .frame(width: max(110, geo.size.width * 0.12))
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 12) {
                    ForEach(switches, id: \.self) { LiveFootswitch(block: $0) }
                    if store.tempoAvailable { LiveTapSwitch() }
                }
                .frame(height: min(150, max(100, geo.size.height * 0.2)))
                .disabled(store.state != .ready)
                }
                .allowsHitTesting(!locked)
                .opacity(locked ? 0.92 : 1)
            }
            .padding(16)
        }
        .background(ScreenBackgroundView(.live))
        .sheet(isPresented: $editingSetlists) {
            NavigationStack {
                Form { SetlistsSection() }
                    .navigationTitle("Setlists")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { editingSetlists = false } } }
            }
        }
    }

    // MARK: Barra de arriba: setlist y candado

    private var topBar: some View {
        HStack(spacing: 12) {
            Menu {
                Button { setlists.activate(nil, store: store) } label: {
                    Label("Sin setlist (presets en orden)", systemImage: setlists.active == nil ? "checkmark" : "list.number")
                }
                if !setlists.setlists.isEmpty { Divider() }
                ForEach(setlists.setlists) { s in
                    Button { setlists.activate(s.id, store: store) } label: {
                        Label(s.name + " (\(s.songs.count))", systemImage: setlists.activeID == s.id ? "checkmark" : "music.note.list")
                    }
                }
                Divider()
                Button { editingSetlists = true } label: { Label("Editar setlists…", systemImage: "pencil") }
            } label: {
                Label(setlists.active?.name ?? "Setlist", systemImage: "music.note.list")
                    .font(.headline)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
            }
            .disabled(locked)

            if let a = setlists.active, let song = setlists.currentSong {
                Text(trf("Canción %@ de %@", setlists.songIndex + 1, a.songs.count))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let next = setlists.song(offset: 1) {
                    Text(trf("Sigue: %@", next.title))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !song.title.isEmpty {
                    Text("Última").font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if lockHint {
                Text("Mantén presionado para desbloquear")
                    .font(.callout.weight(.semibold))
                    .transition(.opacity)
            }
            lockButton
        }
        .frame(height: 44)
        .shadow(color: .black.opacity(0.6), radius: 6)
        .animation(.easeInOut(duration: 0.2), value: lockHint)
    }

    private var lockButton: some View {
        Image(systemName: locked ? "lock.fill" : "lock.open")
            .font(.title2.weight(.semibold))
            .foregroundStyle(locked ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .frame(width: 52, height: 44)
            .background(Capsule().fill(locked ? Color.orange.opacity(0.22) : Color.black.opacity(0.45)))
            .contentShape(Rectangle())
            .onTapGesture {
                if locked {
                    // con candado, un toque no basta: así no se quita por accidente
                    lockHint = true
                    Task { try? await Task.sleep(for: .seconds(2)); lockHint = false }
                } else {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    locked = true
                }
            }
            .onLongPressGesture(minimumDuration: 0.8) {
                guard locked else { return }
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                locked = false
                lockHint = false
            }
            .accessibilityLabel(locked ? "Pantalla bloqueada" : "Bloquear pantalla")
            .accessibilityHint(locked ? "Mantén presionado para desbloquear" : "Bloquea los toques en Live; el pedal de pie sigue funcionando")
            .accessibilityAction(named: locked ? "Desbloquear" : "Bloquear") { locked.toggle() }
    }

    // MARK: Preset al centro

    private func presetDisplay(height: CGFloat) -> some View {
        ZStack {
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                if let c = store.currentPreset, let shown = store.displaySkin(for: c) {
                    let skin = AmpSkins.skin(shown.index)
                    Image(skin.asset)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxHeight: height * (skin.isPedal ? 0.34 : 0.4))
                        .shadow(color: .black.opacity(0.7), radius: 18, y: 10)
                }
                if setlists.active != nil, let song = setlists.currentSong {
                    Text(song.title)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Text(store.currentPresetInfo?.label ?? "–")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                Text(store.currentPresetInfo?.name ?? "Sin preset")
                    .font(.system(size: 76, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.35)
                    .multilineTextAlignment(.center)
                if let c = store.currentPreset, let info = store.toneModels[c] {
                    Text(info.amp ?? info.model)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .shadow(color: .black.opacity(0.7), radius: 10)   // se lee bien sobre la foto de fondo
            .id(store.currentPreset)
            .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity),
                                    removal: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.22), value: store.currentPreset)
        .animation(.snappy(duration: 0.22), value: setlists.songIndex)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    guard store.state == .ready, abs(v.translation.width) > abs(v.translation.height) else { return }
                    if v.translation.width < -80 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        step(+1)
                    } else if v.translation.width > 80 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        step(-1)
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preset actual")
        .accessibilityAction(named: "Siguiente preset") { store.nextPreset() }
        .accessibilityAction(named: "Preset anterior") { store.previousPreset() }
    }
}

/// Botón lateral gigante: flecha + número y nombre del preset al que vas a ir.
struct LivePresetButton: View {
    @Environment(ControllerStore.self) private var store
    @Environment(SetlistStore.self) private var setlists
    let direction: Int

    /// Con setlist activo: la canción a la que vas.
    private var song: Song? { setlists.active != nil ? setlists.song(offset: direction) : nil }

    private var target: Preset? {
        guard store.maxPresets > 0 else { return nil }
        let current = store.currentPreset ?? 0
        let i = (current + direction + store.maxPresets) % store.maxPresets
        return store.presets.indices.contains(i) ? store.presets[i] : nil
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            if setlists.active != nil {
                if direction < 0 { setlists.previous(store: store) } else { setlists.next(store: store) }
            } else {
                if direction < 0 { store.previousPreset() } else { store.nextPreset() }
            }
        } label: {
            // Solo un círculo con la flecha y el preset destino; toda la columna sigue
            // siendo tocable (útil en el escenario) pero ya no se ve un recuadro enorme.
            VStack(spacing: 10) {
                Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                    .font(.system(size: 30, weight: .bold))
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .overlay(Circle().stroke(Color.white.opacity(0.15)))
                if setlists.active != nil {
                    if let s = song {
                        Text(s.title)
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 4)
                        if store.presets.indices.contains(s.slot) {
                            Text(store.presets[s.slot].label)
                                .font(.caption.weight(.heavy).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(direction < 0 ? "Inicio" : "Fin").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let t = target {
                    Text(t.label)
                        .font(.headline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(t.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 4)
                }
            }
            .shadow(color: .black.opacity(0.6), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(LivePressStyle())
        .disabled(store.state != .ready)
        .accessibilityLabel(direction < 0 ? "Preset anterior" : "Preset siguiente")
        .accessibilityValue(target.map { trf("Banco %@ %@, %@", $0.bank, $0.slot, $0.name) } ?? "")
    }
}

/// Footswitch grande para un bloque: LED, nombre y tipo. Un toque = encender/apagar.
struct LiveFootswitch: View {
    @Environment(ControllerStore.self) private var store
    let block: EffectBlock

    var body: some View {
        let on = store.isBlockOn(block)
        Button {
            guard let i = block.enableIndex else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            store.setToggle(i, !on)
        } label: {
            VStack(spacing: 8) {
                Circle()
                    .fill(on ? Color.red : Color(white: 0.25))
                    .frame(width: 16, height: 16)
                    .shadow(color: on ? .red : .clear, radius: 10)
                Text(block.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill((on ? Color(white: 0.2) : Color(white: 0.09)).opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(on ? Color.orange : Color.white.opacity(0.08), lineWidth: on ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(LivePressStyle())
        .animation(.easeOut(duration: 0.12), value: on)
        .accessibilityLabel(block.title)
        .accessibilityValue(on ? "Encendido" : "Apagado")
    }

    /// Para modulación/delay/reverb, el tipo; para gate/comp, la posición.
    private var subtitle: String {
        switch block {
        case .mod, .delay, .reverb: return store.blockSubtitle(block)
        default:
            if let p = block.postIndex { return store.isOn(p) ? "Post" : "Pre" }
            return ""
        }
    }
}

/// Se hunde un poco al presionar, para que se sienta como un botón físico.
struct LivePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
