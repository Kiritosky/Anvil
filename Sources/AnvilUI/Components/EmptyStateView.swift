import SwiftUI

/// What a pane shows before the user has done anything.
///
/// Every empty pane in the app uses this, so "nothing here yet" always looks
/// deliberate rather than broken.
public struct EmptyStateView<Actions: View>: View {
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey?
    private let systemImage: String
    private let tone: AnvilTone
    private let actions: Actions

    public init(
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        systemImage: String,
        tone: AnvilTone = .neutral,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: AnvilSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(tone == .neutral ? AnvilColor.textTertiary : tone.color.opacity(0.75))

            VStack(spacing: AnvilSpacing.xxs) {
                Text(title)
                    .font(AnvilFont.body.weight(.medium))
                    .foregroundStyle(AnvilColor.textSecondary)
                if let message {
                    Text(message)
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: AnvilSpacing.sm) { actions }
        }
        .padding(AnvilSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    public init(
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        systemImage: String,
        tone: AnvilTone = .neutral
    ) {
        self.init(
            title: title,
            message: message,
            systemImage: systemImage,
            tone: tone,
            actions: { EmptyView() }
        )
    }
}
