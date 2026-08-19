import SwiftUI

/// Wie groß eine Karte in ihrem Umfeld wirkt.
public enum AnvilCardSize: Sendable {
    /// Eine Zeile in einer Liste, die für sich steht.
    case regular
    /// Ein Eintrag in einer dichten Aufzählung — Vorschauzeilen, Chips,
    /// Wortlisten. Hier wäre der große Radius eine Blase statt einer Karte.
    case compact

    var radius: CGFloat {
        switch self {
        case .regular: AnvilRadius.md
        case .compact: AnvilRadius.sm
        }
    }
}

extension View {
    /// Die Fläche, auf der eine Zeile in einer Liste sitzt.
    public func anvilCard(_ size: AnvilCardSize = .regular, isSelected: Bool = false) -> some View {
        background {
            RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                .fill(isSelected ? AnvilColor.selection : AnvilColor.surface)
        }
    }
}
