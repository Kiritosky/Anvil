import AnvilKit
import AppKit
import Foundation
import PDFKit
import Testing

@testable import AnvilToolbox

@Suite("Seitenauswahl")
struct PageRangeTests {
    private func range(_ text: String, _ pageCount: Int = 10) throws -> PageRange {
        try PageRange(parsing: text, pageCount: pageCount)
    }

    /// Menschen zählen ab 1, PDFKit ab 0. Genau dazwischen entstehen die
    /// Fehler, also steht es in einem Test.
    @Test
    func pagesAreOneBasedAndIndicesAreNot() throws {
        #expect(try range("1").indices == [0])
        #expect(try range("1-3").indices == [0, 1, 2])
        #expect(try range("10").indices == [9])
    }

    /// Nichts einzutippen ist der häufigste Fall — und meint alle Seiten.
    @Test
    func nothingMeansEverything() throws {
        #expect(try range("").indices == Array(0..<10))
        #expect(try range("   ").count == 10)
    }

    @Test
    func openEndedRangesReachTheEdges() throws {
        #expect(try range("8-").indices == [7, 8, 9])
        #expect(try range("-3").indices == [0, 1, 2])
    }

    @Test
    func severalPartsAreCombinedInOrder() throws {
        #expect(try range("5, 1-2").indices == [4, 0, 1])
    }

    /// Wer 1-100 in ein Dokument mit zehn Seiten tippt, meint alle zehn und
    /// keinen Fehler.
    @Test
    func whatIsOutsideFallsAwayInsteadOfThrowing() throws {
        #expect(try range("1-100").count == 10)
        #expect(try range("50").isEmpty)
        #expect(try range("0").isEmpty)
    }

    @Test
    func aPageNamedTwiceAppearsOnce() throws {
        #expect(try range("1, 1, 2, 1").indices == [0, 1])
    }

    /// Rückwärts geschrieben ist trotzdem gemeint.
    @Test
    func aBackwardsRangeIsRead() throws {
        #expect(try range("5-3").indices == [2, 3, 4])
    }

    @Test(arguments: ["a", "1-b", "x-3", "1..3"])
    func nonsenseThrows(_ text: String) {
        #expect(throws: AnvilError.self) { try PageRange(parsing: text, pageCount: 10) }
    }

    @Test
    func anEmptyDocumentSelectsNothing() throws {
        #expect(try PageRange(parsing: "", pageCount: 0).isEmpty)
        #expect(try PageRange(parsing: "1-5", pageCount: 0).isEmpty)
    }

    /// Zusammengefasst zurückgeschrieben: aus 1,2,3,7 wird „1-3, 7".
    @Test
    func writingItBackJoinsWhatIsAdjacent() throws {
        #expect(try range("1,2,3,7").text == "1-3, 7")
        #expect(try range("5").text == "5")
        #expect(try range("").text == "1-10")
        #expect(PageRange(pages: [], pageCount: 10).text.isEmpty)
    }
}

