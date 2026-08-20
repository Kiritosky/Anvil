import SwiftUI

/// The options column on the right of a tool.
public struct InspectorPane<Content: View>: View {
    @Environment(\.anvilTheme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: theme.density.sectionSpacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.density.contentPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: AnvilSize.inspectorWidth)
        .background(AnvilColor.surface)
        .anvilFlatSurfaces()
    }
}

/// A titled group of options inside the inspector.
public struct InspectorSection<Content: View>: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let footnote: LocalizedStringKey?
    private let content: Content

    public init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        footnote: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.footnote = footnote
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
            HStack(spacing: AnvilSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AnvilFont.micro)
                }
                Text(title)
                    .textCase(.uppercase)
                    .font(AnvilFont.label)
                    .tracking(0.6)
            }
            .foregroundStyle(AnvilColor.textTertiary)

            VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let footnote {
                Text(footnote)
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Ein Abschnitt im Inspektor, der nur erklärt.
public struct InspectorNote: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let footnote: LocalizedStringKey

    public init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        footnote: LocalizedStringKey
    ) {
        self.title = title
        self.systemImage = systemImage
        self.footnote = footnote
    }

    public var body: some View {
        InspectorSection(title, systemImage: systemImage, footnote: footnote) {
            EmptyView()
        }
    }
}

/// A label-over-control row, the inspector's unit of layout.
public struct OptionRow<Control: View>: View {
    private let label: LocalizedStringKey
    private let help: LocalizedStringKey?
    private let control: Control

    public init(
        _ label: LocalizedStringKey,
        help: LocalizedStringKey? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.label = label
        self.help = help
        self.control = control()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
            Text(label)
                .font(AnvilFont.body)
                .foregroundStyle(AnvilColor.textSecondary)

            control
                .frame(maxWidth: .infinity, alignment: .leading)

            if let help {
                Text(help)
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
