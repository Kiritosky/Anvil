import AnvilKit
import Foundation

// MARK: - YAML lesen

extension StructuredValue {
    /// Liest YAML — die Teilmenge, die in Konfigurationsdateien vorkommt.
    ///
    /// Abgedeckt: Zuordnungen und Listen über Einrückung, Listen und
    /// Zuordnungen in einer Zeile (`[1, 2]`, `{a: 1}`), Anführungszeichen in
    /// beiden Formen, Blocktext mit `|` und `>`, Kommentare, mehrere
    /// Dokumente (das erste gewinnt).
    ///
    /// **Nicht** abgedeckt: Anker und Verweise (`&`, `*`), Typangaben (`!!`),
    /// zusammengesetzte Schlüssel (`? `). Das sind die Ecken von YAML, die
    /// selbst YAML-Bibliotheken uneinheitlich auslegen — hier führen sie zu
    /// Text statt zu einer falschen Struktur.
    public static func yaml(parsing text: String) throws -> StructuredValue {
        var reader = YAMLReader(text: text)
        return try reader.document()
    }

    struct YAMLReader {
        struct Line {
            let indent: Int
            let text: String
            /// Zeilen eines Blocktexts sind Text und keine Struktur: an ihnen
            /// wird nichts entfernt und nichts umgeschrieben.
            let isRaw: Bool

            init(indent: Int, text: String, isRaw: Bool = false) {
                self.indent = indent
                self.text = text
                self.isRaw = isRaw
            }
        }

        private(set) var lines: [Line] = []
        var index = 0

        init(text: String) {
            /// Solange gesetzt, gehört jede tiefer eingerückte Zeile zu einem
            /// Blocktext und wird unangetastet durchgereicht.
            var rawBelow: Int?

            for raw in TextLines.split(text) {
                let indent = raw.prefix { $0 == " " }.count
                let bare = raw.trimmingCharacters(in: .whitespaces)

                if let limit = rawBelow {
                    if bare.isEmpty || indent > limit {
                        lines.append(Line(indent: indent, text: bare, isRaw: true))
                        continue
                    }
                    rawBelow = nil
                }

                let withoutComment = YAMLReader.stripComment(raw)
                let trimmed = withoutComment.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                // Dokumenttrenner und -ende gehören nicht zum Inhalt.
                guard trimmed != "---", trimmed != "..." else { continue }

                // „- eins" wird zu einem Marker und einer eigenen Zeile
                // darunter. Danach kennt der Rest des Lesers nur noch zwei
                // Fälle statt vier — und `- schlüssel: wert` fällt von selbst
                // richtig heraus, weil YAML die Fortsetzung genau dort
                // einrückt.
                var level = indent
                var content = Substring(trimmed)
                while content == "-" || content.hasPrefix("- ") {
                    lines.append(Line(indent: level, text: "-"))
                    if content == "-" {
                        content = ""
                        break
                    }
                    content = content.dropFirst(2).drop { $0 == " " }
                    level += 2
                }
                guard !content.isEmpty else { continue }
                lines.append(Line(indent: level, text: String(content)))

                // Endet die Zeile auf `|` oder `>`, ist alles Tiefere darunter
                // Text.
                if let split = YAMLReader.splitKey(String(content)),
                   let marker = split.value.first,
                   marker == "|" || marker == ">" {
                    rawBelow = level
                }
            }

            // Leerzeilen am Ende eines Blocktexts gehören nicht dazu.
            while let last = lines.last, last.isRaw, last.text.isEmpty {
                lines.removeLast()
            }
        }

