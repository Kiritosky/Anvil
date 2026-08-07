import SwiftUI

/// How much visual weight a button carries.
public enum AnvilButtonRole: Sendable {
    /// The one action the screen is about. At most one per view.
    case primary
    /// Supporting actions.
    case secondary
    /// Low-weight actions in dense rows and pane headers.
    case ghost
    /// Deletes and discards.
    case destructive

    var tint: Color {
        switch self {
        case .primary: AnvilColor.accent
        case .secondary, .ghost: AnvilColor.textPrimary
        case .destructive: AnvilColor.danger
        }
    }
}

/// The app's button.
///
/// Handles the busy state itself: pass `isBusy` and it swaps its icon for a
/// spinner and disables itself, so no tool has to build that combination twice.
public struct AnvilButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let role: AnvilButtonRole
    private let isBusy: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        role: AnvilButtonRole = .secondary,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isBusy = isBusy
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: AnvilSpacing.xs) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(AnvilFont.body.weight(role == .primary ? .semibold : .regular))
            }
        }
        .buttonStyle(AnvilButtonStyle(role: role))
        .disabled(isBusy || !isEnabled)
    }
}

/// Visual treatment for ``AnvilButton``. Also usable on a bare `Button`.
public struct AnvilButtonStyle: ButtonStyle {
    private let role: AnvilButtonRole
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    public init(role: AnvilButtonRole = .secondary) {
        self.role = role
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground(pressed: configuration.isPressed))
            .padding(.horizontal, AnvilSpacing.md)
            .frame(height: AnvilSize.controlHeight)
            .background(background(pressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous))
            .overlay {
                if role == .secondary {
                    RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                        .strokeBorder(AnvilColor.border, lineWidth: AnvilSize.hairline)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(AnvilMotion.quick, value: isHovering)
            .animation(AnvilMotion.quick, value: configuration.isPressed)
    }

    private func foreground(pressed: Bool) -> Color {
        switch role {
        case .primary: AnvilColor.textOnAccent
        case .destructive: AnvilColor.danger
        case .secondary, .ghost: AnvilColor.textPrimary
        }
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch role {
        case .primary:
            AnvilColor.accent.opacity(pressed ? 0.75 : (isHovering ? 0.92 : 1))
        case .secondary:
            AnvilColor.field.opacity(pressed ? 0.6 : (isHovering ? 1 : 0.85))
        case .ghost:
            (pressed || isHovering) ? AnvilColor.hover : Color.clear
        case .destructive:
            AnvilColor.danger.opacity(pressed ? 0.24 : (isHovering ? 0.16 : 0.1))
        }
    }
}

/// A square, icon-only button for header bars and pane accessories.
public struct AnvilIconButtonStyle: ButtonStyle {
    private let isActive: Bool
    private let tone: AnvilTone
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    public init(isActive: Bool = false, tone: AnvilTone = .neutral) {
        self.isActive = isActive
        self.tone = tone
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(
                isActive
                    ? AnvilColor.accent
                    : (tone == .neutral ? AnvilColor.textSecondary : tone.color)
            )
            .frame(width: AnvilSize.controlHeight, height: AnvilSize.controlHeight)
            .background {
                RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? AnvilColor.hover.opacity(1.4)
                            : (isActive ? AnvilColor.selection : (isHovering ? AnvilColor.hover : .clear))
                    )
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(AnvilMotion.quick, value: isHovering)
    }
}
