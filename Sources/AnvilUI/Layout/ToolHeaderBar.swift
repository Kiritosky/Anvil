import SwiftUI

/// The bar at the top of every tool: identity on the left, actions on the right.
public struct ToolHeaderBar<Actions: View>: View {
    private let title: String
    private let subtitle: String
    private let systemImage: String
    private let tone: AnvilTone
    private let actions: Actions

    public init(
        title: String,
        subtitle: String = "",
        systemImage: String,
        tone: AnvilTone = .accent,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tone = tone
        self.actions = actions()
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.md) {
            ToolIconBadge(systemImage: systemImage, tone: tone)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AnvilFont.title)
                    .foregroundStyle(AnvilColor.textPrimary)
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AnvilSpacing.lg)

            HStack(spacing: AnvilSpacing.sm) {
                actions
            }
        }
        .padding(.horizontal, AnvilSpacing.lg)
        .frame(height: AnvilSize.headerHeight)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

extension ToolHeaderBar where Actions == EmptyView {
    public init(
        title: String,
        subtitle: String = "",
        systemImage: String,
        tone: AnvilTone = .accent
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tone: tone,
            actions: { EmptyView() }
        )
    }
}

/// The tinted rounded square a tool is identified by.
public struct ToolIconBadge: View {
    private let systemImage: String
    private let tone: AnvilTone
    private let size: CGFloat

    public init(systemImage: String, tone: AnvilTone = .accent, size: CGFloat = 30) {
        self.systemImage = systemImage
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size / 3.4, style: .continuous)
            .fill(tone.fill)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.48, weight: .medium))
                    .foregroundStyle(tone.color)
            }
            .frame(width: size, height: size)
    }
}
