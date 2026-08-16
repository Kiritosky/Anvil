import AnvilKit
import AnvilUI
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// PDFs zusammenführen, teilen, drehen, auslesen — im Stapel.
public struct PDFToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    private enum Operation: String, Hashable, CaseIterable, Identifiable {
        case merge
        case select
        case remove
        case split
        case rotate
        case text

        var id: String { rawValue }

        var title: String {
            switch self {
            case .merge: localized("Zusammenführen")
            case .select: localized("Seiten behalten")
            case .remove: localized("Seiten löschen")
            case .split: localized("Teilen")
            case .rotate: localized("Drehen")
            case .text: localized("Text herausziehen")
            }
        }

        var systemImage: String {
            switch self {
            case .merge: "arrow.triangle.merge"
            case .select: "checkmark.rectangle.stack"
            case .remove: "rectangle.stack.badge.minus"
            case .split: "square.split.1x2"
            case .rotate: "rotate.right"
            case .text: "doc.text"
            }
        }

        /// Ob die Seitenauswahl überhaupt eine Rolle spielt.
        var usesPages: Bool {
            self == .select || self == .remove || self == .rotate
        }

        /// Ob mehrere Dateien Sinn ergeben.
        var isBatch: Bool { self == .merge }
    }

    @State private var files: [URL] = []
    @State private var documents: [PDFDocument] = []
    @State private var operation: Operation = .merge
    @State private var pages = ""
    @State private var splitSize = 1
    @State private var rotation = 90
    @State private var extracted = ""
    @State private var isWorking = false
    @State private var error: AnvilError?
    @State private var note: String?

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
            AnvilButton(
                "Ausführen",
                systemImage: "play.fill",
                role: .primary,
                isBusy: isWorking
            ) {
                run()
            }
            .disabled(documents.isEmpty || isWorking)
        }
        .anvilErrorBanner($error)
        .anvilFilesDrop(.file, error: $error) { dropped in
            add(dropped.compactMap(\.url))
        }
        .onChange(of: operation) { extracted = "" }
    }

    // MARK: - Dateien

    private func add(_ urls: [URL]) {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfs.isEmpty else {
            error = .invalidInput(localized("Das war kein PDF."))
            return
        }

        var seen = Set(files.map(\.path))
        files += pdfs.filter { seen.insert($0.path).inserted }

        let loaded = PDFTools.load(files)
        documents = loaded.documents
        // Die Liste der Dateien und die der Dokumente werden nebeneinander
        // indiziert. Eine Datei, die sich nicht öffnen ließ, muss deshalb aus
        // beiden verschwinden — sonst steht in der Tabelle der falsche Name
        // neben den Seitenzahlen.
        files = files.filter { !loaded.failed.contains($0) }
        if !loaded.failed.isEmpty {
            let names = loaded.failed.map(\.lastPathComponent).joined(separator: ", ")
            error = .invalidInput(localized("Nicht zu öffnen: \(names)"))
        }
    }

    private func choose() {
        guard let folder = SavePanel.directory(prompt: localized("Ordner mit PDFs wählen")) else {
            return
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        add(contents)
    }

    /// Das erste Dokument — worauf sich alles außer dem Zusammenführen
    /// bezieht.
    private var first: PDFDocument? { documents.first }

    private func range(for document: PDFDocument) throws -> PageRange {
        try PageRange(parsing: pages, pageCount: document.pageCount)
    }

    // MARK: - Tun

    private func run() {
        isWorking = true
        note = nil
        error = nil
        do {
            switch operation {
            case .merge: try runMerge()
            case .select, .remove, .rotate: try runSinglePageOperation()
            case .split: try runSplit()
            case .text: try runText()
            }
        } catch {
            self.error = AnvilError.wrapping(error)
        }
        isWorking = false
    }

    private func runMerge() throws {
        let merged = try PDFTools.merge(documents)
        guard let url = SavePanel.url(suggestedName: localized("Zusammengeführt"), type: .pdf) else {
            return
        }
        try PDFTools.write(merged, to: url)
        note = localized("\(String(merged.pageCount)) Seiten geschrieben.")
    }

    private func runSinglePageOperation() throws {
        guard let document = first else { return }
        let selection = try range(for: document)

        let result: PDFDocument
        switch operation {
        case .select: result = try PDFTools.select(selection, from: document)
        case .remove: result = try PDFTools.removing(selection, from: document)
        default: result = try PDFTools.rotated(document, by: rotation, pages: selection)
        }

        guard let url = SavePanel.url(
            suggestedName: files[0].deletingPathExtension().lastPathComponent,
            type: .pdf
        ) else { return }
        try PDFTools.write(result, to: url)
        note = localized("\(String(result.pageCount)) Seiten geschrieben.")
    }

    private func runSplit() throws {
        guard let document = first else { return }
        let parts = try PDFTools.split(document, every: splitSize)
        guard let folder = SavePanel.directory(prompt: localized("Wohin damit?")) else { return }

        let stem = files[0].deletingPathExtension().lastPathComponent
        for (index, part) in parts.enumerated() {
            let url = ExportFile.uniqueURL(
                in: folder,
                named: "\(stem)-\(index + 1)",
                extension: "pdf"
            )
            try PDFTools.write(part, to: url)
        }
        note = localized("\(String(parts.count)) Dateien geschrieben.")
    }

    private func runText() throws {
        // Bei mehreren Dateien bekommt jeder Block seinen Namen davor — sonst
        // weiß nach dem Einfügen niemand mehr, was woher kam.
        extracted = TextBlocks.combine(
            documents.enumerated().map { index, document in
                (name: files[index].lastPathComponent, text: PDFTools.text(of: document))
            }
        )
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            AnvilPane("Dateien", systemImage: "doc.on.doc", tone: .neutral) {
                if files.isEmpty {
                    EmptyStateView(
                        title: "Noch keine PDFs",
                        message: "Dateien ins Fenster ziehen — oder einen Ordner wählen.",
                        systemImage: "doc.richtext",
                        actions: {
                            AnvilButton("Ordner wählen", systemImage: "folder") { choose() }
                        }
                    )
                } else if operation == .text, !extracted.isEmpty {
                    AnvilTextView(extracted, isMonospaced: false)
                } else {
                    DataGrid(header: Self.columns, rows: rows)
                }
            } accessory: {
                if !files.isEmpty {
                    HStack(spacing: AnvilSpacing.xs) {
                        if operation == .text, !extracted.isEmpty {
                            CopyButton(text: extracted)
                        }
                        ClearButton {
                            files = []
                            documents = []
                            extracted = ""
                        }
                    }
                }
            }

            if let note {
                AnvilBanner(title: .resolved(note), tone: .success, onDismiss: { self.note = nil })
                    .padding(AnvilSpacing.md)
            }

            ToolStatusBar {
                StatusMetric("\(files.count)", label: "Dateien", systemImage: "doc.on.doc")
                StatusMetric("\(totalPages)", label: "Seiten", systemImage: "doc.plaintext")
                if operation.usesPages, let document = first,
                   let selection = try? range(for: document) {
                    StatusMetric(
                        "\(selection.count)",
                        label: "ausgewählt",
                        systemImage: "checkmark",
                        tone: .accent
                    )
                }
            } trailing: {
                StatusPill(.resolved(operation.title), systemImage: operation.systemImage, tone: .accent)
            }
        }
    }

    private var totalPages: Int {
        documents.reduce(0) { $0 + $1.pageCount }
    }

    private static let columns = [
        localized("Datei"),
        localized("Seiten"),
        localized("Größe"),
        localized("Text")
    ]

    private var rows: [[String]] {
        documents.enumerated().map { index, document in
            let info = PDFTools.info(of: document)
            return [
                files[index].lastPathComponent,
                "\(info.pageCount)",
                "\(info.width) × \(info.height)",
                info.hasText ? localized("ja") : localized("nein")
            ]
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Was tun",
            systemImage: "wrench.and.screwdriver",
            footnote: operation.isBatch
                ? "Zusammengeführt wird in der Reihenfolge der Liste."
                : "Alles außer dem Zusammenführen bezieht sich auf die erste Datei."
        ) {
            ChipPicker(
                selection: $operation,
                options: Operation.allCases,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
        }

        if operation.usesPages {
            InspectorSection(
                "Seiten",
                systemImage: "number",
                footnote: "1-3, 5, 8- — wie im Druckdialog. Leer heißt alle. Was es nicht gibt, fällt weg."
            ) {
                AnvilTextField(text: $pages, placeholder: "1-3, 5", isMonospaced: true)
            }
        }

        if operation == .split {
            InspectorSection(
                "Teilen",
                systemImage: "square.split.1x2",
                footnote: "Jeder Teil wird eine eigene Datei, durchnummeriert."
            ) {
                OptionRow("Seiten je Teil") {
                    AnvilStepper(value: $splitSize, in: 1...500)
                }
            }
        }

        if operation == .rotate {
            InspectorSection(
                "Drehen",
                systemImage: "rotate.right",
                footnote: "Wird auf die vorhandene Drehung aufgeschlagen."
            ) {
                ChipPicker(
                    selection: $rotation,
                    options: [90, 180, 270],
                    title: { "\($0)°" }
                )
            }
        }

        if let document = first {
            InspectorSection("Erste Datei", systemImage: "info.circle") {
                let info = PDFTools.info(of: document)
                KeyValueList([
                    KeyValueList.Item(localized("Seiten"), "\(info.pageCount)"),
                    KeyValueList.Item(localized("Größe"), "\(info.width) × \(info.height)"),
                    KeyValueList.Item(
                        localized("Titel"),
                        info.title.isEmpty ? "—" : info.title
                    ),
                    KeyValueList.Item(
                        localized("Textschicht"),
                        info.hasText ? localized("ja") : localized("nein"),
                        tone: info.hasText ? .success : .warning
                    )
                ])
            }
        }

        InspectorSection(
            "Wovon Anvil die Finger lässt",
            systemImage: "hand.raised",
            footnote: "Geschrieben wird immer eine neue Datei. Die Vorlage bleibt, wie sie ist — auch dann, wenn beim Schreiben etwas schiefgeht."
        ) {
            AnvilButton("Ordner wählen", systemImage: "folder") { choose() }
        }
    }
}
