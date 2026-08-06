import AnvilKit
import SwiftUI

/// An inline message with an optional action.
///
/// The app has exactly one way to say "something is off": this. Errors, missing
/// permissions and model-unavailable states all render through it, which is why
/// it takes a ``AnvilError`` directly as well as free-form text.
public struct AnvilBanner: View {
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey?
    private let tone: AnvilTone
    private let actionTitle: LocalizedStringKey?
    private let action: (() -> Void)?
    private let onDismiss: (() -> Void)?

    public init(
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        tone: AnvilTone = .info,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    /// Renders a ``AnvilError`` with its title, message and recovery hint.
    public init(
        error: AnvilError,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        // The error's own text is already localised, so it goes in resolved
        // rather than being looked up a second time.
        let hint = error.recoverySuggestion
        self.init(
            title: .resolved(error.title),
            message: .resolved(hint.map { "\(error.message)\n\n\($0)" } ?? error.message),
            tone: error.isCancellation ? .neutral : .danger,
            actionTitle: actionTitle,
            action: action,
            onDismiss: onDismiss
        )
    }

    public var body: some View {
        HStack(alignment: .top, spacing: AnvilSpacing.sm) {
            Image(systemName: tone.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone.color)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                Text(title)
                    .font(AnvilFont.body.weight(.semibold))
                    .foregroundStyle(AnvilColor.textPrimary)
                if let message {
                    Text(message)
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: AnvilSpacing.sm)

            HStack(spacing: AnvilSpacing.xs) {
                if let actionTitle, let action {
                    AnvilButton(actionTitle, role: .secondary, action: action)
                }
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(AnvilIconButtonStyle())
                    .anvilHelp("Ausblenden")
                }
            }
        }
        .padding(AnvilSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .fill(tone.fill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .strokeBorder(tone.color.opacity(0.3), lineWidth: 1)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

extension View {
    /// Shows a banner above this view whenever `error` is non-nil.
    public func anvilErrorBanner(
        _ error: Binding<AnvilError?>,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: AnvilSpacing.md) {
            if let value = error.wrappedValue {
                AnvilBanner(
                    error: value,
                    actionTitle: actionTitle,
                    action: action,
                    onDismiss: { error.wrappedValue = nil }
                )
            }
            self
        }
        .animation(AnvilMotion.standard, value: error.wrappedValue?.message)
    }
}
