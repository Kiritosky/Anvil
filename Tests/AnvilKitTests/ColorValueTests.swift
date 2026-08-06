import AppKit
import Foundation
import Testing

@testable import AnvilKit

@Suite("ColorValue")
struct ColorValueTests {
    private func parse(_ text: String) throws -> ColorValue {
        try #require(ColorValue(parsing: text))
    }

    // MARK: - Parsing

    @Test
    func readsHexWithAndWithoutHash() throws {
        let expected = ColorValue(red255: 58, green255: 123, blue255: 213)
        #expect(try parse("#3A7BD5") == expected)
        #expect(try parse("3a7bd5") == expected)
        #expect(try parse("  #3A7BD5  ") == expected)
    }

    @Test
    func expandsTheShortHexForm() throws {
        #expect(try parse("#f0c") == ColorValue(red255: 255, green255: 0, blue255: 204))
    }

    @Test
    func readsAlphaFromHex() throws {
        let color = try parse("#3A7BD580")
        #expect(color.red255 == 58)
        #expect(abs(color.alpha - 128.0 / 255) < 0.001)
    }

    @Test
    func readsRGBAndRGBA() throws {
        #expect(try parse("rgb(58, 123, 213)") == ColorValue(red255: 58, green255: 123, blue255: 213))

        let transparent = try parse("rgba(58,123,213,0.5)")
        #expect(transparent.alpha == 0.5)
    }

    @Test
    func readsHSL() throws {
        let red = try parse("hsl(0, 100%, 50%)")
        #expect(red.red255 == 255)
        #expect(red.green255 == 0)
        #expect(red.blue255 == 0)

        let green = try parse("hsl(120, 100%, 50%)")
        #expect(green.green255 == 255)
    }

    @Test
    func readsNamesInBothLanguages() throws {
        #expect(try parse("blau") == ColorValue(red255: 0, green255: 0, blue255: 255))
        #expect(try parse("BLUE") == ColorValue(red255: 0, green255: 0, blue255: 255))
        #expect(try parse("weiß") == ColorValue.white)
    }

    @Test
    func refusesWhatIsNotAColour() {
        #expect(ColorValue(parsing: "") == nil)
        #expect(ColorValue(parsing: "guten morgen") == nil)
        #expect(ColorValue(parsing: "#12345") == nil)
        #expect(ColorValue(parsing: "#zzzzzz") == nil)
    }

    // MARK: - Notations

    @Test
    func writesHexInUpperCase() throws {
        #expect(try parse("rgb(58, 123, 213)").hex == "#3A7BD5")
    }

    @Test
    func roundTripsThroughHSL() throws {
        let original = try parse("#3A7BD5")
        let (hue, saturation, lightness) = original.hsl
        let rebuilt = ColorValue(hue: hue, saturation: saturation, lightness: lightness)
        #expect(rebuilt.hex == original.hex)
    }

    @Test
    func dropsAlphaFromTheShortNotations() throws {
        let color = try parse("rgba(58,123,213,0.5)")
        #expect(color.rgbNotation.hasPrefix("rgba("))
        #expect(color.hex == "#3A7BD5")
    }

    @Test
    func writesCodeThatCompiles() throws {
        let notation = try parse("#000000").swiftUINotation
        #expect(notation == "Color(red: 0, green: 0, blue: 0)")
    }

    // MARK: - Contrast

    @Test
    func blackOnWhiteIsTheMaximum() {
        let contrast = ColorValue.black.contrast(with: .white)
        #expect(abs(contrast - 21) < 0.01)
    }

    @Test
    func aColourAgainstItselfHasNoContrast() throws {
        let color = try parse("#3A7BD5")
        #expect(abs(color.contrast(with: color) - 1) < 0.001)
    }

    @Test
    func contrastIsSymmetric() throws {
        let one = try parse("#3A7BD5")
        let other = try parse("#FFD400")
        #expect(abs(one.contrast(with: other) - other.contrast(with: one)) < 0.0001)
    }

    @Test
    func greenWeighsMoreThanBlue() throws {
        let green = try parse("#00FF00")
        let blue = try parse("#0000FF")
        #expect(green.relativeLuminance > blue.relativeLuminance)
    }

    @Test
    func ratesTheUsualThresholds() {
        #expect(ColorValue.rating(for: 21) == .aaa)
        #expect(ColorValue.rating(for: 7) == .aaa)
        #expect(ColorValue.rating(for: 4.5) == .aa)
        #expect(ColorValue.rating(for: 3) == .largeTextOnly)
        #expect(ColorValue.rating(for: 2.9) == .failed)
    }

    @Test
    func picksTheReadableForeground() throws {
        #expect(try parse("#FFFFF0").readableForeground == .black)
        #expect(try parse("#101020").readableForeground == .white)
    }
}
