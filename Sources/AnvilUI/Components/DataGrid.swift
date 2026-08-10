import SwiftUI

/// Eine Tabelle aus Zeichenketten.
///
/// Bewusst nicht SwiftUIs `Table`: die will ihre Spalten zur Übersetzungszeit
/// kennen. Hier stehen sie erst zur Laufzeit fest — sie kommen aus einer
/// Datei, die jemand hineinzieht.
///
/// Kopfzeile und Daten liegen im selben Rollbereich, damit sie beim seitlichen
/// Rollen zusammenbleiben; `pinnedViews` hält den Kopf beim senkrechten Rollen
/// oben fest.
public struct DataGrid: View {
    private let header: [String]
    private let rows: [[String]]
    private let sortedColumn: Int?
    private let isAscending: Bool
    private let onSort: ((Int) -> Void)?

    /// - Parameter onSort: Fehlt es, sind die Spaltenköpfe keine Knöpfe. Eine
    ///   Tabelle, die aussieht, als ließe sie sich sortieren, und es dann nicht
    ///   tut, ist schlimmer als eine, die es gar nicht anbietet.
    public init(
        header: [String],
        rows: [[String]],
        sortedColumn: Int? = nil,
        isAscending: Bool = true,
        onSort: ((Int) -> Void)? = nil
    ) {
        self.header = header
        self.rows = rows
        self.sortedColumn = sortedColumn
        self.isAscending = isAscending
        self.onSort = onSort
    }

    public var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        dataRow(number: index + 1, row: row)
                    }
                } header: {
                    headerRow
                }
            }
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
                if let onSort {
                    Button {
                        withAnimation(AnvilMotion.quick) { onSort(index) }
                    } label: {
                        headerCell(index: index, name: name)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    headerCell(index: index, name: name)
                }
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
        // Jede zweite Zeile getönt: über zehn Spalten hinweg verliert man ohne
        // die Führung die Zeile.
        .background(number.isMultiple(of: 2) ? AnvilColor.surface : Color.clear)
    }
}
