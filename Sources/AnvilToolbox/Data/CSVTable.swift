import AnvilKit
import Foundation

/// Eine Tabelle aus Text: CSV, TSV, mit Semikolon, mit Strichen.
public struct CSVTable: Sendable {
    /// Womit die Spalten getrennt sind.
    public enum Delimiter: String, Hashable, Sendable, CaseIterable, Identifiable {
        case comma
        case semicolon
        case tab
        case pipe

        public var id: String { rawValue }

        public var character: Character {
            switch self {
            case .comma: ","
            case .semicolon: ";"
            case .tab: "\t"
            case .pipe: "|"
            }
        }

        public var title: String {
            switch self {
            case .comma: localized("Komma")
            case .semicolon: localized("Semikolon")
            case .tab: localized("Tabulator")
            case .pipe: localized("Strich")
            }
        }

        /// Das Zeichen so, wie man es zeigen kann — ein Tabulator ist sonst
        /// eine leere Stelle in der Auswahl.
        public var symbol: String {
            self == .tab ? "⇥" : String(character)
        }
    }

    /// Die Kopfzeile. Ohne Kopfzeile stehen hier „Spalte 1", „Spalte 2" …,
    /// damit alles darunter — Sortieren, JSON, Statistik — nur einen Fall
    /// kennt statt zwei.
    public let header: [String]
    public let rows: [[String]]
    /// Ob die Kopfzeile aus den Daten kam oder erfunden wurde.
    public let hasNamedColumns: Bool
    public let delimiter: Delimiter

    public var columnCount: Int { header.count }
    public var rowCount: Int { rows.count }
    public var isEmpty: Bool { rows.isEmpty && header.isEmpty }

    // MARK: - Lesen

    public init(parsing text: String, delimiter: Delimiter, hasHeader: Bool) {
        self.delimiter = delimiter
        var records = Self.records(in: text, separatedBy: delimiter.character)

        let width = records.map(\.count).max() ?? 0
        for index in records.indices where records[index].count < width {
            records[index] += Array(repeating: "", count: width - records[index].count)
        }

        guard !records.isEmpty else {
            header = []
            rows = []
            hasNamedColumns = false
            return
        }

        if hasHeader {
            header = records[0].enumerated().map { index, name in
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? Self.columnName(index) : trimmed
            }
            rows = Array(records.dropFirst())
            hasNamedColumns = true
        } else {
            header = (0..<width).map(Self.columnName)
            rows = records
            hasNamedColumns = false
        }
    }

    private init(header: [String], rows: [[String]], hasNamedColumns: Bool, delimiter: Delimiter) {
        self.header = header
        self.rows = rows
        self.hasNamedColumns = hasNamedColumns
        self.delimiter = delimiter
    }

    /// Eine Tabelle ohne alles — der Zustand, bevor jemand etwas eingeworfen
    /// hat.
    public static let empty = CSVTable(
        header: [],
        rows: [],
        hasNamedColumns: false,
        delimiter: .comma
    )

    static func columnName(_ index: Int) -> String {
        localized("Spalte \(index + 1)")
    }

    /// Zerlegt den Text nach RFC 4180.
    static func records(in text: String, separatedBy separator: Character) -> [[String]] {
        let text = TextLines.normalized(text)

        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var isQuoted = false
        var sawAnything = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            record.append(field)
            field = ""
        }

