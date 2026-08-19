import AnvilKit
import Foundation

// MARK: - TOML lesen

extension StructuredValue {
    /// Liest TOML.
    public static func toml(parsing text: String) throws -> StructuredValue {
        var root = TOMLTable()
        var path: [String] = []

        for raw in TextLines.split(text) {
            let line = TOMLReader.stripComment(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[[") {
                guard line.hasSuffix("]]") else {
                    throw unreadable(localized("Eine Tabellenreihe endet mit ]]: \(line)"))
                }
                path = try TOMLReader.path(String(line.dropFirst(2).dropLast(2)))
                try root.startRow(at: path)
                continue
            }
            if line.hasPrefix("[") {
                guard line.hasSuffix("]") else {
                    throw unreadable(localized("Eine Tabelle endet mit ]: \(line)"))
                }
                path = try TOMLReader.path(String(line.dropFirst().dropLast()))
                try root.startTable(at: path)
                continue
            }

            guard let equals = TOMLReader.assignment(in: line) else {
                throw unreadable(localized("Das ist weder eine Tabelle noch eine Zuweisung: \(line)"))
            }
            let keyPath = try TOMLReader.path(equals.key)
            let value = try TOMLReader.value(equals.value)
            try root.set(value, at: path + keyPath)
        }

        return root.value
    }

    /// Ein Baum aus Tabellen, der beim Lesen wächst.
    struct TOMLTable {
        private var pairs: [Pair] = []

        var value: StructuredValue { .object(pairs) }

        /// `[a.b]` — legt die Kette an, falls es sie noch nicht gibt.
        mutating func startTable(at path: [String]) throws {
            try Self.modify(&pairs, path: path) { _ in }
        }

        /// `[[a.b]]` — hängt eine weitere Tabelle an die Liste an.
        mutating func startRow(at path: [String]) throws {
            guard let last = path.last else { return }
            try Self.modify(&pairs, path: Array(path.dropLast())) { table in
                let index = table.firstIndex { $0.key == last }
                var rows = index.flatMap { table[$0].value.elements } ?? []
                rows.append(.object([]))
                Self.store(&table, key: last, value: .array(rows), at: index)
            }
        }

        mutating func set(_ value: StructuredValue, at path: [String]) throws {
            guard let last = path.last else { return }
            try Self.modify(&pairs, path: Array(path.dropLast())) { table in
                guard !table.contains(where: { $0.key == last }) else {
                    throw StructuredValue.unreadable(
                        localized("Diesen Schlüssel gibt es schon: \(last)")
                    )
                }
                table.append(Pair(last, value))
            }
        }

        /// Geht den Pfad entlang, legt an, was fehlt, und lässt `body` am Ende
        /// die Tabelle bearbeiten.
        private static func modify(
            _ pairs: inout [Pair],
            path: [String],
            body: (inout [Pair]) throws -> Void
        ) throws {
            guard let head = path.first else {
                try body(&pairs)
                return
            }

            let rest = Array(path.dropFirst())
            let index = pairs.firstIndex { $0.key == head }
            let existing = index.map { pairs[$0].value } ?? .object([])

            if case let .array(rows) = existing, let last = rows.last {
                var inner = last.pairs ?? []
                try modify(&inner, path: rest, body: body)
                var updated = rows
                updated[updated.count - 1] = .object(inner)
                store(&pairs, key: head, value: .array(updated), at: index)
                return
            }

            var inner = existing.pairs ?? []
            try modify(&inner, path: rest, body: body)
            store(&pairs, key: head, value: .object(inner), at: index)
        }

        private static func store(
            _ pairs: inout [Pair],
            key: String,
            value: StructuredValue,
            at index: Int?
        ) {
            if let index {
                pairs[index] = Pair(key, value)
            } else {
                pairs.append(Pair(key, value))
            }
        }
    }

    enum TOMLReader {
        /// Ein `#` beginnt einen Kommentar — außer in Anführungszeichen.
        static func stripComment(_ line: String) -> String {
            var result = ""
            var quote: Character?
            for character in line {
                if let open = quote {
                    result.append(character)
                    if character == open { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                    result.append(character)
                } else if character == "#" {
                    break
                } else {
                    result.append(character)
                }
            }
            return result
        }

        /// `a.b."c d"` → `["a", "b", "c d"]`
        static func path(_ text: String) throws -> [String] {
            let parts = StructuredValue.splitTopLevel(text, separator: ".")
            let keys = parts
                .map { StructuredValue.unquoted($0.trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.isEmpty }
            guard !keys.isEmpty else {
                throw StructuredValue.unreadable(localized("Ein Schlüssel darf nicht leer sein."))
            }
            return keys
        }

        /// Trennt `schlüssel = wert` am ersten `=` außerhalb von
        /// Anführungszeichen.
        static func assignment(in line: String) -> (key: String, value: String)? {
            var quote: Character?
            let characters = Array(line)
            for (offset, character) in characters.enumerated() {
                if let open = quote {
                    if character == open { quote = nil }
                    continue
                }
                if character == "\"" || character == "'" {
                    quote = character
                    continue
                }
                guard character == "=" else { continue }
                let key = String(characters[0..<offset]).trimmingCharacters(in: .whitespaces)
                let value = String(characters[(offset + 1)...]).trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { return nil }
                return (key, value)
            }
            return nil
        }

        static func value(_ text: String) throws -> StructuredValue {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                throw StructuredValue.unreadable(localized("Hinter dem Gleichheitszeichen fehlt der Wert."))
            }

            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                let body = String(trimmed.dropFirst().dropLast())
                let parts = StructuredValue.splitTopLevel(body, separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                return .array(try parts.map { try value($0) })
            }
            if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
                let body = String(trimmed.dropFirst().dropLast())
                var pairs: [Pair] = []
                for part in StructuredValue.splitTopLevel(body, separator: ",") {
                    let entry = part.trimmingCharacters(in: .whitespaces)
                    guard !entry.isEmpty else { continue }
                    guard let split = assignment(in: entry) else {
                        throw StructuredValue.unreadable(
                            localized("In einer Tabelle gehört zu jedem Schlüssel ein Wert: \(entry)")
                        )
                    }
                    pairs.append(Pair(StructuredValue.unquoted(split.key), try value(split.value)))
                }
                return .object(pairs)
            }
            if StructuredValue.isQuoted(trimmed) {
                return .string(StructuredValue.unquoted(trimmed))
            }
            if trimmed == "true" { return .boolean(true) }
            if trimmed == "false" { return .boolean(false) }
            if let number = StructuredValue.strictNumber(trimmed) { return .number(number) }
            return .string(trimmed)
        }
    }
}

// MARK: - TOML schreiben

extension StructuredValue {
    /// Als TOML.
    public var tomlText: String {
        guard case let .object(pairs) = self else {
            return "wert = " + Self.tomlScalar(self)
        }
        var lines: [String] = []
        Self.tomlBody(pairs, path: [], into: &lines)
        return lines.joined(separator: "\n")
    }

    /// Schreibt eine Tabelle: erst die einfachen Werte, dann die
    /// Untertabellen.
    private static func tomlBody(_ pairs: [Pair], path: [String], into lines: inout [String]) {
        let plain = pairs.filter { !isTable($0.value) && !isTableArray($0.value) }
        let tables = pairs.filter { isTable($0.value) }
        let rows = pairs.filter { isTableArray($0.value) }

        for pair in plain {
            lines.append(tomlKey(pair.key) + " = " + tomlScalar(pair.value))
        }

        for pair in tables {
            let inner = path + [pair.key]
            if !lines.isEmpty { lines.append("") }
            lines.append("[" + inner.map(tomlKey).joined(separator: ".") + "]")
            tomlBody(pair.value.pairs ?? [], path: inner, into: &lines)
        }

        for pair in rows {
            let inner = path + [pair.key]
            for element in pair.value.elements ?? [] {
                if !lines.isEmpty { lines.append("") }
                lines.append("[[" + inner.map(tomlKey).joined(separator: ".") + "]]")
                tomlBody(element.pairs ?? [], path: inner, into: &lines)
            }
        }
    }

    private static func isTable(_ value: StructuredValue) -> Bool {
        if case let .object(pairs) = value { return !pairs.isEmpty }
        return false
    }

    /// Eine Liste, in der nur Objekte stehen — daraus wird `[[…]]`.
    private static func isTableArray(_ value: StructuredValue) -> Bool {
        guard case let .array(values) = value, !values.isEmpty else { return false }
        return values.allSatisfy { isTable($0) }
    }

    static func tomlScalar(_ value: StructuredValue) -> String {
        switch value {
        case let .string(text): return quotedJSON(text)
        case let .number(number): return numberText(number)
        case let .boolean(flag): return flag ? "true" : "false"
        case .null: return "\"\""
        case let .array(values):
            return "[" + values.map { tomlScalar($0) }.joined(separator: ", ") + "]"
        case let .object(pairs):
            let body = pairs.map { tomlKey($0.key) + " = " + tomlScalar($0.value) }
            return "{ " + body.joined(separator: ", ") + " }"
        }
    }

    static func tomlKey(_ key: String) -> String {
        let plain = !key.isEmpty
            && key.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" || $0 == "-" }
        return plain ? key : quotedJSON(key)
    }
}
