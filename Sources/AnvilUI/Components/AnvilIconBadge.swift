import SwiftUI

/// An SF Symbol in a rounded square — the thing the eye lands on first in a
/// row or on a card.
public struct AnvilIconBadge: View {
    private let systemImage: String
    private let tone: AnvilTone
    private let size: CGFloat

    public init(_ systemImage: String, tone: AnvilTone = .accent, size: CGFloat = AnvilSize.iconBadge) {
        self.systemImage = systemImage
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(AnvilColor.elevated)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(AnvilColor.border, lineWidth: AnvilSize.hairline)
            }
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(tone.color)
            }
            .frame(width: size, height: size)
    }
}

/// A small capsule carrying one word: a state, a count, a capability.
public struct AnvilPill: View {
    private let title: LocalizedStringKey
    private let tone: AnvilTone
    private let systemImage: String?

    public init(_ title: LocalizedStringKey, tone: AnvilTone = .neutral, systemImage: String? = nil) {
        self.title = title
        self.tone = tone
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(AnvilFont.micro)
            }
            Text(title)
                .font(AnvilFont.caption)
        }
        .foregroundStyle(tone == .neutral ? AnvilColor.textSecondary : tone.color)
        .padding(.horizontal, AnvilSpacing.sm)
        .padding(.vertical, 2)
        .background {
            Capsule(style: .continuous)
                .fill(tone == .neutral ? AnvilColor.elevated : tone.fill)
        }
    }
}
