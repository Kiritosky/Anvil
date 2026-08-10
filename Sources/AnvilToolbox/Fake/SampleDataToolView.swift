import AnvilKit
import AnvilUI
import SwiftUI

/// Testdaten erzeugen — dieselben bei demselben Startwert.
public struct SampleDataToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    private enum Output: String, Hashable, CaseIterable, Identifiable {
        case table
        case csv
        case json
        case sql

        var id: String { rawValue }

        var title: String {
            switch self {
            case .table: localized("Tabelle")
            case .csv: "CSV"
            case .json: "JSON"
            case .sql: "SQL"
            }
        }

        var systemImage: String {
            switch self {
            case .table: "tablecells"
            case .csv: "text.quote"
            case .json: "curlybraces"
            case .sql: "cylinder"
            }
        }
    }

    @State private var count = 25
    @State private var fields: [SampleData.Field] = SampleData.Field.common
    @State private var region: SampleData.Region = .german
    @State private var seed: UInt64 = 1
    @State private var output: Output = .table
    @State private var tableName = "daten"
    @State private var data = SampleData(count: 25, fields: SampleData.Field.common)
    /// Die Tabelle daneben, damit sie nicht bei jedem Zugriff neu entsteht.
    @State private var table = CSVTable.empty

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
            AnvilButton("Neu würfeln", systemImage: "die.face.5") {
                // Ein neuer Startwert, nicht echter Zufall: das Ergebnis
                // bleibt wiederholbar, es ist nur ein anderes.
                seed = UInt64.random(in: 1...9_999_999)
            }
        }
        .onAppear(perform: generate)
        .onChange(of: count) { generate() }
        .onChange(of: fields) { generate() }
        .onChange(of: region) { generate() }
        .onChange(of: seed) { generate() }
    }

    private func generate() {
        data = SampleData(count: count, fields: fields, region: region, seed: seed)
        table = data.table
    }

    // MARK: - Content

    private var outputText: String {
        switch output {
        case .table, .csv: return table.text(delimiter: .comma)
        case .json: return table.json
        case .sql: return table.sql(table: tableName)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            AnvilPane(.resolved(output.title), systemImage: output.systemImage, tone: .neutral) {
                if data.rows.isEmpty {
                    EmptyStateView(
                        title: "Keine Zeilen",
                        message: "Rechts einstellen, wie viele es sein sollen.",
                        systemImage: "tablecells"
                    )
                } else if output == .table {
                    DataGrid(header: table.header, rows: table.rows)
                } else {
                    AnvilTextView(outputText, isMonospaced: true)
                }
            } accessory: {
                CopyButton(text: outputText)
            }

            ToolStatusBar {
                StatusMetric("\(data.rows.count)", label: "Zeilen", systemImage: "list.bullet")
                StatusMetric("\(fields.count)", label: "Spalten", systemImage: "tablecells")
                StatusMetric("\(seed)", label: "Startwert", systemImage: "die.face.5", tone: .accent)
            } trailing: {
                StatusPill(.resolved(region.title), tone: .neutral)
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Umfang",
            systemImage: "number",
            footnote: "Mehr als tausend Zeilen zeigt niemand mehr an, gebraucht werden sie trotzdem."
        ) {
            OptionRow("Zeilen") {
                Stepper(value: $count, in: 1...10_000, step: stepSize) {
                    Text(verbatim: "\(count)")
                        .font(AnvilFont.mono)
                }
            }
        }

        InspectorSection(
            "Startwert",
            systemImage: "die.face.5",
            footnote: "Derselbe Startwert ergibt dieselbe Tabelle — auf jedem Rechner, zu jeder Zeit. Genau deshalb steht er hier und ist nicht versteckt."
        ) {
            OptionRow("Zahl") {
                Stepper(value: seedValue, in: 1...9_999_999) {
                    Text(verbatim: "\(seed)")
                        .font(AnvilFont.mono)
                }
            }
        }

        InspectorSection(
            "Spalten",
            systemImage: "tablecells",
            footnote: "Die Reihenfolge folgt der Liste, nicht der Reihenfolge des Anklickens."
        ) {
            FlowLayout(spacing: AnvilSpacing.xs, lineSpacing: AnvilSpacing.xs) {
                ForEach(SampleData.Field.allCases) { field in
                    Chip(
                        title: field.title,
                        isSelected: fields.contains(field)
                    ) {
                        toggle(field)
                    }
                }
            }
        }

        InspectorSection("Sprachraum", systemImage: "globe") {
            ChipPicker(
                selection: $region,
                options: SampleData.Region.allCases,
                title: { $0.title }
            )
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
        }
    }

    /// Ein `Stepper` will einen `Int`; der Startwert ist ein `UInt64`, weil er
    /// im Erzeuger einer ist.
    private var seedValue: Binding<Int> {
        Binding(
            get: { Int(clamping: seed) },
            set: { seed = UInt64(max(1, $0)) }
        )
    }

    /// Bis fünfzig in Einerschritten, danach in Zehnern: Wer 2000 Zeilen will,
    /// klickt sonst zweitausendmal.
    private var stepSize: Int {
        switch count {
        case ..<50: 1
        case ..<500: 10
        default: 100
        }
    }

    private func toggle(_ field: SampleData.Field) {
        if let index = fields.firstIndex(of: field) {
            // Die letzte Spalte bleibt: eine Tabelle ohne Spalten ist keine.
            guard fields.count > 1 else { return }
            fields.remove(at: index)
        } else {
            fields.append(field)
            // Nach der festen Reihenfolge des Aufzählungstyps sortiert, damit
            // die Spalten nicht davon abhängen, was man zuerst angeklickt hat.
            fields.sort { left, right in
                let order = SampleData.Field.allCases
                return (order.firstIndex(of: left) ?? 0) < (order.firstIndex(of: right) ?? 0)
            }
        }
    }
}
