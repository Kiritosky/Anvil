import AnvilKit
import Foundation

/// Suchen und Ersetzen in vielen Dateien — erst als Plan, dann als Tat.
public struct ReplacePlan: Sendable {
    // MARK: - Regeln

    public struct Rules: Sendable, Hashable {
        /// Was gesucht wird. Leer heißt: nichts tun.
        public var search = ""
        public var replacement = ""
        public var isRegularExpression = false
        public var ignoresCase = false
        /// Nur ganze Wörter — „Datei" trifft dann nicht in „Dateiname".
        public var wholeWords = false

        public init() {}

        public var isEmpty: Bool { search.isEmpty }
    }

    // MARK: - Was dabei herauskommt

    /// Eine Zeile, die sich ändert.
    public struct Hit: Sendable, Hashable, Identifiable {
        public let id: Int
        /// Die Zeilennummer, ab eins.
        public let line: Int
        public let before: String
        public let after: String

        public init(id: Int, line: Int, before: String, after: String) {
            self.id = id
            self.line = line
            self.before = before
            self.after = after
        }
    }

    /// Warum eine Datei nicht angefasst wird.
    public enum Skip: String, Sendable, Hashable {
        /// Nullbytes darin — das ist kein Text, und ein Ersetzen darin
        /// zerstört die Datei.
        case binary
        /// Größer als die Grenze. Eine Datei, die nicht in den Speicher passt,
        /// lässt sich auch nicht vorher anzeigen.
        case tooLarge
        /// Nicht als UTF-8 lesbar oder gar nicht zu öffnen.
        case unreadable
        /// Alles in Ordnung, nur kein Treffer.
        case noMatch

        public var title: String {
            switch self {
            case .binary: localized("keine Textdatei")
            case .tooLarge: localized("zu groß")
            case .unreadable: localized("nicht lesbar")
            case .noMatch: localized("kein Treffer")
            }
        }

        /// Ob es sich lohnt, davon zu erzählen.
        public var isWorthMentioning: Bool { self != .noMatch }
    }

    public struct Entry: Sendable, Identifiable {
        public let url: URL
        public let hits: [Hit]
        public let skip: Skip?
        /// Der neue Inhalt der Datei. Nur vorhanden, wenn etwas zu tun ist.
        let updated: String?

        public var id: String { url.path }
        public var name: String { url.lastPathComponent }
        public var willChange: Bool { skip == nil && !hits.isEmpty }

        public init(url: URL, hits: [Hit], skip: Skip?, updated: String?) {
            self.url = url
            self.hits = hits
            self.skip = skip
            self.updated = updated
        }
    }

    public let entries: [Entry]
    public let rules: Rules

    public var changing: [Entry] { entries.filter(\.willChange) }
    public var skipped: [Entry] { entries.filter { $0.skip?.isWorthMentioning == true } }
    public var hitCount: Int { entries.reduce(0) { $0 + $1.hits.count } }
    public var isReady: Bool { !rules.isEmpty && !changing.isEmpty }

    public static let empty = ReplacePlan(entries: [], rules: Rules())

    init(entries: [Entry], rules: Rules) {
        self.entries = entries
        self.rules = rules
    }

    // MARK: - Planen

    /// Wie groß eine Datei höchstens sein darf.
    public static let maxBytes = 4 * 1024 * 1024

    /// Liest die Dateien und baut den Plan.
    public init(files: [URL], rules: Rules, maxBytes: Int = ReplacePlan.maxBytes) {
        guard !rules.isEmpty else {
            self.init(entries: [], rules: rules)
            return
        }

        let entries = files.map { url -> Entry in
            let sizes = try? FileManager.default.attributesOfItem(atPath: url.path)
            if let size = sizes?[.size] as? Int, size > maxBytes {
                return Entry(url: url, hits: [], skip: .tooLarge, updated: nil)
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                return Entry(url: url, hits: [], skip: .unreadable, updated: nil)
            }
            return Self.entry(for: url, text: text, rules: rules)
        }
        self.init(entries: entries, rules: rules)
    }

