import AnvilKit
import AnvilUI
import SwiftUI

/// Eine ganze Farbliste prüfen und ausgeben.
public struct ColorPaletteToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    private enum Output: String, Hashable, CaseIterable, Identifiable {
        case table
        case css
        case swift

        var id: String { rawValue }

        var title: String {
            switch self {
            case .table: localized("Tabelle")
            case .css: "CSS"
            case .swift: "SwiftUI"
            }
        }

        var systemImage: String {
            switch self {
            case .table: "tablecells"
            case .css: "curlybraces"
            case .swift: "swift"
            }
        }
    }

    @State private var input = ""
    @State private var output: Output = .table
    @State private var palette = ColorPalette.empty
    @State private var dropError: AnvilError?
    @State private var orientation: WorkbenchOrientation = .horizontal

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
        }
        .onAppear {
            restore()
            read()
        }
        .onDisappear(perform: remember)
        .onChange(of: input) { read() }
    }

    // MARK: - Zurückholen und merken

    private func restore() {
        if let handed = context.handoff.take(for: metadata.id) {
            input = handed
            return
        }
        guard let draft = context.drafts.draft(for: metadata.id) else { return }
        input = draft.input
    }

    private func remember() {
        context.drafts.save(
            DraftStore.Draft(input: input),
            for: metadata.id,
            allowed: context.settings[.remembersInput]
        )
    }

    private func read() {
        palette = ColorPalette(input)
    }

    private var outputText: String {
        switch output {
        case .table: palette.report
        case .css: palette.css
        case .swift: palette.swift
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
        AnvilPane("Farben", systemImage: "paintpalette") {
            AnvilTextEditor(
                text: $input,
                placeholder: "--marke: #3A7BD5;\nHintergrund #FFFFFF\nrgb(58, 123, 213)",
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

    @ViewBuilder
    private var resultPane: some View {
        AnvilPane(.resolved(output.title), systemImage: output.systemImage, tone: .neutral) {
            if palette.isEmpty {
                EmptyStateView(
                    title: "Noch keine Liste",
                    message: "Eine Farbe je Zeile. Namen davor stören nicht — auch nicht die Schreibweise aus einer Stilvorlage.",
                    systemImage: "paintpalette"
                )
            } else if output == .table {
                DataGrid(
                    header: ColorPalette.reportColumns,
                    rows: palette.entries.map { palette.row($0) }
                )
            } else {
                AnvilTextView(outputText, isMonospaced: true)
            }
        } accessory: {
            HStack(spacing: AnvilSpacing.xs) {
                HandoffMenu(context: context, from: metadata.id, text: outputText)
                CopyButton(text: outputText)
            }
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(palette.readable.count)", label: "Farben", systemImage: "paintpalette")
            if !palette.unreadable.isEmpty {
                StatusMetric(
                    "\(palette.unreadable.count)",
                    label: "nicht erkannt",
                    systemImage: "questionmark.circle",
                    tone: .warning
                )
            }
            if !twins.isEmpty {
                StatusMetric(
                    "\(twins.count)",
                    label: "Doppelgänger",
                    systemImage: "circle.on.circle",
                    tone: .accent
                )
            }
        } trailing: {
            if !palette.isEmpty, twins.isEmpty, palette.unreadable.isEmpty {
                StatusPill("alles sauber", systemImage: "checkmark", tone: .success)
            }
        }
    }

    private var twins: [ColorPalette.Twin] { palette.twins() }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection("Ausgabe", systemImage: "arrow.right.doc.on.clipboard") {
            ChipPicker(
                selection: $output,
                options: Output.allCases,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
        }

        if !twins.isEmpty {
            InspectorSection(
                "Doppelgänger",
                systemImage: "circle.on.circle",
                footnote: "Farben, die sich in keinem Kanal um mehr als drei von 255 unterscheiden. Auf zwei Bildschirmen nebeneinander sieht die niemand auseinander."
            ) {
                KeyValueList(twins.prefix(20).map { twin in
                    KeyValueList.Item(
                        "\(twin.first.label) · \(twin.second.label)",
                        twin.isIdentical ? localized("dieselbe Farbe") : localized("fast dieselbe"),
                        tone: twin.isIdentical ? .warning : .neutral
                    )
                })
            }
        }

        if !palette.unreadable.isEmpty {
            InspectorSection(
                "Nicht erkannt",
                systemImage: "questionmark.circle",
                footnote: "Erkannt werden #RGB, #RRGGBB, rgb(), rgba(), hsl(), hsla() und eine Handvoll Namen."
            ) {
                KeyValueList(palette.unreadable.prefix(20).map { entry in
                    KeyValueList.Item(entry.source, localized("keine Farbe"), tone: .warning)
                })
            }
        }

        InspectorNote(
            "Kontrast",
            systemImage: "circle.lefthalf.filled",
            footnote: "Die beiden letzten Spalten sagen, wie sich die Farbe auf Weiß und auf Schwarz liest. 4,5:1 ist die Grenze für Fließtext, 3:1 für große Schrift."
        )
    }
}
