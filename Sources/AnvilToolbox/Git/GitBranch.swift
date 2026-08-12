import AnvilKit
import Foundation

/// Ein lokaler Zweig, so wie `git for-each-ref` ihn beschreibt.
///
/// Der Anlass: In jedem Repository, das länger als ein halbes Jahr lebt, liegen
/// Zweige, deren Arbeit längst in `main` steckt und deren Gegenstück auf dem
/// Server nicht mehr existiert. Sie stehen niemandem im Weg und gehen deshalb
/// nie weg. Wer sie sehen will, muss dafür drei Befehle tippen und deren
/// Ausgaben im Kopf zusammenführen — das ist der Grund, warum es niemand tut.
public struct GitBranch: Sendable, Hashable, Identifiable {
    public let name: String
    /// Wann zuletzt etwas darauf passiert ist.
    public let lastCommit: Date?
    /// Das Gegenstück auf dem Server, sofern eines eingetragen ist.
    public let upstream: String?
    public let ahead: Int
    public let behind: Int
    /// Das Gegenstück ist eingetragen, aber auf dem Server nicht mehr da.
    public let isGone: Bool
    /// Der Zweig, auf dem gerade gearbeitet wird.
    public let isCurrent: Bool

    public var id: String { name }

    public init(
        name: String,
        lastCommit: Date? = nil,
        upstream: String? = nil,
        ahead: Int = 0,
        behind: Int = 0,
        isGone: Bool = false,
        isCurrent: Bool = false
    ) {
        self.name = name
        self.lastCommit = lastCommit
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.isGone = isGone
        self.isCurrent = isCurrent
    }

    /// Wie viele Tage seit dem letzten Commit vergangen sind.
    public func age(now: Date = Date()) -> Int? {
        guard let lastCommit else { return nil }
        return Calendar.current.dateComponents([.day], from: lastCommit, to: now).day
    }

    /// Ob der Zweig ein Kandidat zum Aufräumen ist.
    ///
    /// Zwei Bedingungen, und beide müssen erfüllt sein: Das Gegenstück auf dem
    /// Server ist weg *und* lokal liegt nichts, was nicht auch dort war. Ein
    /// Zweig mit eigenen Commits wird nie vorgeschlagen — der Vorschlag wäre
    /// dann eine Aufforderung, Arbeit wegzuwerfen.
    public var isStale: Bool { isGone && ahead == 0 && !isCurrent }

    // MARK: - Lesen

    /// Das Format, mit dem die Liste geholt wird.
    ///
    /// Tabulatorgetrennt, weil in einem Zweignamen alles vorkommen darf außer
    /// Leerzeichen und Steuerzeichen — ein Tabulator ist also das einzige
    /// Trennzeichen, das nicht im Namen stecken kann.
    public static let refFormat =
        "%(refname:short)%09%(committerdate:iso8601-strict)%09%(upstream:short)%09%(upstream:track)%09%(HEAD)"

    /// Zerlegt die Ausgabe von `git for-each-ref` mit ``refFormat``.
    public static func list(_ text: String) -> [GitBranch] {
        TextLines.split(text, keepingEmpty: false).compactMap(read(_:))
    }

    static func read(_ line: String) -> GitBranch? {
        let fields = line.components(separatedBy: "\t")
        guard fields.count >= 5, !fields[0].isEmpty else { return nil }

        let track = fields[3]
        let upstream = fields[2].isEmpty ? nil : fields[2]

        return GitBranch(
            name: fields[0],
            lastCommit: isoDate(fields[1]),
            upstream: upstream,
            ahead: number(after: "ahead", in: track),
            behind: number(after: "behind", in: track),
            isGone: track.contains("gone"),
            // `%(HEAD)` ist „*" für den aktuellen Zweig und sonst ein
            // Leerzeichen.
            isCurrent: fields[4].trimmingCharacters(in: .whitespaces) == "*"
        )
    }

    /// `iso8601-strict` liefert genau das, was `ISO8601DateFormatter` erwartet.
    private static func isoDate(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        return isoFormatter.date(from: text)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func number(after word: String, in text: String) -> Int {
        guard let range = text.range(of: word + " ") else { return 0 }
        let digits = text[range.upperBound...].prefix { $0.isNumber }
        return Int(digits) ?? 0
    }
}
