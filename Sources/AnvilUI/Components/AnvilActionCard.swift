import SwiftUI

/// A card that offers one thing: icon, title, a sentence, one action. Used in
/// grids where the choices are equals — bundles, starting points, tools.
public struct AnvilActionCard<Action: View>: View {
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let systemImage: String
    private let tone: AnvilTone
    private let action: Action

    @State private var isHovering = false

    public init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String,
        tone: AnvilTone = .accent,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tone = tone
        self.action = action()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
            HStack(spacing: AnvilSpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tone.color)

                Text(title)
                    .font(AnvilFont.rowTitle)
                    .foregroundStyle(AnvilColor.textPrimary)
            }

            if let subtitle {
                Text(subtitle)
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            action
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .anvilSurface(.elevated, radius: AnvilRadius.md)
        .overlay {
            if isHovering {
                RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                    .strokeBorder(AnvilColor.accent.opacity(0.5), lineWidth: AnvilSize.hairline)
            }
        }
        .onHover { isHovering = $0 }
        .animation(AnvilMotion.quick, value: isHovering)
    }
}

extension AnvilActionCard where Action == EmptyView {
    public init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String,
        tone: AnvilTone = .accent
    ) {
        self.init(title, subtitle: subtitle, systemImage: systemImage, tone: tone) { EmptyView() }
    }
}
