import AnvilKit
import Foundation

/// Findet Git-Repositories unter einem Ordner.
public enum RepositoryScan {
    /// Wie tief gesucht wird, wenn nichts anderes gesagt ist.
    ///
    /// Drei Ebenen decken die übliche Ablage ab — `~/Code/Firma/projekt` —
    /// und halten die Suche von `node_modules` fern, wo sie sonst Minuten
    /// verbringt, um nichts zu finden.
    public static let defaultDepth = 3

    /// Ordner, in denen niemand ein eigenes Repository sucht.
    ///
    /// Alle vier enthalten regelmäßig fremde Repositories — Abhängigkeiten,
    /// Baureste, Zwischenstände. Wer sie mitzählt, bekommt eine Liste, in der
    /// die eigene Arbeit untergeht.
    static let ignoredFolders: Set<String> = [
        "node_modules", ".build", "Pods", "vendor", "DerivedData", ".swiftpm",
        "Carthage", "target", "venv", ".venv", "__pycache__"
    ]

    /// Alle Repositories unter `root`, `root` selbst eingeschlossen.
    ///
    /// Ein gefundenes Repository wird nicht weiter durchsucht: Ein Untermodul
    /// gehört dem übergeordneten Repository und ist keine eigene Baustelle.
    public static func repositories(under root: URL, maxDepth: Int = defaultDepth) -> [URL] {
        var found: [URL] = []
        collect(root, depth: 0, maxDepth: maxDepth, into: &found)
        return found.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func collect(_ folder: URL, depth: Int, maxDepth: Int, into found: inout [URL]) {
        guard depth <= maxDepth else { return }
        guard isDirectory(folder) else { return }

        if isRepository(folder) {
            found.append(folder)
            return
        }

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []

        for child in contents where !ignoredFolders.contains(child.lastPathComponent) {
            collect(child, depth: depth + 1, maxDepth: maxDepth, into: &found)
        }
    }

    /// Ob in dem Ordner ein Repository liegt.
    ///
    /// `.git` ist meist ein Ordner, bei einem Arbeitsbaum (`git worktree`)
    /// aber eine Datei — beides zählt.
    public static func isRepository(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: ".git").path)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
