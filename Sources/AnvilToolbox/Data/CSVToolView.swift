import AnvilKit
import AnvilUI
import SwiftUI

/// Eine Tabelle ansehen, sortieren, filtern und woanders hin mitnehmen.
///
/// Der Fall, für den es das gibt: Man bekommt einen Export und will ihn
/// *anschauen*, bevor man ihn irgendwo hineinlädt. Eine Tabellenkalkulation
/// dafür zu starten dauert länger als die Frage, die man hat.
public struct CSVToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    /// Was hinten herauskommt.
    private enum Output: String, Hashable, CaseIterable, Identifiable {
        case table
        case json
        case markdown
        case sql
        case delimited

        var id: String { rawValue }

        var title: String {
            switch self {
            case .table: localized("Tabelle")
            case .json: "JSON"
            case .markdown: "Markdown"
            case .sql: "SQL"
            case .delimited: localized("Als Text")
            }
        }

        var systemImage: String {
            switch self {
            case .table: "tablecells"
            case .json: "curlybraces"
            case .markdown: "text.alignleft"
            case .sql: "cylinder"
            case .delimited: "text.quote"
            }
        }
    }

    @State private var input = ""
    @State private var needle = ""
    @State private var chosenDelimiter: CSVTable.Delimiter?
    @State private var targetDelimiter: CSVTable.Delimiter = .comma
    @State private var hasHeader = true
    @State private var output: Output = .table
    @State private var sortColumn: Int?
    @State private var isAscending = true
    @State private var tableName = "daten"
    @State private var dropError: AnvilError?
    @State private var orientation: WorkbenchOrientation = .horizontal

    /// Die Tabelle wird einmal gelesen und liegt dann herum.
    ///
    /// Als berechnete Eigenschaft sähe das kürzer aus und würde bei jedem
    /// Zugriff neu zerlegen — bei einem Export mit zehntausend Zeilen wären
    /// das mehrere Durchläufe je gezeichnetem Bild.
    @State private var table = CSVTable.empty
    @State private var shown = CSVTable.empty
    @State private var delimiter = CSVTable.Delimiter.comma

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            WorkbenchOrientationPicker(orientation: $orientation)
        }
        .anvilErrorBanner($dropError)
        .anvilFileDrop(.text, error: $dropError) { dropped in
            guard case let .text(text, _) = dropped else { return }
            input = text
            // Eine abgelegte Datei bringt ihr eigenes Trennzeichen mit; eine
            // Wahl von vorhin wäre jetzt die falsche.
            chosenDelimiter = nil
            sortColumn = nil
        }
        .onAppear {
            restore()
            reread()
        }
        .onDisappear(perform: remember)
        .onChange(of: input) { reread() }
        .onChange(of: chosenDelimiter) { reread() }
        .onChange(of: hasHeader) { reread() }
        .onChange(of: needle) { refine() }
        .onChange(of: sortColumn) { refine() }
        .onChange(of: isAscending) { refine() }
    }

    // MARK: - Zurückholen und merken

    private func restore() {
        guard let draft = context.drafts.draft(for: metadata.id) else { return }
        input = draft.input
        needle = draft.extra("needle")
    }

    private func remember() {
        context.drafts.save(
            DraftStore.Draft(input: input, extras: ["needle": needle]),
            for: metadata.id,
            allowed: context.settings[.remembersInput]
        )
    }

    // MARK: - Die Tabelle

    /// Liest den Text neu ein. Nur nötig, wenn sich am Text, am Trennzeichen
    /// oder an der Kopfzeile etwas ändert.
    private func reread() {
        delimiter = chosenDelimiter ?? CSVTable.detectDelimiter(in: input)
        table = CSVTable(parsing: input, delimiter: delimiter, hasHeader: hasHeader)
        // Eine Sortierung nach Spalte 7 ergibt in einer Tabelle mit drei
        // Spalten nichts mehr.
        if let column = sortColumn, !table.header.indices.contains(column) {
            sortColumn = nil
        }
        refine()
    }

    /// Filtert und sortiert das schon Gelesene — das ist billig genug, um bei
    /// jedem Tastendruck im Filterfeld zu laufen.
    private func refine() {
        let filtered = table.filtered(by: needle)
        shown = sortColumn.map { filtered.sorted(by: $0, ascending: isAscending) } ?? filtered
    }

    private var outputText: String {
        switch output {
        case .table, .delimited: shown.text(delimiter: targetDelimiter)
        case .json: shown.json
        case .markdown: shown.markdown
        case .sql: shown.sql(table: tableName)
        }
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            inputPane
        } secondary: {
            resultPane
        } status: {
            statusBar
        }
    }

    private var inputPane: some View {
        AnvilPane("Tabelle", systemImage: "tablecells") {
            AnvilTextEditor(
                text: $input,
                placeholder: "Name,Ort,Umsatz\nAnna,Bremen,1200\nBen,Kiel,980",
                isMonospaced: true
            )
        } accessory: {
            Button { input = context.pasteboard.string() ?? input } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Einfügen")
        }
    }

    private var resultPane: some View {
        AnvilPane(.resolved(output.title), systemImage: output.systemImage, tone: .neutral) {
            if table.isEmpty {
                EmptyStateView(
                    title: "Noch keine Tabelle",
                    message: "CSV, TSV oder mit Semikolon — das Trennzeichen erkennt Anvil selbst.",
                    systemImage: "tablecells"
                )
            } else if shown.rowCount == 0 {
                EmptyStateView(
                    title: "Keine Zeile passt",
                    message: "Der Filter rechts trifft in keiner Spalte.",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            } else if output == .table {
                grid
            } else {
                AnvilTextView(outputText, isMonospaced: true)
            }
        } accessory: {
            CopyButton(text: outputText)
        }
    }

    // MARK: Das Gitter

    private var grid: some View {
        DataGrid(
            header: shown.header,
            rows: shown.rows,
            sortedColumn: sortColumn,
            isAscending: isAscending,
            onSort: sort(by:)
        )
    }

    private func sort(by column: Int) {
        if sortColumn == column {
            // Dritter Klick hebt die Sortierung wieder auf — sonst käme man
            // nie zur ursprünglichen Reihenfolge zurück.
            if isAscending {
                isAscending = false
            } else {
                sortColumn = nil
                isAscending = true
            }
        } else {
            sortColumn = column
            isAscending = true
        }
    }

    // MARK: Statuszeile

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(shown.rowCount)", label: "Zeilen", systemImage: "list.bullet")
            StatusMetric("\(shown.columnCount)", label: "Spalten", systemImage: "tablecells")
            if shown.rowCount != table.rowCount {
                StatusMetric(
                    "\(table.rowCount - shown.rowCount)",
                    label: "ausgeblendet",
                    systemImage: "line.3.horizontal.decrease.circle",
                    tone: .accent
                )
            }
        } trailing: {
            StatusPill(
                .resolved(delimiter.title),
                systemImage: chosenDelimiter == nil ? "wand.and.rays" : "text.cursor",
                tone: .neutral
            )
        }
    }

    // MARK: - Inspector

    /// „Automatisch" steht als leere Wahl vorne — der Typ muss dranstehen,
    /// sonst weiß `nil` in einer Liste nicht, wovon es die Abwesenheit ist.
    private static let delimiterChoices: [CSVTable.Delimiter?] =
        [nil] + CSVTable.Delimiter.allCases.map(Optional.init)

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Trennzeichen",
            systemImage: "text.insert",
            footnote: "Automatisch wählt das Zeichen, das in jeder Zeile gleich oft vorkommt."
        ) {
            ChipPicker(
                selection: $chosenDelimiter,
                options: Self.delimiterChoices,
                title: { $0.map { "\($0.title) \($0.symbol)" } ?? localized("Automatisch") }
            )

            Toggle("Erste Zeile ist die Kopfzeile", isOn: $hasHeader)
                .font(AnvilFont.body)
        }

        InspectorSection("Filtern", systemImage: "line.3.horizontal.decrease.circle") {
            AnvilTextField(text: $needle, placeholder: "Text in irgendeiner Spalte")
        }

        InspectorSection("Ausgabe", systemImage: "arrow.right.doc.on.clipboard") {
            ChipPicker(
                selection: $output,
                options: Output.allCases,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )

            if output == .sql {
                OptionRow("Tabellenname") {
                    AnvilTextField(text: $tableName, placeholder: "daten", isMonospaced: true)
                }
            }

            if output == .table || output == .delimited {
                OptionRow("Beim Kopieren trennen mit") {
                    ChipPicker(
                        selection: $targetDelimiter,
                        options: CSVTable.Delimiter.allCases,
                        title: { "\($0.title) \($0.symbol)" }
                    )
                }
            }
        }

        if !table.isEmpty {
            InspectorSection("Spalten", systemImage: "chart.bar") {
                KeyValueList(shown.summaries.map { summary in
                    KeyValueList.Item(
                        summary.name,
                        columnDescription(summary),
                        tone: summary.isNumeric ? .accent : .neutral
                    )
                })
            }
        }
    }

    /// Was eine Spalte auf einen Blick verrät.
    ///
    /// Bei Zahlen der Bereich — danach fragt man bei Zahlen zuerst. Sonst wie
    /// viele verschiedene Werte darin stehen, denn genau daran erkennt man
    /// eine Kategorie-Spalte.
    private func columnDescription(_ summary: CSVTable.ColumnSummary) -> String {
        if summary.isNumeric, let minimum = summary.minimum, let maximum = summary.maximum {
            return "\(Self.number(minimum)) – \(Self.number(maximum))"
        }
        if summary.empty > 0 {
            return localized("\(summary.distinct) verschiedene, \(summary.empty) leer")
        }
        return localized("\(summary.distinct) verschiedene")
    }

    /// Ohne Nachkommastellen, wo keine nötig sind — „1200" statt „1200,0".
    private static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int(value))
            : String(format: "%.2f", value)
    }
}
