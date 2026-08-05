import SwiftUI

/// The options column on the right of a tool.
///
/// Scrollable, fixed width, its own background. Tools fill it with
/// ``InspectorSection`` groups — never with ad-hoc `Form`s, so that every tool's
/// options read the same way.
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
    private let title: String
    private let systemImage: String?
    private let footnote: String?
    private let content: Content

    public init(
        _ title: String,
        systemImage: String? = nil,
        footnote: String? = nil,
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
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title.uppercased())
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

/// A label-over-control row, the inspector's unit of layout.
///
/// Vertical rather than side-by-side: the inspector is narrow, and stacked
/// labels keep long German option names from truncating.
public struct OptionRow<Control: View>: View {
    private let label: String
    private let help: String?
    private let control: Control

    public init(_ label: String, help: String? = nil, @ViewBuilder control: () -> Control) {
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
