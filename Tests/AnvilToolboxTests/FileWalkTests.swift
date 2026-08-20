import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Ordner durchgehen")
struct FileWalkTests {
    private func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    private func paths(_ folders: [URL]) -> [String] {
        FileWalk.distinctRoots(folders).map(\.path)
    }

    // MARK: - Enthalten

    @Test
    func aFolderContainsItselfAndWhatIsBelow() {
        #expect(FileWalk.contains(url("/a/b"), url("/a/b")))
        #expect(FileWalk.contains(url("/a/b"), url("/a/b/c/datei.txt")))
        #expect(!FileWalk.contains(url("/a/b"), url("/a")))
    }

    /// Der Fallstrick beim Vergleich über den Präfix: „/a/bc" fängt mit
    /// „/a/b" an, liegt aber nicht darin.
    @Test
    func aSimilarNameIsNoContainment() {
        #expect(!FileWalk.contains(url("/a/b"), url("/a/bc")))
    }

    // MARK: - Doppelte Wurzeln

    /// Zwei Wurzeln, von denen eine unter der anderen liegt, hätten jede
    /// Datei darunter zweimal gezählt — im Dublettenfinder wäre sie damit
    /// ihre eigene Dublette.
    @Test
    func aFolderBelowAnotherFallsAway() {
        #expect(paths([url("/a"), url("/a/b")]) == ["/a"])
    }

    /// Auch andersherum, wenn der engere zuerst kommt.
    @Test
    func theWiderFolderWins() {
        #expect(paths([url("/a/b"), url("/a")]) == ["/a"])
    }

    @Test
    func theSameFolderTwiceStaysOnce() {
        #expect(paths([url("/a"), url("/a")]) == ["/a"])
    }

    @Test
    func separateFoldersAllStay() {
        #expect(paths([url("/a"), url("/b"), url("/c")]) == ["/a", "/b", "/c"])
    }

    @Test
    func theOrderOfWhatStaysIsKept() {
        #expect(paths([url("/b"), url("/a"), url("/b/tief")]) == ["/b", "/a"])
    }

    @Test
    func nothingInIsNothingOut() {
        #expect(FileWalk.distinctRoots([]).isEmpty)
    }
}
