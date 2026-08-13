import AnvilKit
import Foundation
import Testing

@testable import AnvilUI

@Suite("Gezogene Dateien einordnen")
@MainActor
struct FileDropTests {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "anvil-drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Der Fall, der ein halbes Dutzend Werkzeuge betraf: Wer einen Ordner
    /// hineinzieht, will ihn durchsuchen lassen — und bekam eine
    /// Fehlermeldung, weil ein Ordner sich nicht als Text lesen lässt.
    @Test
    func aFolderComesThroughAsAFile() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        switch FileDropReader.load(folder, kinds: .any) {
        case let .success(.file(url)):
            #expect(url.lastPathComponent == folder.lastPathComponent)
        case let .success(other):
            Issue.record("Ein Ordner kam als \(other) durch.")
        case let .failure(failure):
            Issue.record("Ein Ordner wurde abgewiesen: \(failure.message)")
        }
    }

    /// Auch ein Paket ist auf der Platte ein Ordner. Wer eine App in ein
    /// Werkzeug zieht, das Ordner durchsieht, meint ihren Inhalt.
    @Test
    func aPackageIsAFolderToo() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let bundle = folder.appending(path: "Beispiel.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        switch FileDropReader.load(bundle, kinds: .any) {
        case .success(.file): break
        default: Issue.record("Ein Paket kam nicht als Datei durch.")
        }
    }

    @Test
    func aTextFileIsStillReadAsText() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appending(path: "notiz.txt")
        try Data("Hallo".utf8).write(to: file)

        switch FileDropReader.load(file, kinds: .any) {
        case let .success(.text(text, _)):
            #expect(text == "Hallo")
        default:
            Issue.record("Eine Textdatei kam nicht als Text durch.")
        }
    }

    /// Wer die Bytes will, bekommt die Bytes — auch von einer Textdatei.
    @Test
    func aFileTargetGetsTheFileItself() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appending(path: "notiz.txt")
        try Data("Hallo".utf8).write(to: file)

        switch FileDropReader.load(file, kinds: .file) {
        case .success(.file): break
        default: Issue.record("Eine Datei kam nicht unentziffert durch.")
        }
    }

    @Test
    func aFolderIsRecognisedAsSuch() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appending(path: "notiz.txt")
        try Data("Hallo".utf8).write(to: file)

        #expect(FileDropReader.isDirectory(folder))
        #expect(!FileDropReader.isDirectory(file))
        #expect(!FileDropReader.isDirectory(folder.appending(path: "gibt-es-nicht")))
    }
}
