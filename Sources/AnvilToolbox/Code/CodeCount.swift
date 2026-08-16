import AnvilKit
import Foundation

/// Wie viel Code hier eigentlich liegt.
///
/// Die Frage kommt selten allein: „Wie groß ist das Projekt" heißt in
/// Wirklichkeit „woraus besteht es" — und die Antwort ist eine Verteilung,
/// keine Zahl. Zwanzigtausend Zeilen sagen wenig; zwanzigtausend Zeilen
/// Swift neben achttausend Zeilen YAML sagen viel.
public struct CodeCount: Sendable, Hashable {
    /// Was von einer Sprache im Projekt liegt.
    public struct Entry: Sendable, Hashable, Identifiable {
        public let language: String
        public let files: Int
        /// Zeilen, auf denen etwas steht, das kein Kommentar ist.
        public let code: Int
        public let comments: Int
        public let blanks: Int

        public var id: String { language }
        public var lines: Int { code + comments + blanks }

        /// Wie viel davon Kommentar ist, zwischen 0 und 1.
        public var commentShare: Double {
            let written = code + comments
            guard written > 0 else { return 0 }
            return Double(comments) / Double(written)
        }

        public init(language: String, files: Int, code: Int, comments: Int, blanks: Int) {
            self.language = language
            self.files = files
            self.code = code
            self.comments = comments
            self.blanks = blanks
        }
    }

    /// Die größten zuerst — danach fragt, wer wissen will, woraus etwas
    /// besteht.
    public let entries: [Entry]
    /// Dateien, die keiner bekannten Sprache gehören.
    public let skipped: Int

    public static let empty = CodeCount(entries: [], skipped: 0)

    public init(entries: [Entry], skipped: Int) {
        self.entries = entries
        self.skipped = skipped
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var fileCount: Int { entries.reduce(0) { $0 + $1.files } }
    public var totalCode: Int { entries.reduce(0) { $0 + $1.code } }
    public var totalComments: Int { entries.reduce(0) { $0 + $1.comments } }
    public var totalBlanks: Int { entries.reduce(0) { $0 + $1.blanks } }
    public var totalLines: Int { totalCode + totalComments + totalBlanks }

    /// Der Anteil einer Sprache am Code — nicht an allen Zeilen.
    ///
    /// Leerzeilen gehören niemandem: Ein Diagramm, in dem eine Sprache groß
    /// aussieht, weil in ihr großzügig Absätze gesetzt werden, beantwortet
    /// die Frage nicht.
    public func share(of entry: Entry) -> Double {
        guard totalCode > 0 else { return 0 }
        return Double(entry.code) / Double(totalCode)
    }

    // MARK: - Zählen

    /// Eine Datei, so wie der Zähler sie braucht.
    public struct SourceFile: Sendable {
        public let path: String
        public let text: String

        public init(path: String, text: String) {
            self.path = path
            self.text = text
        }
    }

    /// Zählt einen Stapel Dateien.
    ///
    /// Die Dateien kommen als Text herein statt als Pfade: So lässt sich das
    /// Zählen prüfen, ohne ein Projekt auf die Platte zu legen — und der
    /// Aufrufer entscheidet, was er überhaupt einliest.
    public static func count(_ files: [SourceFile]) -> CodeCount {
        var totals: [String: Entry] = [:]
        var skipped = 0

        for file in files {
            guard !CodeLanguage.isIgnored(file.path),
                  let language = CodeLanguage.of(path: file.path)
            else {
                skipped += 1
                continue
            }

            let counted = count(file.text, in: language)
            let previous = totals[language.name]
            totals[language.name] = Entry(
                language: language.name,
                files: (previous?.files ?? 0) + 1,
                code: (previous?.code ?? 0) + counted.code,
                comments: (previous?.comments ?? 0) + counted.comments,
                blanks: (previous?.blanks ?? 0) + counted.blanks
            )
        }

        let entries = totals.values.sorted {
            $0.code == $1.code ? $0.language < $1.language : $0.code > $1.code
        }
        return CodeCount(entries: entries, skipped: skipped)
    }

    /// Zerlegt eine Datei in Code, Kommentar und Leerzeile.
    ///
    /// Eine Faustregel und kein Übersetzer: Ein `//` in einer Zeichenkette
    /// zählt hier als Kommentar. Das falsch zu bekommen kostet in einem
    /// Projekt ein paar Zeilen von zwanzigtausend — es richtig zu bekommen
    /// kostet einen Übersetzer je Sprache.
    static func count(_ text: String, in language: CodeLanguage) -> (
        code: Int, comments: Int, blanks: Int
    ) {
        guard !text.isEmpty else { return (0, 0, 0) }

        var code = 0
        var comments = 0
        var blanks = 0
        var isInBlock = false

        for line in TextLines.split(text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isInBlock {
                comments += 1
                if let close = language.blockClose, trimmed.contains(close) { isInBlock = false }
                continue
            }

            if trimmed.isEmpty {
                blanks += 1
                continue
            }

            if let open = language.blockOpen, trimmed.hasPrefix(open) {
                comments += 1
                // Ein Block, der in derselben Zeile wieder zugeht, macht die
                // nächste nicht zum Kommentar.
                let rest = trimmed.dropFirst(open.count)
                if let close = language.blockClose, !rest.contains(close) { isInBlock = true }
                continue
            }

            if language.lineComments.contains(where: { trimmed.hasPrefix($0) }) {
                comments += 1
                continue
            }

            code += 1
        }

        return (code, comments, blanks)
    }

    // MARK: - Ausgeben

    public static let reportColumns = [
        localized("Sprache"),
        localized("Dateien"),
        localized("Code"),
        localized("Kommentar"),
        localized("Leer"),
        localized("Anteil")
    ]

    public func rows() -> [[String]] {
        entries.map { entry in
            [
                entry.language,
                "\(entry.files)",
                "\(entry.code)",
                "\(entry.comments)",
                "\(entry.blanks)",
                Self.percent(share(of: entry))
            ]
        }
    }

    /// Ein Anteil als Prozentzahl.
    public static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded())) %"
    }

    /// Die Zählung als Text — das, was in eine Notiz oder ein Ticket geht.
    public var report: String {
        let header = Self.reportColumns.joined(separator: "\t")
        let body = rows().map { $0.joined(separator: "\t") }
        let sum = [
            localized("Gesamt"),
            "\(fileCount)",
            "\(totalCode)",
            "\(totalComments)",
            "\(totalBlanks)",
            ""
        ].joined(separator: "\t")
        return ([header] + body + [sum]).joined(separator: "\n")
    }
}
