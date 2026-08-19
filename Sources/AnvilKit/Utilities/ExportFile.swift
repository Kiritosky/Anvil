import Foundation

/// Dateien, die es nur gibt, weil etwas den Rechner verlässt.
public enum ExportFile {
    /// Aus einem beliebigen Text ein Dateiname, den das Dateisystem annimmt.
    public static func sanitize(_ name: String, fallback: String = "Anvil") -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)

        let collapsed = name
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        var trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if trimmed.count > 80 {
            trimmed = String(trimmed.prefix(80)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Ein Pfad in `directory`, den es noch nicht gibt.
    public static func uniqueURL(
        in directory: URL,
        named name: String,
        extension pathExtension: String
    ) -> URL {
        let base = sanitize(name)
        let candidate = directory.appending(path: "\(base).\(pathExtension)")
        guard FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) else {
            return candidate
        }

        for number in 2...999 {
            let next = directory.appending(path: "\(base) \(number).\(pathExtension)")
            if !FileManager.default.fileExists(atPath: next.path(percentEncoded: false)) {
                return next
            }
        }

        let stamp = Int(Date().timeIntervalSince1970)
        return directory.appending(path: "\(base) \(stamp).\(pathExtension)")
    }

    /// Dasselbe für einen Ordner, der angelegt werden soll.
    public static func uniqueFolderURL(in directory: URL, named name: String) -> URL {
        let base = sanitize(name)
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

    /// Legt eine Datei zum Herausziehen an und gibt zurück, wo sie liegt.
    public static func temporary(
        named name: String,
        extension pathExtension: String,
        contents: Data
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Anvil-Export/\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appending(path: "\(sanitize(name)).\(pathExtension)")
            try contents.write(to: url)
            return url
        } catch {
            throw AnvilError.storage(
                localized("Die Datei zum Herausziehen ließ sich nicht anlegen: \(error.localizedDescription)")
            )
        }
    }
}
