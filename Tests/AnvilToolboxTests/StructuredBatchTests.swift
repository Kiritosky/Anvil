import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Formate erkennen")
struct StructuredFormatTests {
    /// Die Endung ist die Auskunft dessen, der die Datei angelegt hat.
    @Test
    func theExtensionDecidesBeforeTheContent() {
        // Inhalt, den die Inhaltserkennung für TOML halten würde.
        #expect(StructuredFormat.detect(name: "config.yaml", text: "a = 1") == .yaml)
        #expect(StructuredFormat.detect(name: "config.yml", text: "a = 1") == .yaml)
        #expect(StructuredFormat.detect(name: "config.json", text: "a: 1") == .json)
    }

    @Test
    func withoutAKnownExtensionTheContentDecides() {
        #expect(StructuredFormat.detect(name: "config.txt", text: "a = 1") == .toml)
        #expect(StructuredFormat.detect(name: "config", text: "a: 1") == .yaml)
        #expect(StructuredFormat.detect(name: "x.conf", text: #"{"a": 1}"#) == .json)
    }

    @Test
    func everyFormatKnowsItsExtension() {
        #expect(StructuredFormat.json.fileExtension == "json")
        #expect(StructuredFormat.yaml.fileExtension == "yaml")
        #expect(StructuredFormat.toml.fileExtension == "toml")
        #expect(StructuredFormat.named("YML") == .yaml)
        #expect(StructuredFormat.named("md") == nil)
    }

    @Test
    func readingAndWritingGoThroughTheSameType() throws {
        let value = try StructuredFormat.yaml.read("a: 1")
        #expect(StructuredFormat.json.write(value).contains("\"a\""))
    }
}

@Suite("Formate im Stapel")
struct StructuredBatchTests {
    private func file(_ name: String, _ text: String) -> (url: URL, text: String) {
        (URL(fileURLWithPath: "/Code/\(name)"), text)
    }

    @Test
    func everyFileGetsItsOwnTarget() {
        let batch = StructuredBatch(
            files: [file("a.yaml", "a: 1"), file("b.toml", "b = 2")],
            target: .json
        )
        #expect(batch.writing.count == 2)
        #expect(batch.entries[0].source == .yaml)
        #expect(batch.entries[1].source == .toml)
        #expect(batch.entries[0].destination(.json).lastPathComponent == "a.json")
        #expect(batch.isReady)
    }

    /// Eine Datei, die schon im Zielformat vorliegt, umzuwandeln hieße, sie
    /// über sich selbst zu schreiben.
    @Test
    func aFileThatIsAlreadyInTheTargetFormatIsLeftAlone() {
        let batch = StructuredBatch(files: [file("a.json", #"{"a": 1}"#)], target: .json)
        #expect(batch.entries[0].problem == .sameFormat)
        #expect(batch.writing.isEmpty)
        #expect(batch.isReady == false)
    }

    @Test
    func aFileThatCannotBeReadSaysWhy() throws {
        let batch = StructuredBatch(files: [file("a.json", "{kaputt")], target: .yaml)
        let problem = try #require(batch.entries[0].problem)
        #expect(batch.entries[0].converted == nil)
        #expect(!problem.detail.isEmpty)
    }

    /// Eine Datei am Ziel zu überschreiben wäre nicht rückgängig zu machen.
    @Test
    func anOccupiedTargetBlocksTheEntry() {
        let batch = StructuredBatch(
            files: [file("a.yaml", "a: 1")],
            target: .json,
            existing: ["/Code/a.json"]
        )
        #expect(batch.entries[0].problem == .occupied)
        #expect(batch.isReady == false)
    }

    @Test
    func oneBadFileDoesNotStopTheOthers() {
        let batch = StructuredBatch(
            files: [file("a.yaml", "a: 1"), file("b.json", "{kaputt")],
            target: .toml
        )
        #expect(batch.writing.count == 1)
        #expect(batch.blocked.count == 1)
        #expect(batch.isReady)
    }

    @Test
    func theReportHasAHeaderAndOneLinePerFile() {
        let batch = StructuredBatch(
            files: [file("a.yaml", "a: 1"), file("b.yaml", "b: 2")],
            target: .json
        )
        let lines = batch.report.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)
        #expect(lines[0].split(separator: "\t").count == StructuredBatch.reportColumns.count)
        #expect(lines[1].hasPrefix("a.yaml\t"))
    }

    @Test
    func nothingInIsAnEmptyBatch() {
        #expect(StructuredBatch.empty.isEmpty)
        #expect(StructuredBatch.empty.isReady == false)
    }

    // MARK: - Auf der Platte

    private func makeFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "anvil-batch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test
    func theWholeWayThroughAndBackAgain() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = folder.appending(path: "config.yaml")
        try "name: Anvil\nport: 8080".write(to: source, atomically: true, encoding: .utf8)

        let batch = StructuredBatch(urls: [source], target: .json)
        #expect(batch.isReady)

        let outcome = try batch.execute()
        #expect(outcome.written == 1)

        let written = folder.appending(path: "config.json")
        let text = try String(contentsOf: written, encoding: .utf8)
        #expect(text.contains("\"name\""))
        #expect(text.contains("8080"))
        // Die Quelle bleibt, wie sie war.
        #expect(try String(contentsOf: source, encoding: .utf8) == "name: Anvil\nport: 8080")

        try StructuredBatch.revert(outcome.created)
        #expect(FileManager.default.fileExists(atPath: written.path) == false)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    /// Was schon dalag, kommt nie in die Liste — und wird deshalb auch beim
    /// Zurücknehmen nicht gelöscht.
    @Test
    func anExistingTargetIsNeitherWrittenNorRemoved() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = folder.appending(path: "config.yaml")
        let target = folder.appending(path: "config.json")
        try "a: 1".write(to: source, atomically: true, encoding: .utf8)
        try "von Hand".write(to: target, atomically: true, encoding: .utf8)

        let batch = StructuredBatch(urls: [source], target: .json)
        #expect(batch.entries[0].problem == .occupied)
        #expect(throws: AnvilError.self) { try batch.execute() }
        #expect(try String(contentsOf: target, encoding: .utf8) == "von Hand")
    }

    @Test
    func aFileThatIsNoTextSaysSo() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appending(path: "bild.yaml")
        try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: url)

        let batch = StructuredBatch(urls: [url], target: .json)
        #expect(batch.entries.count == 1)
        #expect(batch.isReady == false)
    }
}
