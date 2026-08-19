import AnvilKit
import Foundation

/// Ein Markdown-Dokument, aufgeschlüsselt.
public struct MarkdownDocument: Sendable {
    public let source: String
    public let lines: [String]

    /// Für jede Zeile, ob sie in einem Codeblock steht.
    private let isCode: [Bool]

    public init(_ source: String) {
        self.source = source
        let lines = TextLines.split(source)
        self.lines = lines

        var inFence = false
        var fence: Character = "`"
        var flags: [Bool] = []
        flags.reserveCapacity(lines.count)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let marker = trimmed.first
            let isFence = Self.isFence(trimmed)
            if isFence, !inFence {
                inFence = true
                fence = marker ?? "`"
                flags.append(true)
            } else if isFence, inFence, marker == fence {
                inFence = false
                flags.append(true)
            } else {
                flags.append(inFence || line.hasPrefix("    ") || line.hasPrefix("\t"))
            }
        }
        self.isCode = flags
    }

    /// Drei Zeichen, nicht eins: ein einzelnes Backtick ist ein Code-Schnipsel
    /// mitten im Satz und macht keinen Block auf.
    static func isFence(_ trimmed: String) -> Bool {
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return false }
        let head = trimmed.prefix(3)
        return head.count == 3 && head.allSatisfy { $0 == marker }
    }

    // MARK: - Gliederung

    public struct Heading: Sendable, Identifiable, Hashable {
        public let id: Int
        /// 1 bis 6.
        public let level: Int
        public let text: String
        /// Der Anker, unter dem GitHub und die meisten anderen sie verlinken.
        public let anchor: String
        /// Zeilennummer ab 1.
        public let line: Int
    }

    public var headings: [Heading] {
        var result: [Heading] = []
        var seen: [String: Int] = [:]

        for (index, line) in lines.enumerated() where !isCode[index] {
            guard let (level, text) = Self.heading(at: index, in: lines, line: line) else { continue }
            let base = Self.anchor(for: text)
            let count = seen[base, default: 0]
            seen[base] = count + 1
            let anchor = count == 0 ? base : "\(base)-\(count)"
            result.append(
                Heading(id: index, level: level, text: text, anchor: anchor, line: index + 1)
            )
        }
        return result
    }

    /// Beide Schreibweisen: `## Titel` und der Titel mit `---` darunter.
    private static func heading(at index: Int, in lines: [String], line: String) -> (Int, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("#") {
            let hashes = trimmed.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes) else { return nil }
            let rest = trimmed.dropFirst(hashes)
            guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
            let text = rest.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return (hashes, text)
        }

        guard !trimmed.isEmpty, index + 1 < lines.count else { return nil }
        let below = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard below.count >= 2 else { return nil }
        if below.allSatisfy({ $0 == "=" }) { return (1, trimmed) }
        if below.allSatisfy({ $0 == "-" }) { return (2, trimmed) }
        return nil
    }

    /// Der Anker zu einer Überschrift, so wie GitHub ihn bildet.
    public static func anchor(for text: String) -> String {
        var anchor = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                anchor.append(character)
            } else if character == " " || character == "-" || character == "_" {
                anchor.append("-")
            }
        }
        return anchor
    }

    /// Das Inhaltsverzeichnis als Markdown-Liste.
    public var tableOfContents: String {
        let headings = self.headings
        guard let top = headings.map(\.level).min() else { return "" }
        return headings.map { heading in
            let indent = String(repeating: "  ", count: heading.level - top)
            return "\(indent)- [\(heading.text)](#\(heading.anchor))"
        }
        .joined(separator: "\n")
    }

    // MARK: - Verweise

    public struct Link: Sendable, Identifiable, Hashable {
        public let id: Int
        public let text: String
        public let target: String
        public let isImage: Bool
        public let line: Int

        public var isExternal: Bool {
            target.hasPrefix("http://") || target.hasPrefix("https://")
        }

        public var isAnchor: Bool { target.hasPrefix("#") }
    }

    public var links: [Link] {
        guard let expression = try? NSRegularExpression(pattern: Self.linkPattern) else { return [] }

        var result: [Link] = []
        for (index, line) in lines.enumerated() where !isCode[index] {
            for match in expression.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let textRange = Range(match.range(at: 2), in: line),
                      let targetRange = Range(match.range(at: 3), in: line)
                else { continue }
                let isImage = match.range(at: 1).length > 0
                result.append(
                    Link(
                        id: result.count,
                        text: String(line[textRange]),
                        target: Self.targetOnly(String(line[targetRange])),
                        isImage: isImage,
                        line: index + 1
                    )
                )
            }
        }
        return result
    }

    /// `[Text](Ziel)` und dasselbe mit `!` davor für ein Bild.
    static let linkPattern = #"(!)?\[([^\]]*)\]\(([^)]*)\)"#

    static func targetOnly(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(of: " ") else { return trimmed }
        return String(trimmed[trimmed.startIndex..<space])
    }

    // MARK: - Zahlen

    public struct Statistics: Sendable {
        public let words: Int
        public let characters: Int
        /// Zeichen ohne Leerraum — die Zahl, die Redaktionen meinen.
        public let charactersWithoutSpaces: Int
        public let paragraphs: Int
        public let headings: Int
        public let links: Int
        public let images: Int
        public let codeBlocks: Int
        public let tasksOpen: Int
        public let tasksDone: Int
        /// In Minuten, aufgerundet, bei 200 Wörtern je Minute.
        public let readingMinutes: Int
    }

    public var statistics: Statistics {
        let prose = lines.enumerated()
            .filter { !isCode[$0.offset] }
            .map(\.element)

        let words = prose
            .joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .count

        var paragraphs = 0
        var inParagraph = false
        for (index, line) in lines.enumerated() {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank || isCode[index] {
                inParagraph = false
            } else if !inParagraph {
                paragraphs += 1
                inParagraph = true
            }
        }

        var fences = 0
        for (index, line) in lines.enumerated() where isCode[index] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { fences += 1 }
        }

        var open = 0
        var done = 0
        for (index, line) in lines.enumerated() where !isCode[index] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let marker = Self.taskMarker(trimmed) else { continue }
            if marker { done += 1 } else { open += 1 }
        }

        let characters = source.count
        return Statistics(
            words: words,
            characters: characters,
            charactersWithoutSpaces: source.filter { !$0.isWhitespace }.count,
            paragraphs: paragraphs,
            headings: headings.count,
            links: links.filter { !$0.isImage }.count,
            images: links.filter(\.isImage).count,
            codeBlocks: fences / 2,
            tasksOpen: open,
            tasksDone: done,
            readingMinutes: max(1, Int((Double(words) / 200).rounded(.up)))
        )
    }

    /// `- [x] erledigt` → `true`, `- [ ] offen` → `false`, sonst `nil`.
    static func taskMarker(_ trimmed: String) -> Bool? {
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") else {
            return nil
        }
        let rest = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("[x]") || rest.hasPrefix("[X]") { return true }
        if rest.hasPrefix("[ ]") { return false }
        return nil
    }

    // MARK: - Was nicht stimmt

    public struct Problem: Sendable, Identifiable, Hashable {
        public enum Kind: String, Sendable, Hashable {
            case skippedLevel
            case duplicateAnchor
            case emptyTarget
            case brokenAnchor
            case unclosedFence

            public var title: String {
                switch self {
                case .skippedLevel: localized("Überschriftstufe übersprungen")
                case .duplicateAnchor: localized("Überschrift kommt doppelt vor")
                case .emptyTarget: localized("Verweis ohne Ziel")
                case .brokenAnchor: localized("Sprungmarke gibt es nicht")
                case .unclosedFence: localized("Codeblock nicht geschlossen")
                }
            }
        }

        public let id: Int
        public let kind: Kind
        public let detail: String
        public let line: Int
    }

    public var problems: [Problem] {
        var result: [Problem] = []
        let headings = self.headings

        var previous = 0
        for heading in headings {
            if previous > 0, heading.level > previous + 1 {
                result.append(
                    Problem(
                        id: result.count,
                        kind: .skippedLevel,
                        detail: "H\(previous) → H\(heading.level): \(heading.text)",
                        line: heading.line
                    )
                )
            }
            previous = heading.level
        }

        var seen: Set<String> = []
        for heading in headings {
            let base = Self.anchor(for: heading.text)
            if !seen.insert(base).inserted {
                result.append(
                    Problem(
                        id: result.count,
                        kind: .duplicateAnchor,
                        detail: heading.text,
                        line: heading.line
                    )
                )
            }
        }

        let anchors = Set(headings.map(\.anchor))
        for link in links {
            if link.target.isEmpty {
                result.append(
                    Problem(id: result.count, kind: .emptyTarget, detail: link.text, line: link.line)
                )
            } else if link.isAnchor, !anchors.contains(String(link.target.dropFirst())) {
                result.append(
                    Problem(id: result.count, kind: .brokenAnchor, detail: link.target, line: link.line)
                )
            }
        }

        if let line = unclosedFenceLine {
            result.append(
                Problem(id: result.count, kind: .unclosedFence, detail: "```", line: line)
            )
        }
        return result
    }

    /// Die Zeile, in der ein Codeblock aufgeht und nicht mehr zugeht.
    private var unclosedFenceLine: Int? {
        var openedAt: Int?
        var marker: Character = "`"
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first, first == "`" || first == "~",
                  trimmed.prefix(3).count == 3,
                  trimmed.prefix(3).allSatisfy({ $0 == first })
            else { continue }
            if openedAt == nil {
                openedAt = index + 1
                marker = first
            } else if first == marker {
                openedAt = nil
            }
        }
        return openedAt
    }
}
