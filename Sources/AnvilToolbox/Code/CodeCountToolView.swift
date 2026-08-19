import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// Woraus ein Projekt besteht — Sprache für Sprache.
public struct CodeCountToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    /// Was gezählt wird — einer oder mehrere. Wer fünf Auschecks
    /// nebeneinander liegen hat, will die Summe und nicht fünf Durchläufe.
    @State private var roots: [URL] = []
    @State private var name = ""
    @State private var count = CodeCount.empty
    @State private var isWorking = false
    @State private var error: AnvilError?
    @State private var orientation: WorkbenchOrientation = .horizontal

    @State private var repositoryName = ""
    @State private var repositories: [GitHubRepository] = []
    @State private var isLoadingList = false
    /// Der Klon, den Anvil selbst angelegt hat — und danach wieder wegräumt.
    @State private var clone: URL?

    private let account = GitHubAccount()
    private var github: GitHubClient { GitHubClient(account: account) }

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

            if !roots.isEmpty {
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
            open(dropped.compactMap(\.url))
        }
    }

    // MARK: - Zählen

    private func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        discardClone()
        roots = urls.map { FileWalk.isDirectory($0) ? $0 : $0.deletingLastPathComponent() }
        name = roots.count == 1
            ? (roots.first?.lastPathComponent ?? "")
            : localized("\(roots.count) Projekte")
        measure()
    }

    // MARK: - Von GitHub

    /// Holt die Liste der eigenen Repositories.
    private func loadRepositories() {
        guard !isLoadingList else { return }
        Task {
            isLoadingList = true
            defer { isLoadingList = false }
            do {
                repositories = try await github.repositories()
            } catch {
                self.error = AnvilError.wrapping(error)
            }
        }
    }

    /// Klont ein Repository flach und zählt es.
    private func count(_ repository: GitHubRepository) {
        guard !isWorking else { return }
        Task {
            isWorking = true

            do {
                discardClone()
                let folder = FileManager.default.temporaryDirectory
                    .appending(path: "anvil-code-\(UUID().uuidString)")
                try FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true
                )

                let checkout = try await github.clone(repository, into: folder)
                clone = folder
                roots = [checkout]
                name = repository.fullName
            } catch {
                self.error = AnvilError.wrapping(error)
                isWorking = false
                return
            }

            isWorking = false
            measure()
        }
    }

    /// Nimmt einen eingetippten Namen oder eine eingefügte Adresse.
    private func countTyped() {
        guard let fullName = GitHubRepository.fullName(from: repositoryName) else {
            error = .invalidInput(localized("Das ist kein Repository — erwartet wird `besitzer/name`."))
            return
        }

        Task {
            do {
                count(try await github.repository(fullName))
            } catch {
                self.error = AnvilError.wrapping(error)
            }
        }
    }

    private func discardClone() {
        guard let clone else { return }
        try? FileManager.default.removeItem(at: clone)
        self.clone = nil
    }

    private func chooseFolder() {
        guard let folder = SavePanel.directory(prompt: localized("Ordner wählen")) else { return }
        open([folder])
    }

    private func measure() {
        let folders = roots
        guard !folders.isEmpty, !isWorking else { return }

        Task {
            isWorking = true
            defer { isWorking = false }

            count = await Task.detached {
                let files = folders.flatMap { folder in
                    FileWalk.files(in: folder).compactMap { file -> CodeCount.SourceFile? in
                        let path = FileWalk.relativePath(of: file.url, under: folder)
                        guard !CodeLanguage.isIgnored(path),
                              CodeLanguage.of(path: path) != nil,
                              let text = try? TextFile.read(at: file.url)
                        else { return nil }
                        return CodeCount.SourceFile(path: path, text: text)
                    }
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
            if roots.isEmpty {
                EmptyStateView(
                    title: "Noch kein Projekt",
                    message: "Zieh einen Projektordner hinein — oder gleich mehrere. Anvil zählt jede Zeile und sagt, woraus das Ganze besteht.",
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
            if roots.count > 1 {
                StatusMetric("\(roots.count)", label: "Projekte", systemImage: "folder")
            }
            if count.skipped > 0 {
                StatusMetric("\(count.skipped)", label: "übergangen", systemImage: "minus.circle")
            }
        } trailing: {
            if !name.isEmpty {
                StatusPill(.resolved(name), systemImage: "folder", tone: .neutral)
            }
            if count.totalComments > 0 {
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
            if !roots.isEmpty {
                KeyValueList(roots.map { folder in
                    KeyValueList.Item(folder.lastPathComponent, folder.deletingLastPathComponent().path)
                })
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

        InspectorSection(
            "Von GitHub",
            systemImage: "chevron.left.forwardslash.chevron.right",
            footnote: account.isConnected
                ? "Verbunden — private Repositories gehen auch. Geklont wird flach, ins temporäre Verzeichnis, und der Klon geht weg, sobald etwas anderes gezählt wird."
                : "Ohne Zugang gehen nur öffentliche Repositories. Das Token kommt in die Einstellungen unter „KI & Konten\" und liegt im Schlüsselbund."
        ) {
            OptionRow("Repository") {
                AnvilTextField(
                    text: $repositoryName,
                    placeholder: "besitzer/name",
                    isMonospaced: true
                )
            }
            AnvilButton("Holen und zählen", systemImage: "arrow.down.circle", isBusy: isWorking) {
                countTyped()
            }
            .disabled(isWorking || repositoryName.isEmpty)

            if account.isConnected {
                AnvilButton("Meine Repositories", systemImage: "list.bullet", isBusy: isLoadingList) {
                    loadRepositories()
                }
                .disabled(isLoadingList)
            }
        }

        if !repositories.isEmpty {
            InspectorSection(
                "Zuletzt bespielt",
                systemImage: "clock",
                footnote: "Ein Klick holt das Repository und zählt es."
            ) {
                ForEach(repositories.prefix(12)) { repository in
                    Button { count(repository) } label: {
                        HStack(spacing: AnvilSpacing.xs) {
                            Image(systemName: repository.isPrivate ? "lock" : "globe")
                                .font(AnvilFont.caption)
                                .foregroundStyle(AnvilColor.textTertiary)
                            Text.raw(repository.fullName)
                                .font(AnvilFont.body)
                                .foregroundStyle(AnvilColor.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                }
            }
        }

        InspectorNote(
            "Wie gezählt wird",
            systemImage: "info.circle",
            footnote: "Erkannt wird an der Endung, gezählt Zeile für Zeile: leer, Kommentar, oder Code. Das ist eine Faustregel und kein Übersetzer — ein `//` in einer Zeichenkette zählt als Kommentar. In zwanzigtausend Zeilen macht das ein paar aus; es richtig zu bekommen kostet einen Übersetzer je Sprache."
        )
    }
}
