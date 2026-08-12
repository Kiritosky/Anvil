import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Ordner vergleichen")
struct FolderComparisonTests {
    private func compare(
        left: [(path: String, size: Int)],
        right: [(path: String, size: Int)],
        sameContent: (String) -> Bool = { _ in true }
    ) -> FolderComparison {
        FolderComparison(left: left, right: right, sameContent: sameContent)
    }

    @Test
    func whatIsOnlyOnOneSideIsMarked() {
        let result = compare(
            left: [("a.txt", 10), ("nur-links.txt", 20)],
            right: [("a.txt", 10), ("nur-rechts.txt", 30)]
        )
        #expect(result.entries(.onlyLeft).map(\.path) == ["nur-links.txt"])
        #expect(result.entries(.onlyRight).map(\.path) == ["nur-rechts.txt"])
        #expect(result.entries(.same).map(\.path) == ["a.txt"])
    }

    /// Verschiedene Größe heißt verschiedener Inhalt — dafür muss niemand
    /// etwas lesen.
    @Test
    func differentSizesAreNeverRead() {
        var asked = 0
        let result = compare(
            left: [("a.txt", 10)],
            right: [("a.txt", 11)],
            sameContent: { _ in asked += 1; return true }
        )
        #expect(result.entries(.different).count == 1)
        #expect(asked == 0)
    }

    /// Gleiche Größe heißt noch gar nichts — zwei verschiedene Bilder können
    /// auf das Byte gleich groß sein.
    @Test
    func sameSizeStillAsksForTheContent() {
        var asked = 0
        let result = compare(
            left: [("a.txt", 10)],
            right: [("a.txt", 10)],
            sameContent: { _ in asked += 1; return false }
        )
        #expect(asked == 1)
        #expect(result.entries(.different).count == 1)
    }

    /// Der Pfad unterhalb der Ordner ist der Schlüssel — wie die Ordner
    /// darüber heißen, spielt keine Rolle.
    @Test
    func theRelativePathIsWhatMatches() {
        let result = compare(
            left: [("bilder/2026/anna.jpg", 100)],
            right: [("bilder/2026/anna.jpg", 100)]
        )
        #expect(result.entries(.same).count == 1)
    }

    @Test
    func bothSizesAreKept() {
        let result = compare(left: [("a.txt", 10)], right: [("a.txt", 11)])
        #expect(result.entries[0].leftSize == 10)
        #expect(result.entries[0].rightSize == 11)

        let missing = compare(left: [("a.txt", 10)], right: [])
        #expect(missing.entries[0].rightSize == nil)
    }

    /// Erst das Auffällige: Wer vergleicht, sucht den Unterschied und nicht
    /// die Bestätigung.
    @Test
    func theNoteworthyComesFirst() {
        let result = compare(
            left: [("a-gleich.txt", 10), ("z-nur-links.txt", 10)],
            right: [("a-gleich.txt", 10)]
        )
        #expect(result.entries[0].path == "z-nur-links.txt")
        #expect(result.noteworthy.count == 1)
    }

    @Test
    func twoEqualFoldersAreIdentical() {
        let same = compare(left: [("a.txt", 10)], right: [("a.txt", 10)])
        #expect(same.isIdentical)

        let notSame = compare(left: [("a.txt", 10)], right: [])
        #expect(notSame.isIdentical == false)
    }

    /// Zwei leere Ordner sind nicht „gleich" im Sinne einer Bestätigung —
    /// es gibt nichts, was gleich sein könnte.
    @Test
    func twoEmptyFoldersAreNotAConfirmation() {
        let nothing = compare(left: [], right: [])
        #expect(nothing.isEmpty)
        #expect(nothing.isIdentical == false)
    }

    @Test
    func onlySameIsUnremarkable() {
        #expect(FolderComparison.Difference.same.isNoteworthy == false)
        for difference in FolderComparison.Difference.allCases where difference != .same {
            #expect(difference.isNoteworthy)
        }
    }

    @Test
    func theReportHasAHeaderAndOneLinePerFile() {
        let result = compare(left: [("a.txt", 10), ("b.txt", 10)], right: [("a.txt", 10)])
        let lines = result.report.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)
        #expect(lines[0].split(separator: "\t").count == FolderComparison.reportColumns.count)
    }
}

@Suite("Durch Ordner laufen")
struct FileWalkTests {
    private func makeFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "anvil-walk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test
    func everyFileBelowTheFolderComesAlong() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let inner = folder.appending(path: "tief")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 10).write(to: folder.appending(path: "a.txt"))
        try Data(repeating: 0x41, count: 20).write(to: inner.appending(path: "b.txt"))

        let files = FileWalk.files(in: folder)
        #expect(files.count == 2)
        #expect(files.map(\.size).sorted() == [10, 20])
    }

    @Test
    func tooSmallIsLeftOut() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        try Data(repeating: 0x41, count: 10).write(to: folder.appending(path: "klein.txt"))
        try Data(repeating: 0x41, count: 100).write(to: folder.appending(path: "gross.txt"))

        #expect(FileWalk.files(in: folder, minimumBytes: 50).count == 1)
    }

    /// Nur die oberste Ebene — das braucht das Umbenennen, das sonst den
    /// ganzen Baum in die Liste zöge.
    @Test
    func theShallowWalkStaysOnTop() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let inner = folder.appending(path: "tief")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try Data().write(to: folder.appending(path: "a.txt"))
        try Data().write(to: inner.appending(path: "b.txt"))

        let names = FileWalk.shallow(folder).map(\.lastPathComponent).sorted()
        #expect(names == ["a.txt", "tief"])
    }

    @Test
    func theRelativePathLosesTheFolderAbove() {
        let folder = URL(fileURLWithPath: "/Users/anna/Bilder")
        let file = URL(fileURLWithPath: "/Users/anna/Bilder/2026/anna.jpg")
        #expect(FileWalk.relativePath(of: file, under: folder) == "2026/anna.jpg")
    }

    /// Eine Datei, die gar nicht darunter liegt, behält wenigstens ihren
    /// Namen — statt eines Pfads, der nirgendwohin zeigt.
    @Test
    func aFileOutsideKeepsItsName() {
        let folder = URL(fileURLWithPath: "/Users/anna/Bilder")
        let file = URL(fileURLWithPath: "/tmp/anna.jpg")
        #expect(FileWalk.relativePath(of: file, under: folder) == "anna.jpg")
    }

    @Test
    func aFolderThatIsNotThereIsEmpty() {
        #expect(FileWalk.files(in: URL(fileURLWithPath: "/gibt/es/nicht")).isEmpty)
        #expect(FileWalk.isDirectory(URL(fileURLWithPath: "/gibt/es/nicht")) == false)
    }
}
