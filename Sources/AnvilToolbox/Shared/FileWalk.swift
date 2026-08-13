import Foundation

/// Alle Dateien unter einem Ordner.
///
/// Drei Werkzeuge liefen vorher jedes mit seiner eigenen Fassung durch das
/// Dateisystem, und jede hatte eine andere Meinung dazu, was ein Ordner
/// eigentlich enthält. Das ist die Sorte Doppelung, die harmlos bleibt, bis
/// eine Fassung etwas lernt, das die anderen nicht wissen — etwa, dass ein
/// Paket im Finder wie eine Datei aussieht und ein Ordner mit tausend Dateien
/// darin ist.
enum FileWalk {
    /// Was hier nie mitkommt.
    ///
    /// Versteckte Dateien und Pakete: Wer einen Projektordner hineinzieht,
    /// meint seine Dateien und nicht die Innereien von `.git`, und wer eine
    /// App im Ordner liegen hat, meint sie als ein Ding.
    static let options: FileManager.DirectoryEnumerationOptions =
        [.skipsHiddenFiles, .skipsPackageDescendants]

    /// Jede reguläre Datei unter `folder`, samt Unterordnern.
    ///
    /// - Parameter minimumBytes: Kleineres wird übergangen.
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
    ///
    /// - Parameter includingHidden: Versteckte Dateien kommen mit. Für die
    ///   allermeisten Werkzeuge wäre das falsch — für eines, das `.env`
    ///   sucht, ist es die ganze Aufgabe.
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

    /// Der Pfad einer Datei relativ zu einem Ordner darüber.
    ///
    /// Das ist der Schlüssel, an dem sich zwei Ordner vergleichen lassen:
    /// `bilder/2026/anna.jpg` heißt in beiden dasselbe, auch wenn die Ordner
    /// darüber verschieden heißen.
    static func relativePath(of url: URL, under folder: URL) -> String {
        let base = folder.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        guard full.hasPrefix(base) else { return url.lastPathComponent }
        let cut = full.dropFirst(base.count)
        return String(cut.drop { $0 == "/" })
    }
}
