import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// Wo der Platz hingeht — Ordner für Ordner.
public struct DiskUsageToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var root: URL?
    @State private var trail: [URL] = []
    @State private var usage = DiskUsage.empty
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

            if !trail.isEmpty {
                AnvilButton("Zurück", systemImage: "chevron.left") { back() }
                    .disabled(isWorking)
            }

            if root != nil {
                AnvilButton(
                    "Neu messen",
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

    // MARK: - Messen

    private func open(_ url: URL) {
        trail = []
        root = FileWalk.isDirectory(url) ? url : url.deletingLastPathComponent()
        measure()
    }

    /// Steigt in einen Ordner hinab, ohne den Weg dahin zu vergessen.
    private func descend(into node: DiskUsage.Node) {
        guard node.isDirectory, let root else { return }
        trail.append(root)
        self.root = URL(fileURLWithPath: node.path)
        measure()
    }

    private func back() {
        guard let previous = trail.popLast() else { return }
        root = previous
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

            // Einmal durch einen großen Ordner zu laufen dauert Sekunden.
            // Auf dem Hauptthread stünde so lange das Fenster.
            usage = await Task.detached {
                DiskUsage.make(root: root, files: FileWalk.files(in: root))
            }.value
        }
    }

    private func reveal(_ node: DiskUsage.Node) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            treePane
        } secondary: {
            filePane
        } status: {
            statusBar
        }
    }

    @ViewBuilder
    private var treePane: some View {
        AnvilPane("Ordner", systemImage: "chart.bar") {
            if root == nil {
                EmptyStateView(
                    title: "Noch kein Ordner",
                    message: "Zieh einen Ordner hinein. Anvil rechnet zusammen, was darunter liegt, und sortiert nach Größe statt nach Alphabet.",
                    systemImage: "externaldrive",
                    actions: {
                        AnvilButton("Ordner wählen", systemImage: "folder") { chooseFolder() }
                    }
                )
            } else if isWorking {
                EmptyStateView(
                    title: "Wird gemessen",
                    message: "Jede Datei darunter wird einmal angesehen — gelesen wird keine.",
                    systemImage: "hourglass"
                )
            } else if usage.isEmpty {
                EmptyStateView(
                    title: "Nichts darin",
                    message: "In diesem Ordner liegt keine Datei, die zählt.",
                    systemImage: "tray"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AnvilSpacing.xs) {
                        ForEach(usage.children) { node in
                            bar(node)
                        }
                    }
                    .padding(AnvilSpacing.md)
                }
            }
        } accessory: {
            if !usage.isEmpty {
                CopyButton(text: usage.report)
            }
        }
    }

    /// Eine Zeile mit einem Balken darunter.
    ///
    /// Der Balken ist der Punkt: Zahlen nebeneinander muss man vergleichen,
    /// Längen sieht man.
    private func bar(_ node: DiskUsage.Node) -> some View {
        Button {
            if node.isDirectory { descend(into: node) } else { reveal(node) }
        } label: {
            VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                HStack(spacing: AnvilSpacing.xs) {
                    Image(systemName: node.isDirectory ? "folder" : "doc")
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textTertiary)
                    Text.raw(node.name)
                        .font(AnvilFont.rowTitle)
                        .foregroundStyle(AnvilColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text.raw(DiskUsage.percent(node.share(of: usage.total)))
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textTertiary)
                    Text.raw(StoredData.size(node.bytes))
                        .font(AnvilFont.monoSmall)
                        .foregroundStyle(AnvilColor.textSecondary)
                }

                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                        .fill(node.isDirectory ? AnvilColor.accent : AnvilColor.info)
                        .frame(width: geometry.size.width * node.share(of: usage.total))
                }
                .frame(height: AnvilSize.barHeight)
            }
            .padding(AnvilSpacing.sm)
            .background {
                RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                    .fill(AnvilColor.surface)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .anvilHelp(node.isDirectory ? "Hineingehen" : "Im Finder zeigen")
    }

    @ViewBuilder
    private var filePane: some View {
        AnvilPane("Die größten Dateien", systemImage: "doc.on.doc", tone: .neutral) {
            if usage.isEmpty {
                EmptyStateView(
                    title: "Nichts zu zeigen",
                    message: "Sobald gemessen ist, stehen hier die zwanzig größten Dateien — egal wie tief sie liegen.",
                    systemImage: "doc"
                )
            } else {
                DataGrid(
                    header: DiskUsage.reportColumns,
                    rows: usage.rows(usage.largestFiles())
                )
            }
        } accessory: {
            if !usage.isEmpty {
                HandoffMenu(context: context, from: metadata.id, text: usage.report)
            }
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(usage.fileCount)", label: "Dateien", systemImage: "doc")
            StatusMetric(
                "\(usage.children.count)",
                label: "Posten",
                systemImage: "list.bullet",
                tone: .accent
            )
            if !trail.isEmpty {
                StatusMetric("\(trail.count)", label: "Ebenen tief", systemImage: "arrow.down.right")
            }
        } trailing: {
            if let root {
                StatusPill(.resolved(root.lastPathComponent), systemImage: "folder", tone: .neutral)
            }
            StatusPill(
                .resolved(localized("\(StoredData.size(usage.total)) belegt")),
                systemImage: "externaldrive",
                tone: usage.total > 0 ? .accent : .neutral
            )
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Ordner",
            systemImage: "folder",
            footnote: "Versteckte Ordner bleiben draußen, Pakete zählen als ein Ding. Ein Klick auf einen Ordner geht hinein, der Knopf oben wieder heraus."
        ) {
            if let root {
                KeyValueList([KeyValueList.Item(localized("Gemessen"), root.path)])
            }
            AnvilButton("Ordner wählen", systemImage: "folder") { chooseFolder() }
        }

        if !usage.isEmpty {
            InspectorSection(
                "Nach Endung",
                systemImage: "chart.pie",
                footnote: "Manchmal ist die Antwort kein Ordner, sondern eine Endung, die überall verstreut liegt."
            ) {
                KeyValueList(usage.byExtension().map { node in
                    KeyValueList.Item(node.name, StoredData.size(node.bytes))
                })
            }

            InspectorSection(
                "Pfade kopieren",
                systemImage: "doc.on.clipboard",
                footnote: "Die Pfade der größten Dateien, eine Zeile je Datei — für den Blick im Terminal, bevor etwas weggeht."
            ) {
                AnvilButton("Pfade der größten Dateien", systemImage: "doc.on.clipboard") {
                    context.pasteboard.copy(
                        usage.largestFiles().map(\.path).joined(separator: "\n")
                    )
                }
            }
        }

        InspectorSection(
            "Was gezählt wird",
            systemImage: "info.circle",
            footnote: "Gezählt wird die Größe der Dateien, nicht der belegte Platz auf der Platte. Bei vielen winzigen Dateien liegt der echte Verbrauch höher, weil jede einen ganzen Block bekommt."
        ) {
            EmptyView()
        }
    }
}