        /// Ein `#` beginnt einen Kommentar — außer in Anführungszeichen.
        static func stripComment(_ line: String) -> String {
            var result = ""
            var quote: Character?
            var previous: Character = " "
            for character in line {
                if let open = quote {
                    result.append(character)
                    if character == open, previous != "\\" { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                    result.append(character)
                } else if character == "#", previous == " " || result.isEmpty {
                    break
                } else {
                    result.append(character)
                }
                previous = character
            }
            return result
        }

        mutating func document() throws -> StructuredValue {
            guard !lines.isEmpty else { return .null }
            return try block(indent: lines[0].indent)
        }

        mutating func block(indent: Int) throws -> StructuredValue {
            guard index < lines.count else { return .null }
            if lines[index].text == "-" { return try sequence(indent: indent) }

            // Kein Schlüssel in der Zeile: dann ist sie der Wert. Das ist der
            // Fall bei jedem Listeneintrag ohne Doppelpunkt — ohne diesen
            // Zweig würde aus „- eins" eine leere Zuordnung.
            guard YAMLReader.splitKey(lines[index].text) != nil else {
                let text = lines[index].text
                index += 1
                return try StructuredValue.yamlInline(text)
            }
            return try mapping(indent: indent)
        }

        mutating func sequence(indent: Int) throws -> StructuredValue {
            var items: [StructuredValue] = []
            while index < lines.count, !lines[index].isRaw,
                  lines[index].indent == indent, lines[index].text == "-" {
                index += 1
                items.append(try child(deeperThan: indent))
            }
            return .array(items)
        }

        mutating func mapping(indent: Int) throws -> StructuredValue {
            var pairs: [Pair] = []
            while index < lines.count, !lines[index].isRaw, lines[index].indent == indent {
                let line = lines[index]
                guard let split = YAMLReader.splitKey(line.text) else { break }
                index += 1

                if split.value.isEmpty {
                    pairs.append(Pair(split.key, try child(deeperThan: indent)))
                } else if let marker = split.value.first, marker == "|" || marker == ">" {
                    pairs.append(Pair(split.key, .string(blockText(folded: marker == ">"))))
                } else {
                    pairs.append(Pair(split.key, try StructuredValue.yamlInline(split.value)))
                }
            }
            return .object(pairs)
        }

        /// Der eingerückte Block unter einer Zeile — oder nichts.
        mutating func child(deeperThan indent: Int) throws -> StructuredValue {
            guard index < lines.count, !lines[index].isRaw,
                  lines[index].indent > indent else { return .null }
            return try block(indent: lines[index].indent)
        }

        /// Blocktext hinter `|` oder `>`.
        ///
        /// `|` behält die Zeilenumbrüche, `>` faltet sie zu Leerzeichen — das
        /// ist der einzige Unterschied, und er ist der Grund, warum es beide
        /// gibt.
        mutating func blockText(folded: Bool) -> String {
            guard index < lines.count, lines[index].isRaw else { return "" }
            // Die Einrückung der ersten Zeile ist die des Blocks; was darüber
            // hinausgeht, gehört zum Text.
            let indent = lines[index].indent
            var collected: [String] = []
            while index < lines.count, lines[index].isRaw {
                let line = lines[index]
                let extra = max(0, line.indent - indent)
                collected.append(String(repeating: " ", count: extra) + line.text)
                index += 1
            }
            return collected.joined(separator: folded ? " " : "\n")
        }

        /// Trennt `schlüssel: wert` am ersten Doppelpunkt außerhalb von
        /// Anführungszeichen — und nur, wenn ein Leerzeichen folgt oder die
        /// Zeile dort endet. Sonst zerfiele `zeit: 12:30` an der falschen
        /// Stelle.
        static func splitKey(_ text: String) -> (key: String, value: String)? {
            var quote: Character?
            let characters = Array(text)
            for (offset, character) in characters.enumerated() {
                if let open = quote {
                    if character == open { quote = nil }
                    continue
                }
                if character == "\"" || character == "'" {
                    quote = character
                    continue
                }
                // In einer eingebetteten Liste oder Zuordnung trennt der
                // Doppelpunkt nichts auf dieser Ebene.
                if character == "[" || character == "{" { return nil }
                guard character == ":" else { continue }
                let isEnd = offset == characters.count - 1
                guard isEnd || characters[offset + 1] == " " else { continue }
                let key = String(characters[0..<offset]).trimmingCharacters(in: .whitespaces)
                let value = isEnd
                    ? ""
                    : String(characters[(offset + 1)...]).trimmingCharacters(in: .whitespaces)
                return (StructuredValue.unquoted(key), value)
            }
            return nil
        }
    }

    // MARK: In einer Zeile

