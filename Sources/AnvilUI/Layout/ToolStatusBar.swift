import SwiftUI

/// The thin strip at the bottom of a tool.
///
/// Holds counts, timings, the active model and errors — the things a user
/// glances at but never clicks. Keeping them here stops that information from
/// competing with the tool's actual content.
public struct ToolStatusBar<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    public init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.md) {
            HStack(spacing: AnvilSpacing.md) { leading }
            Spacer(minLength: AnvilSpacing.sm)
            HStack(spacing: AnvilSpacing.md) { trailing }
        }
        .font(AnvilFont.caption)
        .foregroundStyle(AnvilColor.textSecondary)
        .padding(.horizontal, AnvilSpacing.md)
        .frame(height: AnvilSize.statusBarHeight)
        .frame(maxWidth: .infinity)
        .background(AnvilColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .strokeBorder(AnvilColor.border, lineWidth: 1)
        }
    }
}

extension ToolStatusBar where Trailing == EmptyView {
    public init(@ViewBuilder leading: () -> Leading) {
        self.init(leading: leading, trailing: { EmptyView() })
    }
}

/// One labelled reading in a status bar: an icon, a value, a caption.
public struct StatusMetric: View {
    private let systemImage: String
    private let value: String
    private let label: String?
    private let tone: AnvilTone

    public init(_ value: String, label: String? = nil, systemImage: String, tone: AnvilTone = .neutral) {
        self.value = value
        self.label = label
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(tone == .neutral ? AnvilColor.textTertiary : tone.color)
            Text(value)
                .foregroundStyle(AnvilColor.textPrimary)
                .monospacedDigit()
            if let label {
                Text(label)
                    .foregroundStyle(AnvilColor.textTertiary)
            }
        }
        .font(AnvilFont.caption)
        .help(label ?? value)
    }
}
