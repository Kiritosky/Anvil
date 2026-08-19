import AnvilKit
import Foundation

/// Ein Wert, wie ihn JSON, YAML und TOML alle drei kennen.
public indirect enum StructuredValue: Sendable, Hashable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null
    case array([StructuredValue])
    case object([Pair])

    public struct Pair: Sendable, Hashable {
        public let key: String
        public let value: StructuredValue

        public init(_ key: String, _ value: StructuredValue) {
            self.key = key
            self.value = value
        }
    }

    // MARK: - Bequemlichkeiten

    public var isContainer: Bool {
        switch self {
        case .array, .object: true
        default: false
        }
    }

    /// Ein Behälter, in dem etwas steht.
    public var hasChildren: Bool {
        switch self {
        case let .array(values): !values.isEmpty
        case let .object(pairs): !pairs.isEmpty
        default: false
        }
    }

    public var pairs: [Pair]? {
        if case let .object(pairs) = self { return pairs }
        return nil
    }

    public var elements: [StructuredValue]? {
        if case let .array(values) = self { return values }
        return nil
    }

    /// Wie viele Werte insgesamt darin stecken — für die Statuszeile.
    public var count: Int {
        switch self {
        case .array(let values): 1 + values.reduce(0) { $0 + $1.count }
        case .object(let pairs): 1 + pairs.reduce(0) { $0 + $1.value.count }
        default: 1
        }
    }

    /// Wie tief geschachtelt.
    public var depth: Int {
        switch self {
        case .array(let values): 1 + (values.map(\.depth).max() ?? 0)
        case .object(let pairs): 1 + (pairs.map(\.value.depth).max() ?? 0)
        default: 0
        }
    }

    // MARK: - Skalare lesen

    /// Was ein unangeführter Skalar bedeutet.
    public static func scalar(_ text: String) -> StructuredValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch trimmed.lowercased() {
        case "true", "yes", "on": return .boolean(true)
        case "false", "no", "off": return .boolean(false)
        case "null", "nil", "~", "": return .null
        default: break
        }
        if let number = strictNumber(trimmed) { return .number(number) }
        return .string(trimmed)
    }

    /// Eine Zahl — aber nur, wenn sie wirklich eine ist.
    static func strictNumber(_ text: String) -> Double? {
        guard !text.isEmpty else { return nil }
        let body = text.hasPrefix("-") || text.hasPrefix("+") ? String(text.dropFirst()) : text
        guard let first = body.first, first.isASCII, first.isNumber || first == "." else { return nil }
        guard body.allSatisfy({ $0.isASCII && ($0.isNumber || ".eE+-_".contains($0)) }) else {
            return nil
        }
        return Double(text.replacingOccurrences(of: "_", with: ""))
    }
}

// MARK: - JSON lesen

extension StructuredValue {
    /// Liest JSON — von Hand, damit die Reihenfolge der Schlüssel erhalten
    /// bleibt.
    public static func json(parsing text: String) throws -> StructuredValue {
        var parser = JSONReader(text: Array(text))
        let value = try parser.value()
        try parser.expectEnd()
        return value
    }

    struct JSONReader {
        let text: [Character]
        var index = 0

        init(text: [Character]) {
            self.text = text
        }

        mutating func skipSpace() {
            while index < text.count, text[index].isWhitespace { index += 1 }
        }

        mutating func expectEnd() throws {
            skipSpace()
            guard index >= text.count else {
                throw StructuredValue.unreadable(localized("Hinter dem Wert steht noch etwas."))
            }
        }

        mutating func value() throws -> StructuredValue {
            skipSpace()
            guard index < text.count else {
                throw StructuredValue.unreadable(localized("Da steht nichts."))
            }

            switch text[index] {
            case "{": return try object()
            case "[": return try array()
            case "\"": return .string(try string())
            default: return try literal()
            }
        }

