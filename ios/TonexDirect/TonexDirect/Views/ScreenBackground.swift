import SwiftUI
import PhotosUI
import UIKit

/// Fondos de Live y Editar: una imagen con poco desenfoque y oscurecida para que se lea todo.
/// Se pueden apagar, elegir entre las incluidas o usar una foto propia del iPad.
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

/// Pantallas con fondo propio. Cada una guarda sus ajustes y su foto por separado.
enum BackgroundScope: String {
    case live, edit

    var title: String { self == .live ? "Fondo del modo Live" : "Fondo del modo Editar" }
    var defaultSource: LiveBackgroundSource { self == .live ? .studio : .stage }
    var defaultDim: Double { self == .live ? 0.5 : 0.6 }
    /// Prefijo de las claves (Live conserva las que ya tenía).
    private var prefix: String { self == .live ? "liveBg" : "editBg" }
    func key(_ name: String) -> String { "\(prefix).\(name)" }

    /// La foto propia se guarda en Documentos (reducida, para no gastar memoria).
    var customURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(rawValue)_background.jpg")
    }

    func saveCustom(_ image: UIImage) throws {
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

    func loadCustom() -> UIImage? { UIImage(contentsOfFile: customURL.path) }
}

/// La imagen de fondo ya compuesta (desenfoque + oscurecido). Negro si está apagada.
struct ScreenBackgroundView: View {
    let scope: BackgroundScope
    @AppStorage private var enabled: Bool
    @AppStorage private var source: String
    @AppStorage private var blur: Double
    @AppStorage private var dim: Double
    @AppStorage private var customVersion: Int
    @State private var custom: UIImage?

    init(_ scope: BackgroundScope) {
        self.scope = scope
        _enabled = AppStorage(wrappedValue: true, scope.key("enabled"))
        _source = AppStorage(wrappedValue: scope.defaultSource.rawValue, scope.key("source"))
        _blur = AppStorage(wrappedValue: 4.0, scope.key("blur"))
        _dim = AppStorage(wrappedValue: scope.defaultDim, scope.key("dim"))
        _customVersion = AppStorage(wrappedValue: 0, scope.key("customVersion"))
    }

    private var kind: LiveBackgroundSource { LiveBackgroundSource(rawValue: source) ?? scope.defaultSource }

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
            .task(id: "\(customVersion)-\(source)") {
                custom = kind == .custom ? scope.loadCustom() : nil
            }
    }

    private var image: Image? {
        if let asset = kind.asset { return Image(asset) }
        return custom.map { Image(uiImage: $0) }
    }
}

/// Sección de Ajustes para el fondo de una pantalla.
struct BackgroundSettings: View {
    let scope: BackgroundScope
    @AppStorage private var enabled: Bool
    @AppStorage private var source: String
    @AppStorage private var blur: Double
    @AppStorage private var dim: Double
    @AppStorage private var customVersion: Int
    @State private var pick: PhotosPickerItem?
    @State private var error: String?

    init(_ scope: BackgroundScope) {
        self.scope = scope
        _enabled = AppStorage(wrappedValue: true, scope.key("enabled"))
        _source = AppStorage(wrappedValue: scope.defaultSource.rawValue, scope.key("source"))
        _blur = AppStorage(wrappedValue: 4.0, scope.key("blur"))
        _dim = AppStorage(wrappedValue: scope.defaultDim, scope.key("dim"))
        _customVersion = AppStorage(wrappedValue: 0, scope.key("customVersion"))
    }

    private var hasCustom: Bool { FileManager.default.fileExists(atPath: scope.customURL.path) }

    var body: some View {
        Section {
            Toggle("Imagen de fondo", isOn: $enabled)
            if enabled {
                ScreenBackgroundView(scope)
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
            Text(scope.title)
        } footer: {
            Text(scope == .live
                 ? "Oscurecer un poco ayuda a leer el nombre del preset con las luces del escenario."
                 : "Con más oscuro se leen mejor las perillas y los valores.")
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { error = "No se pudo abrir esa imagen."; return }
                    try scope.saveCustom(image)
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
