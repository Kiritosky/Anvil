import AnvilKit
import SwiftUI

extension ColorValue {
    /// The same colour, for SwiftUI.
    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension Color {
    /// Reads a colour the way the colour tool does — hex, rgb(), hsl(), or a
    /// name — falling back to grey rather than to a crash.
    public init(parsing text: String, fallback: Color = .gray) {
        guard let value = ColorValue(parsing: text) else {
            self = fallback
            return
        }
        self = value.color
    }
}
