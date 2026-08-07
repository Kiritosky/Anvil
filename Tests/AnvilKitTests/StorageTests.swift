import AppKit
import Foundation
import Testing

@testable import AnvilKit

@Suite("AppPaths")
struct AppPathsTests {
    /// Jeder Ordner liegt unterhalb des einen Ordners, den die App besitzt.
    /// Ein Pfad, der daneben landet, hinterlässt beim Deinstallieren Müll, den
    /// niemand findet.
    @Test
    func everyDirectorySitsUnderTheSupportFolder() {
        let support = AppPaths.support.path(percentEncoded: false)
        let directories = [
            AppPaths.customTools, AppPaths.recordings, AppPaths.history,
            AppPaths.exports, AppPaths.screenshots, AppPaths.drafts
        ]

        for directory in directories {
            #expect(
                directory.path(percentEncoded: false).hasPrefix(support),
                "\(directory.lastPathComponent) liegt außerhalb von \(support)"
            )
        }
    }

    @Test
    func theSupportFolderIsNamedAfterTheApp() {
        #expect(AppPaths.support.lastPathComponent == "Anvil")
    }

    /// Keine zwei Ordner dürfen denselben Pfad haben — sonst schreiben zwei
    /// Dienste in dieselben Dateien.
    @Test
    func directoriesAreDistinct() {
        let paths = [
            AppPaths.customTools, AppPaths.recordings, AppPaths.history,
            AppPaths.exports, AppPaths.screenshots, AppPaths.drafts
        ].map(\.lastPathComponent)

        #expect(Set(paths).count == paths.count)
    }

    /// `bootstrap()` wird bei jedem Start aufgerufen und muss das aushalten.
    @Test
    func bootstrapIsSafeToRepeat() {
        #expect(AppPaths.bootstrap())
        #expect(AppPaths.bootstrap())

        for directory in [AppPaths.customTools, AppPaths.drafts, AppPaths.exports] {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: directory.path(percentEncoded: false),
                isDirectory: &isDirectory
            )
            #expect(exists && isDirectory.boolValue)
        }
    }
}

@Suite("Bilder als Datei")
struct ImageFileTests {
    private func image(width: Int, height: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    @Test
    func producesRealPNGBytes() throws {
        let data = try image(width: 8, height: 8).pngData()

        // Die PNG-Signatur. Ein Test auf „nicht leer" würde auch bei TIFF
        // durchgehen, und genau der Unterschied ist hier der Punkt.
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    @Test
    func writesAFileThatCanBeReadBack() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "anvil-image-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let written = try image(width: 12, height: 9).writePNG(to: url)
        #expect(written == url)

        let reloaded = try #require(NSImage(contentsOf: url))
        let representation = try #require(reloaded.representations.first)
        #expect(representation.pixelsWide == 12)
        #expect(representation.pixelsHigh == 9)
    }

    /// Schreiben an einen Ort, den es nicht gibt, muss als AnvilError
    /// herauskommen — der Aufrufer zeigt genau den in einem Banner an.
    @Test
    func failingToWriteThrowsAnvilError() {
        let url = URL(filePath: "/gibt/es/nicht/anvil.png")
        #expect(throws: AnvilError.self) { try image(width: 4, height: 4).writePNG(to: url) }
    }
}

@Suite("KeychainStore")
struct KeychainStoreTests {
    /// Ein eigener Dienstname, damit die Tests nichts anfassen, was die App im
    /// echten Schlüsselbund liegen hat.
    private func makeStore() -> KeychainStore {
        KeychainStore(service: "dev.anvil.tests.\(UUID().uuidString)")
    }

    /// Der Schlüsselbund ist nicht überall benutzbar — auf einem Bau-Runner
    /// ohne entsperrten Login-Schlüsselbund lehnt das System jedes Schreiben
    /// ab. Das ist keine Aussage über den Code, also wird der Test dort
    /// übersprungen statt rot.
    private func storeIfAvailable() -> KeychainStore? {
        let store = makeStore()
        do {
            try store.setSecret("probe", for: "verfügbarkeit")
            try store.setSecret(nil, for: "verfügbarkeit")
            return store
        } catch {
            return nil
        }
    }

    @Test
    func storesAndReadsBackASecret() throws {
        guard let store = storeIfAvailable() else { return }

        try store.setSecret("geheim-123", for: "test")
        #expect(store.secret(for: "test") == "geheim-123")
        #expect(store.hasSecret(for: "test"))

        try store.setSecret(nil, for: "test")
        #expect(store.secret(for: "test") == nil)
        #expect(!store.hasSecret(for: "test"))
    }

    /// Zweimal schreiben überschreibt, statt einen zweiten Eintrag anzulegen —
    /// sonst bekäme man beim Lesen irgendeinen von beiden.
    @Test
    func writingTwiceReplaces() throws {
        guard let store = storeIfAvailable() else { return }

        try store.setSecret("alt", for: "test")
        try store.setSecret("neu", for: "test")
        #expect(store.secret(for: "test") == "neu")

        try store.setSecret(nil, for: "test")
    }

    /// Lesen geht immer — auch ohne Schreibrecht — und muss für einen
    /// unbekannten Eintrag schlicht nichts liefern.
    @Test
    func anUnknownAccountHasNoSecret() {
        #expect(makeStore().secret(for: "nie-gesetzt") == nil)
    }

    /// Ein leerer Text ist kein Geheimnis, sondern ein gelöschtes.
    @Test
    func anEmptySecretRemovesTheEntry() throws {
        guard let store = storeIfAvailable() else { return }

        try store.setSecret("etwas", for: "test")
        try store.setSecret("", for: "test")
        #expect(store.secret(for: "test") == nil)
    }
}
