import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("QR-Codes im Stapel")
struct QRCodeBatchTests {
    @Test
    func oneLinePerCode() {
        let batch = QRCodeBatch("https://anvil.dev\nhttps://example.com")
        #expect(batch.entries.count == 2)
        #expect(batch.writing.count == 2)
        #expect(batch.isReady)
    }

    @Test
    func emptyLinesAreNotCodes() {
        let batch = QRCodeBatch("\n\nhallo\n\n")
        #expect(batch.entries.count == 1)
    }

    /// Die Form, die aus einer Tabellenkalkulation kommt.
    @Test
    func aTabSeparatesTheNameFromTheContent() {
        let batch = QRCodeBatch("Besprechungsraum\thttps://anvil.dev/raum-1")
        #expect(batch.entries[0].name == "Besprechungsraum")
        #expect(batch.entries[0].text == "https://anvil.dev/raum-1")
    }

    @Test
    func withoutANameTheContentBecomesOne() {
        let batch = QRCodeBatch("https://anvil.dev")
        // Der Doppelpunkt darf nicht in den Namen: im Finder trennt er Pfade.
        #expect(!batch.entries[0].name.contains(":"))
        #expect(!batch.entries[0].name.contains("/"))
        #expect(!batch.entries[0].name.isEmpty)
    }

    /// Zwei gleiche Zeilen ergäben zweimal denselben Dateinamen — die erste
    /// wäre weg.
    @Test
    func theSecondOfTwoEqualNamesIsNumbered() {
        let batch = QRCodeBatch("hallo\nhallo\nhallo")
        #expect(batch.entries[0].name == "hallo")
        #expect(batch.entries[1].name == "hallo 2")
        #expect(batch.entries[2].name == "hallo 3")
    }

    @Test
    func aLineOfPunctuationStillGetsAName() {
        let batch = QRCodeBatch("///")
        #expect(!batch.entries[0].name.isEmpty)
    }

    @Test
    func anEmptyContentIsMarked() {
        let batch = QRCodeBatch("Name\t")
        #expect(batch.entries[0].problem == .empty)
        #expect(batch.isReady == false)
    }

    /// Mehr, als in einen QR-Code passt — das Muster wäre nicht mehr lesbar.
    @Test
    func tooMuchTextIsMarked() {
        let batch = QRCodeBatch(String(repeating: "a", count: QRCodeBatch.maxBytes + 1))
        #expect(batch.entries[0].problem == .tooLong)
        #expect(batch.writing.isEmpty)
    }

    /// Gerechnet wird in Byte, nicht in Zeichen: Ein Emoji ist vier davon.
    @Test
    func theLimitCountsBytes() {
        let text = String(repeating: "🔧", count: QRCodeBatch.maxBytes / 4 + 1)
        #expect(text.count < QRCodeBatch.maxBytes)
        #expect(QRCodeBatch(text).entries[0].problem == .tooLong)
    }

    @Test
    func oneBadLineDoesNotStopTheOthers() {
        let batch = QRCodeBatch("gut\n\t")
        #expect(batch.writing.count == 1)
        #expect(batch.blocked.count == 1)
        #expect(batch.isReady)
    }

    @Test
    func theReportHasAHeaderAndOneLinePerCode() {
        let batch = QRCodeBatch("eins\nzwei")
        let lines = batch.report.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)
        #expect(lines[0].split(separator: "\t").count == QRCodeBatch.reportColumns.count)
        #expect(lines[1].hasPrefix("eins.png\t"))
    }

    @Test
    func nothingInIsAnEmptyBatch() {
        #expect(QRCodeBatch("").isEmpty)
        #expect(QRCodeBatch.empty.isReady == false)
    }

    // MARK: - Schreiben

    private func makeFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "anvil-qr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Das Bild kommt als Parameter herein — so lässt sich der Plan prüfen,
    /// ohne dass CoreImage laufen muss.
    private func fakeImage(_ text: String) -> Data {
        Data(text.utf8)
    }

    @Test
    func everyCodeBecomesAFile() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let batch = QRCodeBatch("eins\nzwei")
        let outcome = try batch.write(to: folder) { fakeImage($0) }

        #expect(outcome.written == 2)
        #expect(outcome.created.count == 2)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "eins.png").path))
    }

    /// Wer dreißig Bilder in einen Ordner legt, in dem schon welche liegen,
    /// darf keine davon verlieren.
    @Test
    func anExistingFileIsNeverOverwritten() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let existing = folder.appending(path: "eins.png")
        try Data("von Hand".utf8).write(to: existing)

        let outcome = try QRCodeBatch("eins").write(to: folder) { fakeImage($0) }
        #expect(outcome.written == 1)
        #expect(try Data(contentsOf: existing) == Data("von Hand".utf8))
        #expect(outcome.created[0] != existing)
    }

    @Test
    func blockedLinesAreNotWritten() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let outcome = try QRCodeBatch("gut\n\t").write(to: folder) { fakeImage($0) }
        #expect(outcome.written == 1)
    }

    @Test
    func aBatchWithNothingToDoRefusesToRun() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(throws: AnvilError.self) {
            try QRCodeBatch("").write(to: folder) { fakeImage($0) }
        }
    }
}
