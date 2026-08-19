import AnvilKit
import SwiftUI

/// How tightly the UI is packed.
public enum AnvilDensity: String, CaseIterable, Codable, Sendable, Identifiable {
    case comfortable
    case compact

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .comfortable: localized("Komfortabel")
        case .compact: localized("Kompakt")
        }
    }

    /// Padding inside cards and panes.
    public var contentPadding: CGFloat {
        switch self {
        case .comfortable: AnvilSpacing.lg
        case .compact: AnvilSpacing.md
        }
    }

    /// Gap between sections of a tool.
    public var sectionSpacing: CGFloat {
        switch self {
        case .comfortable: AnvilSpacing.xl
        case .compact: AnvilSpacing.lg
        }
    }

    /// Vertical padding of a list row.
    public var rowPadding: CGFloat {
        switch self {
        case .comfortable: AnvilSpacing.sm
        case .compact: AnvilSpacing.xs
        }
    }
}

/// Theme values that a view can override for its subtree.
public struct AnvilTheme: Sendable, Equatable {
    public var density: AnvilDensity
    /// Corner radius for cards in this subtree.
    public var cardRadius: CGFloat
    /// Set by containers that already draw a background, so nested cards go flat.
    public var prefersFlatSurfaces: Bool

    public init(
        density: AnvilDensity = .comfortable,
        cardRadius: CGFloat = AnvilRadius.lg,
        prefersFlatSurfaces: Bool = false
    ) {
        self.density = density
        self.cardRadius = cardRadius
        self.prefersFlatSurfaces = prefersFlatSurfaces
    }

    public static let `default` = AnvilTheme()
}

private struct AnvilThemeKey: EnvironmentKey {
    static let defaultValue = AnvilTheme.default
}

extension EnvironmentValues {
    public var anvilTheme: AnvilTheme {
        get { self[AnvilThemeKey.self] }
        set { self[AnvilThemeKey.self] = newValue }
    }
}

extension View {
    /// Applies a theme to this view and everything below it.
    public func anvilTheme(_ theme: AnvilTheme) -> some View {
        environment(\.anvilTheme, theme)
    }

    /// Applies just the density, keeping the rest of the inherited theme.
    public func anvilDensity(_ density: AnvilDensity) -> some View {
        transformEnvironment(\.anvilTheme) { $0.density = density }
    }

    /// Tells nested cards not to draw their own background.
    public func anvilFlatSurfaces(_ flat: Bool = true) -> some View {
        transformEnvironment(\.anvilTheme) { $0.prefersFlatSurfaces = flat }
    }
}
