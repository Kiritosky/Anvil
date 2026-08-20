import Foundation

/// Alle Dateien unter einem Ordner.
enum FileWalk {
    /// Was hier nie mitkommt.
    static let options: FileManager.DirectoryEnumerationOptions =
        [.skipsHiddenFiles, .skipsPackageDescendants]

    /// Jede reguläre Datei unter `folder`, samt Unterordnern.
    static func files(in folder: URL, minimumBytes: Int = 0) -> [(url: URL, size: Int)] {
        let manager = FileManager.default
        guard let walker = manager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: options
        ) else { return [] }

        var result: [(url: URL, size: Int)] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
            guard size >= minimumBytes else { continue }
            result.append((url, size))
        }
        return result
    }

    /// Nur die Pfade — für alles, was die Größe nicht braucht.
    static func urls(in folder: URL) -> [URL] {
        files(in: folder).map(\.url)
    }

    /// Was direkt in dem Ordner liegt, ohne Unterordner.
    static func shallow(_ folder: URL, includingHidden: Bool = false) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: includingHidden ? [] : [.skipsHiddenFiles]
        )) ?? []
    }

    /// Ob der Pfad auf einen Ordner zeigt.
    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Wirft Ordner weg, die schon unter einem anderen der Liste liegen —
    /// sonst zählt dieselbe Datei zweimal und gilt am Ende als ihre eigene
    /// Dublette.
    static func distinctRoots(_ folders: [URL]) -> [URL] {
        var kept: [URL] = []
        for folder in folders.map(\.standardizedFileURL) {
            guard !kept.contains(where: { contains($0, folder) }) else { continue }
            kept.removeAll { contains(folder, $0) }
            kept.append(folder)
        }
        return kept
    }

    /// Ob `other` derselbe Ordner ist oder darunter liegt.
    static func contains(_ folder: URL, _ other: URL) -> Bool {
        let base = folder.standardizedFileURL.path
        let full = other.standardizedFileURL.path
        return full == base || full.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    /// Der Pfad einer Datei relativ zu einem Ordner darüber.
    static func relativePath(of url: URL, under folder: URL) -> String {
        let base = folder.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        guard full.hasPrefix(base) else { return url.lastPathComponent }
        let cut = full.dropFirst(base.count)
        return String(cut.drop { $0 == "/" })
    }
}
