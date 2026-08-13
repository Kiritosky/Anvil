import AnvilKit
import Foundation

/// Packt und entpackt Zip-Archive.
///
/// Zwei Werkzeuge aus dem System statt einer Bibliothek: `unzip` liest das
/// Verzeichnis, `ditto` packt und entpackt. `ditto` ist dabei nicht Geschmack,
/// sondern der Unterschied zwischen einem Archiv, das auf einem Mac ankommt,
/// und einem, bei dem Ressourcenzweige, Rechte und Symlinks unterwegs
/// verloren gehen — es ist dasselbe Werkzeug, das der Finder benutzt.
public struct ArchiveTool: Sendable {
    private let runner = ProcessRunner()

    public init() {}

    /// Endungen, die Anvil als Archiv liest.
    ///
    /// Nur Zip: `ditto -k` kann nichts anderes, und ein Werkzeug, das ein
    /// `.tar.gz` annimmt und dann scheitert, hat einen Schritt zu spät nein
    /// gesagt.
    public static let archiveExtensions: Set<String> = ["zip", "ipa", "jar", "zipx"]

    public static func isArchive(_ url: URL) -> Bool {
        archiveExtensions.contains(url.pathExtension.lowercased())
    }

    /// Ob auf diesem Mac die beiden Werkzeuge liegen.
    public func isAvailable() -> Bool {
        let manager = FileManager.default
        return manager.isExecutableFile(atPath: Self.unzip)
            && manager.isExecutableFile(atPath: Self.ditto)
    }

    private static let unzip = "/usr/bin/unzip"
    private static let ditto = "/usr/bin/ditto"

    // MARK: - Hineinsehen

    /// Was im Archiv liegt, ohne etwas anzufassen.
    public func list(_ archive: URL) async throws -> ArchiveListing {
        // `-l` listet, `-qq` lässt Kopf- und Fußzeile weg. Beides ist seit
        // Info-ZIP 5 unverändert; nichts davon schreibt.
        let result = try await runner.run(
            Self.unzip,
            arguments: ["-l", "-qq", archive.path],
            timeout: 60
        )
        return ArchiveListing.read(try result.outputOrThrow())
    }

    // MARK: - Auspacken

    /// Packt ein Archiv in einen eigenen Ordner unterhalb von `folder`.
    ///
    /// Immer in einen eigenen Ordner, auch wenn im Archiv schon einer liegt:
    /// Der Fall, in dem ein Archiv seinen Inhalt über den Zielordner
    /// verstreut, kostet danach eine halbe Stunde Aufräumen, der doppelte
    /// Ordner einen Doppelklick.
    @discardableResult
    public func unpack(_ archive: URL, into folder: URL) async throws -> URL {
        let name = archive.deletingPathExtension().lastPathComponent
        let destination = Self.uniqueFolder(in: folder, named: name)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            _ = try await runner.run(
                Self.ditto,
                arguments: ["-x", "-k", archive.path, destination.path],
                timeout: 900
            ).outputOrThrow()
        } catch {
            // Ein leerer Ordner, der nach einem Fehlschlag stehen bleibt, ist
            // die Sorte Müll, die man erst Wochen später wiederfindet.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        return destination
    }

    // MARK: - Einpacken

    /// Packt eine Datei oder einen Ordner in ein Archiv daneben.
    ///
    /// `--keepParent` behält den Namen des Ordners im Archiv. Ohne das packt
    /// `ditto` den Inhalt ohne Hülle, und das entpackte Archiv verteilt sich
    /// beim Empfänger über dessen Download-Ordner.
    @discardableResult
    public func pack(_ source: URL, into folder: URL) async throws -> URL {
        let destination = ExportFile.uniqueURL(
            in: folder,
            named: source.deletingPathExtension().lastPathComponent,
            extension: "zip"
        )

        _ = try await runner.run(
            Self.ditto,
            arguments: [
                "-c", "-k", "--sequesterRsrc", "--keepParent",
                source.path, destination.path
            ],
            timeout: 900
        ).outputOrThrow()

        return destination
    }

    // MARK: - Ordnernamen

    /// Ein Ordnername, den es noch nicht gibt — durchnummeriert wie im Finder.
    static func uniqueFolder(in directory: URL, named name: String) -> URL {
        let base = ExportFile.sanitize(name)
        let manager = FileManager.default
        let candidate = directory.appending(path: base)
        guard manager.fileExists(atPath: candidate.path(percentEncoded: false)) else {
            return candidate
        }

        for number in 2...999 {
            let next = directory.appending(path: "\(base) \(number)")
            if !manager.fileExists(atPath: next.path(percentEncoded: false)) { return next }
        }

        return directory.appending(path: "\(base) \(Int(Date().timeIntervalSince1970))")
    }
}
