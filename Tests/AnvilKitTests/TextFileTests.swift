import Foundation
import Testing

@testable import AnvilKit

@Suite("TextFile")
struct TextFileTests {
    // MARK: - Was Text ist

    @Test
    func readsUTF8() throws {
        let text = "Grüße aus München — ohne Umwege."
        let decoded = TextFile.decode(Data(text.utf8))
        #expect(decoded == text)
    }

    @Test
    func emptyFileIsEmptyText() {
        #expect(TextFile.decode(Data()) == "")
    }

    /// Ein reines ASCII-Dokument darf nie an der Kodierung scheitern — es ist
    /// in jeder der Kandidaten-Kodierungen dasselbe.
    @Test
    func readsPlainASCII() {
        #expect(TextFile.decode(Data("id,name\n1,anvil\n".utf8)) == "id,name\n1,anvil\n")
    }

    // MARK: - Byte Order Marks

    @Test
    func stripsUTF8ByteOrderMark() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("Hallo".utf8))
        #expect(TextFile.decode(data) == "Hallo")
    }

    /// Ohne Auswertung der Mark läge hier zwischen jedem Buchstaben ein
    /// Nullbyte — und die Binärprüfung würde die Datei anschließend ablehnen.
    @Test
    func readsUTF16WithByteOrderMark() throws {
        let text = "Zwei Bytes pro Zeichen"
        let data = try #require(text.data(using: .utf16LittleEndian).map {
            Data([0xFF, 0xFE]) + $0
        })
        #expect(TextFile.decode(data) == text)
    }

    @Test
    func readsBigEndianUTF16() throws {
        let text = "Andersherum"
        let data = try #require(text.data(using: .utf16BigEndian).map {
            Data([0xFE, 0xFF]) + $0
        })
        #expect(TextFile.decode(data) == text)
    }

    // MARK: - Alte Kodierungen

    /// Eine Latin-1-Datei ist als UTF-8 ungültig. Ohne Rückfallebene bekäme der
    /// Benutzer „lässt sich nicht lesen" für eine Datei, die sein Editor
    /// problemlos öffnet.
    @Test
    func fallsBackToLatin1() throws {
        let text = "Café"
        let data = try #require(text.data(using: .isoLatin1))
        #expect(String(data: data, encoding: .utf8) == nil)
        #expect(TextFile.decode(data) == text)
    }

    // MARK: - Was kein Text ist

    /// Der Grund für die Nullbyte-Prüfung: isoLatin1 nimmt jedes Byte an und
    /// würde für ein PNG bereitwillig Kästchen-„Text" liefern.
    @Test
    func rejectsBinary() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
        #expect(TextFile.decode(png) == nil)
    }

    @Test
    func rejectsNulBytesInOtherwiseReadableData() {
        var data = Data("Sieht aus wie Text".utf8)
        data.append(0)
        data.append(contentsOf: Array("und ist es doch nicht".utf8))
        #expect(TextFile.decode(data) == nil)
    }

    // MARK: - Von der Platte

    @Test
    func readsFileFromDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "anvil-textfile-\(UUID().uuidString).txt")
        let text = "Zeile eins\nZeile zwei\n"
        try Data(text.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let read = try TextFile.read(at: url)
        #expect(read == text)
    }

    @Test
    func refusesFilesOverTheSizeLimit() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "anvil-textfile-\(UUID().uuidString).txt")
        try Data(repeating: 0x41, count: TextFile.sizeLimit + 1).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: AnvilError.self) { try TextFile.read(at: url) }
    }

    @Test
    func missingFileReportsStorageFailure() {
        let url = URL(filePath: "/gibt/es/nicht/anvil.txt")
        #expect(throws: AnvilError.self) { try TextFile.read(at: url) }
    }
}
