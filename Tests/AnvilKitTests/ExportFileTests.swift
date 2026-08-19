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

    // MARK: - Ein Stapel in einen Ordner

    /// Der Fall, der bei einem Stapel wirklich weh tut: In den Zielordner
    /// gehen dreißig Dateien, und eine davon heißt wie eine, die schon da
    /// liegt. Überschreiben würde das Original vernichten, und man merkt es
    /// erst, wenn es weg ist.
    @Test
    func aSecondFileWithTheSameNameGetsANumber() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "anvil-unique-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = ExportFile.uniqueURL(in: directory, named: "Foto", extension: "jpg")
        #expect(first.lastPathComponent == "Foto.jpg")
        try Data("eins".utf8).write(to: first)

        let second = ExportFile.uniqueURL(in: directory, named: "Foto", extension: "jpg")
        #expect(second.lastPathComponent == "Foto 2.jpg")
        try Data("zwei".utf8).write(to: second)

        let third = ExportFile.uniqueURL(in: directory, named: "Foto", extension: "jpg")
        #expect(third.lastPathComponent == "Foto 3.jpg")

        let original = try String(contentsOf: first, encoding: .utf8)
        #expect(original == "eins")
    }

    /// Dieselbe Endung entscheidet mit: ein Foto.png neben einem Foto.jpg ist
    /// kein Zusammenstoß.
    @Test
    func differentExtensionsDoNotCollide() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "anvil-unique-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data().write(to: ExportFile.uniqueURL(in: directory, named: "Foto", extension: "png"))
        let jpg = ExportFile.uniqueURL(in: directory, named: "Foto", extension: "jpg")
        #expect(jpg.lastPathComponent == "Foto.jpg")
    }

    @Test
    func theNameIsCleanedBeforeTheCollisionCheck() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "anvil-unique-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = ExportFile.uniqueURL(in: directory, named: "a/b", extension: "png")
        #expect(url.lastPathComponent == "a b.png")
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
