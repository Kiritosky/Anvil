import AppKit
import SwiftUI

/// A colour that resolves per appearance without the call site knowing about it.
private func dynamic(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    })
}

private func grey(_ value: CGFloat) -> NSColor {
    NSColor(srgbRed: value, green: value, blue: value, alpha: 1)
}

/// Semantic colours.
///
/// Surfaces form a stack: `canvas` at the back, `surface` for a card on it,
/// `elevated` for a row inside that card, `field` for anything editable. Each
/// step is a small brightness change plus a hairline, never a shadow — depth
/// that survives being screenshotted and scaled.
public enum AnvilColor {
    // MARK: Surfaces

    /// The window background behind everything, sidebar included.
    public static let canvas = dynamic(light: grey(0.961), dark: grey(0.106))
    /// A card or pane sitting on the canvas.
    public static let surface = dynamic(light: grey(1.0), dark: grey(0.149))
    /// A row or control sitting inside a card.
    public static let elevated = dynamic(light: grey(0.976), dark: grey(0.188))
    /// Editable areas: text editors, code panes. Recessed, not raised.
    public static let field = dynamic(light: grey(1.0), dark: grey(0.082))
    /// A row that is hovered but not selected.
    public static let hover = dynamic(
        light: NSColor(white: 0, alpha: 0.045),
        dark: NSColor(white: 1, alpha: 0.06)
    )
    /// A selected row that keeps its normal label colour.
    public static let selection = Color.accentColor.opacity(0.16)
    /// A selected row that carries the accent outright — the sidebar pill.
    /// Its label must switch to ``textOnAccent``.
    public static let selectionStrong = Color.accentColor

    // MARK: Lines

    public static let separator = dynamic(
        light: NSColor(white: 0, alpha: 0.09),
        dark: NSColor(white: 1, alpha: 0.10)
    )
    /// Border around a card or an inactive input.
    public static let border = dynamic(
        light: NSColor(white: 0, alpha: 0.10),
        dark: NSColor(white: 1, alpha: 0.11)
    )
    /// Border around the focused input.
    public static let borderFocused = Color.accentColor.opacity(0.7)

    // MARK: Text

    public static let textPrimary = Color(nsColor: .labelColor)
    public static let textSecondary = Color(nsColor: .secondaryLabelColor)
    public static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    /// Text drawn on top of an accent-filled surface.
    public static let textOnAccent = Color.white

    // MARK: Status

    /// Status colours are darkened for the light scheme: the system greens and
    /// yellows are tuned for dark backgrounds and turn illegible on white.
    public static let accent = Color.accentColor
    public static let success = dynamic(
        light: NSColor(srgbRed: 0.00, green: 0.44, blue: 0.18, alpha: 1),
        dark: .systemGreen
    )
    public static let warning = dynamic(
        light: NSColor(srgbRed: 0.68, green: 0.42, blue: 0.00, alpha: 1),
        dark: .systemOrange
    )
    public static let danger = dynamic(
        light: NSColor(srgbRed: 0.68, green: 0.08, blue: 0.10, alpha: 1),
        dark: .systemRed
    )
    public static let info = dynamic(
        light: NSColor(srgbRed: 0.00, green: 0.35, blue: 0.66, alpha: 1),
        dark: .systemBlue
    )
    /// Marks output produced by a model, as opposed to deterministic output.
    public static let ai = dynamic(
        light: NSColor(srgbRed: 0.44, green: 0.19, blue: 0.66, alpha: 1),
        dark: .systemPurple
    )
    /// Marks work that happens on-device only.
    public static let onDevice = dynamic(
        light: NSColor(srgbRed: 0.00, green: 0.44, blue: 0.40, alpha: 1),
        dark: .systemTeal
    )
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
