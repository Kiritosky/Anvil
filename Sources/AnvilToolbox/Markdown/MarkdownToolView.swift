import AnvilKit
import AnvilUI
import SwiftUI

/// Markdown ansehen, prüfen und mitnehmen.
///
/// Drei Fragen an ein Markdown-Dokument, die man ohne Werkzeug schlecht
/// beantwortet: Wie ist es gegliedert? Wohin zeigt es? Und was stimmt daran
/// nicht — doppelte Überschriften, übersprungene Stufen, Sprungmarken ins
/// Leere. Die Vorschau ist der Nebeneffekt, nicht der Zweck.
public struct MarkdownToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    private enum Output: String, Hashable, CaseIterable, Identifiable {
        case outline
        case links
        case problems
        case html
        case page

        var id: String { rawValue }

        var title: String {
            switch self {
            case .outline: localized("Gliederung")
            case .links: localized("Verweise")
            case .problems: localized("Prüfung")
            case .html: "HTML"
            case .page: localized("Ganze Seite")
            }
        }

        var systemImage: String {
            switch self {
            case .outline: "list.bullet.indent"
            case .links: "link"
            case .problems: "checkmark.seal"
            case .html: "chevron.left.forwardslash.chevron.right"
            case .page: "doc.richtext"
            }
        }
    }

    @State private var input = ""
    @State private var output: Output = .outline
    /// Einmal gelesen statt bei jedem Zugriff — die Statuszeile, der
    /// Inspector und die Ergebnisspalte fragen alle dasselbe Dokument.
    @State private var document = MarkdownDocument("")
    /// Mehrere Dateien auf einmal. Leer heißt: eine einzelne Eingabe.
    @State private var batch = MarkdownBatch([])
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
        .anvilFilesDrop(.text, error: $dropError) { dropped in
            let files = dropped.compactMap { file -> (name: String, text: String)? in
                guard case let .text(text, url) = file else { return nil }
                return (url?.lastPathComponent ?? localized("Ohne Namen"), text)
            }
            guard !files.isEmpty else { return }

            // Eine Datei bleibt eine Eingabe — der Stapel lohnt erst ab zwei,
            // und die Einzelansicht kann mehr.
            if files.count == 1 {
                batch = MarkdownBatch([])
                input = files[0].text
            } else {
                batch = MarkdownBatch(files)
            }
        }
        .onAppear {
            restore()
            document = MarkdownDocument(input)
        }
        .onDisappear(perform: remember)
        .onChange(of: input) { document = MarkdownDocument(input) }
    }

    private func restore() {
        // Hereingereichtes sticht den eigenen Entwurf.
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

    // MARK: - Das Dokument

    private var outputText: String {
        // Im Stapel gibt der Kopieren-Knopf den Bericht heraus — die Ansicht
        // zeigt ja auch keine einzelne Datei.
        if !batch.isEmpty {
            return batch.problemCount > 0
                ? batch.report + "\n\n" + batch.problemReport
                : batch.report
        }
        switch output {
        case .outline: return document.tableOfContents
        case .links: return document.links.map { "\($0.text)\t\($0.target)" }.joined(separator: "\n")
        case .problems:
            return document.problems
                .map { "\($0.line)\t\($0.kind.title)\t\($0.detail)" }
                .joined(separator: "\n")
        case .html: return document.html
        case .page: return document.htmlPage()
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
        AnvilPane("Markdown", systemImage: "text.alignleft") {
            AnvilTextEditor(
                text: $input,
                placeholder: "# Überschrift\n\nText mit einem [Link](https://example.com).",
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
        AnvilPane(
            batch.isEmpty ? .resolved(output.title) : "Stapel",
            systemImage: batch.isEmpty ? output.systemImage : "doc.on.doc",
            tone: .neutral
        ) {
            if !batch.isEmpty {
                batchTable
            } else if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyStateView(
                    title: "Noch kein Text",
                    message: "Markdown einwerfen oder eine Datei ins Fenster ziehen.",
                    systemImage: "text.alignleft"
                )
            } else {
                switch output {
                case .outline: outline(document)
                case .links: linkList(document)
                case .problems: problemList(document)
                case .html, .page: AnvilTextView(outputText, isMonospaced: true)
                }
            }
        } accessory: {
            HStack(spacing: AnvilSpacing.xs) {
                if !batch.isEmpty {
                    Button { batch = MarkdownBatch([]) } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(AnvilIconButtonStyle())
                    .anvilHelp("Stapel schließen")
                }
                HandoffMenu(context: context, from: metadata.id, text: outputText)
                CopyButton(text: outputText)
            }
        }
    }

    // MARK: Der Stapel

    private static let batchColumns = [
        localized("Datei"),
        localized("Wörter"),
        localized("Überschriften"),
        localized("Links"),
        localized("Beanstandungen")
    ]

    @ViewBuilder
    private var batchTable: some View {
        VStack(spacing: 0) {
            DataGrid(
                header: Self.batchColumns,
                rows: batch.entries.map { entry in
                    let statistics = entry.document.statistics
                    return [
                        entry.name,
                        "\(statistics.words)",
                        "\(statistics.headings)",
                        "\(statistics.links)",
                        "\(entry.problemCount)"
                    ]
                }
            )

            if batch.problemCount > 0 {
                AnvilSection(
                    "Was zwischen den Dateien nicht stimmt",
                    subtitle: "Verweise auf Dateien und Sprungmarken, die es nicht gibt"
                ) {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
                            ForEach(batch.entries) { entry in
                                ForEach(entry.crossProblems) { problem in
                                    crossRow(file: entry.name, problem: problem)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: AnvilSize.secondaryListHeight)
                }
                .padding(AnvilSpacing.md)
            }
        }
    }

    private func crossRow(file: String, problem: MarkdownBatch.CrossProblem) -> some View {
        HStack(spacing: AnvilSpacing.sm) {
            StatusPill(.resolved(problem.kind.title), tone: .warning)
            Text(verbatim: "\(file):\(problem.line)")
                .font(AnvilFont.monoSmall)
                .foregroundStyle(AnvilColor.textTertiary)
            Text(verbatim: problem.target)
                .font(AnvilFont.mono)
                .foregroundStyle(AnvilColor.textPrimary)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AnvilSpacing.sm)
        .padding(.vertical, AnvilSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .fill(AnvilColor.surface)
        }
    }

    @ViewBuilder
    private func outline(_ document: MarkdownDocument) -> some View {
        let headings = document.headings
        if headings.isEmpty {
            EmptyStateView(
                title: "Keine Überschriften",
                message: "Ohne Überschriften gibt es nichts zu gliedern — und keine Sprungmarken.",
                systemImage: "number"
            )
        } else {
            let top = headings.map(\.level).min() ?? 1
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                    ForEach(headings) { heading in
                        HStack(spacing: AnvilSpacing.sm) {
                            Text(verbatim: "H\(heading.level)")
                                .font(AnvilFont.monoSmall)
                                .foregroundStyle(AnvilColor.textTertiary)
                                .frame(width: AnvilSize.tableRowNumberWidth, alignment: .leading)

                            Text(verbatim: heading.text)
                                .font(heading.level == top ? AnvilFont.rowTitle : AnvilFont.body)
                                .foregroundStyle(AnvilColor.textPrimary)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Text(verbatim: "#\(heading.anchor)")
                                .font(AnvilFont.monoSmall)
                                .foregroundStyle(AnvilColor.textTertiary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                        // Eingerückt nach der relativen Tiefe: ein Dokument,
                        // das bei H2 anfängt, soll nicht schon beim ersten
                        // Eintrag eingerückt sein.
                        .padding(.leading, CGFloat(heading.level - top) * AnvilSpacing.lg)
                        .padding(.vertical, AnvilSpacing.xs)
                        .padding(.horizontal, AnvilSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                                .fill(AnvilColor.surface)
                        }
                    }
                }
                .padding(AnvilSpacing.md)
            }
        }
    }

    @ViewBuilder
    private func linkList(_ document: MarkdownDocument) -> some View {
        let links = document.links
        if links.isEmpty {
            EmptyStateView(
                title: "Keine Verweise",
                message: "Weder Links noch Bilder im Text.",
                systemImage: "link"
            )
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                    ForEach(links) { link in
                        HStack(spacing: AnvilSpacing.sm) {
                            Image(systemName: link.isImage ? "photo" : "link")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AnvilColor.textTertiary)

                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: link.text.isEmpty ? link.target : link.text)
                                    .font(AnvilFont.body)
                                    .foregroundStyle(AnvilColor.textPrimary)
                                    .lineLimit(1)
                                Text(verbatim: link.target)
                                    .font(AnvilFont.monoSmall)
                                    .foregroundStyle(AnvilColor.textTertiary)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }

                            Spacer(minLength: 0)

                            StatusPill(
                                link.isExternal ? "auswärts" : (link.isAnchor ? "im Dokument" : "Datei"),
                                tone: link.isExternal ? .info : .neutral
                            )
                        }
                        .padding(AnvilSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                                .fill(AnvilColor.surface)
                        }
                    }
                }
                .padding(AnvilSpacing.md)
            }
        }
    }

    @ViewBuilder
    private func problemList(_ document: MarkdownDocument) -> some View {
        let problems = document.problems
        if problems.isEmpty {
            EmptyStateView(
                title: "Nichts zu beanstanden",
                message: "Die Gliederung steigt lückenlos, jede Überschrift ist eindeutig, und alle Sprungmarken gibt es.",
                systemImage: "checkmark.seal",
                tone: .success
            )
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: AnvilSpacing.sm) {
                    ForEach(problems) { problem in
                        AnvilBanner(
                            title: .resolved(problem.kind.title),
                            message: .resolved(localized("Zeile \(problem.line): \(problem.detail)")),
                            tone: .warning
                        )
                    }
                }
                .padding(AnvilSpacing.md)
            }
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if !batch.isEmpty {
            ToolStatusBar {
                StatusMetric("\(batch.entries.count)", label: "Dateien", systemImage: "doc.on.doc")
                StatusMetric("\(batch.wordCount)", label: "Wörter", systemImage: "text.word.spacing")
                StatusMetric(
                    "\(batch.problemCount)",
                    label: "Beanstandungen",
                    systemImage: batch.problemCount == 0 ? "checkmark" : "exclamationmark.triangle",
                    tone: batch.problemCount == 0 ? .success : .warning
                )
            } trailing: {
                StatusPill("Stapel", systemImage: "doc.on.doc", tone: .accent)
            }
        } else {
            singleStatusBar
        }
    }

    private var singleStatusBar: some View {
        let statistics = document.statistics
        return ToolStatusBar {
            StatusMetric("\(statistics.words)", label: "Wörter", systemImage: "text.word.spacing")
            StatusMetric("\(statistics.readingMinutes)", label: "Min. Lesezeit", systemImage: "clock")
            StatusMetric("\(statistics.headings)", label: "Überschriften", systemImage: "number")
            if statistics.tasksOpen + statistics.tasksDone > 0 {
                StatusMetric(
                    "\(statistics.tasksDone)/\(statistics.tasksOpen + statistics.tasksDone)",
                    label: "Aufgaben",
                    systemImage: "checklist",
                    tone: statistics.tasksOpen == 0 ? .success : .accent
                )
            }
        } trailing: {
            let problems = document.problems.count
            StatusPill(
                problems == 0 ? "in Ordnung" : .resolved("\(problems)"),
                systemImage: problems == 0 ? "checkmark" : "exclamationmark.triangle",
                tone: problems == 0 ? .success : .warning
            )
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection("Ansicht", systemImage: "eye") {
            ChipPicker(
                selection: $output,
                options: Output.allCases,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
        }

        InspectorSection(
            "Inhaltsverzeichnis",
            systemImage: "list.bullet.indent",
            footnote: "Setzt die Liste oben in den Text ein, mit Sprungmarken wie auf GitHub."
        ) {
            AnvilButton("Vorne einfügen", systemImage: "text.insert") {
                insertTableOfContents()
            }
            .disabled(document.headings.count < 2)
        }

        InspectorSection("Umfang", systemImage: "chart.bar") {
            let statistics = document.statistics
            KeyValueList([
                KeyValueList.Item(localized("Wörter"), "\(statistics.words)"),
                KeyValueList.Item(localized("Zeichen"), "\(statistics.characters)"),
                KeyValueList.Item(localized("ohne Leerzeichen"), "\(statistics.charactersWithoutSpaces)"),
                KeyValueList.Item(localized("Absätze"), "\(statistics.paragraphs)"),
                KeyValueList.Item(localized("Überschriften"), "\(statistics.headings)"),
                KeyValueList.Item(localized("Links"), "\(statistics.links)"),
                KeyValueList.Item(localized("Bilder"), "\(statistics.images)"),
                KeyValueList.Item(localized("Codeblöcke"), "\(statistics.codeBlocks)")
            ])
        }
    }

    /// Setzt das Inhaltsverzeichnis vor den ersten Abschnitt.
    ///
    /// Hinter die erste Überschrift, nicht davor: über dem Titel steht ein
    /// Inhaltsverzeichnis in keinem Dokument.
    private func insertTableOfContents() {
        let contents = document.tableOfContents
        guard !contents.isEmpty else { return }

        var lines = document.lines
        let insertAt = document.headings.first.map { $0.line } ?? 0
        lines.insert(contentsOf: ["", contents], at: min(insertAt, lines.count))
        input = lines.joined(separator: "\n")
    }
}
