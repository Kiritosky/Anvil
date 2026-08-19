import Foundation
import Testing

@testable import AnvilKit

@Suite("Was auf der Platte liegt")
struct DataInventoryTests {
    private func makeFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "anvil-daten-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func write(_ bytes: Int, to folder: URL, as name: String) throws {
        try Data(repeating: 0x41, count: bytes).write(to: folder.appending(path: name))
    }

    @Test
    func filesAndBytesAreCounted() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try write(100, to: folder, as: "a.json")
        try write(50, to: folder, as: "b.json")

        let counted = DataInventory.count(in: folder)
        #expect(counted.files == 2)
        #expect(counted.bytes == 150)
    }

    /// Der Verlauf liegt in Unterordnern, sobald ein Werkzeug welche anlegt.
    @Test
    func subfoldersAreCountedToo() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let inner = folder.appending(path: "tief")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try write(10, to: folder, as: "a.json")
        try write(20, to: inner, as: "b.json")

        let counted = DataInventory.count(in: folder)
        #expect(counted.files == 2)
        #expect(counted.bytes == 30)
    }

    /// Ein Ordner, den es nicht gibt, ist kein Fehler — nur nichts.
    @Test
    func aMissingFolderIsEmpty() {
        let counted = DataInventory.count(in: URL(fileURLWithPath: "/gibt/es/nicht"))
        #expect(counted.files == 0)
        #expect(counted.bytes == 0)
    }

    /// Der Ordner selbst bleibt stehen: Die App legt ihn beim Start an und
    /// schreibt später hinein.
    @Test
    func emptyingLeavesTheFolderItself() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try write(10, to: folder, as: "a.json")
        try DataInventory.empty(at: folder)

        #expect(DataInventory.count(in: folder).files == 0)
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test
    func emptyingWhatIsAlreadyEmptyIsNoError() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try DataInventory.empty(at: folder)
        #expect(DataInventory.count(in: folder).files == 0)
    }

    // MARK: - Was gezeigt wird

    @Test
    func nothingThereSaysSo() {
        let item = StoredData(kind: .history, byteCount: 0, fileCount: 0)
        #expect(item.isEmpty)
        #expect(item.summary == localized("leer"))
    }

    @Test
    func theSummaryNamesFilesAndSize() {
        let item = StoredData(kind: .recordings, byteCount: 2_000_000, fileCount: 3)
        #expect(!item.isEmpty)
        #expect(item.summary.contains("3"))
        #expect(item.summary.contains("MB"))
    }

    /// Eigene Werkzeuge sind keine Ablage, sondern Arbeit.
    @Test
    func clearingEverythingSparesTheUsersOwnTools() {
        #expect(StoredData.Kind.customTools.isRemovedWithEverything == false)
        let rest = StoredData.Kind.allCases.filter { $0 != .customTools }
        #expect(rest.allSatisfy { $0.isRemovedWithEverything })
    }

    @Test
    func everyKindHasItsOwnFolder() {
        var seen: Set<String> = []
        for kind in StoredData.Kind.allCases {
            #expect(seen.insert(kind.url.path).inserted, "\(kind.rawValue)")
            #expect(!kind.title.isEmpty)
            #expect(!kind.explanation.isEmpty)
            #expect(!kind.systemImage.isEmpty)
        }
    }

    @Test
    func theTotalIsTheSumOfTheParts() {
        let items = [
            StoredData(kind: .history, byteCount: 100, fileCount: 1),
            StoredData(kind: .drafts, byteCount: 200, fileCount: 2)
        ]
        #expect(DataInventory.totalBytes(items) == 300)
        #expect(DataInventory.totalBytes([]) == 0)
    }
}

@Suite("Der Verlauf vergisst")
struct HistoryStoreForgetTests {
    @Test @MainActor
    func forgettingClearsDiskAndMemory() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "anvil-verlauf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let store = HistoryStore(directory: folder)
        store.record(
            HistoryEntry(toolID: "test.tool", title: "Test", input: "ein", output: "aus")
        )
        #expect(store.entries(for: "test.tool").count == 1)
        #expect(DataInventory.count(in: folder).files == 1)

        store.forgetEverything()
        #expect(store.entries(for: "test.tool").isEmpty)
        #expect(DataInventory.count(in: folder).files == 0)
    }
}
