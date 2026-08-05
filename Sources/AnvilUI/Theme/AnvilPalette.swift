import AppKit
import SwiftUI

/// Semantic colours.
///
/// Everything resolves from AppKit's system colours, so light mode, dark mode,
/// increased contrast and the user's accent colour all work without a second
/// set of definitions.
public enum AnvilColor {
    // MARK: Surfaces

    /// The window background behind everything.
    public static let canvas = Color(nsColor: .windowBackgroundColor)
    /// A card or pane sitting on the canvas.
    public static let surface = Color(nsColor: .controlBackgroundColor)
    /// Editable areas: text editors, code panes.
    public static let field = Color(nsColor: .textBackgroundColor)
    /// A row that is hovered but not selected.
    public static let hover = Color(nsColor: .quaternaryLabelColor).opacity(0.35)
    /// The selected row in a list or sidebar.
    public static let selection = Color.accentColor.opacity(0.18)

    // MARK: Lines

    public static let separator = Color(nsColor: .separatorColor)
    /// Border around an inactive input.
    public static let border = Color(nsColor: .separatorColor).opacity(0.9)
    /// Border around the focused input.
    public static let borderFocused = Color.accentColor.opacity(0.7)

    // MARK: Text

    public static let textPrimary = Color(nsColor: .labelColor)
    public static let textSecondary = Color(nsColor: .secondaryLabelColor)
    public static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    /// Text drawn on top of an accent-filled surface.
    public static let textOnAccent = Color.white

    // MARK: Status

    public static let accent = Color.accentColor
    public static let success = Color(nsColor: .systemGreen)
    public static let warning = Color(nsColor: .systemOrange)
    public static let danger = Color(nsColor: .systemRed)
    public static let info = Color(nsColor: .systemBlue)
    /// Marks output produced by a model, as opposed to deterministic output.
    public static let ai = Color(nsColor: .systemPurple)
    /// Marks work that happens on-device only.
    public static let onDevice = Color(nsColor: .systemTeal)
}

/// The tone of a status surface — pills, banners, buttons.
public enum AnvilTone: String, CaseIterable, Sendable {
    case neutral
    case accent
    case success
    case warning
    case danger
    case info
    case ai

    public var color: Color {
        switch self {
        case .neutral: AnvilColor.textSecondary
        case .accent: AnvilColor.accent
        case .success: AnvilColor.success
        case .warning: AnvilColor.warning
        case .danger: AnvilColor.danger
        case .info: AnvilColor.info
        case .ai: AnvilColor.ai
        }
    }

    /// The tinted background used behind ``color`` at small sizes.
    public var fill: Color {
        color.opacity(0.14)
    }

    public var systemImage: String {
        switch self {
        case .neutral: "circle"
        case .accent: "sparkle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        case .ai: "sparkles"
        }
    }
}
