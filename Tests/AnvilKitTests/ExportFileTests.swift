import Foundation
import Testing

@testable import AnvilKit

@Suite("ExportFile")
struct ExportFileTests {
    // MARK: - Was aus dem Namen wird

    @Test
    func keepsAnOrdinaryName() {
        #expect(ExportFile.sanitize("Bildschirmfoto 2026-08-06") == "Bildschirmfoto 2026-08-06")
    }

    /// Der Schrägstrich trennt Pfade, der Doppelpunkt tut es im Finder. Beides
    /// muss weg, sonst landet die Datei woanders — oder nirgends.
    @Test
    func removesPathSeparators() {
        #expect(ExportFile.sanitize("https://anvil.dev/start") == "https anvil.dev start")
        #expect(ExportFile.sanitize("Termin: 14 Uhr") == "Termin 14 Uhr")
    }

    /// Der Name kommt oft aus mehrzeiligem Inhalt. Ein Zeilenumbruch im
    /// Dateinamen ist erlaubt und trotzdem eine Zumutung.
    @Test
    func collapsesWhitespaceAndNewlines() {
        #expect(ExportFile.sanitize("Zeile eins\nZeile zwei") == "Zeile eins Zeile zwei")
        #expect(ExportFile.sanitize("  viel   Luft  ") == "viel Luft")
    }

    /// Ein führender Punkt macht die Datei auf dem Mac unsichtbar — auf dem
    /// Schreibtisch käme dann scheinbar nichts an.
    @Test
    func neverStartsWithADot() {
        #expect(ExportFile.sanitize(".gitignore") == "gitignore")
        #expect(ExportFile.sanitize("...") == "Anvil")
    }

    @Test
    func fallsBackWhenNothingUsableIsLeft() {
        #expect(ExportFile.sanitize("") == "Anvil")
        #expect(ExportFile.sanitize("///") == "Anvil")
        #expect(ExportFile.sanitize("   ", fallback: "QR-Code") == "QR-Code")
    }

    @Test
    func shortensOverlyLongNames() {
        let long = String(repeating: "a", count: 500)
        let name = ExportFile.sanitize(long)
        #expect(name.count == 80)
    }

    /// Umlaute und Emoji sind im Dateisystem erlaubt und sollen bleiben — die
    /// Bereinigung ist keine Übersetzung nach ASCII.
    @Test
    func keepsCharactersTheFileSystemAllows()  {
        #expect(ExportFile.sanitize("Grüße 🎉") == "Grüße 🎉")
    }

    // MARK: - Die Datei selbst

    @Test
    func writesToItsOwnDirectory() throws {
        let url = try ExportFile.temporary(
            named: "Ergebnis",
            extension: "txt",
            contents: Data("hallo".utf8)
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(url.lastPathComponent == "Ergebnis.txt")
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written == "hallo")
    }

    /// Zwei Exporte mit demselben Namen dürfen sich nicht in die Quere kommen:
    /// der zweite Zug darf die Datei des ersten nicht überschreiben, während
    /// die vielleicht noch kopiert wird.
    @Test
    func twoExportsWithTheSameNameDoNotCollide() throws {
        let first = try ExportFile.temporary(
            named: "Gleich",
            extension: "txt",
            contents: Data("eins".utf8)
        )
        let second = try ExportFile.temporary(
            named: "Gleich",
            extension: "txt",
            contents: Data("zwei".utf8)
        )
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }

        #expect(first != second)
        let contentsOfFirst = try String(contentsOf: first, encoding: .utf8)
        #expect(contentsOfFirst == "eins")
    }

    @Test
    func sanitizesTheNameOnTheWayToDisk() throws {
        let url = try ExportFile.temporary(
            named: "a/b:c",
            extension: "png",
            contents: Data()
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(url.lastPathComponent == "a b c.png")
    }
}
