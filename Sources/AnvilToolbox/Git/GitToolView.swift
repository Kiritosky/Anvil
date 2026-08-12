import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// Der Blick über alle Repositories auf diesem Mac.
///
/// Die Frage, die dieses Werkzeug beantwortet, stellt sich vor jedem Urlaub und
/// vor jedem Rechnerwechsel: Liegt irgendwo noch Arbeit, die es nur hier gibt?
/// Beantworten lässt sie sich heute nur, indem man dreißig Ordner einzeln
/// aufmacht — und genau deshalb macht es niemand.
public struct GitToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var root: URL?
    @State private var overview = GitOverview.empty
    @State private var selectedPath: String?
    @State private var filter: GitOverview.Filter = .all
    @State private var depth = RepositoryScan.defaultDepth
    @State private var isWorking = false
    @State private var scanned = 0
    @State private var total = 0
    @State private var hasNoGit = false
    @State private var error: AnvilError?
    @State private var note: String?
    @State private var orientation: WorkbenchOrientation = .horizontal

    private let reader = GitReader()

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
                AnvilButton("Alle holen", systemImage: "arrow.down.circle", isBusy: isWorking) {
                    fetchAll()
                }
                .disabled(isWorking || overview.isEmpty)

                AnvilButton(
                    "Neu einlesen",
                    systemImage: "arrow.clockwise",
                    role: .primary,
                    isBusy: isWorking
                ) {
                    rescan()
                }
                .disabled(isWorking)
            }
        }
        .anvilErrorBanner($error)
        .anvilFilesDrop(.any, error: $error) { dropped in
            guard let folder = dropped.compactMap(\.url).first else { return }
            open(folder)
        }
    }

    // MARK: - Einlesen

    private func open(_ folder: URL) {
        // Wer eine Datei aus einem Repository hineinzieht, meint den Ordner
        // darum — nicht die Datei.
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
        root = isDirectory.boolValue ? folder : folder.deletingLastPathComponent()
        rescan()
    }

    private func chooseFolder() {
        guard let folder = SavePanel.directory(prompt: localized("Ordner wählen")) else { return }
        open(folder)
    }

    private func rescan() {
        guard let root else { return }
        Task { await scan(root) }
    }

    private func scan(_ folder: URL) async {
        isWorking = true
        defer { isWorking = false }

        note = nil
        selectedPath = nil
        hasNoGit = false

        guard await reader.isAvailable() else {
            hasNoGit = true
            overview = .empty
            return
        }

        let folders = RepositoryScan.repositories(under: folder, maxDepth: depth)
        total = folders.count
        scanned = 0
        overview = .empty

        // Schwungweise statt alles auf einmal: So wächst die Liste sichtbar,
        // statt dass der Benutzer eine halbe Minute lang auf nichts schaut.
        var collected: [GitRepository] = []
        for start in stride(from: 0, to: folders.count, by: GitReader.batchSize) {
            let end = min(start + GitReader.batchSize, folders.count)
            collected += await reader.read(Array(folders[start..<end]))
            scanned = collected.count
            overview = GitOverview(collected)
        }
    }

    /// Die Massenaktion, um die es hier eigentlich geht.
    ///
    /// Geholt wird, was gerade in der Liste steht — nicht immer alles. Wer auf
    /// „Hinterher" gefiltert hat, meint genau diese.
    private func fetchAll() {
        let targets = overview.filtered(filter)
        guard !targets.isEmpty else { return }

        Task {
            isWorking = true
            note = nil
            total = targets.count
            scanned = 0

            var failures = 0
            for repository in targets {
                do {
                    try await reader.fetch(repository.url)
                } catch {
                    failures += 1
                }
                scanned += 1
            }

            if let root {
                await scan(root)
            }
            isWorking = false
            note = failures == 0
                ? localized("Alle \(targets.count) Repositories geholt.")
                : localized("\(failures) von \(targets.count) ließen sich nicht holen.")
        }
    }

    // MARK: - Auswahl

    private var shown: [GitRepository] { overview.filtered(filter) }

    private var selected: GitRepository? {
        selectedPath.flatMap { path in overview.repositories.first { $0.id == path } }
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            listPane
        } secondary: {
            detailPane
        } status: {
            statusBar
        }
    }

    @ViewBuilder
    private var listPane: some View {
        AnvilPane("Repositories", systemImage: "folder.badge.gearshape") {
            if hasNoGit {
                EmptyStateView(
                    title: "Kein git gefunden",
                    message: "Installiere die Command Line Tools mit „xcode-select --install\" — danach findet Anvil es von selbst.",
                    systemImage: "exclamationmark.triangle"
                )
            } else if root == nil {
                EmptyStateView(
                    title: "Noch kein Ordner",
                    message: "Zieh den Ordner hinein, in dem deine Projekte liegen. Anvil sucht darin nach Repositories.",
                    systemImage: "folder",
                    actions: {
                        AnvilButton("Ordner wählen", systemImage: "folder") { chooseFolder() }
                    }
                )
            } else if shown.isEmpty {
                EmptyStateView(
                    title: isWorking ? "Wird gelesen" : "Nichts dabei",
                    message: isWorking
                        ? "Einen Moment — die Repositories werden der Reihe nach gelesen."
                        : "In diesem Ordner liegt nichts, was zum Filter passt.",
                    systemImage: isWorking ? "hourglass" : "magnifyingglass"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: AnvilSpacing.xxs) {
                        ForEach(shown) { repository in
                            Button {
                                selectedPath = selectedPath == repository.id ? nil : repository.id
                            } label: {
                                RepositoryRow(
                                    repository: repository,
                                    isSelected: selectedPath == repository.id
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Im Finder zeigen") { reveal(repository.url) }
                                Button("Pfad kopieren") {
                                    context.pasteboard.copy(repository.url.path)
                                }
                            }
                        }
                    }
                    .padding(AnvilSpacing.sm)
                }
            }
        } accessory: {
            if isWorking, total > 0 {
                ProgressStrip(
                    "Repositories",
                    progress: Double(scanned) / Double(total),
                    tone: .accent
                )
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        AnvilPane(
            .resolved(selected?.name ?? localized("Übersicht")),
            systemImage: selected == nil ? "list.bullet.rectangle" : "shippingbox",
            tone: .neutral
        ) {
            if let repository = selected {
                detail(of: repository)
            } else if overview.isEmpty {
                EmptyStateView(
                    title: "Nichts zu zeigen",
                    message: "Sobald ein Ordner gelesen ist, steht hier die Übersicht.",
                    systemImage: "list.bullet.rectangle"
                )
            } else {
                DataGrid(
                    header: GitOverview.reportColumns,
                    rows: shown.map(GitOverview.row)
                )
            }
        } accessory: {
            if !overview.isEmpty {
                HStack(spacing: AnvilSpacing.xs) {
                    HandoffMenu(context: context, from: metadata.id, text: overview.report(filter))
                    CopyButton(text: overview.report(filter))
                }
            }
        }

        if let note {
            AnvilBanner(title: .resolved(note), tone: .success, onDismiss: { self.note = nil })
                .padding(AnvilSpacing.md)
        }
    }

    @ViewBuilder
    private func detail(of repository: GitRepository) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AnvilSpacing.lg) {
                if let failure = repository.failure {
                    AnvilBanner(title: "git kam nicht durch", message: .resolved(failure), tone: .danger)
                }

                KeyValueList(facts(of: repository))

                if !repository.status.changes.isEmpty {
                    labelled("Was sich geändert hat", systemImage: "pencil") {
                        DataGrid(
                            header: [localized("Wo"), localized("Art"), localized("Datei")],
                            rows: repository.status.changes.map { change in
                                [change.stage.title, change.code, change.path]
                            }
                        )
                        .frame(height: AnvilSize.resultMinHeight)
                    }
                }

                if !repository.branches.isEmpty {
                    labelled("Zweige", systemImage: "arrow.triangle.branch") {
                        DataGrid(
                            header: [
                                localized("Zweig"),
                                localized("Zuletzt"),
                                localized("Voraus"),
                                localized("Zurück"),
                                localized("Hinweis")
                            ],
                            rows: repository.branches.map(Self.branchRow)
                        )
                        .frame(height: AnvilSize.resultMinHeight)
                    }
                }
            }
            .padding(AnvilSpacing.md)
        }
    }

    private func facts(of repository: GitRepository) -> [KeyValueList.Item] {
        let status = repository.status
        var items: [KeyValueList.Item] = [
            KeyValueList.Item(
                localized("Zweig"),
                status.branch ?? localized("abgelöster HEAD"),
                tone: status.branch == nil ? .warning : .neutral
            )
        ]
        items.append(
            KeyValueList.Item(
                localized("Gegenstück"),
                status.upstream ?? localized("keins"),
                tone: status.upstream == nil ? .warning : .neutral
            )
        )
        if status.ahead > 0 {
            items.append(KeyValueList.Item(
                localized("Nur hier"),
                localized("\(status.ahead) Commits"),
                tone: .accent
            ))
        }
        if status.behind > 0 {
            items.append(KeyValueList.Item(
                localized("Nur dort"),
                localized("\(status.behind) Commits")
            ))
        }
        for stage in GitStatus.Change.Stage.allCases where status.count(stage) > 0 {
            items.append(KeyValueList.Item(
                stage.title,
                "\(status.count(stage))",
                tone: stage == .conflicted ? .danger : .neutral
            ))
        }
        items.append(KeyValueList.Item(localized("Ordner"), repository.url.path))
        return items
    }

    private static func branchRow(_ branch: GitBranch) -> [String] {
        [
            branch.isCurrent ? "● " + branch.name : branch.name,
            branch.age().map { days in localized("vor \(days) Tagen") } ?? "—",
            "\(branch.ahead)",
            "\(branch.behind)",
            branch.isStale
                ? localized("kann weg")
                : (branch.isGone ? localized("Gegenstück weg") : (branch.upstream ?? localized("nur lokal")))
        ]
    }

    @ViewBuilder
    private func labelled<Content: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
            HStack(spacing: AnvilSpacing.xs) {
                Image(systemName: systemImage)
                    .font(AnvilFont.label)
                Text(title)
                    .font(AnvilFont.sectionTitle)
            }
            .foregroundStyle(AnvilColor.textSecondary)

            content()
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Statuszeile

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(overview.count)", label: "Repositories", systemImage: "shippingbox")
            if !overview.dirty.isEmpty {
                StatusMetric(
                    "\(overview.dirty.count)",
                    label: "geändert",
                    systemImage: "pencil",
                    tone: .accent
                )
            }
            if !overview.ahead.isEmpty {
                StatusMetric(
                    "\(overview.ahead.count)",
                    label: "nicht gepusht",
                    systemImage: "arrow.up",
                    tone: .warning
                )
            }
            if overview.staleBranchCount > 0 {
                StatusMetric(
                    "\(overview.staleBranchCount)",
                    label: "alte Zweige",
                    systemImage: "arrow.triangle.branch"
                )
            }
        } trailing: {
            if isWorking {
                StatusPill("liest", systemImage: "hourglass", tone: .accent)
            } else if overview.needingAttention.isEmpty, !overview.isEmpty {
                StatusPill("alles sauber", systemImage: "checkmark", tone: .success)
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Ordner",
            systemImage: "folder",
            footnote: "Anvil sucht nur nach Repositories und öffnet keines. Gelesen wird, was git ohnehin verrät."
        ) {
            if let root {
                KeyValueList([KeyValueList.Item(localized("Gewählt"), root.path)])
            }
            AnvilButton("Ordner wählen", systemImage: "folder") { chooseFolder() }
        }

        InspectorSection(
            "Suchtiefe",
            systemImage: "arrow.down.right",
            footnote: "Wie viele Ebenen unter dem Ordner gesucht wird. Ein gefundenes Repository wird nicht weiter durchsucht."
        ) {
            OptionRow("Ebenen") {
                AnvilStepper(value: $depth, in: 1...6)
            }
        }

        InspectorSection(
            "Zeigen",
            systemImage: "line.3.horizontal.decrease.circle",
            footnote: "„Auffällig\" heißt: etwas ist nicht gepusht, nicht committet, oder ein Zweig kann weg. „Kann weg\" wiederum heißt: Das Gegenstück auf dem Server ist gelöscht und lokal liegt kein eigener Commit mehr darauf. Anvil löscht nichts — es sagt nur, wo etwas liegt."
        ) {
            ChipPicker(
                selection: $filter,
                options: GitOverview.Filter.allCases,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
        }

        if !overview.failed.isEmpty {
            InspectorSection(
                "Nicht gelesen",
                systemImage: "exclamationmark.triangle",
                footnote: "Diese Ordner sehen aus wie ein Repository, git kommt aber nicht hinein."
            ) {
                KeyValueList(overview.failed.map { repository in
                    KeyValueList.Item(repository.name, repository.failure ?? "", tone: .danger)
                })
            }
        }
    }
}

