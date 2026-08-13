import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Platz zusammenrechnen")
struct DiskUsageTests {
    private let root = URL(fileURLWithPath: "/Code/projekt")

    private func file(_ path: String, _ size: Int) -> (url: URL, size: Int) {
        (url: root.appending(path: path), size: size)
    }

    private var usage: DiskUsage {
        DiskUsage.make(root: root, files: [
            file("bilder/eins.png", 3_000),
            file("bilder/zwei.png", 2_000),
            file("bilder/tief/drei.png", 1_000),
            file("video.mov", 10_000),
            file("liesmich.md", 100)
        ])
    }

    @Test
    func everythingIsCountedOnce() {
        #expect(usage.total == 16_100)
        #expect(usage.fileCount == 5)
    }

    /// Der Punkt der Übung: nach Größe, nicht nach Alphabet.
    @Test
    func theBiggestComesFirst() {
        #expect(usage.children.map(\.name) == ["video.mov", "bilder", "liesmich.md"])
    }

    /// Alles unter einem Ordner zählt zu ihm, auch was tiefer liegt.
    @Test
    func aFolderCarriesEverythingBelowIt() throws {
        let folder = try #require(usage.children.first { $0.name == "bilder" })
        #expect(folder.isDirectory)
        #expect(folder.bytes == 6_000)
        #expect(folder.fileCount == 3)
    }

    /// Eine Datei direkt im Ordner ist ihr eigener Posten und kein Ordner.
    @Test
    func aLooseFileStandsForItself() throws {
        let node = try #require(usage.children.first { $0.name == "video.mov" })
        #expect(!node.isDirectory)
        #expect(node.fileCount == 1)
        #expect(node.path == "/Code/projekt/video.mov")
    }

    @Test
    func theShareIsRelativeToTheWhole() throws {
        let node = try #require(usage.children.first)
        #expect(abs(node.share(of: usage.total) - 10_000.0 / 16_100.0) < 0.000_1)
        #expect(DiskUsage.percent(node.share(of: usage.total)) == "62 %")
        #expect(DiskUsage.percent(0) == "0 %")
        #expect(DiskUsage.percent(1) == "100 %")
    }

    @Test
    func aShareOfNothingIsNothing() {
        let node = DiskUsage.Node(
            name: "leer",
            path: "/leer",
            bytes: 0,
            fileCount: 0,
            isDirectory: true
        )
        #expect(node.share(of: 0) == 0)
    }

    @Test
    func theLargestFilesIgnoreTheirDepth() {
        let names = usage.largestFiles(3).map(\.name)
        #expect(names == ["video.mov", "eins.png", "zwei.png"])
        #expect(usage.largestFiles().count == 5)
    }

    @Test
    func extensionsAreAddedUpAcrossFolders() throws {
        let kinds = usage.byExtension()
        #expect(kinds.first?.name == "mov")
        let png = try #require(kinds.first { $0.name == "png" })
        #expect(png.bytes == 6_000)
        #expect(png.fileCount == 3)
    }

    @Test
    func aFileWithoutAnExtensionIsCountedToo() {
        let usage = DiskUsage.make(root: root, files: [file("Makefile", 10)])
        #expect(usage.byExtension().first?.name == localized("ohne Endung"))
    }

    @Test
    func theReportHasALinePerEntry() {
        let lines = usage.report.components(separatedBy: "\n")
        #expect(lines.count == usage.children.count + 1)
        #expect(usage.rows(usage.children).allSatisfy {
            $0.count == DiskUsage.reportColumns.count
        })
    }

    /// Ordner bekommen im Bericht einen Schrägstrich — sonst sähe „bilder"
    /// aus wie eine Datei ohne Endung.
    @Test
    func foldersAreMarkedInTheReport() {
        #expect(usage.report.contains("bilder/"))
    }

    @Test
    func anEmptyFolderIsNoError() {
        let usage = DiskUsage.make(root: root, files: [])
        #expect(usage.isEmpty)
        #expect(usage.total == 0)
        #expect(usage.children.isEmpty)
        #expect(usage.byExtension().isEmpty)
        #expect(DiskUsage.empty.isEmpty)
    }
}
