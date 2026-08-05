import Foundation

/// How Anvil handles languages.
///
/// The development language is German, and **the German text is the key**. So
/// `String(localized: "Aufnehmen")` looks up "Aufnehmen", and if no translation
/// exists it renders "Aufnehmen" — the correct German. That means:
///
/// - no invented key names like `speech.record.button` to keep in sync,
/// - a missing translation degrades to correct German rather than to a key,
/// - adding a language is one `.lproj` folder, nothing else.
///
/// Everything resolves against `Bundle.main`, which is the app bundle. Library
/// targets therefore need no `bundle:` argument and no `Bundle.module`, and
/// SwiftUI's implicit `Text("…")` already does the right thing.
///
/// ## Rules for new code
///
/// - Text written literally in a view: pass it to a component that takes
///   `LocalizedStringKey`, or use `Text("…")`. Nothing else to do.
/// - Text built in a model, catalog or error: wrap it in
///   ``AnvilKit/localized(_:comment:)`` or `String(localized:)`.
/// - Text that must *not* be translated (file names, identifiers, model names,
///   user content): use `Text(verbatim:)` or plain `String`.
/// - Values inside a sentence go through interpolation, so the key keeps its
///   format specifier: `localized("\(count) Wörter")` has the key
///   `"%lld Wörter"`.
public enum Localization {
    /// Languages the app ships translations for.
    ///
    /// German is the source language and has no `.lproj` of its own — its
    /// strings *are* the keys.
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
    ///
    /// Running the executable straight out of SwiftPM's build folder — rather
    /// than the assembled `.app` — leaves the `.lproj` folders behind, and
    /// everything falls back to German. Worth being able to check rather than
    /// wonder.
    public static var hasLoadedTranslations: Bool {
        !Bundle.main.localizations.filter { $0 != "Base" }.isEmpty
    }
}

/// Looks up a translation for `key`, falling back to the key itself.
///
/// A free function rather than a `String` extension so it reads like what it is
/// at the call site: `localized("Aufnehmen")`.
///
/// - Parameter comment: context for whoever translates it. Worth writing
///   whenever the German is ambiguous out of context — "Stopp" as a button is
///   not "Stopp" as a status.
public func localized(_ key: String.LocalizationValue, comment: StaticString? = nil) -> String {
    String(localized: key, comment: comment)
}

/// Looks up a translation for a string that is only known at runtime.
///
/// Used where display text arrives as data rather than as a literal — tool
/// titles from a catalog, mode names, anything a `ToolMetadata` was built with.
/// Text that has no entry (a user's own tool title, say) simply comes back
/// unchanged, which is exactly the desired behaviour.
public func localized(runtime value: String) -> String {
    guard !value.isEmpty else { return value }
    return String(localized: String.LocalizationValue(stringLiteral: value))
}