@Suite("PDF bearbeiten")
struct PDFToolsTests {
    /// Ein PDF mit so vielen Seiten, auf jeder ihre Nummer.
    ///
    /// Selbst gebaut statt aus einer Datei geladen: ein Test, der eine
    /// Beispieldatei braucht, prüft irgendwann die Beispieldatei.
    private func makeDocument(pages: Int, text: (Int) -> String = { "Seite \($0)" }) throws -> PDFDocument {
        let document = PDFDocument()
        for index in 0..<pages {
            let image = NSImage(size: CGSize(width: 200, height: 280))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 200, height: 280).fill()
            (text(index + 1) as NSString).draw(
                at: CGPoint(x: 20, y: 140),
                withAttributes: [.font: NSFont.systemFont(ofSize: 18)]
            )
            image.unlockFocus()

            let page = try #require(PDFPage(image: image))
            document.insert(page, at: index)
        }
        return document
    }

    @Test
    func mergingKeepsEveryPageInOrder() throws {
        let first = try makeDocument(pages: 2)
        let second = try makeDocument(pages: 3)
        let merged = try PDFTools.merge([first, second])
        #expect(merged.pageCount == 5)
        // Die Vorlagen bleiben, wie sie sind.
        #expect(first.pageCount == 2)
        #expect(second.pageCount == 3)
    }

    @Test
    func mergingNothingThrows() {
        #expect(throws: AnvilError.self) { try PDFTools.merge([]) }
    }

    @Test
    func selectingTakesThePagesInTheGivenOrder() throws {
        let document = try makeDocument(pages: 5)
        let range = try PageRange(parsing: "4, 1", pageCount: 5)
        let result = try PDFTools.select(range, from: document)
        #expect(result.pageCount == 2)
        #expect(document.pageCount == 5)
    }

    @Test
    func removingLeavesTheRest() throws {
        let document = try makeDocument(pages: 5)
        let range = try PageRange(parsing: "2-3", pageCount: 5)
        #expect(try PDFTools.removing(range, from: document).pageCount == 3)
    }

    /// Ein Dokument ohne Seite ist keins.
    @Test
    func removingEverythingThrows() throws {
        let document = try makeDocument(pages: 2)
        let all = try PageRange(parsing: "1-2", pageCount: 2)
        #expect(throws: AnvilError.self) { try PDFTools.removing(all, from: document) }
    }

    @Test
    func splittingMakesPartsOfTheGivenSize() throws {
        let document = try makeDocument(pages: 5)
        let parts = try PDFTools.split(document, every: 2)
        #expect(parts.map(\.pageCount) == [2, 2, 1])

        let single = try PDFTools.split(document, every: 1)
        #expect(single.count == 5)

        // Größer als das Dokument: ein Teil, alles darin.
        #expect(try PDFTools.split(document, every: 99).map(\.pageCount) == [5])
    }

    @Test
    func splittingIntoNothingThrows() throws {
        let document = try makeDocument(pages: 3)
        #expect(throws: AnvilError.self) { try PDFTools.split(document, every: 0) }
    }

    @Test
    func rotationIsAddedToWhatIsAlreadyThere() throws {
        let document = try makeDocument(pages: 3)
        let range = try PageRange(parsing: "2", pageCount: 3)
        let once = try PDFTools.rotated(document, by: 90, pages: range)
        #expect(once.page(at: 1)?.rotation == 90)
        #expect(once.page(at: 0)?.rotation == 0)

        let twice = try PDFTools.rotated(once, by: 90, pages: range)
        #expect(twice.page(at: 1)?.rotation == 180)
        // Und die Vorlage ist unverändert.
        #expect(once.page(at: 1)?.rotation == 90)
    }

    @Test
    func anglesAreNormalisedToQuarterTurns() {
        #expect(PDFTools.normalised(0) == 0)
        #expect(PDFTools.normalised(90) == 90)
        #expect(PDFTools.normalised(360) == 0)
        #expect(PDFTools.normalised(450) == 90)
        #expect(PDFTools.normalised(-90) == 270)
        #expect(PDFTools.normalised(-450) == 270)
    }

    @Test
    func theInfoSaysWhatIsInside() throws {
        let document = try makeDocument(pages: 4)
        let info = PDFTools.info(of: document)
        #expect(info.pageCount == 4)
        #expect(info.width > 0)
        #expect(info.height > 0)
        #expect(!info.isEncrypted)
    }

    /// Ein Bild-PDF hat keine Textschicht. Das ist kein Fehler, sondern die
    /// Auskunft, dass hier die Texterkennung gebraucht wird.
    @Test
    func aScannedPageHasNoTextLayer() throws {
        let document = try makeDocument(pages: 2)
        #expect(!PDFTools.info(of: document).hasText)
        #expect(PDFTools.text(of: document).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func writingAndReadingBackGivesTheSamePageCount() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("anvil-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let document = try makeDocument(pages: 3)
        let url = folder.appendingPathComponent("test.pdf")
        try PDFTools.write(document, to: url)

        let reloaded = try #require(PDFDocument(url: url))
        #expect(reloaded.pageCount == 3)
    }

    @Test
    func loadingSortsTheReadableFromTheRest() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("anvil-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let good = folder.appendingPathComponent("gut.pdf")
        try PDFTools.write(try makeDocument(pages: 1), to: good)

        let bad = folder.appendingPathComponent("kaputt.pdf")
        try Data("kein PDF".utf8).write(to: bad)

        let loaded = PDFTools.load([good, bad])
        #expect(loaded.documents.count == 1)
        #expect(loaded.failed == [bad])
    }
}
