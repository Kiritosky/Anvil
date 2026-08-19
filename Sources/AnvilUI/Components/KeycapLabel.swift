import SwiftUI

/// Eine Tastenkombination, gezeichnet wie eine Taste: „⌥⌘D", „⌘1".
public struct KeycapLabel: View {
    private let keys: String
    /// Für Kürzel, die zwar eingetragen, aber gerade nicht scharf sind.
    private let isMuted: Bool

    public init(_ keys: String, isMuted: Bool = false) {
        self.keys = keys
        self.isMuted = isMuted
    }

    public var body: some View {
        Text.raw(keys)
            .font(AnvilFont.monoSmall)
            .foregroundStyle(isMuted ? AnvilColor.textTertiary : AnvilColor.textSecondary)
            .padding(.horizontal, AnvilSpacing.xs)
            .padding(.vertical, AnvilSpacing.xxs)
            .background {
                RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                    .fill(AnvilColor.field)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                    .strokeBorder(AnvilColor.border, lineWidth: AnvilSize.hairline)
            }
            .fixedSize()
            .accessibilityHidden(true)
    }
}