        func endRecord() {
            endField()
            if record.count > 1 || !(record.first ?? "").isEmpty {
                records.append(record)
            }
            record = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            sawAnything = true

            if isQuoted {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            isQuoted = false
                            pending = next
                        }
                    } else {
                        isQuoted = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"" where field.isEmpty:
                isQuoted = true
            case separator:
                endField()
            case "\n":
                endRecord()
            default:
                field.append(character)
            }
        }

        if sawAnything { endRecord() }
        return records
    }

    /// Rät das Trennzeichen.
    public static func detectDelimiter(in text: String) -> Delimiter {
        let lines = TextLines.split(text, keepingEmpty: false).prefix(20)
        guard !lines.isEmpty else { return .comma }

        var best = Delimiter.comma
        var bestScore = -1

        for candidate in Delimiter.allCases {
            let counts = lines.map { line in
                Self.records(in: line, separatedBy: candidate.character).first?.count ?? 0
            }
            guard let columns = counts.first, columns > 1 else { continue }
            let isConsistent = counts.allSatisfy { $0 == columns }
            let score = (isConsistent ? 1000 : 0) + columns
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    // MARK: - Umformen

    /// Sortiert nach einer Spalte — numerisch, wenn die Spalte Zahlen enthält.
    public func sorted(by column: Int, ascending: Bool = true) -> CSVTable {
        guard header.indices.contains(column) else { return self }
        let numeric = summary(of: column).isNumeric

        let sortedRows = rows.sorted { left, right in
            let a = left.indices.contains(column) ? left[column] : ""
            let b = right.indices.contains(column) ? right[column] : ""
            let isBefore: Bool
            if numeric, let x = Self.number(a), let y = Self.number(b) {
                isBefore = x < y
            } else {
                isBefore = a.localizedStandardCompare(b) == .orderedAscending
            }
            return ascending ? isBefore : !isBefore
        }

        return CSVTable(
            header: header,
            rows: sortedRows,
            hasNamedColumns: hasNamedColumns,
            delimiter: delimiter
        )
    }

    /// Behält nur die Zeilen, in denen der Text irgendwo vorkommt.
    public func filtered(by needle: String) -> CSVTable {
        let trimmed = needle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return self }
        let kept = rows.filter { row in
            row.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
        return CSVTable(
            header: header,
            rows: kept,
            hasNamedColumns: hasNamedColumns,
            delimiter: delimiter
        )
    }

    /// Nur die genannten Spalten, in der angegebenen Reihenfolge.
    public func selecting(_ columns: [Int]) -> CSVTable {
        let valid = columns.filter(header.indices.contains)
        guard !valid.isEmpty else { return self }
        return CSVTable(
            header: valid.map { header[$0] },
            rows: rows.map { row in valid.map { row.indices.contains($0) ? row[$0] : "" } },
            hasNamedColumns: hasNamedColumns,
            delimiter: delimiter
        )
    }

    // MARK: - Ausgeben

    /// Wieder als Text, mit dem gewünschten Trennzeichen.
    public func text(delimiter target: Delimiter, includingHeader: Bool = true) -> String {
        let separator = target.character
        func quoted(_ field: String) -> String {
            let needsQuotes = field.contains(separator)
                || field.contains("\"")
                || field.contains("\n")
                || field.contains("\r")
            guard needsQuotes else { return field }
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }

        let body = rows.map { row in row.map(quoted).joined(separator: String(separator)) }
        guard includingHeader, hasNamedColumns else { return body.joined(separator: "\n") }
        return ([header.map(quoted).joined(separator: String(separator))] + body).joined(separator: "\n")
    }

    /// Als JSON: ein Objekt je Zeile, Spaltenreihenfolge erhalten.
    public var json: String {
        guard !rows.isEmpty else { return "[]" }
        let objects = rows.map { row -> String in
            let pairs = header.enumerated().map { index, name -> String in
                let value = row.indices.contains(index) ? row[index] : ""
                return "    \(Self.quotedJSON(name)): \(Self.jsonValue(value))"
            }
            return "  {\n" + pairs.joined(separator: ",\n") + "\n  }"
        }
        return "[\n" + objects.joined(separator: ",\n") + "\n]"
    }

    /// Als Markdown-Tabelle.
    public var markdown: String {
        guard !header.isEmpty else { return "" }
        func cell(_ text: String) -> String {
            text.replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: " ")
        }
        let head = "| " + header.map(cell).joined(separator: " | ") + " |"
        let rule = "| " + header.map { _ in "---" }.joined(separator: " | ") + " |"
        let body = rows.map { row in
            "| " + (0..<header.count)
                .map { cell(row.indices.contains($0) ? row[$0] : "") }
                .joined(separator: " | ") + " |"
        }
        return ([head, rule] + body).joined(separator: "\n")
    }

    /// Als `INSERT`-Anweisungen.
    public func sql(table name: String) -> String {
        guard !rows.isEmpty else { return "" }
        let tableName = Self.sqlIdentifier(name.isEmpty ? "daten" : name)
        let columns = header.map(Self.sqlIdentifier).joined(separator: ", ")
        return rows.map { row in
            let values = (0..<header.count)
                .map { Self.sqlValue(row.indices.contains($0) ? row[$0] : "") }
                .joined(separator: ", ")
            return "INSERT INTO \(tableName) (\(columns)) VALUES (\(values));"
        }
        .joined(separator: "\n")
    }

    // MARK: - Was in den Spalten steht

    /// Was über eine Spalte zu sagen ist.
    public struct ColumnSummary: Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let filled: Int
        public let empty: Int
        public let distinct: Int
        public let isNumeric: Bool
        public let minimum: Double?
        public let maximum: Double?
        public let sum: Double?
        public let mean: Double?
    }

    public func summary(of column: Int) -> ColumnSummary {
        let name = header.indices.contains(column) ? header[column] : Self.columnName(column)
        let values = rows.map { $0.indices.contains(column) ? $0[column] : "" }
        let filled = values.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let numbers = filled.compactMap(Self.number)
        let isNumeric = !numbers.isEmpty && numbers.count == filled.count

        return ColumnSummary(
            id: column,
            name: name,
            filled: filled.count,
            empty: values.count - filled.count,
            distinct: Set(values).count,
            isNumeric: isNumeric,
            minimum: isNumeric ? numbers.min() : nil,
            maximum: isNumeric ? numbers.max() : nil,
            sum: isNumeric ? numbers.reduce(0, +) : nil,
            mean: isNumeric ? numbers.reduce(0, +) / Double(numbers.count) : nil
        )
    }

    public var summaries: [ColumnSummary] {
        header.indices.map(summary(of:))
    }

    // MARK: - Kleinkram

    static func number(_ text: String) -> Double? {
        NumericText.value(in: text)
    }

    static func quotedJSON(_ text: String) -> String {
        var result = "\""
        for character in text.unicodeScalars {
            switch character {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if character.value < 0x20 {
                    result += String(format: "\\u%04x", character.value)
                } else {
                    result.unicodeScalars.append(character)
                }
            }
        }
        return result + "\""
    }

    /// Zahlen und Wahrheitswerte bleiben in JSON unangeführt — sonst wäre das
    /// Ergebnis zwar gültiges JSON, aber für nichts zu gebrauchen, was damit
    /// weiterrechnet.
    static func jsonValue(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "null" }
        if trimmed == "true" || trimmed == "false" { return trimmed }
        if isJSONNumber(trimmed) { return trimmed }
        return quotedJSON(text)
    }

    /// Genau die Zahlenschreibweise, die JSON kennt.
    static func isJSONNumber(_ text: String) -> Bool {
        let body = text.hasPrefix("-") ? text.dropFirst() : Substring(text)
        guard let first = body.first, first.isASCII, first.isNumber else { return false }
        guard body.allSatisfy({ $0.isASCII && ($0.isNumber || ".eE+-".contains($0)) }) else {
            return false
        }
        if body.count > 1, first == "0" {
            let second = body[body.index(after: body.startIndex)]
            guard second == "." || second == "e" || second == "E" else { return false }
        }
        return Double(text) != nil
    }

    static func sqlIdentifier(_ text: String) -> String {
        let cleaned = text.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "_"
        }
        let joined = String(cleaned)
        return joined.first?.isNumber == true ? "_" + joined : joined
    }

    static func sqlValue(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "NULL" }
        if isJSONNumber(trimmed) { return trimmed }
        return "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
