import AnvilKit
import AppKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("TextRecognizer")
struct TextRecognizerTests {
    private func line(_ text: String, x: CGFloat, y: CGFloat) -> TextRecognizer.Line {
        TextRecognizer.Line(
            id: 0,
            text: text,
            box: CGRect(x: x, y: y, width: 0.2, height: 0.02),
            confidence: 1
        )
    }

    @Test
    func readsTopToBottom() {
        // Vision's origin is bottom-left, so the larger y comes first.
        let sorted = TextRecognizer.sortIntoReadingOrder([
            line("unten", x: 0.1, y: 0.2),
            line("oben", x: 0.1, y: 0.8)
        ])
        #expect(sorted.map(\.text) == ["oben", "unten"])
    }

    @Test
    func readsLeftToRightWithinALine() {
        let sorted = TextRecognizer.sortIntoReadingOrder([
            line("rechts", x: 0.6, y: 0.5),
            line("links", x: 0.1, y: 0.5)
        ])
        #expect(sorted.map(\.text) == ["links", "rechts"])
    }

    @Test
    func keepsColumnsApart() {
        // Two columns, three rows: the reading order is row by row.
        let sorted = TextRecognizer.sortIntoReadingOrder([
            line("B1", x: 0.6, y: 0.9),
            line("A2", x: 0.1, y: 0.6),
            line("A1", x: 0.1, y: 0.9),
            line("B2", x: 0.6, y: 0.6)
        ])
        #expect(sorted.map(\.text) == ["A1", "B1", "A2", "B2"])
    }

    @Test
    func aSlightlyOffBaselineStillCountsAsOneLine() {
        // Real observations never share an exact midpoint.
        let sorted = TextRecognizer.sortIntoReadingOrder([
            line("zwei", x: 0.5, y: 0.503),
            line("eins", x: 0.1, y: 0.5)
        ])
        #expect(sorted.map(\.text) == ["eins", "zwei"])
    }

    @Test
    func renumbersAfterSorting() {
        let sorted = TextRecognizer.sortIntoReadingOrder([
            line("unten", x: 0.1, y: 0.2),
            line("oben", x: 0.1, y: 0.8)
        ])
        #expect(sorted.map(\.id) == [0, 1])
    }

    @Test
    func joinsLinesWithLineBreaks() {
        let result = TextRecognizer.Result(lines: [
            line("erste", x: 0, y: 0.9),
            line("zweite", x: 0, y: 0.8)
        ])
        #expect(result.text == "erste\nzweite")
        #expect(!result.isEmpty)
    }

    @Test
    func anEmptyResultHasNoConfidence() {
        let result = TextRecognizer.Result(lines: [])
        #expect(result.isEmpty)
        #expect(result.confidence == 0)
    }

    @Test
    func confidenceIsTheAverage() {
        let result = TextRecognizer.Result(lines: [
            TextRecognizer.Line(id: 0, text: "a", box: .zero, confidence: 0.4),
            TextRecognizer.Line(id: 1, text: "b", box: .zero, confidence: 0.8)
        ])
        #expect(abs(result.confidence - 0.6) < 0.0001)
    }

    @Test
    func refusesAnImageItCannotRead() {
        #expect(throws: AnvilError.self) {
            try TextRecognizer.recognize(NSImage(size: .zero))
        }
    }

    @Test
    func findsNothingInABlankPicture() throws {
        let image = NSImage(size: NSSize(width: 200, height: 80))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 80).fill()
        image.unlockFocus()

        #expect(try TextRecognizer.recognize(image).isEmpty)
    }

    @Test
    func readsTextItDrewItself() throws {
        let size = NSSize(width: 420, height: 120)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        ("ANVIL" as NSString).draw(
            at: NSPoint(x: 20, y: 30),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 64, weight: .bold),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()

        let result = try TextRecognizer.recognize(image, mode: .exact, languages: ["en-US"])
        #expect(result.text.uppercased().contains("ANVIL"))
    }
}

@Suite("Text mehrerer Bilder")
struct RecognizedTextCombiningTests {
    /// Bei einem Bild bleibt es der reine Text — man will ihn einfügen, nicht
    /// lesen, wo er herkommt.
    @Test
    func aSinglePieceStaysPlain() {
        let combined = TextRecognizer.Result.combine([("screenshot.png", "Hallo Welt")])
        #expect(combined == "Hallo Welt")
    }

    /// Ab zwei bekommt jeder Block den Namen seines Bildes. Ohne den weiß nach
    /// dem Einfügen niemand mehr, welcher Absatz aus welchem Screenshot stammt.
    @Test
    func severalPiecesGetHeadings() {
        let combined = TextRecognizer.Result.combine([
            ("eins.png", "Erster Text"),
            ("zwei.png", "Zweiter Text")
        ])

        #expect(combined == """
        eins.png
        Erster Text

        zwei.png
        Zweiter Text
        """)
    }

    /// Ein Bild ohne Text fällt nicht heraus, sondern bekommt seinen Hinweis.
    /// Eine Lücke, die man nicht sieht, hält man für Text, den es nie gab.
    @Test
    func anEmptyPieceIsStillListed() {
        let combined = TextRecognizer.Result.combine([
            ("mit.png", "Da steht was"),
            ("ohne.png", "   \n  ")
        ])

        #expect(combined.contains("ohne.png"))
        #expect(combined.contains(localized("— kein Text —")))
    }

    @Test
    func nothingAtAllProducesNothing() {
        #expect(TextRecognizer.Result.combine([]).isEmpty)
    }
}
