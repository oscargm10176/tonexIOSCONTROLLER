import SwiftUI
import PhotosUI
import UIKit

/// Fondo del modo Live: una imagen con poco desenfoque y oscurecida para que se lea todo.
/// Se puede apagar, elegir entre las incluidas o usar una foto propia del iPad.
enum LiveBackgroundSource: String, CaseIterable, Identifiable {
    case studio, stage, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .studio: return "Estudio"
        case .stage: return "Escenario"
        case .custom: return "Mi foto"
        }
    }
    var asset: String? {
        switch self {
        case .studio: return "live_background"
        case .stage: return "loading_background"
        case .custom: return nil
        }
    }
}

enum LiveBackgroundKeys {
    static let enabled = "liveBg.enabled"
    static let source = "liveBg.source"
    static let blur = "liveBg.blur"
    static let dim = "liveBg.dim"
    static let customVersion = "liveBg.customVersion"

    /// La foto propia se guarda en Documentos (reducida, para no gastar memoria).
    static var customURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("live_background.jpg")
    }

    static func saveCustom(_ image: UIImage) throws {
        let maxSide: CGFloat = 2400
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return }
        try data.write(to: customURL, options: .atomic)
    }

    static func loadCustom() -> UIImage? {
        UIImage(contentsOfFile: customURL.path)
    }
}

/// La imagen de fondo ya compuesta (desenfoque + oscurecido). Negro si está apagada.
struct LiveBackgroundView: View {
    @AppStorage(LiveBackgroundKeys.enabled) private var enabled = true
    @AppStorage(LiveBackgroundKeys.source) private var source = LiveBackgroundSource.studio.rawValue
    @AppStorage(LiveBackgroundKeys.blur) private var blur = 4.0
    @AppStorage(LiveBackgroundKeys.dim) private var dim = 0.5
    @AppStorage(LiveBackgroundKeys.customVersion) private var customVersion = 0
    @State private var custom: UIImage?

    private var kind: LiveBackgroundSource { LiveBackgroundSource(rawValue: source) ?? .studio }

    var body: some View {
        Color.black
            .overlay {
                if enabled, let image {
                    image
                        .resizable()
                        .scaledToFill()
                        // un poco más grande para que el desenfoque no deje bordes claros
                        .scaleEffect(1 + blur / 200)
                        .blur(radius: blur, opaque: true)
                        .overlay(Color.black.opacity(dim))
                        .transition(.opacity)
                }
            }
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
            .animation(.easeInOut(duration: 0.3), value: enabled)
            .task(id: customVersion) { custom = kind == .custom ? LiveBackgroundKeys.loadCustom() : nil }
            .onChange(of: source) { _, _ in custom = kind == .custom ? LiveBackgroundKeys.loadCustom() : nil }
    }

    private var image: Image? {
        if let asset = kind.asset { return Image(asset) }
        return custom.map { Image(uiImage: $0) }
    }
}

/// Sección de Ajustes para el fondo de Live.
struct LiveBackgroundSettings: View {
    @AppStorage(LiveBackgroundKeys.enabled) private var enabled = true
    @AppStorage(LiveBackgroundKeys.source) private var source = LiveBackgroundSource.studio.rawValue
    @AppStorage(LiveBackgroundKeys.blur) private var blur = 4.0
    @AppStorage(LiveBackgroundKeys.dim) private var dim = 0.5
    @AppStorage(LiveBackgroundKeys.customVersion) private var customVersion = 0
    @State private var pick: PhotosPickerItem?
    @State private var error: String?

    private var hasCustom: Bool { FileManager.default.fileExists(atPath: LiveBackgroundKeys.customURL.path) }

    var body: some View {
        Section {
            Toggle("Imagen de fondo", isOn: $enabled)
            if enabled {
                LiveBackgroundView()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(Text("Vista previa").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8)))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .id(customVersion)

                Picker("Imagen", selection: $source) {
                    ForEach(LiveBackgroundSource.allCases.filter { $0 != .custom || hasCustom || source == $0.rawValue }) {
                        Text($0.title).tag($0.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                PhotosPicker(selection: $pick, matching: .images) {
                    Label(hasCustom ? "Cambiar mi foto…" : "Usar una foto del iPad…", systemImage: "photo.on.rectangle")
                }

                LabeledContent("Desenfoque") {
                    Slider(value: $blur, in: 0...20, step: 1).frame(maxWidth: 260)
                }
                LabeledContent("Oscurecer") {
                    Slider(value: $dim, in: 0...0.85).frame(maxWidth: 260)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        } header: {
            Text("Fondo del modo Live")
        } footer: {
            Text("Oscurecer un poco ayuda a leer el nombre del preset con las luces del escenario.")
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { error = "No se pudo abrir esa imagen."; return }
                    try LiveBackgroundKeys.saveCustom(image)
                    error = nil
                    source = LiveBackgroundSource.custom.rawValue
                    customVersion += 1
                } catch {
                    self.error = "No se pudo guardar la imagen."
                }
                pick = nil
            }
        }
    }
}
