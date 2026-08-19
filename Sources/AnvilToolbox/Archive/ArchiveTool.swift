import AnvilKit
import Foundation

/// Packt und entpackt Zip-Archive.
public struct ArchiveTool: Sendable {
    private let runner = ProcessRunner()

    public init() {}

    /// Endungen, die Anvil als Archiv liest.
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
        let result = try await runner.run(
            Self.unzip,
            arguments: ["-l", "-qq", archive.path],
            timeout: 60
        )
        return ArchiveListing.read(try result.outputOrThrow())
    }

    // MARK: - Auspacken

    /// Packt ein Archiv in einen eigenen Ordner unterhalb von `folder`.
    @discardableResult
    public func unpack(_ archive: URL, into folder: URL) async throws -> URL {
        let name = archive.deletingPathExtension().lastPathComponent
        let destination = ExportFile.uniqueFolderURL(in: folder, named: name)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            _ = try await runner.run(
                Self.ditto,
                arguments: ["-x", "-k", archive.path, destination.path],
                timeout: 900
            ).outputOrThrow()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        return destination
    }

    // MARK: - Einpacken

    /// Packt eine Datei oder einen Ordner in ein Archiv daneben.
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

}
