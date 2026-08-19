import AnvilKit
import Foundation

// MARK: - Nach HTML

extension MarkdownDocument {
    /// Das Dokument als HTML.
    public var html: String {
        var blocks: [String] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append("<p>" + paragraph.map(Self.inline).joined(separator: "\n") + "</p>")
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if Self.isFence(trimmed) {
                flushParagraph()
                let marker = trimmed.first ?? "`"
                let language = String(trimmed.drop(while: { $0 == marker }))
                    .trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                index += 1
                while index < lines.count {
                    let inner = lines[index].trimmingCharacters(in: .whitespaces)
                    if Self.isFence(inner), inner.first == marker { break }
                    body.append(lines[index])
                    index += 1
                }
                index += 1
                let attribute = language.isEmpty ? "" : " class=\"language-\(Self.escape(language))\""
                blocks.append(
                    "<pre><code\(attribute)>"
                        + body.map(Self.escape).joined(separator: "\n")
                        + "</code></pre>"
                )
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if Self.isRule(trimmed) {
                flushParagraph()
                blocks.append("<hr>")
                index += 1
                continue
            }

            if let (level, text) = Self.atxHeading(trimmed) {
                flushParagraph()
                blocks.append(Self.headingHTML(level: level, text: text))
                index += 1
                continue
            }

            if index + 1 < lines.count, paragraph.isEmpty {
                let below = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if below.count >= 2, below.allSatisfy({ $0 == "=" }) {
                    blocks.append(Self.headingHTML(level: 1, text: trimmed))
                    index += 2
                    continue
                }
                if below.count >= 2, below.allSatisfy({ $0 == "-" }) {
                    blocks.append(Self.headingHTML(level: 2, text: trimmed))
                    index += 2
                    continue
                }
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while index < lines.count {
                    let inner = lines[index].trimmingCharacters(in: .whitespaces)
                    guard inner.hasPrefix(">") else { break }
                    quoted.append(String(inner.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(
                    "<blockquote><p>" + quoted.map(Self.inline).joined(separator: "\n") + "</p></blockquote>"
                )
                continue
            }

            if let table = Self.table(at: index, in: lines) {
                flushParagraph()
                blocks.append(table.html)
                index = table.nextIndex
                continue
            }

            if Self.listMarker(trimmed) != nil {
                flushParagraph()
                let list = Self.list(at: index, in: lines)
                blocks.append(list.html)
                index = list.nextIndex
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }

        flushParagraph()
        return blocks.joined(separator: "\n")
    }

    private static func headingHTML(level: Int, text: String) -> String {
        "<h\(level) id=\"\(escape(anchor(for: text)))\">\(inline(text))</h\(level)>"
    }

    // MARK: Blöcke erkennen

    static func atxHeading(_ trimmed: String) -> (Int, String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (hashes, text)
    }

    /// `---`, `***`, `___` — drei oder mehr desselben Zeichens, sonst nichts.
    static func isRule(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, "-*_".contains(first) else { return false }
        let bare = trimmed.filter { !$0.isWhitespace }
        return bare.count >= 3 && bare.allSatisfy { $0 == first }
    }

    /// Gibt zurück, womit ein Listenpunkt anfängt: `nil`, wenn keiner.
    static func listMarker(_ trimmed: String) -> (isOrdered: Bool, content: String)? {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return (false, String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return (true, String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }

    private static func list(at start: Int, in lines: [String]) -> (html: String, nextIndex: Int) {
        var index = start
        var items: [String] = []
        var isOrdered = false
        var hasTasks = false

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard let marker = listMarker(trimmed) else { break }
            if index == start { isOrdered = marker.isOrdered }
            guard marker.isOrdered == isOrdered else { break }

            if let done = taskMarker(trimmed) {
                hasTasks = true
                let text = String(marker.content.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let checked = done ? " checked" : ""
                items.append(
                    "<li><input type=\"checkbox\" disabled\(checked)> \(inline(text))</li>"
                )
            } else {
                items.append("<li>\(inline(marker.content))</li>")
            }
            index += 1
        }

        let tag = isOrdered ? "ol" : "ul"
        let attribute = hasTasks ? " class=\"task-list\"" : ""
        let html = "<\(tag)\(attribute)>\n" + items.joined(separator: "\n") + "\n</\(tag)>"
        return (html, index)
    }

    // MARK: Tabellen

    struct TableBlock {
        let html: String
        let nextIndex: Int
    }

    /// Eine Tabelle mit Strichen — aber nur, wenn unter der Kopfzeile
    /// tatsächlich die Trennzeile steht. Sonst wäre jede Zeile mit einem
    /// Strich darin eine Tabelle.
    static func table(at start: Int, in lines: [String]) -> TableBlock? {
        guard start + 1 < lines.count else { return nil }
        let head = lines[start].trimmingCharacters(in: .whitespaces)
        let rule = lines[start + 1].trimmingCharacters(in: .whitespaces)
        guard head.contains("|"), isTableRule(rule) else { return nil }

        let alignments = cells(rule).map { cell -> String in
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            switch (left, right) {
            case (true, true): return " style=\"text-align:center\""
            case (false, true): return " style=\"text-align:right\""
            default: return ""
            }
        }

        func alignment(_ index: Int) -> String {
            alignments.indices.contains(index) ? alignments[index] : ""
        }

        let headCells = cells(head).enumerated()
            .map { "<th\(alignment($0.offset))>\(inline($0.element))</th>" }
            .joined()

        var body: [String] = []
        var index = start + 2
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard line.contains("|"), !line.isEmpty else { break }
            let row = cells(line).enumerated()
                .map { "<td\(alignment($0.offset))>\(inline($0.element))</td>" }
                .joined()
            body.append("<tr>\(row)</tr>")
            index += 1
        }

        let html = """
        <table>
        <thead><tr>\(headCells)</tr></thead>
        <tbody>
        \(body.joined(separator: "\n"))
        </tbody>
        </table>
        """
        return TableBlock(html: html, nextIndex: index)
    }

    static func isTableRule(_ line: String) -> Bool {
        guard line.contains("-") else { return false }
        let bare = line.filter { !$0.isWhitespace }
        guard !bare.isEmpty else { return false }
        return bare.allSatisfy { "|-:".contains($0) }
    }

    /// Die Zellen einer Tabellenzeile, ohne die Striche außen.
    static func cells(_ line: String) -> [String] {
        var work = Substring(line)
        if work.hasPrefix("|") { work = work.dropFirst() }
        if work.hasSuffix("|") { work = work.dropLast() }
        return String(work).components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: Fließtext

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Eine Zeile Fließtext als HTML.
    static func inline(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)

        while let open = rest.firstIndex(of: "`") {
            result += emphasise(escape(String(rest[rest.startIndex..<open])))
            let after = rest.index(after: open)
            guard let close = rest[after...].firstIndex(of: "`") else {
                result += escape(String(rest[open...]))
                return result
            }
            result += "<code>" + escape(String(rest[after..<close])) + "</code>"
            rest = rest[rest.index(after: close)...]
        }

        return result + emphasise(escape(String(rest)))
    }

    /// Bilder, Links, fett, kursiv, durchgestrichen.
    static func emphasise(_ escaped: String) -> String {
        var text = escaped
        for rule in emphasisRules {
            guard let expression = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            text = expression.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: rule.template
            )
        }
        return text
    }

    private static let emphasisRules: [(pattern: String, template: String)] = [
        (#"!\[([^\]]*)\]\(([^)\s]+)[^)]*\)"#, "<img src=\"$2\" alt=\"$1\">"),
        (#"\[([^\]]*)\]\(([^)\s]+)[^)]*\)"#, "<a href=\"$2\">$1</a>"),
        (#"\*\*([^*]+)\*\*"#, "<strong>$1</strong>"),
        (#"(?<![A-Za-z0-9])__([^_]+)__(?![A-Za-z0-9])"#, "<strong>$1</strong>"),
        (#"~~([^~]+)~~"#, "<del>$1</del>"),
        (#"\*([^*]+)\*"#, "<em>$1</em>"),
        (#"(?<![A-Za-z0-9_])_([^_]+)_(?![A-Za-z0-9_])"#, "<em>$1</em>")
    ]

    /// Eine vollständige Seite, nicht nur der Rumpf.
    public func htmlPage(title: String = "") -> String {
        let heading = title.isEmpty ? (headings.first?.text ?? localized("Dokument")) : title
        return """
        <!DOCTYPE html>
        <html lang="de">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(Self.escape(heading))</title>
        <style>
        :root { color-scheme: light dark; }
        body {
          font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          max-width: 46rem; margin: 3rem auto; padding: 0 1.5rem;
        }
        pre { background: rgba(127,127,127,.12); padding: 1rem; overflow-x: auto; border-radius: .5rem; }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em; }
        pre code { font-size: .85em; }
        blockquote { margin: 1rem 0; padding-left: 1rem; border-left: 3px solid rgba(127,127,127,.4); }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid rgba(127,127,127,.35); padding: .4rem .6rem; text-align: left; }
        img { max-width: 100%; }
        hr { border: none; border-top: 1px solid rgba(127,127,127,.35); }
        .task-list { list-style: none; padding-left: 1rem; }
        </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }
}
