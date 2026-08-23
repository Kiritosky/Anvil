import SwiftUI

/// The workhorse list row: badge, title with optional pills, subtitle, and an
/// action on the right. Every list of things-you-can-do in the app is a stack
/// of these, which is what makes the app look like one app.
public struct AnvilRow<Trailing: View>: View {
    private let systemImage: String
    private let tone: AnvilTone
    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let pills: [AnvilRowPill]
    private let trailing: Trailing

    @State private var isHovering = false

    public init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String,
        tone: AnvilTone = .accent,
        pills: [AnvilRowPill] = [],
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tone = tone
        self.pills = pills
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.md) {
            AnvilIconBadge(systemImage, tone: tone)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: AnvilSpacing.sm) {
                    Text(title)
                        .font(AnvilFont.rowTitle)
                        .foregroundStyle(AnvilColor.textPrimary)

                    ForEach(pills) { pill in
                        AnvilPill(pill.title, tone: pill.tone, systemImage: pill.systemImage)
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: AnvilSpacing.md)

            trailing
        }
        .padding(.horizontal, AnvilSpacing.md)
        .padding(.vertical, AnvilSpacing.sm)
        .background {
            if isHovering {
                RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                    .fill(AnvilColor.hover)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(AnvilMotion.quick, value: isHovering)
    }
}

extension AnvilRow where Trailing == EmptyView {
    public init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String,
        tone: AnvilTone = .accent,
        pills: [AnvilRowPill] = []
    ) {
        self.init(
            title,
            subtitle: subtitle,
            systemImage: systemImage,
            tone: tone,
            pills: pills,
            trailing: { EmptyView() }
        )
    }
}

/// One of the little capsules next to a row title.
public struct AnvilRowPill: Identifiable {
    public let id = UUID()
    public let title: LocalizedStringKey
    public let tone: AnvilTone
    public let systemImage: String?

    public init(_ title: LocalizedStringKey, tone: AnvilTone = .neutral, systemImage: String? = nil) {
        self.title = title
        self.tone = tone
        self.systemImage = systemImage
    }
}

/// A stack of rows in one card, separated by hairlines rather than gaps.
public struct AnvilRowGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
        }
        .anvilSurface(.surface, padding: AnvilSpacing.xs)
    }
}