        mutating func object() throws -> StructuredValue {
            index += 1
            var pairs: [Pair] = []
            skipSpace()
            if index < text.count, text[index] == "}" {
                index += 1
                return .object(pairs)
            }

            while true {
                skipSpace()
                guard index < text.count, text[index] == "\"" else {
                    throw StructuredValue.unreadable(localized("Ein Schlüssel steht in Anführungszeichen."))
                }
                let key = try string()
                skipSpace()
                guard index < text.count, text[index] == ":" else {
                    throw StructuredValue.unreadable(localized("Hinter dem Schlüssel fehlt der Doppelpunkt."))
                }
                index += 1
                pairs.append(Pair(key, try value()))
                skipSpace()
                guard index < text.count else {
                    throw StructuredValue.unreadable(localized("Die geschweifte Klammer geht nicht zu."))
                }
                if text[index] == "," {
                    index += 1
                    continue
                }
                if text[index] == "}" {
                    index += 1
                    return .object(pairs)
                }
                throw StructuredValue.unreadable(localized("Zwischen zwei Einträgen gehört ein Komma."))
            }
        }

        mutating func array() throws -> StructuredValue {
            index += 1
            var values: [StructuredValue] = []
            skipSpace()
            if index < text.count, text[index] == "]" {
                index += 1
                return .array(values)
            }

            while true {
                values.append(try value())
                skipSpace()
                guard index < text.count else {
                    throw StructuredValue.unreadable(localized("Die eckige Klammer geht nicht zu."))
                }
                if text[index] == "," {
                    index += 1
                    continue
                }
                if text[index] == "]" {
                    index += 1
                    return .array(values)
                }
                throw StructuredValue.unreadable(localized("Zwischen zwei Einträgen gehört ein Komma."))
            }
        }

        mutating func string() throws -> String {
            index += 1
            var result = ""
            while index < text.count {
                let character = text[index]
                index += 1
                if character == "\"" { return result }
                guard character == "\\" else {
                    result.append(character)
                    continue
                }
                guard index < text.count else { break }
                let escaped = text[index]
                index += 1
                switch escaped {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "b": result.append("\u{8}")
                case "f": result.append("\u{C}")
                case "u":
                    guard index + 4 <= text.count,
                          let code = UInt32(String(text[index..<(index + 4)]), radix: 16),
                          let scalar = Unicode.Scalar(code)
                    else {
                        throw StructuredValue.unreadable(localized("Nach \\u stehen vier Hexziffern."))
                    }
                    result.unicodeScalars.append(scalar)
                    index += 4
                default: result.append(escaped)
                }
            }
            throw StructuredValue.unreadable(localized("Die Anführungszeichen gehen nicht zu."))
        }

        /// `true`, `false`, `null` und Zahlen.
        mutating func literal() throws -> StructuredValue {
            let start = index
            while index < text.count, !",]}: \n\t\r".contains(text[index]) {
                index += 1
            }
            let word = String(text[start..<index])
            switch word {
            case "true": return .boolean(true)
            case "false": return .boolean(false)
            case "null": return .null
            default: break
            }
            guard let number = StructuredValue.strictNumber(word) else {
                throw StructuredValue.unreadable(localized("Das ist kein Wert: \(word)"))
            }
            return .number(number)
        }
    }

    static func unreadable(_ message: String) -> AnvilError {
        AnvilError.invalidInput(message)
    }
}

// MARK: - JSON schreiben

extension StructuredValue {
    public var jsonText: String {
        jsonText(indent: 0)
    }

    private func jsonText(indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)

        switch self {
        case let .string(text): return Self.quotedJSON(text)
        case let .number(value): return Self.numberText(value)
        case let .boolean(flag): return flag ? "true" : "false"
        case .null: return "null"
        case let .array(values):
            guard !values.isEmpty else { return "[]" }
            let body = values.map { inner + $0.jsonText(indent: indent + 1) }
            return "[\n" + body.joined(separator: ",\n") + "\n" + pad + "]"
        case let .object(pairs):
            guard !pairs.isEmpty else { return "{}" }
            let body = pairs.map {
                inner + Self.quotedJSON($0.key) + ": " + $0.value.jsonText(indent: indent + 1)
            }
            return "{\n" + body.joined(separator: ",\n") + "\n" + pad + "}"
        }
    }

    /// Ganze Zahlen ohne Nachkommastellen — `1` und nicht `1.0`.
    static func numberText(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }

    static func quotedJSON(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}
