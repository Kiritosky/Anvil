import SwiftUI

/// A titled content pane: header strip, then content.
///
/// The workhorse container inside tools — an input pane, a result pane, a log.
/// Panes fill the space they are given, so two of them inside a
/// ``WorkbenchLayout`` line up exactly.
public struct AnvilPane<Content: View, Accessory: View>: View {
    @Environment(\.anvilTheme) private var theme

    private let title: LocalizedStringKey
    private let systemImage: String?
    private let tone: AnvilTone
    /// Drawn flush to the pane edges (text editors), or inset (forms, lists).
    private let contentInset: Bool
    private let content: Content
    private let accessory: Accessory

    public init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        tone: AnvilTone = .neutral,
        contentInset: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.contentInset = contentInset
        self.content = content()
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(contentInset ? theme.density.contentPadding : 0)
        }
        .frame(minHeight: AnvilSize.paneMinHeight)
        .background(AnvilColor.field)
        .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                .strokeBorder(AnvilColor.border, lineWidth: AnvilSize.hairline)
        }
    }

    private var header: some View {
        HStack(spacing: AnvilSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tone == .neutral ? AnvilColor.textTertiary : tone.color)
            }
            Text(title)
                .textCase(.uppercase)
                .font(AnvilFont.label)
                .tracking(0.6)
                .foregroundStyle(AnvilColor.textTertiary)

            Spacer(minLength: AnvilSpacing.sm)

            HStack(spacing: AnvilSpacing.xs) {
                accessory
            }
        }
        .padding(.horizontal, AnvilSpacing.md)
        .frame(height: 30)
        .background(AnvilColor.surface)
    }
}

extension AnvilPane where Accessory == EmptyView {
    public init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        tone: AnvilTone = .neutral,
        contentInset: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title,
            systemImage: systemImage,
            tone: tone,
            contentInset: contentInset,
            content: content,
            accessory: { EmptyView() }
        )
    }
}

/// A plain surface with the app's card treatment.
///
/// Use for grouped content that does not need a header. Nested cards go flat
/// automatically via ``AnvilTheme/prefersFlatSurfaces``, so a card inside the
/// inspector does not stack two backgrounds on top of each other.
public struct AnvilCard<Content: View>: View {
    @Environment(\.anvilTheme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(theme.density.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if theme.prefersFlatSurfaces {
                    RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                        .fill(AnvilColor.field)
                } else {
                    RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                        .fill(AnvilColor.surface)
                }
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: theme.prefersFlatSurfaces ? AnvilRadius.md : theme.cardRadius,
                    style: .continuous
                )
                .strokeBorder(AnvilColor.border, lineWidth: AnvilSize.hairline)
            }
    }
}

/// A titled block of content inside a tool's main area.
public struct AnvilSection<Content: View>: View {
    @Environment(\.anvilTheme) private var theme

    private let title: LocalizedStringKey
    private let subtitle: LocalizedStringKey?
    private let content: Content

    public init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AnvilFont.sectionTitle)
                    .foregroundStyle(AnvilColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textSecondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
