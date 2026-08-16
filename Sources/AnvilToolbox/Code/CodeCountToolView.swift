import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// Woraus ein Projekt besteht — Sprache für Sprache.
public struct CodeCountToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var root: URL?
    @State private var name = ""
    @State private var count = CodeCount.empty
    @State private var isWorking = false
    @State private var error: AnvilError?
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

            if root != nil {
                AnvilButton(
                    "Neu zählen",
                    systemImage: "arrow.clockwise",
                    role: .primary,
                    isBusy: isWorking
                ) {
                    measure()
                }
                .disabled(isWorking)
            }
        }
        .anvilErrorBanner($error)
        .anvilFilesDrop(.file, error: $error) { dropped in
            guard let url = dropped.compactMap(\.url).first else { return }
            open(url)
        }
    }

    // MARK: - Zählen

    private func open(_ url: URL) {
        root = FileWalk.isDirectory(url) ? url : url.deletingLastPathComponent()
        name = root?.lastPathComponent ?? ""
        measure()
    }

    private func chooseFolder() {
        guard let folder = SavePanel.directory(prompt: localized("Ordner wählen")) else { return }
        open(folder)
    }

    private func measure() {
        guard let root, !isWorking else { return }

        Task {
            isWorking = true
            defer { isWorking = false }

            // Lesen und zählen gehen beide über die Platte und über jede
            // Zeile. Auf dem Hauptthread stünde so lange das Fenster.
            count = await Task.detached {
                let files = FileWalk.files(in: root).compactMap { file -> CodeCount.SourceFile? in
                    let path = FileWalk.relativePath(of: file.url, under: root)
                    // Erst prüfen, ob die Datei überhaupt zählt: Eine Datei zu
                    // lesen, um sie danach wegzuwerfen, ist die teuerste Art,
                    // nichts zu tun.
                    guard !CodeLanguage.isIgnored(path),
                          CodeLanguage.of(path: path) != nil,
                          let text = try? TextFile.read(at: file.url)
                    else { return nil }
                    return CodeCount.SourceFile(path: path, text: text)
                }
                return CodeCount.count(files)
            }.value
        }
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            chartPane
        } secondary: {
            tablePane
        } status: {
            statusBar
        }
    }

    @ViewBuilder
    private var chartPane: some View {
        AnvilPane("Sprachen", systemImage: "chart.bar") {
            if root == nil {
                EmptyStateView(
                    title: "Noch kein Projekt",
                    message: "Zieh einen Projektordner hinein. Anvil zählt jede Zeile und sagt, woraus das Projekt besteht.",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    actions: {
                        AnvilButton("Ordner wählen", systemImage: "folder") { chooseFolder() }
                    }
                )
            } else if isWorking {
                EmptyStateView(
                    title: "Wird gezählt",
                    message: "Jede Datei wird einmal gelesen — gerechnet wird nichts zweimal.",
                    systemImage: "hourglass"
                )
            } else if count.isEmpty {
                EmptyStateView(
                    title: "Kein Code gefunden",
                    message: "In diesem Ordner liegt keine Datei in einer Sprache, die Anvil kennt.",
                    systemImage: "questionmark.folder"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AnvilSpacing.md) {
                        composition
                        ForEach(count.entries) { entry in
                            bar(entry)
                        }
                    }
                    .padding(AnvilSpacing.md)
                }
            }
        } accessory: {
            if !count.isEmpty {
                CopyButton(text: count.report)
            }
        }
    }

    /// Der Balken über allem: wie viel davon Code, Kommentar und Leerzeile
    /// ist.
    private var composition: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
            HStack(spacing: AnvilSpacing.sm) {
                legend("Code", color: AnvilColor.accent, value: count.totalCode)
                legend("Kommentar", color: AnvilColor.info, value: count.totalComments)
                legend("Leer", color: AnvilColor.textTertiary, value: count.totalBlanks)
                Spacer(minLength: 0)
            }

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    segment(count.totalCode, of: geometry.size.width, color: AnvilColor.accent)
                    segment(count.totalComments, of: geometry.size.width, color: AnvilColor.info)
                    segment(
                        count.totalBlanks,
                        of: geometry.size.width,
                        color: AnvilColor.textTertiary.opacity(0.4)
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous))
            }
            .frame(height: AnvilSize.barHeight)
        }
        .padding(AnvilSpacing.sm)
        .anvilCard()
    }

    private func legend(_ title: LocalizedStringKey, color: Color, value: Int) -> some View {
        HStack(spacing: AnvilSpacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: AnvilSize.dot, height: AnvilSize.dot)
            Text(title)
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.textSecondary)
            Text.raw("\(value)")
                .font(AnvilFont.caption.monospacedDigit())
                .foregroundStyle(AnvilColor.textTertiary)
        }
    }

    private func segment(_ value: Int, of width: CGFloat, color: Color) -> some View {
        let total = max(count.totalLines, 1)
        return Rectangle()
            .fill(color)
            .frame(width: width * CGFloat(value) / CGFloat(total))
    }

    /// Eine Sprache mit ihrem Anteil als Balken.
    private func bar(_ entry: CodeCount.Entry) -> some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
            HStack(spacing: AnvilSpacing.xs) {
                Text.raw(entry.language)
                    .font(AnvilFont.rowTitle)
                    .foregroundStyle(AnvilColor.textPrimary)
                let fileCount = entry.files
                StatusPill(
                    .resolved(localized("\(fileCount) Dateien")),
                    systemImage: "doc",
                    tone: .neutral
                )
                Spacer(minLength: 0)
                Text.raw(CodeCount.percent(count.share(of: entry)))
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
                Text.raw("\(entry.code)")
                    .font(AnvilFont.monoSmall)
                    .foregroundStyle(AnvilColor.textSecondary)
            }

            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                    .fill(AnvilColor.accent)
                    .frame(width: geometry.size.width * count.share(of: entry))
            }
            .frame(height: AnvilSize.barHeight)
        }
        .padding(AnvilSpacing.sm)
        .anvilCard()
    }

    @ViewBuilder
    private var tablePane: some View {
        AnvilPane("Zahlen", systemImage: "tablecells", tone: .neutral) {
            if count.isEmpty {
                EmptyStateView(
                    title: "Nichts zu zeigen",
                    message: "Sobald gezählt ist, steht hier jede Sprache mit ihren Zeilen.",
                    systemImage: "tablecells"
                )
            } else {
                DataGrid(header: CodeCount.reportColumns, rows: count.rows())
            }
        } accessory: {
            if !count.isEmpty {
                HandoffMenu(context: context, from: metadata.id, text: count.report)
            }
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(count.totalCode)", label: "Zeilen Code", systemImage: "chevron.left.forwardslash.chevron.right", tone: .accent)
            StatusMetric("\(count.entries.count)", label: "Sprachen", systemImage: "globe")
            StatusMetric("\(count.fileCount)", label: "Dateien", systemImage: "doc.on.doc")
            if count.skipped > 0 {
                StatusMetric("\(count.skipped)", label: "übergangen", systemImage: "minus.circle")
            }
        } trailing: {
            if !name.isEmpty {
                StatusPill(.resolved(name), systemImage: "folder", tone: .neutral)
            }
            if count.totalComments > 0 {
                // Erst benennen, dann einsetzen: `CodeCount.percent(…)` liefert
                // Text, sieht aber nach einer Zahl aus — für den Menschen wie
                // für die Übersetzungsprüfung.
                let commentText = CodeCount.percent(commentShare)
                StatusPill(
                    .resolved(localized("\(commentText) Kommentar")),
                    systemImage: "text.bubble",
                    tone: .info
                )
            }
        }
    }

    private var commentShare: Double {
        let written = count.totalCode + count.totalComments
        guard written > 0 else { return 0 }
        return Double(count.totalComments) / Double(written)
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Projekt",
            systemImage: "folder",
            footnote: "Versteckte Ordner bleiben draußen, `node_modules`, `Pods`, `vendor` und `build` auch. Wer wissen will, wie groß sein Projekt ist, meint nicht die Abhängigkeiten."
        ) {
            if let root {
                KeyValueList([KeyValueList.Item(localized("Gezählt"), root.path)])
            }
            AnvilButton("Ordner wählen", systemImage: "folder") { chooseFolder() }
        }

        if !count.isEmpty {
            InspectorSection(
                "Die größten Sprachen",
                systemImage: "chart.pie",
                footnote: "Anteil am Code, nicht an allen Zeilen: Leerzeilen gehören niemandem."
            ) {
                KeyValueList(count.entries.prefix(8).map { entry in
                    KeyValueList.Item(entry.language, CodeCount.percent(count.share(of: entry)))
                })
            }

            InspectorSection(
                "Kommentare",
                systemImage: "text.bubble",
                footnote: "Anteil an den geschriebenen Zeilen — Leerzeilen zählen hier nicht mit."
            ) {
                KeyValueList(count.entries.prefix(8).map { entry in
                    KeyValueList.Item(entry.language, CodeCount.percent(entry.commentShare))
                })
            }
        }

        InspectorNote(
            "Wie gezählt wird",
            systemImage: "info.circle",
            footnote: "Erkannt wird an der Endung, gezählt Zeile für Zeile: leer, Kommentar, oder Code. Das ist eine Faustregel und kein Übersetzer — ein `//` in einer Zeichenkette zählt als Kommentar. In zwanzigtausend Zeilen macht das ein paar aus; es richtig zu bekommen kostet einen Übersetzer je Sprache."
        )
    }
}
