import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Farblisten")
struct ColorPaletteTests {
    @Test
    func oneColourPerLine() {
        let palette = ColorPalette("#3A7BD5\n#FFFFFF")
        #expect(palette.entries.count == 2)
        #expect(palette.readable.count == 2)
        #expect(palette.colors[0].hex == "#3A7BD5")
    }

    @Test
    func emptyLinesAreNotEntries() {
        let palette = ColorPalette("\n\n#000000\n\n")
        #expect(palette.entries.count == 1)
    }

    /// Der Alltagsfall: Die Liste kommt aus einer Stilvorlage.
    @Test
    func aNameInFrontIsKeptAndTheColourStillRead() {
        let palette = ColorPalette("--marke: #3A7BD5;")
        #expect(palette.entries[0].name == "marke")
        #expect(palette.entries[0].color?.hex == "#3A7BD5")
    }

    @Test
    func aPlainNameInFrontWorksToo() {
        let palette = ColorPalette("Hintergrund   #FFFFFF")
        #expect(palette.entries[0].name == "Hintergrund")
        #expect(palette.entries[0].color?.hex == "#FFFFFF")
    }

    /// Funktionale Schreibweisen enthalten selbst Leerzeichen — sie lassen
    /// sich nicht in Wörter zerlegen.
    @Test
    func functionalNotationsSurvive() {
        let palette = ColorPalette("Akzent rgb(58, 123, 213)")
        #expect(palette.entries[0].color?.hex == "#3A7BD5")
        #expect(palette.entries[0].name == "Akzent")
    }

    @Test
    func aLineWithoutAColourIsMarkedAsSuch() {
        let palette = ColorPalette("das ist keine Farbe")
        #expect(palette.readable.isEmpty)
        #expect(palette.unreadable.count == 1)
        #expect(palette.entries[0].label == "das ist keine Farbe")
    }

    @Test
    func aLineWithBothIsReadFromTheRight() {
        let palette = ColorPalette("blau #FF0000")
        #expect(palette.entries[0].color?.hex == "#FF0000")
    }

    // MARK: - Doppelgänger

    /// Das, was eine Einzelansicht prinzipiell nicht kann.
    @Test
    func theSameColourWrittenTwiceIsFound() {
        let palette = ColorPalette("#FFFFFF\nrgb(255, 255, 255)")
        let twins = palette.twins()
        #expect(twins.count == 1)
        #expect(twins[0].isIdentical)
    }

    @Test
    func almostTheSameIsAlsoFound() {
        let palette = ColorPalette("#333333\n#343434")
        let twins = palette.twins()
        #expect(twins.count == 1)
        #expect(!twins[0].isIdentical)
    }

    @Test
    func realDifferencesAreNotReported() {
        let palette = ColorPalette("#333333\n#663333\n#FFFFFF")
        #expect(palette.twins().isEmpty)
    }

    /// Drei gleiche geben drei Paare — jedes einmal, keines doppelt.
    @Test
    func everyPairIsReportedOnce() {
        let palette = ColorPalette("#FFF\n#FFFFFF\nrgb(255,255,255)")
        #expect(palette.twins().count == 3)
    }

    @Test
    func theThresholdCanBeMoved() {
        let palette = ColorPalette("#000000\n#0F0F0F")
        #expect(palette.twins().isEmpty)
        #expect(palette.twins(threshold: 0.1).count == 1)
    }

    // MARK: - Ausgeben

    @Test
    func theReportHasAHeaderAndOneLinePerColour() {
        let palette = ColorPalette("#3A7BD5\n#FFFFFF")
        let lines = palette.report.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)
        #expect(lines[0].split(separator: "\t").count == ColorPalette.reportColumns.count)
    }

    /// Der Kontrast von Weiß auf Weiß ist 1:1 — die Zeile, an der man merkt,
    /// dass die Spalte stimmt.
    @Test
    func theReportCarriesTheContrast() {
        let palette = ColorPalette("#FFFFFF")
        let row = palette.row(palette.entries[0])
        #expect(row.contains("1.00:1"))
        #expect(row.contains("21.00:1"))
    }

    @Test
    func cssUsesTheNames() {
        let palette = ColorPalette("--marke: #3A7BD5;\nHintergrund #FFFFFF")
        let css = palette.css
        #expect(css.contains("--marke: #3A7BD5;"))
        #expect(css.contains("--hintergrund: #FFFFFF;"))
        #expect(css.hasPrefix(":root {"))
        #expect(css.hasSuffix("}"))
    }

    /// Eine Variable namens `--` wäre in jeder Stilvorlage ein Fehler.
    @Test
    func colorsWithoutANameAreNumbered() {
        let palette = ColorPalette("#3A7BD5\n#FFFFFF")
        #expect(palette.css.contains("--farbe-1:"))
        #expect(palette.css.contains("--farbe-2:"))
    }

    @Test
    func swiftIdentifiersAreCamelCase() {
        let palette = ColorPalette("Dunkles Grau #333333")
        #expect(palette.swift.contains("static let dunklesGrau ="))
    }

    /// Ein Bezeichner, der mit einer Ziffer anfängt, ist keiner.
    @Test
    func anIdentifierNeverStartsWithADigit() {
        #expect(ColorPalette.identifier("2. Ebene", fallback: 1, camelCase: true).first?.isNumber == false)
        #expect(ColorPalette.identifier("", fallback: 7) == "farbe-7")
    }

    @Test
    func umlautsBecomeSomethingUsable() {
        #expect(ColorPalette.identifier("Grün", fallback: 1) == "grun")
    }

    @Test
    func unreadableLinesAreLeftOutOfTheExports() {
        let palette = ColorPalette("#FFFFFF\nkeine Farbe hier")
        #expect(palette.css.split(separator: "\n").count == 3)
        #expect(palette.swift.split(separator: "\n").count == 1)
    }

    @Test
    func nothingInIsAnEmptyPalette() {
        #expect(ColorPalette("").isEmpty)
        #expect(ColorPalette.empty.isEmpty)
        #expect(ColorPalette.empty.twins().isEmpty)
    }
}
