import AnvilKit
import Foundation

/// Was `git status --porcelain --branch` über ein Repository sagt.
///
/// Warum ausgerechnet die Porzellan-Form: Sie ist die einzige Ausgabe, die
/// `git` ausdrücklich als stabil zusichert. Die menschenlesbare Fassung ändert
/// sich zwischen Versionen und ist außerdem übersetzt — wer sie zerlegt, baut
/// etwas, das auf einem Rechner mit deutschem `git` anders funktioniert als auf
/// dem eigenen.
public struct GitStatus: Sendable, Hashable {
    /// Eine geänderte Datei.
    public struct Change: Sendable, Hashable, Identifiable {
        /// Wo die Änderung steht.
        public enum Stage: String, Sendable, Hashable, CaseIterable {
            /// Vorgemerkt — beim nächsten Commit dabei.
            case staged
            /// Geändert, aber nicht vorgemerkt.
            case unstaged
            /// Kennt `git` noch gar nicht.
            case untracked
            /// Ein Merge, der noch offen ist.
            case conflicted

            public var title: String {
                switch self {
                case .staged: localized("vorgemerkt")
                case .unstaged: localized("geändert")
                case .untracked: localized("neu")
                case .conflicted: localized("Konflikt")
                }
            }

            public var systemImage: String {
                switch self {
                case .staged: "checkmark.circle"
                case .unstaged: "pencil.circle"
                case .untracked: "questionmark.circle"
                case .conflicted: "exclamationmark.triangle"
                }
            }
        }

        public let stage: Stage
        /// Der Buchstabe, den `git` vergibt: M, A, D, R, C, ?
        public let code: String
        public let path: String

        public var id: String { "\(stage.rawValue)\(code)\(path)" }

        public init(stage: Stage, code: String, path: String) {
            self.stage = stage
            self.code = code
            self.path = path
        }
    }

    /// Der Zweig, auf dem gearbeitet wird. `nil` bei abgelöstem HEAD.
    public let branch: String?
    /// Der Zweig, gegen den verglichen wird, etwa `origin/main`.
    public let upstream: String?
    public let ahead: Int
    public let behind: Int
    public let changes: [Change]
    /// Ein Repository, in dem noch nichts liegt, hat weder Commit noch Verlauf.
    public let hasNoCommitsYet: Bool

    public init(
        branch: String?,
        upstream: String?,
        ahead: Int = 0,
        behind: Int = 0,
        changes: [Change] = [],
        hasNoCommitsYet: Bool = false
    ) {
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.changes = changes
        self.hasNoCommitsYet = hasNoCommitsYet
    }

    // MARK: - Zusammenfassen

    public func count(_ stage: Change.Stage) -> Int {
        changes.filter { $0.stage == stage }.count
    }

    public var isClean: Bool { changes.isEmpty }

    /// Ob hier etwas liegt, das verloren gehen kann.
    ///
    /// Genau danach sucht man, wenn man vor einem Rechnerwechsel durch dreißig
    /// Repositories geht: nicht „ist etwas anders", sondern „ist etwas nur
    /// hier".
    public var hasUnsavedWork: Bool { !isClean || ahead > 0 }

