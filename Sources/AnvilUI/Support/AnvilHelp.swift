import SwiftUI

extension View {
    /// A tooltip that VoiceOver can also read.
    public func anvilHelp(_ text: LocalizedStringKey) -> some View {
        help(text)
            .accessibilityLabel(text)
    }

    /// Dasselbe für Text, der schon übersetzt ist — ein Titel aus einem
    /// Modell, ein zur Laufzeit zusammengesetzter Satz.
    public func anvilHelp(verbatim text: String) -> some View {
        help(text)
            .accessibilityLabel(Text(verbatim: text))
    }
}
