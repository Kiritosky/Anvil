import Foundation
import Testing

@testable import AnvilKit

@Suite("Zeilen")
struct TextLinesTests {
    /// Der Fehler, für den es diesen Typ gibt: `"\r\n"` ist in Swift **ein**
    /// `Character`. `split(separator: "\n")` trennt daran also gar nicht.
    @Test
    func windowsLineEndingsSeparateLines() {
        #expect(TextLines.split("a\r\nb\r\nc") == ["a", "b", "c"])
        // Zum Vergleich, damit klar bleibt, warum die Abkürzung nicht geht:
        #expect("a\r\nb".split(separator: "\n").count == 1)
    }

    /// Und der Fehler in die andere Richtung: über `CharacterSet.newlines`
    /// getrennt wird aus jedem CRLF eine Leerzeile, die es nie gab.
    @Test
    func windowsLineEndingsDoNotBecomeBlankLines() {
        #expect(TextLines.split("a\r\nb").count == 2)
        #expect("a\r\nb".components(separatedBy: .newlines).count == 3)
    }

    @Test
    func oldMacLineEndingsSeparateToo() {
        #expect(TextLines.split("a\rb\rc") == ["a", "b", "c"])
    }

    @Test
    func blankLinesStayUnlessTheyAreNotWanted() {
        #expect(TextLines.split("a\n\nb") == ["a", "", "b"])
        #expect(TextLines.split("a\n\nb", keepingEmpty: false) == ["a", "b"])
    }

    /// Kein Text sind null Zeilen. `components` gäbe hier `[""]` zurück und
    /// damit die Zahl 1 für gar nichts.
    @Test
    func nothingIsZeroLines() {
        #expect(TextLines.count("") == 0)
        #expect(TextLines.split("") == [""])
        #expect(TextLines.count("eine Zeile") == 1)
        #expect(TextLines.count("a\r\nb\r\nc") == 3)
    }

    @Test
    func aTrailingBreakLeavesAnEmptyLastLine() {
        // Bewusst so: wer Zeilennummern vergibt, zählt die Zeile hinter dem
        // letzten Umbruch mit, und wer sie nicht will, filtert sie weg.
        #expect(TextLines.split("a\n") == ["a", ""])
        #expect(TextLines.split("a\n", keepingEmpty: false) == ["a"])
    }
}
