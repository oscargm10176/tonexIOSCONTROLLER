import SwiftUI

/// Idioma de la app: Español o English (o el del sistema). Cambia al instante, sin reiniciar.
///
/// - Los textos fijos de SwiftUI (`Text("…")`, `Button("…")`…) se traducen con el `locale`
///   del entorno, que se pone en la raíz de la app.
/// - Los textos que se arman en código (mensajes, títulos de bloques…) pasan por `tr()`/`trf()`.
/// Las traducciones están en `Localizable.xcstrings` (las claves son el texto en español).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, es, en
    var id: String { rawValue }

    /// Nombre en su propio idioma, para el selector.
    var title: String {
        switch self {
        case .system: return tr("Idioma del sistema")
        case .es: return "Español"
        case .en: return "English"
        }
    }
}

@MainActor
@Observable
final class LanguageStore {
    private static let key = "app.language"

    private(set) var choice: AppLanguage
    /// "es" o "en": lo que realmente se usa.
    private(set) var code: String

    var locale: Locale { Locale(identifier: code) }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.key).flatMap(AppLanguage.init) ?? .system
        choice = saved
        code = Self.resolve(saved)
        L10n.use(code)
    }

    func set(_ language: AppLanguage) {
        choice = language
        code = Self.resolve(language)
        L10n.use(code)
        UserDefaults.standard.set(language.rawValue, forKey: Self.key)
        // También para lo que iOS muestra por su cuenta (permisos, selector de archivos…)
        // la próxima vez que se abra la app.
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    private static func resolve(_ l: AppLanguage) -> String {
        switch l {
        case .es: return "es"
        case .en: return "en"
        case .system:
            let first = (Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "es").lowercased()
            return first.hasPrefix("es") ? "es" : "en"
        }
    }
}

/// Búsqueda de traducciones para textos armados en código.
enum L10n {
    private(set) static var code = "es"
    private static var bundle: Bundle = .main

    static func use(_ code: String) {
        self.code = code
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let b = Bundle(path: path) {
            bundle = b
        } else {
            bundle = .main
        }
    }

    static func string(_ key: String) -> String {
        guard code != "es" else { return key }            // las claves ya están en español
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Traduce un texto fijo (la clave es el texto en español).
func tr(_ key: String) -> String { L10n.string(key) }

/// Traduce un formato con valores: `trf("Leyendo %@ de %@…", "3", "12")`.
/// Todos los valores se pasan como texto (`%@`), así el formato es igual en ambos idiomas.
func trf(_ key: String, _ args: CustomStringConvertible...) -> String {
    let format = L10n.string(key)
    return String(format: format, arguments: args.map { $0.description as NSString as CVarArg })
}
