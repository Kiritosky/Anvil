import AnvilKit
import Foundation

/// Viele QR-Codes auf einmal.
///
/// Der Anlass ist immer eine Liste: Geräte, die ein Etikett bekommen, Links
/// für eine Schulung, ein Gäste-WLAN für jeden Raum. Einzeln ist das
/// zwanzigmal derselbe Handgriff, und beim zwölften Mal vertippt man sich im
/// Dateinamen.
///
/// Wie überall im Stapel gilt: erst der Plan, dann die Tat. Der Plan zeigt zu
/// jeder Zeile den Dateinamen, den sie bekäme — auch die Nummer, die zwei
/// gleiche Zeilen auseinanderhält. Ohne die wäre nach dem Schreiben eine der
/// beiden weg.
public struct QRCodeBatch: Sendable {
    /// Was einem Eintrag im Weg steht.
    public enum Problem: String, Sendable, Hashable {
        /// Nichts drin, was sich verschlüsseln ließe.
        case empty
        /// Mehr, als in einen QR-Code passt.
        case tooLong

        public var title: String {
            switch self {
            case .empty: localized("leer")
            case .tooLong: localized("zu lang")
            }
        }
    }

    public struct Entry: Sendable, Identifiable, Hashable {
        public let id: Int
        /// Was im Code steht.
        public let text: String
        /// Wie die Datei heißen soll, ohne Endung.
        public let name: String
        public let problem: Problem?

        public var willWrite: Bool { problem == nil }

        public init(id: Int, text: String, name: String, problem: Problem?) {
            self.id = id
            self.text = text
            self.name = name
            self.problem = problem
        }
    }

    public let entries: [Entry]

    public var writing: [Entry] { entries.filter(\.willWrite) }
    public var blocked: [Entry] { entries.filter { $0.problem != nil } }
    public var isEmpty: Bool { entries.isEmpty }
    public var isReady: Bool { !writing.isEmpty }

    public static let empty = QRCodeBatch(entries: [])

    init(entries: [Entry]) {
        self.entries = entries
    }

    // MARK: - Planen

    /// Was ein QR-Code höchstens fassen kann.
    ///
    /// Die Obergrenze liegt bei Version 40 und niedrigster Fehlerkorrektur
    /// bei 2 953 Byte. Wer daran kratzt, bekommt ein Muster, das kein Scanner
    /// mehr sicher liest — die Grenze hier ist deshalb die harte, und die
    /// Warnung davor gehört ins Werkzeug.
    public static let maxBytes = 2_953

    /// Liest eine Zeile je Code.
    ///
    /// Steht ein Tabulator in der Zeile, ist davor der Name und dahinter der
    /// Inhalt — genau die Form, die aus einer Tabellenkalkulation kommt. Sonst
    /// wird der Name aus dem Inhalt gebildet.
    public init(_ text: String) {
        var entries: [Entry] = []
        // Wie oft ein Name schon vergeben wurde. Zwei gleiche Zeilen ergäben
        // sonst zweimal denselben Dateinamen, und die erste wäre weg.
        var used: [String: Int] = [:]

        for (index, line) in TextLines.split(text, keepingEmpty: false).enumerated() {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            let hasName = parts.count == 2
            let content = String(hasName ? parts[1] : parts[0])
                .trimmingCharacters(in: .whitespaces)
            let given = hasName ? String(parts[0]).trimmingCharacters(in: .whitespaces) : ""

            // Ein Dateiname wird nicht übersetzt — er muss auf jeder Platte
            // derselbe sein.
            var name = ExportFile.sanitize(
                given.isEmpty ? content : given,
                fallback: "code-\(index + 1)"
            )
            let count = (used[name] ?? 0) + 1
            used[name] = count
            // Wie im Finder: die zweite Datei heißt „Name 2".
            if count > 1 { name = "\(name) \(count)" }

            let problem: Problem?
            if content.isEmpty {
                problem = .empty
            } else if content.utf8.count > Self.maxBytes {
                problem = .tooLong
            } else {
                problem = nil
            }

            entries.append(Entry(id: index, text: content, name: name, problem: problem))
        }

        self.init(entries: entries)
    }

    // MARK: - Ausgeben

    public static let reportColumns = [
        localized("Datei"),
        localized("Inhalt"),
        localized("Hinweis")
    ]

    public func row(_ entry: Entry) -> [String] {
        [entry.name + ".png", entry.text, entry.problem?.title ?? "—"]
    }

    public var report: String {
        let header = Self.reportColumns.joined(separator: "\t")
        return ([header] + entries.map { row($0).joined(separator: "\t") })
            .joined(separator: "\n")
    }

    // MARK: - Ausführen

    public struct Outcome: Sendable {
        public let written: Int
        public let created: [URL]
    }

    /// Schreibt jeden Code als PNG in den Ordner.
    ///
    /// - Parameter make: Wie aus Text ein Bild wird. Als Parameter, damit der
    ///   Plan sich prüfen lässt, ohne dass CoreImage laufen muss.
    @discardableResult
    public func write(
        to folder: URL,
        make: (String) throws -> Data
    ) throws -> Outcome {
        guard isReady else {
            throw AnvilError.invalidInput(
                localized("Es gibt nichts zu schreiben. Erst muss eine Zeile dabei sein, aus der ein Code wird.")
            )
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var created: [URL] = []
        for entry in writing {
            // Nicht einfach `name.png`: Im Zielordner können schon Dateien
            // liegen, von denen der Plan nichts weiß. Überschrieben wird
            // keine — durchnummeriert wird wie im Finder.
            let url = ExportFile.uniqueURL(in: folder, named: entry.name, extension: "png")
            try make(entry.text).write(to: url, options: .atomic)
            created.append(url)
        }
        return Outcome(written: created.count, created: created)
    }
}
