import SwiftUI

extension ColorValue {
    /// The same colour, for SwiftUI.
    ///
    /// Kept out of ``ColorValue`` itself: the type is arithmetic and is tested
    /// without a window. This is the one line that turns it into something a
    /// view can fill with, and every view that needs it uses this one.
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
