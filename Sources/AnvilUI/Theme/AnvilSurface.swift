import SwiftUI

/// Where a surface sits in the stack. Picking a level rather than a colour is
/// what keeps nested containers from all landing on the same grey.
public enum AnvilSurfaceLevel: Sendable {
    /// The window background.
    case canvas
    /// A card or pane on the canvas.
    case surface
    /// A row or control inside a card.
    case elevated
    /// Anything editable.
    case field

    var fill: Color {
        switch self {
        case .canvas: AnvilColor.canvas
        case .surface: AnvilColor.surface
        case .elevated: AnvilColor.elevated
        case .field: AnvilColor.field
        }
    }
}

private struct AnvilSurfaceModifier: ViewModifier {
    @Environment(\.anvilTheme) private var theme

    let level: AnvilSurfaceLevel
    let radius: CGFloat
    let bordered: Bool
    let padding: CGFloat?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .padding(padding ?? theme.contentPadding)
            .background {
                if !theme.prefersFlatSurfaces {
                    shape.fill(level.fill)
                }
            }
            .overlay {
                if bordered && !theme.prefersFlatSurfaces {
                    shape.strokeBorder(AnvilColor.border, lineWidth: AnvilSize.hairline)
                }
            }
            .clipShape(shape)
    }
}

extension View {
    /// The standard container: a level from the surface stack, a continuous
    /// corner and a hairline. Every card, pane and grouped row uses this —
    /// there is no second way to draw a box.
    public func anvilSurface(
        _ level: AnvilSurfaceLevel = .surface,
        radius: CGFloat = AnvilRadius.lg,
        bordered: Bool = true,
        padding: CGFloat? = nil
    ) -> some View {
        modifier(AnvilSurfaceModifier(level: level, radius: radius, bordered: bordered, padding: padding))
    }
}

extension AnvilTheme {
    /// Padding a surface uses when the call site does not say otherwise.
    var contentPadding: CGFloat { density.contentPadding }
}
