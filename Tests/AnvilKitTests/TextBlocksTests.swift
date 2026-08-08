import Foundation
import Testing

@testable import AnvilKit

@Suite("TextBlocks")
struct RecognizedTextCombiningTests {
    /// Bei einem Bild bleibt es der reine Text — man will ihn einfügen, nicht
    /// lesen, wo er herkommt.
    @Test
    func aSinglePieceStaysPlain() {
        let combined = TextBlocks.combine([("screenshot.png", "Hallo Welt")])
        #expect(combined == "Hallo Welt")
    }

    /// Ab zwei bekommt jeder Block den Namen seines Bildes. Ohne den weiß nach
    /// dem Einfügen niemand mehr, welcher Absatz aus welchem Screenshot stammt.
    @Test
    func severalPiecesGetHeadings() {
        let combined = TextBlocks.combine([
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
        let combined = TextBlocks.combine([
            ("mit.png", "Da steht was"),
            ("ohne.png", "   \n  ")
        ])

        #expect(combined.contains("ohne.png"))
        #expect(combined.contains(localized("— kein Text —")))
    }

    @Test
    func nothingAtAllProducesNothing() {
        #expect(TextBlocks.combine([]).isEmpty)
    }
}
