import Foundation

/// A colour, parsed from whatever notation it was written in.
public struct ColorValue: Hashable, Sendable, Codable {
    /// Components in 0…1.
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clampedToUnit
        self.green = green.clampedToUnit
        self.blue = blue.clampedToUnit
        self.alpha = alpha.clampedToUnit
    }

    public init(red255: Int, green255: Int, blue255: Int, alpha: Double = 1) {
        self.init(
            red: Double(red255) / 255,
            green: Double(green255) / 255,
            blue: Double(blue255) / 255,
            alpha: alpha
        )
    }

    // MARK: - Parsing

    /// Reads `#3A7BD5`, `3a7bd5`, `#f0c8`, `rgb(58, 123, 213)`,
    /// `rgba(58,123,213,0.5)`, `hsl(214, 63%, 53%)` and a handful of names.
    public init?(parsing text: String) {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !trimmed.isEmpty else { return nil }

        if let named = Self.named[trimmed] {
            self = named
            return
        }

        if trimmed.hasPrefix("rgb") {
            guard let numbers = Self.numbers(in: trimmed), numbers.count >= 3 else { return nil }
            self.init(
                red255: Int(numbers[0].rounded()),
                green255: Int(numbers[1].rounded()),
                blue255: Int(numbers[2].rounded()),
                alpha: numbers.count > 3 ? numbers[3] : 1
            )
            return
        }

        if trimmed.hasPrefix("hsl") {
            guard let numbers = Self.numbers(in: trimmed), numbers.count >= 3 else { return nil }
            self.init(
                hue: numbers[0],
                saturation: numbers[1] / 100,
                lightness: numbers[2] / 100,
                alpha: numbers.count > 3 ? numbers[3] : 1
            )
            return
        }

        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.allSatisfy(\.isHexDigit) else { return nil }

        let expanded: String
        switch hex.count {
        case 3, 4: expanded = hex.map { "\($0)\($0)" }.joined()
        case 6, 8: expanded = hex
        default: return nil
        }

        let bytes = stride(from: 0, to: expanded.count, by: 2).compactMap { offset -> Int? in
            let start = expanded.index(expanded.startIndex, offsetBy: offset)
            let end = expanded.index(start, offsetBy: 2)
            return Int(expanded[start..<end], radix: 16)
        }
        guard bytes.count >= 3 else { return nil }

        self.init(
            red255: bytes[0],
            green255: bytes[1],
            blue255: bytes[2],
            alpha: bytes.count > 3 ? Double(bytes[3]) / 255 : 1
        )
    }

    /// HSL as CSS defines it: hue in degrees, the rest in 0…1.
    public init(hue: Double, saturation: Double, lightness: Double, alpha: Double = 1) {
        let hue = ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        let chroma = (1 - abs(2 * lightness - 1)) * saturation.clampedToUnit
        let second = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let match = lightness.clampedToUnit - chroma / 2

        let (red, green, blue): (Double, Double, Double) = switch hue {
        case ..<60: (chroma, second, 0)
        case ..<120: (second, chroma, 0)
        case ..<180: (0, chroma, second)
        case ..<240: (0, second, chroma)
        case ..<300: (second, 0, chroma)
        default: (chroma, 0, second)
        }

        self.init(red: red + match, green: green + match, blue: blue + match, alpha: alpha)
    }

    private static func numbers(in text: String) -> [Double]? {
        let inside = text.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
        let parts = inside
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .map { $0.replacingOccurrences(of: "%", with: "") }
            .compactMap { Double($0) }
        return parts.isEmpty ? nil : parts
    }

    // MARK: - Notations

    public var red255: Int { Int((red * 255).rounded()) }
    public var green255: Int { Int((green * 255).rounded()) }
    public var blue255: Int { Int((blue * 255).rounded()) }

    public var hex: String {
        String(format: "#%02X%02X%02X", red255, green255, blue255)
    }

    public var hexWithAlpha: String {
        String(format: "#%02X%02X%02X%02X", red255, green255, blue255, Int((alpha * 255).rounded()))
    }

    public var rgbNotation: String {
        alpha < 1
            ? "rgba(\(red255), \(green255), \(blue255), \(Self.format(alpha)))"
            : "rgb(\(red255), \(green255), \(blue255))"
    }

    /// Hue in degrees, saturation and lightness in 0…1.
    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let lightness = (maximum + minimum) / 2
        let delta = maximum - minimum

        guard delta > 0 else { return (0, 0, lightness) }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maximum {
        case red: hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
        case green: hue = 60 * ((blue - red) / delta + 2)
        default: hue = 60 * ((red - green) / delta + 4)
        }
        if hue < 0 { hue += 360 }

        return (hue, saturation, lightness)
    }

    public var hslNotation: String {
        let (hue, saturation, lightness) = hsl
        let base = "\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%"
        return alpha < 1 ? "hsla(\(base), \(Self.format(alpha)))" : "hsl(\(base))"
    }

    /// Ready to paste into Swift.
    public var swiftUINotation: String {
        "Color(red: \(Self.format(red)), green: \(Self.format(green)), blue: \(Self.format(blue)))"
    }

    public var nsColorNotation: String {
        "NSColor(srgbRed: \(Self.format(red)), green: \(Self.format(green)), blue: \(Self.format(blue)), alpha: \(Self.format(alpha)))"
    }

    // MARK: - Contrast

    /// WCAG relative luminance — not brightness, and not the average of the
    /// channels: green counts for most of what the eye sees.
    public var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// The WCAG contrast ratio, 1 (identical) to 21 (black on white).
    public func contrast(with other: ColorValue) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Whether black or white text sits better on this colour.
    public var readableForeground: ColorValue {
        contrast(with: .black) >= contrast(with: .white) ? .black : .white
    }

    public static let black = ColorValue(red: 0, green: 0, blue: 0)
    public static let white = ColorValue(red: 1, green: 1, blue: 1)

    /// What a contrast ratio is good enough for.
    public enum ContrastRating: String, Sendable, CaseIterable {
        case failed
        case largeTextOnly
        case aa
        case aaa

        public var title: String {
            switch self {
            case .failed: localized("Durchgefallen")
            case .largeTextOnly: localized("Nur große Schrift")
            case .aa: localized("AA")
            case .aaa: localized("AAA")
            }
        }

        public var explanation: String {
            switch self {
            case .failed:
                localized("Unter 3:1 — für Text nicht zu gebrauchen.")
            case .largeTextOnly:
                localized("Ab 3:1 — reicht für Überschriften ab 24 px oder 19 px fett.")
            case .aa:
                localized("Ab 4,5:1 — der Normalfall für Fließtext.")
            case .aaa:
                localized("Ab 7:1 — auch für kleine Schrift und schlechte Bildschirme.")
            }
        }
    }

    public static func rating(for contrast: Double) -> ContrastRating {
        switch contrast {
        case 7...: .aaa
        case 4.5...: .aa
        case 3...: .largeTextOnly
        default: .failed
        }
    }

    // MARK: - Helpers

    /// Up to three decimals, no trailing zeros — the shortest form that still
    /// round-trips a colour component.
    static func format(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// The names worth knowing. Not all 140 CSS names: the long tail is
    /// unreadable ("lightgoldenrodyellow") and nobody types it.
    static let named: [String: ColorValue] = [
        "schwarz": .black, "black": .black,
        "weiss": .white, "weiß": .white, "white": .white,
        "rot": ColorValue(red255: 255, green255: 0, blue255: 0),
        "red": ColorValue(red255: 255, green255: 0, blue255: 0),
        "grün": ColorValue(red255: 0, green255: 128, blue255: 0),
        "gruen": ColorValue(red255: 0, green255: 128, blue255: 0),
        "green": ColorValue(red255: 0, green255: 128, blue255: 0),
        "blau": ColorValue(red255: 0, green255: 0, blue255: 255),
        "blue": ColorValue(red255: 0, green255: 0, blue255: 255),
        "gelb": ColorValue(red255: 255, green255: 255, blue255: 0),
        "yellow": ColorValue(red255: 255, green255: 255, blue255: 0),
        "orange": ColorValue(red255: 255, green255: 165, blue255: 0),
        "lila": ColorValue(red255: 128, green255: 0, blue255: 128),
        "purple": ColorValue(red255: 128, green255: 0, blue255: 128),
        "grau": ColorValue(red255: 128, green255: 128, blue255: 128),
        "gray": ColorValue(red255: 128, green255: 128, blue255: 128),
        "grey": ColorValue(red255: 128, green255: 128, blue255: 128),
        "cyan": ColorValue(red255: 0, green255: 255, blue255: 255),
        "magenta": ColorValue(red255: 255, green255: 0, blue255: 255),
        "türkis": ColorValue(red255: 64, green255: 224, blue255: 208),
        "teal": ColorValue(red255: 0, green255: 128, blue255: 128),
        "navy": ColorValue(red255: 0, green255: 0, blue255: 128),
        "oliv": ColorValue(red255: 128, green255: 128, blue255: 0),
        "olive": ColorValue(red255: 128, green255: 128, blue255: 0),
        "braun": ColorValue(red255: 165, green255: 42, blue255: 42),
        "brown": ColorValue(red255: 165, green255: 42, blue255: 42),
        "rosa": ColorValue(red255: 255, green255: 192, blue255: 203),
        "pink": ColorValue(red255: 255, green255: 192, blue255: 203)
    ]
}

extension Double {
    fileprivate var clampedToUnit: Double {
        Swift.min(1, Swift.max(0, self))
    }
}