    /// `[1, 2]`, `{a: 1}`, `"Text"` oder ein nackter Skalar.
    static func yamlInline(_ text: String) throws -> StructuredValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            let body = String(trimmed.dropFirst().dropLast())
            let parts = splitTopLevel(body, separator: ",")
            return .array(try parts.map { try yamlInline($0) })
        }
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            let body = String(trimmed.dropFirst().dropLast())
            let parts = splitTopLevel(body, separator: ",")
            var pairs: [Pair] = []
            for part in parts where !part.trimmingCharacters(in: .whitespaces).isEmpty {
                guard let split = YAMLReader.splitKey(part) else {
                    throw unreadable(localized("In einer Zuordnung gehört zu jedem Schlüssel ein Wert: \(part)"))
                }
                pairs.append(Pair(split.key, try yamlInline(split.value)))
            }
            return .object(pairs)
        }
        if isQuoted(trimmed) { return .string(unquoted(trimmed)) }
        return scalar(trimmed)
    }

    /// Trennt an einem Zeichen, aber nur außerhalb von Klammern und
    /// Anführungszeichen. `[1, [2, 3]]` hat zwei Teile, nicht drei.
    static func splitTopLevel(_ text: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?

        for character in text {
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
                continue
            }
            switch character {
            case "\"", "'":
                quote = character
                current.append(character)
            case "[", "{":
                depth += 1
                current.append(character)
            case "]", "}":
                depth -= 1
                current.append(character)
            case separator where depth == 0:
                parts.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty || !parts.isEmpty {
            parts.append(current)
        }
        return parts
    }

    static func isQuoted(_ text: String) -> Bool {
        guard text.count >= 2, let first = text.first, let last = text.last else { return false }
        return (first == "\"" && last == "\"") || (first == "'" && last == "'")
    }

    /// Nimmt die Anführungszeichen weg, wenn welche da sind.
    static func unquoted(_ text: String) -> String {
        guard isQuoted(text) else { return text }
        let body = String(text.dropFirst().dropLast())
        guard text.hasPrefix("\"") else {
            // Einfache Anführungszeichen kennen nur eine Ersetzung: '' ist '.
            return body.replacingOccurrences(of: "''", with: "'")
        }
        return body
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

// MARK: - YAML schreiben

extension StructuredValue {
    public var yamlText: String {
        switch self {
        case .array, .object: return yamlText(indent: 0)
        default: return Self.yamlScalar(self)
        }
    }

    private func yamlText(indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)

        switch self {
        case let .object(pairs):
            guard !pairs.isEmpty else { return pad + "{}" }
            return pairs.map { pair in
                let key = Self.yamlKey(pair.key)
                // Ein leerer Behälter passt in dieselbe Zeile — ein voller
                // bekommt den eingerückten Block darunter.
                guard pair.value.hasChildren else {
                    return pad + key + ": " + Self.yamlScalar(pair.value)
                }
                return pad + key + ":\n" + pair.value.yamlText(indent: indent + 1)
            }
            .joined(separator: "\n")

        case let .array(values):
            guard !values.isEmpty else { return pad + "[]" }
            return values.map { value in
                switch value {
                case let .object(inner) where !inner.isEmpty:
                    // Der erste Schlüssel steht hinter dem Strich, der Rest
                    // darunter — so schreibt man YAML von Hand.
                    let block = StructuredValue.object(inner).yamlText(indent: indent + 1)
                    return pad + "- " + String(block.drop { $0 == " " })
                case let .array(inner) where !inner.isEmpty:
                    return pad + "-\n" + value.yamlText(indent: indent + 1)
                default:
                    return pad + "- " + Self.yamlScalar(value)
                }
            }
            .joined(separator: "\n")

        default:
            return pad + Self.yamlScalar(self)
        }
    }

    static func yamlScalar(_ value: StructuredValue) -> String {
        switch value {
        case let .string(text): return yamlString(text)
        case let .number(number): return numberText(number)
        case let .boolean(flag): return flag ? "true" : "false"
        case .null: return "null"
        case .array(let values) where values.isEmpty: return "[]"
        case .object(let pairs) where pairs.isEmpty: return "{}"
        default: return ""
        }
    }

    /// Angeführt wird nur, was sonst als etwas anderes gelesen würde.
    ///
    /// Ein Text wie `nein` oder `12` sähe unangeführt wie ein Wahrheitswert
    /// oder eine Zahl aus — und wäre beim nächsten Einlesen einer.
    static func yamlString(_ text: String) -> String {
        if text.isEmpty { return "\"\"" }
        if text.contains("\n") { return quotedJSON(text) }

        let needsQuotes = text.contains(": ")
            || text.hasSuffix(":")
            || text.hasPrefix("- ")
            || text.hasPrefix("#")
            || text.first == " "
            || text.last == " "
            || "[]{}&*!|>%@`,".contains(where: { text.hasPrefix(String($0)) })
        if needsQuotes { return quotedJSON(text) }

        // Was als Zahl oder Wahrheitswert wieder hereinkäme, muss angeführt
        // werden, sonst ist es beim nächsten Lesen keins mehr.
        if case .string = scalar(text) { return text }
        return quotedJSON(text)
    }

    static func yamlKey(_ key: String) -> String {
        let plain = !key.isEmpty
            && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
        return plain ? key : quotedJSON(key)
    }
}
