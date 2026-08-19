import AnvilKit
import Foundation

/// Mehrere `.env`-Dateien nebeneinander.
public struct EnvComparison: Sendable {
    public let files: [EnvFile]

    public init(_ files: [EnvFile]) {
        self.files = files
    }

    public static let empty = EnvComparison([])

    public var isEmpty: Bool { files.isEmpty }

    /// Ob ein Schlüssel in einer Datei steht — und ob etwas dahinter steht.
    public enum Presence: String, Sendable, Hashable {
        case set
        case empty
        case missing

        public var title: String {
            switch self {
            case .set: localized("gesetzt")
            case .empty: localized("leer")
            case .missing: localized("fehlt")
            }
        }

        public var symbol: String {
            switch self {
            case .set: "●"
            case .empty: "○"
            case .missing: "—"
            }
        }
    }

    /// Ein Schlüssel über alle Dateien hinweg.
    public struct Row: Sendable, Hashable, Identifiable {
        public let key: String
        public let presence: [Presence]
        /// Ob die Werte dort, wo etwas steht, überall gleich sind.
        public let isSame: Bool

        public var id: String { key }

        public var isMissingSomewhere: Bool { presence.contains(.missing) }
        public var isEmptySomewhere: Bool { presence.contains(.empty) }
        public var isEverywhere: Bool { !isMissingSomewhere }
    }

    /// Alle Schlüssel aus allen Dateien, alphabetisch.
    public var keys: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for file in files {
            for key in file.keys where seen.insert(key).inserted {
                result.append(key)
            }
        }
        return result.sorted()
    }

    public var rows: [Row] {
        keys.map { key in
            let values = files.map { $0.value(of: key) }
            let presence = values.map { value -> Presence in
                guard let value else { return .missing }
                return value.isEmpty ? .empty : .set
            }
            let present = values.compactMap { $0 }
            return Row(
                key: key,
                presence: presence,
                isSame: present.allSatisfy { $0 == present.first }
            )
        }
    }

    // MARK: - Was auffällt

    public var missing: [Row] { rows.filter(\.isMissingSomewhere) }
    public var differing: [Row] { rows.filter { !$0.isSame } }
    public var everywhere: [Row] { rows.filter(\.isEverywhere) }
    public var problems: [EnvFile.Problem] { files.flatMap(\.problems) }

    /// Was in genau einer Datei steht — meistens das, was jemand lokal
    /// hinzugefügt und nirgends eingetragen hat.
    public func onlyIn(_ index: Int) -> [Row] {
        guard files.indices.contains(index) else { return [] }
        return rows.filter { row in
            row.presence[index] != .missing
                && row.presence.enumerated().allSatisfy { $0.offset == index || $0.element == .missing }
        }
    }

    /// Wonach die Liste gefiltert wird.
    public enum Filter: String, Sendable, Hashable, CaseIterable, Identifiable {
        case all
        case missing
        case differing

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .all: localized("Alle")
            case .missing: localized("Fehlt irgendwo")
            case .differing: localized("Unterschiedlich")
            }
        }

        public var systemImage: String {
            switch self {
            case .all: "list.bullet"
            case .missing: "questionmark.circle"
            case .differing: "arrow.left.arrow.right"
            }
        }
    }

    public func filtered(_ filter: Filter) -> [Row] {
        switch filter {
        case .all: rows
        case .missing: missing
        case .differing: differing
        }
    }

    // MARK: - Ausgeben

    /// Die Spaltenköpfe: Schlüssel, je Datei eine Spalte, dann der Vergleich.
    public var reportColumns: [String] {
        [localized("Schlüssel")] + files.map(\.name) + [localized("Wert")]
    }

    public func rows(_ filter: Filter = .all) -> [[String]] {
        filtered(filter).map { row in
            [row.key]
                + row.presence.map(\.title)
                + [row.isSame ? localized("gleich") : localized("unterschiedlich")]
        }
    }

    /// Der Vergleich als Text — ohne einen einzigen Wert darin.
    public func report(_ filter: Filter = .all) -> String {
        let header = reportColumns.joined(separator: "\t")
        return ([header] + rows(filter).map { $0.joined(separator: "\t") })
            .joined(separator: "\n")
    }

    /// Die fehlenden Zeilen, fertig zum Einfügen — mit leerem Wert.
    public func missingLines(for index: Int) -> String {
        guard files.indices.contains(index) else { return "" }
        return rows
            .filter { $0.presence[index] == .missing }
            .map { "\($0.key)=" }
            .joined(separator: "\n")
    }
}
