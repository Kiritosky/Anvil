import AnvilKit
import AnvilUI
import AppKit
import CryptoKit
import SwiftUI

/// Dubletten in einem Ordner finden.
public struct DuplicateToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var root: URL?
    @State private var scan = DuplicateScan.empty
    @State private var isWorking = false
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

            if root != nil {
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
            guard let folder = dropped.compactMap(\.url).first else { return }
            open(folder)
        }
        .onChange(of: minimumKilobytes) { search() }
    }

    // MARK: - Suchen

    private func open(_ folder: URL) {
        root = FileWalk.isDirectory(folder) ? folder : folder.deletingLastPathComponent()
        search()
    }

    private func chooseFolder() {
        guard let folder = SavePanel.directory(prompt: localized("Ordner wählen")) else { return }
        open(folder)
    }

    private func search() {
        guard let root, !isWorking else { return }
        let minimum = minimumKilobytes * 1024

        Task {
            isWorking = true
            defer { isWorking = false }

            // Sowohl das Einsammeln als auch das Rechnen geht über die Platte.
            // Auf dem Hauptthread stünde so lange das Fenster.
            scan = await Task.detached {
                let files = FileWalk.files(in: root, minimumBytes: minimum)
                    .map { DuplicateScan.File(url: $0.url, size: $0.size) }
                return DuplicateScan.scan(files) { url in
                    try FileDigest.hex(SHA256.self, of: url)
                }
            }.value
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
            if root == nil {
                EmptyStateView(
                    title: "Noch kein Ordner",
                    message: "Zieh einen Ordner hinein. Anvil sieht sich alles darunter an — erst die Größe, dann den Inhalt.",
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
                    message: "In diesem Ordner liegt keine Datei zweimal.",
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
            if let root {
                KeyValueList([KeyValueList.Item(localized("Gewählt"), root.path)])
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
            footnote: "Erst nach Größe gruppieren, dann nur innerhalb der Gruppen die Prüfsumme rechnen. Zwei Dateien unterschiedlicher Größe können nie gleich sein — dadurch wird fast nichts gelesen."
        ) {
            if scan.examined > 0 {
                KeyValueList([
                    KeyValueList.Item(localized("Angesehen"), "\(scan.examined)"),
                    KeyValueList.Item(localized("Gelesen"), "\(scan.hashed)")
                ])
            }
        }
    }
}
