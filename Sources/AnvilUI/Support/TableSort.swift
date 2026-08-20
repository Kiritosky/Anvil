import AnvilKit
import Foundation

/// Sortiert Tabellenzeilen nach einer Spalte — Zahlen als Zahlen, alles
/// andere alphabetisch, Leeres immer zuletzt.
public enum TableSort {
    public static func rows(_ rows: [[String]], by column: Int, ascending: Bool) -> [[String]] {
        let numbered = Array(rows.enumerated())
        let filled = numbered.filter { !cell($0.element, column).isEmpty }
        let empty = numbered.filter { cell($0.element, column).isEmpty }

        let sorted = filled.sorted { left, right in
            let order = compare(cell(left.element, column), cell(right.element, column))
            guard order != .orderedSame else { return left.offset < right.offset }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }

        return (sorted + empty).map(\.element)
    }

    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = NumericText.leadingValue(in: lhs)
        let right = NumericText.leadingValue(in: rhs)

        switch (left, right) {
        case let (left?, right?) where left != right:
            return left < right ? .orderedAscending : .orderedDescending
        case (.some, nil):
            return .orderedAscending
        case (nil, .some):
            return .orderedDescending
        default:
            return lhs.localizedStandardCompare(rhs)
        }
    }

    private static func cell(_ row: [String], _ column: Int) -> String {
        guard row.indices.contains(column) else { return "" }
        return row[column].trimmingCharacters(in: .whitespaces)
    }
}
