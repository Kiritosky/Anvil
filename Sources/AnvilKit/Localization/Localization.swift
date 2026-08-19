import Foundation

/// How Anvil handles languages.
public enum Localization {
    /// Languages the app ships translations for.
    public static let supportedLanguages = ["de", "en"]

    public static let developmentLanguage = "de"

    /// The language the app is actually running in.
    public static var currentLanguageCode: String {
        Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? developmentLanguage
    }

    /// The current language's own name, for showing in the UI.
    public static var currentLanguageName: String {
        let code = currentLanguageCode
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// Whether translations were actually found in the bundle.
    public static var hasLoadedTranslations: Bool {
        !Bundle.main.localizations.filter { $0 != "Base" }.isEmpty
    }
}

/// Looks up a translation for `key`, falling back to the key itself.
public func localized(_ key: String.LocalizationValue, comment: StaticString? = nil) -> String {
    String(localized: key, comment: comment)
}

/// Looks up a translation for a string that is only known at runtime.
public func localized(runtime value: String) -> String {
    guard !value.isEmpty else { return value }
    return String(localized: String.LocalizationValue(stringLiteral: value))
}