/// Eine Zeile in der Repository-Liste.
///
/// Absichtlich keine Tabellenzeile: Die drei Zahlen, um die es geht, liest man
/// als Zeichen schneller als in Spalten — und der Name darf so lang sein, wie
/// er ist.
private struct RepositoryRow: View {
    let repository: GitRepository
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AnvilSpacing.sm) {
            Image(systemName: repository.needsAttention ? "circle.fill" : "circle")
                .font(AnvilFont.label)
                .foregroundStyle(repository.needsAttention ? AnvilColor.accent : AnvilColor.textTertiary)

            VStack(alignment: .leading, spacing: 0) {
                Text.raw(repository.name)
                    .font(AnvilFont.rowTitle)
                    .foregroundStyle(AnvilColor.textPrimary)
                    .lineLimit(1)

                Text.raw(repository.status.branch ?? localized("abgelöster HEAD"))
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: AnvilSpacing.xs)

            if repository.failure != nil {
                StatusPill("Fehler", systemImage: "exclamationmark.triangle", tone: .danger)
            } else {
                if repository.status.ahead > 0 {
                    StatusPill(.resolved("\(repository.status.ahead)"), systemImage: "arrow.up", tone: .warning)
                }
                if repository.status.behind > 0 {
                    StatusPill(.resolved("\(repository.status.behind)"), systemImage: "arrow.down", tone: .neutral)
                }
                if !repository.status.isClean {
                    StatusPill(
                        .resolved("\(repository.status.changes.count)"),
                        systemImage: "pencil",
                        tone: .accent
                    )
                }
                if !repository.staleBranches.isEmpty {
                    StatusPill(
                        .resolved("\(repository.staleBranches.count)"),
                        systemImage: "arrow.triangle.branch",
                        tone: .neutral
                    )
                }
            }
        }
        .padding(.horizontal, AnvilSpacing.sm)
        .padding(.vertical, AnvilSpacing.xs)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .fill(isSelected ? AnvilColor.selection : (isHovering ? AnvilColor.hover : .clear))
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(AnvilMotion.quick, value: isHovering)
    }
}
