import AnvilKit
import Foundation
import Testing

@testable import AnvilUI

@Suite("Tabellen sortieren")
struct TableSortTests {
    private let table = [
        ["Bild.png", "900 kB", "3"],
        ["Text.md", "1,2 MB", "12"],
        ["Ton.aiff", "40 Bytes", "7"]
    ]

    private func column(_ rows: [[String]], _ index: Int) -> [String] {
        rows.map { $0[index] }
    }

    @Test
    func textIsSortedAlphabetically() {
        let sorted = TableSort.rows(table, by: 0, ascending: true)
        #expect(column(sorted, 0) == ["Bild.png", "Text.md", "Ton.aiff"])
    }

    @Test
    func theOtherDirectionIsTheMirrorImage() {
        let sorted = TableSort.rows(table, by: 0, ascending: false)
        #expect(column(sorted, 0) == ["Ton.aiff", "Text.md", "Bild.png"])
    }

    /// Der eigentliche Punkt: Größen gehören nach ihrem Wert sortiert, nicht
    /// nach ihrer Schreibweise.
    @Test
    func sizesAreSortedByWhatTheyMean() {
        let sorted = TableSort.rows(table, by: 1, ascending: true)
        #expect(column(sorted, 1) == ["40 Bytes", "900 kB", "1,2 MB"])
    }

    /// Als Text wäre „12" kleiner als „3".
    @Test
    func numbersAreSortedAsNumbers() {
        let sorted = TableSort.rows(table, by: 2, ascending: true)
        #expect(column(sorted, 2) == ["3", "7", "12"])
    }

    // MARK: - Ränder

    @Test
    func emptyCellsStayAtTheBottomInBothDirections() {
        let rows = [["b"], [""], ["a"]]
        #expect(column(TableSort.rows(rows, by: 0, ascending: true), 0) == ["a", "b", ""])
        #expect(column(TableSort.rows(rows, by: 0, ascending: false), 0) == ["b", "a", ""])
    }

    /// Gleiche Zellen behalten ihre Reihenfolge — sonst springen Zeilen beim
    /// Sortieren scheinbar grundlos umher.
    @Test
    func equalCellsKeepTheirOrder() {
        let rows = [["gleich", "eins"], ["gleich", "zwei"], ["gleich", "drei"]]
        let sorted = TableSort.rows(rows, by: 0, ascending: false)
        #expect(column(sorted, 1) == ["eins", "zwei", "drei"])
    }

    @Test
    func aShortRowCountsAsEmpty() {
        let sorted = TableSort.rows([["a", "1"], ["b"]], by: 1, ascending: true)
        #expect(sorted.last == ["b"])
    }

    @Test
    func aColumnThatIsNotThereChangesNothing() {
        #expect(TableSort.rows(table, by: 9, ascending: true) == table)
        #expect(TableSort.rows([], by: 0, ascending: true).isEmpty)
    }

    @Test
    func numbersComeBeforeText() {
        #expect(TableSort.compare("7", "sieben") == .orderedAscending)
        #expect(TableSort.compare("sieben", "7") == .orderedDescending)
    }
}
