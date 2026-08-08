import AnvilKit
import CryptoKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("FileDigest")
struct FileDigestTests {
    private func withFile(_ data: Data, _ body: (URL) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "anvil-digest-\(UUID().uuidString).bin")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        try body(url)
    }

    // MARK: - Bekannte Werte

    /// Die veröffentlichten Werte für die leere Eingabe. Wenn die Blocklogik
    /// beim Dateiende etwas falsch macht, fällt es genau hier auf.
    @Test
    func matchesPublishedVectorsForEmptyFile() throws {
        try withFile(Data()) { url in
            let sha256 = try FileDigest.hex(SHA256.self, of: url)
            #expect(sha256 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

            let md5 = try FileDigest.hex(Insecure.MD5.self, of: url)
            #expect(md5 == "d41d8cd98f00b204e9800998ecf8427e")
        }
    }

    @Test
    func matchesPublishedVectorForABC() throws {
        try withFile(Data("abc".utf8)) { url in
            let sha256 = try FileDigest.hex(SHA256.self, of: url)
            #expect(sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

            let sha1 = try FileDigest.hex(Insecure.SHA1.self, of: url)
            #expect(sha1 == "a9993e364706816aba3e25717850c26c9cd0d89d")
        }
    }

    // MARK: - Über Blockgrenzen hinweg

    /// Der eigentliche Grund für diese Tests: die Datei wird in Blöcken
    /// gelesen, und eine Prüfsumme über Blöcke muss dieselbe sein wie eine über
    /// alles auf einmal. Diese Datei ist gut zweieinhalb Blöcke groß, trifft
    /// die Grenze also mitten im Inhalt.
    @Test
    func chunkedResultEqualsSinglePass() throws {
        let size = FileDigest.chunkSize * 2 + 12_345
        var data = Data(capacity: size)
        var value: UInt8 = 0
        for _ in 0..<size {
            data.append(value)
            value = value &+ 31
        }

        try withFile(data) { url in
            let streamed = try FileDigest.hex(SHA256.self, of: url)
            let atOnce = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(streamed == atOnce)
        }
    }

    /// Genau eine Blockgrenze: der zweite Lesevorgang liefert nichts mehr.
    @Test
    func handlesExactChunkBoundary() throws {
        let data = Data(repeating: 0x5A, count: FileDigest.chunkSize)
        try withFile(data) { url in
            let streamed = try FileDigest.hex(SHA512.self, of: url)
            let atOnce = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(streamed == atOnce)
        }
    }

    // MARK: - Alle auf einmal

    /// „Alle" liest die Datei nur einmal — die vier Werte müssen trotzdem
    /// dieselben sein wie einzeln gerechnet.
    @Test
    func allMatchesIndividualRuns() throws {
        try withFile(Data("Anvil prüft Downloads.".utf8)) { url in
            let all = try FileDigest.all(of: url)
            #expect(all.map(\.name) == ["MD5", "SHA-1", "SHA-256", "SHA-512"])

            let expected = [
                try FileDigest.hex(Insecure.MD5.self, of: url),
                try FileDigest.hex(Insecure.SHA1.self, of: url),
                try FileDigest.hex(SHA256.self, of: url),
                try FileDigest.hex(SHA512.self, of: url)
            ]
            #expect(all.map(\.value) == expected)
        }
    }

    // MARK: - Mehrere Dateien

    /// Bei einer Datei nur die Prüfsumme — man hält sie neben die von der
    /// Webseite, und ein Dateiname daneben stört dabei.
    @Test
    func aSingleFileReportsJustTheDigest() throws {
        try withFile(Data("abc".utf8)) { url in
            let report = try FileDigest.report(SHA256.self, of: [url])
            #expect(report == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        }
    }

    /// Ab zwei die shasum-Form: Prüfsumme, zwei Leerzeichen, Name. Das ist
    /// nicht Geschmack, sondern das Format, das `shasum -c` wieder liest.
    @Test
    func severalFilesUseTheShasumFormat() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "anvil-digest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appending(path: "eins.txt")
        let second = directory.appending(path: "zwei.txt")
        try Data("abc".utf8).write(to: first)
        try Data("abc".utf8).write(to: second)

        let report = try FileDigest.report(SHA256.self, of: [first, second])
        let rows = report.components(separatedBy: "\n")

        #expect(rows.count == 2)
        #expect(rows[0] == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  eins.txt")
        #expect(rows[1].hasSuffix("  zwei.txt"))
    }

    /// Eine unlesbare Datei bekommt ihre Zeile mit dem Fehler statt still aus
    /// der Liste zu fallen — sonst prüft jemand fünf von sechs Dateien und
    /// hält das für alle.
    @Test
    func anUnreadableFileStillGetsALine() throws {
        try withFile(Data("abc".utf8)) { url in
            let missing = URL(filePath: "/gibt/es/nicht/anvil.bin")
            let report = try FileDigest.report(SHA256.self, of: [url, missing])
            let rows = report.components(separatedBy: "\n")

            #expect(rows.count == 2)
            #expect(rows[1].contains("anvil.bin"))
            #expect(!rows[1].hasPrefix("ba7816bf"))
        }
    }

    /// „Alle" gruppiert nach Datei — vier Zeilen unter einem Namen sind
    /// lesbar, vier Namen mit je vier Werten dazwischen nicht.
    @Test
    func allLinesGroupsByFile() throws {
        try withFile(Data("abc".utf8)) { url in
            let report = FileDigest.allLines(of: [url, url])
            let blocks = report.components(separatedBy: "\n\n")

            #expect(blocks.count == 2)
            #expect(blocks[0].hasPrefix(url.lastPathComponent))
            #expect(blocks[0].contains("SHA-256"))
        }
    }

    @Test
    func anEmptyListProducesNothing() throws {
        #expect(try FileDigest.report(SHA256.self, of: []).isEmpty)
    }

    // MARK: - Größe und Fehler

    @Test
    func reportsFileSize() throws {
        try withFile(Data(repeating: 0, count: 4096)) { url in
            #expect(FileDigest.size(of: url) == 4096)
        }
    }

    @Test
    func missingFileThrows() {
        let url = URL(filePath: "/gibt/es/nicht/anvil.bin")
        #expect(throws: AnvilError.self) { try FileDigest.hex(SHA256.self, of: url) }
    }
}
