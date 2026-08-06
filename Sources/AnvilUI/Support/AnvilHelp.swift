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

    /// The same, for text that has already been translated — a title out of a
    /// model, or a sentence assembled at runtime.
    public func anvilHelp(_ text: String) -> some View {
        help(text)
            .accessibilityLabel(Text(verbatim: text))
    }
}
