import SwiftUI

extension LocalizedStringKey {
    /// Wraps text that was already translated at runtime.
    ///
    /// Anvil's components take `LocalizedStringKey` so that literals written in
    /// a view are translated with no further ceremony. Some text, though, is
    /// produced by a model object that already localised it — an error message,
    /// a tool title from the registry, an enum's display name.
    ///
    /// Passing such a string here is safe: German source text is its own key,
    /// so a lookup either finds the entry (and returns the same thing) or falls
    /// through to the value. The point of the spelling is intent — a reader can
    /// see at a glance which strings are literals and which are already done.
    public static func resolved(_ value: String) -> LocalizedStringKey {
        LocalizedStringKey(value)
    }

    /// Same, for optional values.
    public static func resolved(_ value: String?) -> LocalizedStringKey? {
        value.map { LocalizedStringKey($0) }
    }
}

extension Text {
    /// Text that must never be translated: file names, identifiers, model
    /// names, anything the user typed.
    public static func raw(_ value: String) -> Text {
        Text(verbatim: value)
    }
}
