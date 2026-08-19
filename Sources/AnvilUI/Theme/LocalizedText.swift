import SwiftUI

extension LocalizedStringKey {
    /// Wraps text that was already translated at runtime.
    public static func resolved(_ value: String) -> LocalizedStringKey {
        LocalizedStringKey(value)
    }

    /// Same, for optional values.
    public static func resolvedIfPresent(_ value: String?) -> LocalizedStringKey? {
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
