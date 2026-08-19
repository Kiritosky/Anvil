import AnvilKit
import Foundation

/// Ein Eintrag in einem Archiv.
public struct ArchiveEntry: Sendable, Hashable, Identifiable {
    /// Der Pfad, so wie er im Archiv steht — mit Schrägstrichen, ohne Anfang.
    public let path: String
    public let size: Int
    /// Datum und Uhrzeit, so wie `unzip` sie geschrieben hat.
    public let dateText: String

    public init(path: String, size: Int, dateText: String = "") {
        self.path = path
        self.size = size
        self.dateText = dateText
    }

    public var id: String { path }

    /// Ordner erkennt man am Schrägstrich am Ende — so schreibt es das
    /// Zip-Format selbst.
    public var isDirectory: Bool { path.hasSuffix("/") }

    public var components: [String] {
        path.components(separatedBy: "/").filter { !$0.isEmpty }
    }

    public var name: String { components.last ?? path }

    /// Der oberste Ordner, in dem der Eintrag liegt — oder er selbst, wenn er
    /// ganz oben liegt.
    public var root: String { components.first ?? path }

    public var depth: Int { max(components.count - 1, 0) }

    public var fileExtension: String {
        let last = name
        guard let dot = last.lastIndex(of: "."), dot != last.startIndex else { return "" }
        return String(last[last.index(after: dot)...]).lowercased()
    }

    /// Warum ein Eintrag beim Auspacken gefährlich wäre.
    public enum Risk: String, Sendable, Hashable, CaseIterable {
        /// Ein absoluter Pfad schreibt dorthin, wo er will.
        case absolute
        /// `../` führt aus dem Zielordner heraus.
        case escapes

        public var title: String {
            switch self {
            case .absolute: localized("Absoluter Pfad")
            case .escapes: localized("Führt aus dem Ordner heraus")
            }
        }
    }

    /// Ob dieser Eintrag beim Auspacken irgendwo landen würde, wo er nicht
    /// hingehört.
    public var risk: Risk? {
        if path.hasPrefix("/") { return .absolute }
        if path.count > 2, path.dropFirst().hasPrefix(":\\") { return .absolute }
        if path.components(separatedBy: "/").contains("..") { return .escapes }
        return nil
    }
}

/// Was in einem Archiv liegt, ohne es auszupacken.
public struct ArchiveListing: Sendable, Hashable {
    public let entries: [ArchiveEntry]

    public init(_ entries: [ArchiveEntry]) {
        self.entries = entries
    }

    public static let empty = ArchiveListing([])

    public var isEmpty: Bool { entries.isEmpty }

    // MARK: - Lesen

    /// Zerlegt die Ausgabe von `unzip -l`.
    public static func read(_ text: String) -> ArchiveListing {
        var entries: [ArchiveEntry] = []
        for line in TextLines.split(text, keepingEmpty: false) {
            guard let entry = readEntry(line) else { continue }
            entries.append(entry)
        }
        return ArchiveListing(entries)
    }

    static func readEntry(_ line: String) -> ArchiveEntry? {
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4 else { return nil }
        guard let size = Int(parts[0]) else { return nil }
        guard parts[2].contains(":") else { return nil }

        let path = String(parts[3]).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }

        return ArchiveEntry(
            path: path,
            size: size,
            dateText: "\(parts[1]) \(parts[2])"
        )
    }

    // MARK: - Zahlen

    public var files: [ArchiveEntry] { entries.filter { !$0.isDirectory } }
    public var folders: [ArchiveEntry] { entries.filter(\.isDirectory) }
    public var totalBytes: Int { entries.reduce(0) { $0 + $1.size } }

    /// Die größten Dateien zuerst — meistens die Antwort auf die Frage,
    /// warum das Archiv so groß ist.
    public var largest: [ArchiveEntry] {
        files.sorted { $0.size > $1.size }
    }

    /// Die obersten Namen im Archiv.
    public var roots: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in entries where seen.insert(entry.root).inserted {
            result.append(entry.root)
        }
        return result.sorted()
    }

    /// Ob das Archiv beim Auspacken alles in den Zielordner schüttet.
    public var scatters: Bool { roots.count > 1 }

    public var risky: [ArchiveEntry] { entries.filter { $0.risk != nil } }

    /// Wie oft welche Endung vorkommt, häufigste zuerst.
    public var kinds: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in files {
            let key = entry.fileExtension.isEmpty ? localized("ohne Endung") : entry.fileExtension
            counts[key, default: 0] += 1
        }
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    // MARK: - Ausgeben

    public static let reportColumns = [
        localized("Datei"),
        localized("Größe"),
        localized("Geändert"),
        localized("Hinweis")
    ]

    public func rows() -> [[String]] {
        entries.map { entry in
            [
                entry.path,
                entry.isDirectory ? "—" : StoredData.size(entry.size),
                entry.dateText.isEmpty ? "—" : entry.dateText,
                entry.risk?.title ?? (entry.isDirectory ? localized("Ordner") : "—")
            ]
        }
    }

    /// Der Inhalt als Text — das, was man in eine Nachricht klebt, wenn
    /// jemand fragt, was in dem Archiv drin ist.
    public var report: String {
        let header = Self.reportColumns.joined(separator: "\t")
        return ([header] + rows().map { $0.joined(separator: "\t") }).joined(separator: "\n")
    }
}