    /// Was in einer Tabellenzeile steht: „3↑ 1↓ 2✚".
    public var shortSummary: String {
        var parts: [String] = []
        if ahead > 0 { parts.append("\(ahead)↑") }
        if behind > 0 { parts.append("\(behind)↓") }
        if !isClean { parts.append("\(changes.count)✚") }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    // MARK: - Lesen

    /// Zerlegt die Ausgabe von `git status --porcelain --branch`.
    ///
    /// - Parameter porcelain: Die Ausgabe, unverändert.
    public init(porcelain text: String) {
        var branch: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var changes: [Change] = []
        var hasNoCommitsYet = false

        for line in TextLines.split(text, keepingEmpty: false) {
            if line.hasPrefix("## ") {
                let header = Self.readHeader(String(line.dropFirst(3)))
                branch = header.branch
                upstream = header.upstream
                ahead = header.ahead
                behind = header.behind
                hasNoCommitsYet = header.hasNoCommitsYet
                continue
            }
            changes += Self.readChange(line)
        }

        self.init(
            branch: branch,
            upstream: upstream,
            ahead: ahead,
            behind: behind,
            changes: changes,
            hasNoCommitsYet: hasNoCommitsYet
        )
    }

    private struct Header {
        var branch: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var hasNoCommitsYet = false
    }

    /// Liest die Zeile hinter `## `.
    ///
    /// Vier Formen kommen vor:
    /// `main`, `main...origin/main`, `main...origin/main [ahead 1, behind 2]`,
    /// `HEAD (no branch)` und `No commits yet on main`.
    private static func readHeader(_ text: String) -> Header {
        var header = Header()
        var rest = text

        if let range = rest.range(of: " ["), rest.hasSuffix("]") {
            let track = rest[range.upperBound...].dropLast()
            header.ahead = number(after: "ahead", in: String(track))
            header.behind = number(after: "behind", in: String(track))
            rest = String(rest[rest.startIndex..<range.lowerBound])
        }

        // „No commits yet on main" — der Zweig existiert, zeigt aber auf nichts.
        if let range = rest.range(of: "No commits yet on ") {
            header.hasNoCommitsYet = true
            rest = String(rest[range.upperBound...])
        }

        if let range = rest.range(of: "...") {
            header.branch = String(rest[rest.startIndex..<range.lowerBound])
            let remote = String(rest[range.upperBound...])
            header.upstream = remote.isEmpty ? nil : remote
        } else if rest == "HEAD (no branch)" {
            header.branch = nil
        } else {
            header.branch = rest.isEmpty ? nil : rest
        }
        return header
    }

    /// Die Zahl hinter einem Wort in „ahead 1, behind 2".
    private static func number(after word: String, in text: String) -> Int {
        guard let range = text.range(of: word + " ") else { return 0 }
        let digits = text[range.upperBound...].prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    /// Liest eine Zeile wie ` M pfad` oder `?? pfad` oder `R  alt -> neu`.
    ///
    /// Gibt bewusst ein Array zurück: Eine Datei kann gleichzeitig vorgemerkt
    /// *und* danach nochmal geändert worden sein (`MM`), und das sind zwei
    /// Dinge, die man wissen will.
    private static func readChange(_ line: String) -> [Change] {
        guard line.count > 3 else { return [] }
        let codes = Array(line.prefix(2))
        let index = codes[0]
        let worktree = codes[1]
        var path = String(line.dropFirst(3))

        // Bei einer Umbenennung nennt `git` beides; interessant ist, wo die
        // Datei jetzt liegt.
        if let range = path.range(of: " -> ") {
            path = String(path[range.upperBound...])
        }
        path = unquote(path)
        guard !path.isEmpty else { return [] }

        if index == "?" && worktree == "?" {
            return [Change(stage: .untracked, code: "?", path: path)]
        }
        // Ignorierte Dateien tauchen nur mit `--ignored` auf und sind dann
        // keine Änderung, sondern eine Auskunft.
        if index == "!" && worktree == "!" { return [] }

        if isConflict(index: index, worktree: worktree) {
            return [Change(stage: .conflicted, code: String([index, worktree]), path: path)]
        }

        var result: [Change] = []
        if index != " " {
            result.append(Change(stage: .staged, code: String(index), path: path))
        }
        if worktree != " " {
            result.append(Change(stage: .unstaged, code: String(worktree), path: path))
        }
        return result
    }

    /// Die Kombinationen, die `git` für einen offenen Merge vergibt.
    private static func isConflict(index: Character, worktree: Character) -> Bool {
        switch (index, worktree) {
        case ("U", _), (_, "U"), ("A", "A"), ("D", "D"): true
        default: false
        }
    }

    /// `git` setzt Pfade mit Sonderzeichen in Anführungszeichen.
    private static func unquote(_ path: String) -> String {
        guard path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 else { return path }
        return String(path.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
