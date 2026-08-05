import SwiftUI

/// A settings page.
///
/// Used by the app's own preference panes *and* by per-tool settings, so a
/// tool's options look identical to the app's own — the user should not be able
/// to tell which of the two they are looking at.
public struct SettingsPage<Content: View>: View {
    @Environment(\.anvilTheme) private var theme

    private let title: LocalizedStringKey
    private let description: LocalizedStringKey?
    private let content: Content

    public init(
        _ title: LocalizedStringKey,
        description: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content()
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.density.sectionSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AnvilFont.title)
                        .foregroundStyle(AnvilColor.textPrimary)
                    if let description {
                        Text(description)
                            .font(AnvilFont.caption)
                            .foregroundStyle(AnvilColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                content
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AnvilSpacing.xl)
        }
        .background(AnvilColor.canvas)
    }
}

/// A titled group of settings rows, drawn as one card.
public struct SettingsGroup<Content: View>: View {
    private let title: LocalizedStringKey?
    private let footnote: LocalizedStringKey?
    private let content: Content

    public init(
        _ title: LocalizedStringKey? = nil,
        footnote: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
            if let title {
                Text(title)
                    .textCase(.uppercase)
                    .font(AnvilFont.label)
                    .tracking(0.6)
                    .foregroundStyle(AnvilColor.textTertiary)
            }

            VStack(spacing: 0) {
                content
            }
            .background {
                RoundedRectangle(cornerRadius: AnvilRadius.lg, style: .continuous)
                    .fill(AnvilColor.surface)
            }
            // Clipping lets every row draw a bottom divider unconditionally:
            // the last one lands on the edge and the border stroke covers it.
            .clipShape(RoundedRectangle(cornerRadius: AnvilRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AnvilRadius.lg, style: .continuous)
                    .strokeBorder(AnvilColor.border, lineWidth: 1)
            }

            if let footnote {
                Text(footnote)
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One row in a ``SettingsGroup``: label and help on the left, control on the
/// right.
public struct SettingsRow<Control: View>: View {
    private let title: LocalizedStringKey
    private let help: LocalizedStringKey?
    private let systemImage: String?
    private let control: Control

    public init(
        _ title: LocalizedStringKey,
        help: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.help = help
        self.systemImage = systemImage
        self.control = control()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: AnvilSpacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(AnvilColor.textSecondary)
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AnvilFont.body)
                    .foregroundStyle(AnvilColor.textPrimary)
                if let help {
                    Text(help)
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: AnvilSpacing.md)

            control
                .labelsHidden()
        }
        .padding(.horizontal, AnvilSpacing.lg)
        .padding(.vertical, AnvilSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, AnvilSpacing.lg)
        }
    }
}

/// A row whose control spans the full width underneath the label — for text
/// fields, pickers with long values and anything that would otherwise squeeze.
public struct SettingsWideRow<Control: View>: View {
    private let title: LocalizedStringKey
    private let help: LocalizedStringKey?
    private let control: Control

    public init(
        _ title: LocalizedStringKey,
        help: LocalizedStringKey? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.help = help
        self.control = control()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
            Text(title)
                .font(AnvilFont.body)
                .foregroundStyle(AnvilColor.textPrimary)

            control
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

            if let help {
                Text(help)
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, AnvilSpacing.lg)
        .padding(.vertical, AnvilSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, AnvilSpacing.lg)
        }
    }
}
