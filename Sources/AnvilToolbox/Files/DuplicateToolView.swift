import AnvilKit
import AnvilUI
import AppKit
import CryptoKit
import SwiftUI

/// Dubletten in einem Ordner finden.
public struct DuplicateToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    /// Mehrere Ordner auf einmal: Dubletten liegen selten im selben.
    @State private var roots: [URL] = []
    @State private var scan = DuplicateScan.empty
    @State private var isWorking = false
    @State private var work: Task<Void, Never>?
    @State private var minimumKilobytes = 1
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

            if !roots.isEmpty {
                AnvilButton(
                    "Neu suchen",
                    systemImage: "arrow.clockwise",
                    role: .primary,
                    isBusy: isWorking
                ) {
                    search()
                }
                .disabled(isWorking)
            }
        }
        .anvilErrorBanner($error)
        .anvilFilesDrop(.file, error: $error) { dropped in
            open(dropped.compactMap(\.url))
        }
        .onChange(of: minimumKilobytes) { search() }
        .onDisappear { work?.cancel() }
    }

    // MARK: - Suchen

    private func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        roots = FileWalk.distinctRoots(
            urls.map { FileWalk.isDirectory($0) ? $0 : $0.deletingLastPathComponent() }
        )
        search()
    }

    private func chooseFolder() {
        open(SavePanel.directories(prompt: localized("Ordner wählen")))
    }

    /// Ein neuer Lauf löst den alten ab — sonst bliebe eine geänderte
    /// Mindestgröße folgenlos, solange noch gesucht wird.
    private func search() {
        let folders = roots
        guard !folders.isEmpty else { return }
        let minimum = minimumKilobytes * 1024

        work?.cancel()
        work = Task {
            isWorking = true

            let job = Task.detached(priority: .userInitiated) {
                let files = folders.flatMap { folder in
                    FileWalk.files(in: folder, minimumBytes: minimum)
                        .map { DuplicateScan.File(url: $0.url, size: $0.size) }
                }
                return DuplicateScan.scan(
                    files,
                    peek: { try FileDigest.prefixHex(SHA256.self, of: $0) },
                    digest: { try FileDigest.hex(SHA256.self, of: $0) }
                )
            }

            let found = await withTaskCancellationHandler {
                await job.value
            } onCancel: {
                job.cancel()
            }

            guard !Task.isCancelled else { return }
            scan = found
            isWorking = false
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            groupPane
        } secondary: {
            tablePane
        } status: {
            statusBar
        }
    }

    @ViewBuilder
    private var groupPane: some View {
        AnvilPane("Gruppen", systemImage: "square.on.square") {
            if roots.isEmpty {
                EmptyStateView(
                    title: "Noch kein Ordner",
                    message: "Zieh einen Ordner hinein — oder gleich mehrere. Anvil sieht sich alles darunter an, erst die Größe, dann den Inhalt.",
                    systemImage: "folder",
                    actions: {
                        AnvilButton("Ordner wählen", systemImage: "folder") { chooseFolder() }
                    }
                )
            } else if isWorking {
                EmptyStateView(
                    title: "Wird gesucht",
                    message: "Gerechnet wird nur, wo zwei Dateien gleich groß sind.",
                    systemImage: "hourglass"
                )
            } else if scan.isEmpty {
                EmptyStateView(
                    title: "Nichts doppelt",
                    message: "Keine Datei liegt hier zweimal.",
                    systemImage: "checkmark.circle"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AnvilSpacing.md) {
                        ForEach(scan.groups) { group in
                            groupView(group)
                        }
                    }
                    .padding(AnvilSpacing.md)
                }
            }
        } accessory: {
            if !scan.isEmpty {
                CopyButton(text: scan.report)
            }
        }
    }

    private func groupView(_ group: DuplicateScan.Group) -> some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
            HStack(spacing: AnvilSpacing.xs) {
                Text.raw(StoredData.size(group.size))
                    .font(AnvilFont.rowTitle)
                    .foregroundStyle(AnvilColor.textPrimary)
                StatusPill(
                    .resolved(localized("\(group.count) gleiche")),
                    systemImage: "square.on.square",
                    tone: .accent
                )
                Spacer(minLength: 0)
                Text.raw(StoredData.size(group.wastedBytes))
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
            }

            ForEach(group.files) { file in
                Button { reveal(file.url) } label: {
                    HStack(spacing: AnvilSpacing.xs) {
                        Image(systemName: "doc")
                            .font(AnvilFont.caption)
                            .foregroundStyle(AnvilColor.textTertiary)
                        Text.raw(file.name)
                            .font(AnvilFont.body)
                            .foregroundStyle(AnvilColor.textPrimary)
                        Text.raw(file.folder)
                            .font(AnvilFont.caption)
                            .foregroundStyle(AnvilColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .anvilHelp("Im Finder zeigen")
            }
        }
        .padding(AnvilSpacing.sm)
        .anvilCard()
    }

    @ViewBuilder
    private var tablePane: some View {
        AnvilPane("Alle Dubletten", systemImage: "tablecells", tone: .neutral) {
            if scan.isEmpty {
                EmptyStateView(
                    title: "Nichts zu zeigen",
                    message: "Sobald etwas doppelt liegt, steht es hier als Tabelle.",
                    systemImage: "tablecells"
                )
            } else {
                DataGrid(header: DuplicateScan.reportColumns, rows: scan.rows())
            }
        } accessory: {
            if !scan.isEmpty {
                HandoffMenu(context: context, from: metadata.id, text: scan.report)
            }
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(scan.examined)", label: "Dateien", systemImage: "doc.on.doc")
            if roots.count > 1 {
                StatusMetric("\(roots.count)", label: "Ordner", systemImage: "folder")
            }
            StatusMetric(
                "\(scan.groups.count)",
                label: "Gruppen",
                systemImage: "square.on.square",
                tone: .accent
            )
            StatusMetric(
                "\(scan.duplicateCount)",
                label: "doppelt",
                systemImage: "arrow.triangle.2.circlepath"
            )
        } trailing: {
            if scan.wastedBytes > 0 {
                StatusPill(
                    .resolved(localized("\(StoredData.size(scan.wastedBytes)) belegt")),
                    systemImage: "externaldrive",
                    tone: .warning
                )
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Ordner",
            systemImage: "folder",
            footnote: "Versteckte Ordner bleiben draußen. Was in .git oder .build doppelt liegt, gehört einem Programm und nicht dir."
        ) {
            if !roots.isEmpty {
                KeyValueList(roots.map { folder in
                    KeyValueList.Item(folder.lastPathComponent, folder.deletingLastPathComponent().path)
                })
            }
            AnvilButton("Ordner wählen", systemImage: "folder") { chooseFolder() }
        }

        InspectorSection(
            "Ab welcher Größe",
            systemImage: "arrow.up.left.and.arrow.down.right",
            footnote: "Kleine Dateien liegen naturgemäß oft doppelt — Symbole, leere Vorlagen, Konfigurationsschnipsel. Sie kosten nichts und verstopfen die Liste."
        ) {
            OptionRow("Mindestens (KB)") {
                AnvilStepper(value: $minimumKilobytes, in: 1...102_400)
            }
        }

        if !scan.isEmpty {
            InspectorSection(
                "Aufräumen",
                systemImage: "trash",
                footnote: "Anvil löscht nichts. Der Befehl behält je Gruppe die erste Datei und geht in die Zwischenablage — ausgeführt wird er dort, wo du siehst, was passiert."
            ) {
                AnvilButton("Lösch-Befehle kopieren", systemImage: "doc.on.clipboard") {
                    context.pasteboard.copy(scan.removalCommands)
                }
            }
        }

        InspectorSection(
            "Wie gesucht wird",
            systemImage: "info.circle",
            footnote: "Erst nach Größe gruppieren, dann die ersten vierundsechzig Kilobyte vergleichen, und nur was beides übersteht, ganz lesen. Zwei gleich große Videos unterscheiden sich fast immer schon im ersten Block — sie ganz zu lesen wären acht Gigabyte für eine Antwort, die nach einem Augenblick feststand."
        ) {
            if scan.examined > 0 {
                KeyValueList([
                    KeyValueList.Item(localized("Angesehen"), "\(scan.examined)"),
                    KeyValueList.Item(localized("Angelesen"), "\(scan.peeked)"),
                    KeyValueList.Item(localized("Ganz gelesen"), "\(scan.hashed)")
                ])
            }
        }
    }
}
