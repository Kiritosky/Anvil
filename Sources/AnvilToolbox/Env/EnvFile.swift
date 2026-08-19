import AnvilKit
import Foundation

/// Eine `.env`-Datei, aufgeschlüsselt.
public struct EnvFile: Sendable, Hashable, Identifiable {
    public let name: String
    public let entries: [Entry]
    public let problems: [Problem]

    public var id: String { name }

    public init(name: String, entries: [Entry], problems: [Problem] = []) {
        self.name = name
        self.entries = entries
        self.problems = problems
    }

    /// Ein Schlüssel mit seinem Wert.
    public struct Entry: Sendable, Hashable, Identifiable {
        public let key: String
        public let value: String
        public let line: Int

        public init(key: String, value: String, line: Int) {
            self.key = key
            self.value = value
            self.line = line
        }

        public var id: String { key }
        public var isEmpty: Bool { value.isEmpty }
    }

    /// Eine Zeile, die nicht aufgeht.
    public struct Problem: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable, Hashable {
            /// Kein `=` in der Zeile.
            case unreadable
            /// Derselbe Schlüssel steht weiter oben schon einmal.
            case duplicate

            public var title: String {
                switch self {
                case .unreadable: localized("Keine Zuweisung")
                case .duplicate: localized("Schon einmal vergeben")
                }
            }
        }

        public let kind: Kind
        public let line: Int
        /// Der Schlüssel — oder die Zeile, wenn es keinen gibt.
        public let subject: String

        public init(kind: Kind, line: Int, subject: String) {
            self.kind = kind
            self.line = line
            self.subject = subject
        }

        public var id: String { "\(line):\(subject)" }
    }

    public var keys: [String] { entries.map(\.key) }

    public func value(of key: String) -> String? {
        entries.first { $0.key == key }?.value
    }

    // MARK: - Lesen

    /// Zerlegt den Text einer `.env`-Datei.
    public static func read(_ text: String, name: String) -> EnvFile {
        var entries: [Entry] = []
        var problems: [Problem] = []
        var index: [String: Int] = [:]

        for (offset, raw) in TextLines.split(text).enumerated() {
            let number = offset + 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let statement = line.hasPrefix("export ")
                ? String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
                : line

            guard let separator = statement.firstIndex(of: "=") else {
                problems.append(Problem(kind: .unreadable, line: number, subject: statement))
                continue
            }

            let key = String(statement[..<separator]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                problems.append(Problem(kind: .unreadable, line: number, subject: statement))
                continue
            }

            let entry = Entry(
                key: key,
                value: unquote(String(statement[statement.index(after: separator)...])),
                line: number
            )

            if let previous = index[key] {
                problems.append(Problem(kind: .duplicate, line: number, subject: key))
                entries[previous] = entry
            } else {
                index[key] = entries.count
                entries.append(entry)
            }
        }

        return EnvFile(name: name, entries: entries, problems: problems)
    }

    /// Nimmt Anführungszeichen weg und schneidet den Kommentar hinter einem
    /// Wert ab.
    static func unquote(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard let first = value.first, let last = value.last else { return "" }

        if value.count >= 2, first == "\"", last == "\"" {
            return unescape(String(value.dropFirst().dropLast()))
        }
        if value.count >= 2, first == "'", last == "'" {
            return String(value.dropFirst().dropLast())
        }

        guard let hash = value.firstIndex(of: "#") else { return value }
        return String(value[..<hash]).trimmingCharacters(in: .whitespaces)
    }

    /// Die Fluchtzeichen, die in doppelten Anführungszeichen etwas bedeuten.
    static func unescape(_ value: String) -> String {
        var result = ""
        var isEscaped = false
        for character in value {
            if isEscaped {
                switch character {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                default: result.append(character)
                }
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }
        if isEscaped { result.append("\\") }
        return result
    }
}