    /// Der Teil ohne Dateisystem — und damit der, der sich prüfen lässt.
    static func entry(for url: URL, text: String, rules: Rules) -> Entry {
        guard !text.contains("\0") else {
            return Entry(url: url, hits: [], skip: .binary, updated: nil)
        }
        let result = apply(rules, to: text)
        guard !result.hits.isEmpty else {
            return Entry(url: url, hits: [], skip: .noMatch, updated: nil)
        }
        return Entry(url: url, hits: result.hits, skip: nil, updated: result.text)
    }

    // MARK: - Ersetzen

    /// Wendet die Regeln auf einen Text an.
    static func apply(_ rules: Rules, to text: String) -> (text: String, hits: [Hit]) {
        guard !rules.isEmpty else { return (text, []) }

        let usesCRLF = text.contains("\r\n")
        let lines = TextLines.normalized(text).components(separatedBy: "\n")

        var hits: [Hit] = []
        var replaced: [String] = []
        replaced.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() {
            let after = replace(in: line, rules: rules)
            if after != line {
                hits.append(Hit(id: hits.count, line: index + 1, before: line, after: after))
            }
            replaced.append(after)
        }

        guard !hits.isEmpty else { return (text, []) }
        let joined = replaced.joined(separator: "\n")
        return (usesCRLF ? joined.replacingOccurrences(of: "\n", with: "\r\n") : joined, hits)
    }

    /// Eine Zeile ersetzen — wörtlich oder als regulärer Ausdruck.
    static func replace(in line: String, rules: Rules) -> String {
        if !rules.isRegularExpression && !rules.wholeWords {
            return line.replacingOccurrences(
                of: rules.search,
                with: rules.replacement,
                options: rules.ignoresCase ? [.caseInsensitive] : []
            )
        }

        var pattern = rules.isRegularExpression
            ? rules.search
            : NSRegularExpression.escapedPattern(for: rules.search)
        if rules.wholeWords {
            pattern = "\\b(?:\(pattern))\\b"
        }
        let template = rules.isRegularExpression
            ? rules.replacement
            : NSRegularExpression.escapedTemplate(for: rules.replacement)

        var options: NSRegularExpression.Options = []
        if rules.ignoresCase { options.insert(.caseInsensitive) }
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return line
        }
        return expression.stringByReplacingMatches(
            in: line,
            range: NSRange(line.startIndex..., in: line),
            withTemplate: template
        )
    }

    // MARK: - Ausführen

    /// Was getan wurde — und wie es sich zurücknehmen ließe.
    public struct Outcome: Sendable {
        public let changedFiles: Int
        public let changedLines: Int
        /// Der alte Inhalt, Datei für Datei. Nur im Arbeitsspeicher.
        public let undo: [(url: URL, text: String)]
    }

    /// Schreibt die Änderungen.
    @discardableResult
    public func execute() throws -> Outcome {
        guard isReady else {
            throw AnvilError.invalidInput(
                localized("Es gibt nichts zu ersetzen. Erst muss ein Treffer da sein.")
            )
        }

        var undo: [(url: URL, text: String)] = []
        var changedLines = 0

        for entry in changing {
            guard let updated = entry.updated else { continue }
            let current = try String(contentsOf: entry.url, encoding: .utf8)
            guard current != updated else { continue }
            guard Self.entry(for: entry.url, text: current, rules: rules).updated == updated else {
                continue
            }

            try updated.write(to: entry.url, atomically: true, encoding: .utf8)
            undo.append((entry.url, current))
            changedLines += entry.hits.count
        }

        return Outcome(changedFiles: undo.count, changedLines: changedLines, undo: undo)
    }

    /// Schreibt zurück, was ``execute()`` hinterlassen hat.
    public static func revert(_ undo: [(url: URL, text: String)]) throws {
        for step in undo {
            try step.text.write(to: step.url, atomically: true, encoding: .utf8)
        }
    }
}
