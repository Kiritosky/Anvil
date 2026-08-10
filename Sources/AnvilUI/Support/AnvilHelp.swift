import SwiftUI

extension View {
    /// A tooltip that VoiceOver can also read.
    ///
    /// `.help(…)` alone leaves an icon-only button announced as "Taste" —
    /// the tooltip is a visual affordance and nothing else. Since every such
    /// button in this app already has a sentence explaining it, the same
    /// sentence becomes its accessibility label, and the two cannot drift.
    public func anvilHelp(_ text: LocalizedStringKey) -> some View {
        help(text)
            .accessibilityLabel(text)
    }

    /// Dasselbe für Text, der schon übersetzt ist — ein Titel aus einem
    /// Modell, ein zur Laufzeit zusammengesetzter Satz.
    ///
    /// Der Name muss `verbatim` heißen und darf **nicht** dieselbe
    /// Überladung ohne Etikett sein. Sonst gewinnt bei einem Literal diese
    /// hier: Der Standardtyp eines Zeichenketten-Literals ist `String`, also
    /// zieht Swift bei zwei gleich benannten Überladungen die mit `String`
    /// vor — und jeder Tooltip in der App stünde ohne Nachschlagen da, auf
    /// Deutsch, in jeder Sprache. Genau dieselbe Falle umgeht `Text` mit
    /// `Text(verbatim:)`.
    public func anvilHelp(verbatim text: String) -> some View {
        help(text)
            .accessibilityLabel(Text(verbatim: text))
    }
}
