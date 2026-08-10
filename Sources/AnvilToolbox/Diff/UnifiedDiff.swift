import AnvilKit
import Foundation

/// Ein Unified Diff, gelesen statt nur angezeigt.
///
/// Der Unterschied zu einem Diff-Betrachter: Hier wird der Patch **verstanden**
/// — welche Dateien, welche Stellen, was dazukommt und was wegfällt — und er
/// lässt sich auf einen Text anwenden und wieder zurücknehmen. Das ist der
/// Fall, für den man ihn braucht: Ein Patch hängt an einem Ticket, und man
/// will wissen, was er täte, bevor man ihn anfasst.
public struct UnifiedDiff: Sendable {
    // MARK: - Bestandteile

    /// Eine Zeile im Patch.
    public struct Line: Sendable, Hashable {
        public enum Kind: String, Sendable, Hashable {
            case context
            case added
            case removed
            /// `\ No newline at end of file` — gehört zum Patch, ist aber
            /// keine Zeile der Datei.
            case note

            public var marker: String {
                switch self {
                case .context: " "
                case .added: "+"
                case .removed: "-"
                case .note: "\\"
                }
            }
        }

        public let kind: Kind
        public let text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }

        /// Ob die Zeile in der alten Fassung stand.
        public var isInOld: Bool { kind == .context || kind == .removed }
        /// Ob die Zeile in der neuen Fassung steht.
        public var isInNew: Bool { kind == .context || kind == .added }
    }

    /// Ein Abschnitt: `@@ -alt,anzahl +neu,anzahl @@`.
    public struct Hunk: Sendable, Identifiable {
        public let id: Int
        /// Zeilennummer ab 1, wie im Patch geschrieben.
        public let oldStart: Int
        public let oldCount: Int
        public let newStart: Int
        public let newCount: Int
        /// Was hinter dem zweiten `@@` steht — meist der umgebende Funktions-
        /// oder Abschnittsname.
        public let heading: String
        public let lines: [Line]

        public var additions: Int { lines.filter { $0.kind == .added }.count }
        public var deletions: Int { lines.filter { $0.kind == .removed }.count }

        /// Die Zeilen, wie sie vorher dastanden.
        public var oldLines: [String] { lines.filter(\.isInOld).map(\.text) }
        /// Die Zeilen, wie sie danach dastehen.
        public var newLines: [String] { lines.filter(\.isInNew).map(\.text) }

        public var header: String {
            let old = oldCount == 1 ? "\(oldStart)" : "\(oldStart),\(oldCount)"
            let new = newCount == 1 ? "\(newStart)" : "\(newStart),\(newCount)"
            let tail = heading.isEmpty ? "" : " \(heading)"
            return "@@ -\(old) +\(new) @@\(tail)"
        }
    }

    /// Alles, was ein Patch mit einer Datei vorhat.
    public struct FilePatch: Sendable, Identifiable {
        public let id: Int
        public let oldPath: String
        public let newPath: String
        public let hunks: [Hunk]

        /// `/dev/null` auf der einen Seite heißt: Datei entsteht oder
        /// verschwindet.
        public var isNew: Bool { oldPath == "/dev/null" }
        public var isDeleted: Bool { newPath == "/dev/null" }
        public var isRename: Bool { !isNew && !isDeleted && oldPath != newPath }

        public var additions: Int { hunks.reduce(0) { $0 + $1.additions } }
        public var deletions: Int { hunks.reduce(0) { $0 + $1.deletions } }

        /// Der Name, unter dem man die Datei sucht.
        public var displayPath: String { isDeleted ? oldPath : newPath }
    }

    public let files: [FilePatch]

    public var additions: Int { files.reduce(0) { $0 + $1.additions } }
    public var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
    public var isEmpty: Bool { files.isEmpty }

    // MARK: - Lesen

    /// Liest einen Unified Diff.
    ///
    /// Robust gegenüber dem, was tatsächlich in Tickets landet: mit und ohne
    /// `diff --git`-Kopf, mit `a/`- und `b/`-Präfix oder ohne, mit
    /// Zeitstempeln hinter dem Dateinamen. Was nicht zu einem Abschnitt
    /// gehört, wird übergangen statt als Fehler behandelt — ein Patch mitten
    /// in einem E-Mail-Text soll trotzdem lesbar sein.
    public init(parsing text: String) {
        var files: [FilePatch] = []
        var oldPath: String?
        var newPath: String?
        var hunks: [Hunk] = []
        var current: (old: Int, oldCount: Int, new: Int, newCount: Int, heading: String)?
        var lines: [Line] = []
        /// Wie viele Zeilen der Abschnitt laut seinem Kopf noch erwartet.
        ///
        /// Ohne das frisst ein Abschnitt die Leerzeile, die ihn vom Text
        /// dahinter trennt — und dieser Kontext, den es nie gab, lässt den
        /// Patch später nirgends mehr passen.
        var oldRemaining = 0
        var newRemaining = 0

        func closeHunk() {
            guard let header = current else { return }
            hunks.append(
                Hunk(
                    id: hunks.count,
                    oldStart: header.old,
                    oldCount: header.oldCount,
                    newStart: header.new,
                    newCount: header.newCount,
                    heading: header.heading,
                    lines: lines
                )
            )
            current = nil
            lines = []
        }

        func closeFile() {
            closeHunk()
            guard !hunks.isEmpty else {
                oldPath = nil
                newPath = nil
                return
            }
            files.append(
                FilePatch(
                    id: files.count,
                    oldPath: oldPath ?? "?",
                    newPath: newPath ?? oldPath ?? "?",
                    hunks: hunks
                )
            )
            hunks = []
            oldPath = nil
            newPath = nil
        }

        for line in TextLines.split(text) {
            if line.hasPrefix("diff --git ") {
                closeFile()
                continue
            }
            if line.hasPrefix("--- ") {
                // Ein neuer `---`-Kopf beginnt eine neue Datei, auch ohne
                // `diff --git` davor.
                closeFile()
                oldPath = Self.path(from: line.dropFirst(4))
                continue
            }
            if line.hasPrefix("+++ ") {
                newPath = Self.path(from: line.dropFirst(4))
                continue
            }
            if line.hasPrefix("@@") {
                closeHunk()
                current = Self.hunkHeader(line)
                oldRemaining = current?.oldCount ?? 0
                newRemaining = current?.newCount ?? 0
                continue
            }

            guard current != nil else { continue }

            // Ein voller Abschnitt nimmt nur noch den „\ No newline"-Vermerk,
            // der hinter seiner letzten Zeile steht und für keine Seite zählt.
            if oldRemaining <= 0, newRemaining <= 0 {
                if line.hasPrefix("\\") {
                    lines.append(
                        Line(kind: .note, text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                    )
                }
                closeHunk()
                continue
            }

            if line.hasPrefix("+") {
                lines.append(Line(kind: .added, text: String(line.dropFirst())))
                newRemaining -= 1
            } else if line.hasPrefix("-") {
                lines.append(Line(kind: .removed, text: String(line.dropFirst())))
                oldRemaining -= 1
            } else if line.hasPrefix(" ") {
                lines.append(Line(kind: .context, text: String(line.dropFirst())))
                oldRemaining -= 1
                newRemaining -= 1
            } else if line.hasPrefix("\\") {
                // Gehört zum Patch, zählt aber für keine Seite mit.
                lines.append(Line(kind: .note, text: String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else if line.isEmpty, oldRemaining > 0 || newRemaining > 0 {
                // Ein leerer Kontext verliert im Transport gern sein führendes
                // Leerzeichen. Solange der Abschnitt noch Zeilen erwartet, ist
                // das die wahrscheinlichere Erklärung als sein Ende.
                lines.append(Line(kind: .context, text: ""))
                oldRemaining -= 1
                newRemaining -= 1
            } else {
                closeHunk()
            }
        }
        closeFile()

        self.files = files
    }

    private init(files: [FilePatch]) {
        self.files = files
    }

    /// Der Dateiname aus einer `---`- oder `+++`-Zeile.
    ///
    /// Hinter dem Namen steht oft ein Zeitstempel, getrennt durch einen
    /// Tabulator; das `a/`- und `b/`-Präfix von Git gehört nicht zum Pfad.
    static func path(from field: Substring) -> String {
        var name = String(field)
        if let tab = name.firstIndex(of: "\t") {
            name = String(name[name.startIndex..<tab])
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if name == "/dev/null" { return name }
        if name.hasPrefix("a/") || name.hasPrefix("b/") { name = String(name.dropFirst(2)) }
        return name
    }

    /// `@@ -12,7 +12,9 @@ func etwas()`
    static func hunkHeader(
        _ line: String
    ) -> (old: Int, oldCount: Int, new: Int, newCount: Int, heading: String)? {
        let body = line.dropFirst(2)
        guard let end = body.range(of: "@@") else { return nil }
        let ranges = body[body.startIndex..<end.lowerBound]
            .split(separator: " ", omittingEmptySubsequences: true)
        guard ranges.count >= 2,
              let old = numbers(ranges[0], sign: "-"),
              let new = numbers(ranges[1], sign: "+")
        else { return nil }

        let heading = String(body[end.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (old.start, old.count, new.start, new.count, heading)
    }

    /// `-12,7` → (12, 7). Ohne Komma ist die Anzahl 1.
    private static func numbers(_ field: Substring, sign: Character) -> (start: Int, count: Int)? {
        guard field.first == sign else { return nil }
        let parts = field.dropFirst().split(separator: ",")
        guard let start = Int(parts.first ?? "") else { return nil }
        guard parts.count > 1 else { return (start, 1) }
        guard let count = Int(parts[1]) else { return nil }
        return (start, count)
    }

    // MARK: - Umkehren

    /// Derselbe Patch andersherum.
    ///
    /// Das ist die Rücknahme: Was hinzugefügt wurde, fällt weg; was wegfiel,
    /// kommt zurück; die Dateien tauschen die Seiten.
    public var reversed: UnifiedDiff {
        UnifiedDiff(
            files: files.map { file in
                FilePatch(
                    id: file.id,
                    oldPath: file.newPath,
                    newPath: file.oldPath,
                    hunks: file.hunks.map { hunk in
                        Hunk(
                            id: hunk.id,
                            oldStart: hunk.newStart,
                            oldCount: hunk.newCount,
                            newStart: hunk.oldStart,
                            newCount: hunk.oldCount,
                            heading: hunk.heading,
                            lines: hunk.lines.map { line in
                                switch line.kind {
                                case .added: Line(kind: .removed, text: line.text)
                                case .removed: Line(kind: .added, text: line.text)
                                case .context, .note: line
                                }
                            }
                        )
                    }
                )
            }
        )
    }

    /// Der Patch wieder als Text.
    public var text: String {
        files.flatMap { file -> [String] in
            ["--- \(file.oldPath)", "+++ \(file.newPath)"]
                + file.hunks.flatMap { hunk -> [String] in
                    [hunk.header] + hunk.lines.map { "\($0.kind.marker)\($0.text)" }
                }
        }
        .joined(separator: "\n")
    }

    // MARK: - Anwenden

    /// Wendet die Abschnitte einer Datei auf einen Text an.
    ///
    /// Die Zeilennummer im Kopf ist ein Hinweis, keine Zusage: Patches werden
    /// gegen eine Fassung geschrieben und gegen eine leicht andere angewendet.
    /// Deshalb wird um die angegebene Stelle herum gesucht — und wenn der
    /// Kontext nirgends passt, gibt es einen Fehler statt einer stillen
    /// Verstümmelung.
    public func applied(_ file: FilePatch, to text: String) throws -> String {
        var lines = TextLines.split(text)
        // Ein abschließender Umbruch ergibt eine leere letzte Zeile, die keine
        // Zeile der Datei ist. Sie wird abgetrennt und am Ende wieder
        // angehängt, sonst verschiebt sie jede Suche.
        let hadTrailingNewline = lines.count > 1 && lines.last?.isEmpty == true
        if hadTrailingNewline { lines.removeLast() }

        // Von hinten nach vorn: so bleiben die Stellen der noch nicht
        // angewendeten Abschnitte gültig.
        for hunk in file.hunks.reversed() {
            let old = hunk.oldLines
            let position = try Self.position(of: old, in: lines, hint: hunk.oldStart - 1, hunk: hunk.id)
            lines.replaceSubrange(position..<(position + old.count), with: hunk.newLines)
        }

        if hadTrailingNewline { lines.append("") }
        return lines.joined(separator: "\n")
    }

    /// Wie weit von der angegebenen Stelle aus gesucht wird.
    ///
    /// Genug für den üblichen Versatz durch ein paar Zeilen darüber, wenig
    /// genug, dass nicht irgendein gleich aussehender Abschnitt am anderen
    /// Ende der Datei erwischt wird.
    static let searchWindow = 200

    static func position(of old: [String], in lines: [String], hint: Int, hunk: Int) throws -> Int {
        guard !old.isEmpty else {
            // Ein Abschnitt, der nur hinzufügt, hat keinen Kontext zum Suchen.
            let position = max(0, min(hint, lines.count))
            return position
        }
        guard old.count <= lines.count else {
            throw Self.doesNotFit(hunk)
        }

        func matches(at index: Int) -> Bool {
            guard index >= 0, index + old.count <= lines.count else { return false }
            return Array(lines[index..<(index + old.count)]) == old
        }

        if matches(at: hint) { return hint }
        for offset in 1...searchWindow {
            if matches(at: hint - offset) { return hint - offset }
            if matches(at: hint + offset) { return hint + offset }
        }
        throw Self.doesNotFit(hunk)
    }

    static func doesNotFit(_ hunk: Int) -> AnvilError {
        AnvilError.invalidInput(
            localized("Abschnitt \(hunk + 1) passt nicht: Der Text drumherum steht so nicht in der Vorlage.")
        )
    }
}
