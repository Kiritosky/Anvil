import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Repositories finden")
struct RepositoryScanTests {
    /// Baut einen Ordnerbaum aus Pfaden. Ein Pfad, der auf `/.git` endet,
    /// macht den Ordner darüber zu einem Repository.
    private func makeTree(_ paths: [String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "anvil-scan-\(UUID().uuidString)")
        for path in paths {
            try FileManager.default.createDirectory(
                at: root.appending(path: path),
                withIntermediateDirectories: true
            )
        }
        return root
    }

    private func names(_ urls: [URL]) -> [String] {
        urls.map(\.lastPathComponent)
    }

    @Test
    func aFolderWithGitInsideIsARepository() throws {
        let root = try makeTree(["projekt/.git", "kein-projekt/quellen"])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(names(RepositoryScan.repositories(under: root)) == ["projekt"])
    }

    @Test
    func theFolderItselfCountsToo() throws {
        let root = try makeTree([".git", "Sources"])
        defer { try? FileManager.default.removeItem(at: root) }

        let found = RepositoryScan.repositories(under: root)
        #expect(found.count == 1)
        #expect(found[0].path == root.path)
    }

    /// Ein Untermodul gehört dem Repository darum und ist keine eigene
    /// Baustelle.
    @Test
    func aRepositoryInsideARepositoryIsNotSearched() throws {
        let root = try makeTree(["projekt/.git", "projekt/untermodul/.git"])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(names(RepositoryScan.repositories(under: root)) == ["projekt"])
    }

    /// `node_modules` und Konsorten enthalten regelmäßig fremde Repositories.
    /// Wer sie mitzählt, findet die eigene Arbeit nicht wieder.
    @Test
    func foreignFoldersAreLeftAlone() throws {
        let root = try makeTree([
            "projekt/.git",
            "projekt2/node_modules/paket/.git",
            "projekt3/.build/abhaengigkeit/.git"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(names(RepositoryScan.repositories(under: root)) == ["projekt"])
    }

    @Test
    func theDepthIsAnEnd() throws {
        let root = try makeTree(["a/b/c/tief/.git"])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(RepositoryScan.repositories(under: root, maxDepth: 2).isEmpty)
        #expect(RepositoryScan.repositories(under: root, maxDepth: 4).count == 1)
    }

    @Test
    func theListIsSortedByName() throws {
        let root = try makeTree(["zebra/.git", "anton/.git", "Mitte/.git"])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(names(RepositoryScan.repositories(under: root)) == ["anton", "Mitte", "zebra"])
    }

    @Test
    func aFolderThatIsNotThereIsNoRepository() {
        let missing = URL(fileURLWithPath: "/gibt/es/nicht")
        #expect(RepositoryScan.repositories(under: missing).isEmpty)
        #expect(RepositoryScan.isRepository(missing) == false)
    }
}
