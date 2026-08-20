import SwiftUI

/// Eine Tabelle aus Zeichenketten. Sortieren kann sie von sich aus; nur wer
/// die Reihenfolge auch außerhalb der Tabelle braucht, gibt `onSort` mit.
public struct DataGrid: View {
    private let header: [String]
    private let rows: [[String]]
    private let givenColumn: Int?
    private let givenAscending: Bool
    private let onSort: ((Int) -> Void)?

    @State private var own: Sort?

    private struct Sort: Equatable {
        var column: Int
        var ascending: Bool
    }

    /// - Parameter onSort: Übernimmt das Sortieren vollständig — dann bestimmen
    ///   `sortedColumn` und `isAscending`, was der Kopf anzeigt.
    public init(
        header: [String],
        rows: [[String]],
        sortedColumn: Int? = nil,
        isAscending: Bool = true,
        onSort: ((Int) -> Void)? = nil
    ) {
        self.header = header
        self.rows = rows
        self.givenColumn = sortedColumn
        self.givenAscending = isAscending
        self.onSort = onSort
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(shownRows.enumerated()), id: \.offset) { index, row in
                        dataRow(number: index + 1, row: row)
                    }
                } header: {
                    headerRow
                }
            }
        }
    }

    // MARK: - Sortieren

    private var sortsItself: Bool { onSort == nil }

    private var sortedColumn: Int? { sortsItself ? own?.column : givenColumn }

    private var isAscending: Bool { sortsItself ? own?.ascending ?? true : givenAscending }

    private var shownRows: [[String]] {
        guard sortsItself, let own, header.indices.contains(own.column) else { return rows }
        return TableSort.rows(rows, by: own.column, ascending: own.ascending)
    }

    /// Dreimal auf denselben Kopf führt zurück zur ursprünglichen Reihenfolge.
    private func sort(by column: Int) {
        guard sortsItself else {
            onSort?(column)
            return
        }
        if own?.column != column {
            own = Sort(column: column, ascending: true)
        } else if own?.ascending == true {
            own?.ascending = false
        } else {
            own = nil
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text(verbatim: "#")
                .font(AnvilFont.label)
                .foregroundStyle(AnvilColor.textTertiary)
                .frame(width: AnvilSize.tableRowNumberWidth, alignment: .trailing)
                .padding(.trailing, AnvilSpacing.sm)

            ForEach(Array(header.enumerated()), id: \.offset) { index, name in
                Button {
                    withAnimation(AnvilMotion.quick) { sort(by: index) }
                } label: {
                    headerCell(index: index, name: name)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, AnvilSpacing.xs)
        .background(AnvilColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AnvilColor.border)
                .frame(height: AnvilSize.hairline)
        }
    }

    private func headerCell(index: Int, name: String) -> some View {
        HStack(spacing: AnvilSpacing.xs) {
            Text(.resolved(name))
                .font(AnvilFont.rowTitle)
                .lineLimit(1)
            if sortedColumn == index {
                Image(systemName: isAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(sortedColumn == index ? AnvilColor.accent : AnvilColor.textSecondary)
        .frame(width: AnvilSize.tableColumnWidth, alignment: .leading)
        .padding(.horizontal, AnvilSpacing.sm)
        .frame(height: AnvilSize.tableRowHeight)
    }

    private func dataRow(number: Int, row: [String]) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: "\(number)")
                .font(AnvilFont.monoSmall)
                .foregroundStyle(AnvilColor.textTertiary)
                .frame(width: AnvilSize.tableRowNumberWidth, alignment: .trailing)
                .padding(.trailing, AnvilSpacing.sm)

            ForEach(Array(header.indices), id: \.self) { index in
                Text(verbatim: row.indices.contains(index) ? row[index] : "")
                    .font(AnvilFont.monoSmall)
                    .foregroundStyle(AnvilColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(width: AnvilSize.tableColumnWidth, alignment: .leading)
                    .padding(.horizontal, AnvilSpacing.sm)
            }
        }
        .frame(height: AnvilSize.tableRowHeight)
        .background(number.isMultiple(of: 2) ? AnvilColor.surface : Color.clear)
    }
}
