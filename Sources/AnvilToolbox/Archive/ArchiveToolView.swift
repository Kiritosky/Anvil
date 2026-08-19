import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// In Archive hineinsehen, sie stapelweise ein- und auspacken.
public struct ArchiveToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    /// Ein Eintrag in der Liste links — ein Archiv oder etwas, das eines
    /// werden soll.
    private struct Item: Identifiable, Sendable {
        let url: URL
        var listing: ArchiveListing?
        var failure: String?

        var id: String { url.path }
        var name: String { url.lastPathComponent }
        var isArchive: Bool { ArchiveTool.isArchive(url) }
    }

    @State private var items: [Item] = []
    @State private var selection: String?
    @State private var destination: URL?
    @State private var isWorking = false
    @State private var error: AnvilError?
    @State private var note: String?
    @State private var orientation: WorkbenchOrientation = .horizontal

    private let archive = ArchiveTool()

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

            if !packable.isEmpty {
                AnvilButton(
                    "Einpacken",
                    systemImage: "archivebox",
                    role: packable.count == items.count ? .primary : .secondary,
                    isBusy: isWorking
                ) {
                    packAll()
                }
                .disabled(isWorking)
            }

            if !archives.isEmpty {
                AnvilButton(
                    "Entpacken",
                    systemImage: "shippingbox",
                    role: .primary,
                    isBusy: isWorking
                ) {
                    unpackAll()
                }
                .disabled(isWorking)
            }
        }
        .anvilErrorBanner($error)
        .anvilFilesDrop(.file, error: $error) { dropped in
            add(dropped.compactMap(\.url))
        }
    }

    // MARK: - Liste

    private var archives: [Item] { items.filter(\.isArchive) }
    private var packable: [Item] { items.filter { !$0.isArchive } }

    private var selected: Item? {
        if let selection, let match = items.first(where: { $0.id == selection }) { return match }
        return archives.first
    }

    private func add(_ urls: [URL]) {
        var seen = Set(items.map(\.id))
        var added: [Item] = []
        for url in urls where seen.insert(url.path).inserted {
            added.append(Item(url: url))
        }
        guard !added.isEmpty else { return }

        items += added
        if selection == nil { selection = added.first?.id }
        inspect(added.filter(\.isArchive).map(\.url))
    }

    /// Archive und alles andere aus einem Dialog holen.
    private func choose() {
        let urls = SavePanel.files(
            prompt: localized("Hinzufügen"),
            includingDirectories: true
        )
        guard !urls.isEmpty else { return }
        add(urls)
    }

    private func clear() {
        items = []
        selection = nil
        note = nil
    }

    // MARK: - Hineinsehen

    /// Liest die Verzeichnisse der genannten Archive.
    private func inspect(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            isWorking = true
            defer { isWorking = false }

            for url in urls {
                do {
                    let listing = try await archive.list(url)
                    update(url) { $0.listing = listing }
                } catch {
                    update(url) { $0.failure = AnvilError.wrapping(error).message }
                }
            }
        }
    }

    private func update(_ url: URL, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == url.path }) else { return }
        change(&items[index])
    }

    // MARK: - Ein- und auspacken

    /// Wohin die Ergebnisse gehen: in den gewählten Ordner, sonst neben das
    /// Original.
    private func target(for url: URL) -> URL {
        destination ?? url.deletingLastPathComponent()
    }

    private func unpackAll() {
        let sources = archives.map(\.url)
        guard !sources.isEmpty, !isWorking else { return }

        Task {
            isWorking = true
            defer { isWorking = false }
            note = nil

            var unpacked: [URL] = []
            for url in sources {
                do {
                    unpacked.append(try await archive.unpack(url, into: target(for: url)))
                } catch {
                    self.error = AnvilError.wrapping(error)
                    break
                }
            }

            guard !unpacked.isEmpty else { return }
            note = localized("\(unpacked.count) Archive entpackt.")
            NSWorkspace.shared.activateFileViewerSelecting(unpacked)
        }
    }

    private func packAll() {
        let sources = packable.map(\.url)
        guard !sources.isEmpty, !isWorking else { return }

        Task {
            isWorking = true
            defer { isWorking = false }
            note = nil

            var written: [URL] = []
            for url in sources {
                do {
                    written.append(try await archive.pack(url, into: target(for: url)))
                } catch {
                    self.error = AnvilError.wrapping(error)
                    break
                }
            }

            guard !written.isEmpty else { return }
            note = localized("\(written.count) Archive geschrieben.")
            NSWorkspace.shared.activateFileViewerSelecting(written)

            add(written)
        }
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
        AnvilPane("Archive", systemImage: "archivebox") {
            if items.isEmpty {
                EmptyStateView(
                    title: "Noch nichts da",
                    message: "Zieh Archive hinein, um hineinzusehen — oder Dateien und Ordner, um sie einzupacken. Beides geht stapelweise.",
                    systemImage: "archivebox",
                    actions: {
                        AnvilButton("Dateien wählen", systemImage: "folder") { choose() }
                    }
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AnvilSpacing.xs) {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                    .padding(AnvilSpacing.md)
                }
            }
        } accessory: {
            if !items.isEmpty {
                ClearButton { clear() }
            }
        }
    }

    private func row(_ item: Item) -> some View {
        Button {
            selection = item.id
        } label: {
            HStack(spacing: AnvilSpacing.xs) {
                Image(systemName: item.isArchive ? "archivebox" : "folder")
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)

                VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                    Text.raw(item.name)
                        .font(AnvilFont.rowTitle)
                        .foregroundStyle(AnvilColor.textPrimary)
                        .lineLimit(1)
                    Text.raw(subtitle(of: item))
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let listing = item.listing, !listing.risky.isEmpty {
                    StatusPill("Prüfen", systemImage: "exclamationmark.triangle", tone: .warning)
                }
            }
            .padding(AnvilSpacing.sm)
            .anvilCard(isSelected: item.id == selected?.id)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(of item: Item) -> String {
        if let failure = item.failure { return failure }
        guard let listing = item.listing else {
            return item.isArchive ? localized("wird gelesen") : localized("wird eingepackt")
        }
        let size = StoredData.size(listing.totalBytes)
        return localized("\(listing.files.count) Dateien, \(size) ausgepackt")
    }

    @ViewBuilder
    private var detailPane: some View {
        AnvilPane("Inhalt", systemImage: "list.bullet", tone: .neutral) {
            if let item = selected, let listing = item.listing {
                if listing.isEmpty {
                    EmptyStateView(
                        title: "Leeres Archiv",
                        message: "In diesem Archiv liegt keine Datei.",
                        systemImage: "shippingbox"
                    )
                } else {
                    DataGrid(header: ArchiveListing.reportColumns, rows: listing.rows())
                }
            } else if let item = selected, let failure = item.failure {
                EmptyStateView(
                    title: "Ließ sich nicht lesen",
                    message: .resolved(failure),
                    systemImage: "exclamationmark.triangle"
                )
            } else {
                EmptyStateView(
                    title: "Nichts ausgewählt",
                    message: "Wähl links ein Archiv. Was darin liegt, steht dann hier — ohne dass etwas ausgepackt wird.",
                    systemImage: "list.bullet"
                )
            }
        } accessory: {
            if let listing = selected?.listing, !listing.isEmpty {
                HandoffMenu(context: context, from: metadata.id, text: listing.report)
            }
        }

        if let note {
            AnvilBanner(title: .resolved(note), tone: .success, onDismiss: { self.note = nil })
                .padding(AnvilSpacing.md)
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(archives.count)", label: "Archive", systemImage: "archivebox")
            if !packable.isEmpty {
                StatusMetric(
                    "\(packable.count)",
                    label: "einzupacken",
                    systemImage: "folder",
                    tone: .accent
                )
            }
            if let listing = selected?.listing {
                StatusMetric("\(listing.files.count)", label: "Dateien", systemImage: "doc")
                StatusMetric(
                    "\(listing.folders.count)",
                    label: "Ordner",
                    systemImage: "folder.badge.gearshape"
                )
            }
        } trailing: {
            if let listing = selected?.listing {
                if !listing.risky.isEmpty {
                    StatusPill(
                        .resolved(localized("\(listing.risky.count) auffällige Pfade")),
                        systemImage: "exclamationmark.triangle",
                        tone: .danger
                    )
                }
                StatusPill(
                    .resolved(localized("\(StoredData.size(listing.totalBytes)) ausgepackt")),
                    systemImage: "externaldrive",
                    tone: .neutral
                )
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Quelle",
            systemImage: "tray",
            footnote: "Archive, Dateien und Ordner dürfen zusammen in der Liste liegen. Entpacken nimmt sich die Archive, Einpacken alles andere."
        ) {
            AnvilButton("Dateien wählen", systemImage: "folder") { choose() }
            if !items.isEmpty {
                AnvilButton("Liste leeren", systemImage: "trash") { clear() }
            }
        }

        InspectorSection(
            "Ziel",
            systemImage: "folder.badge.plus",
            footnote: "Ohne Ziel landet alles neben dem Original. Jedes Archiv bekommt beim Auspacken einen eigenen Ordner — auch wenn schon einer darin liegt."
        ) {
            if let destination {
                KeyValueList([KeyValueList.Item(localized("Ordner"), destination.path)])
            }
            AnvilButton("Zielordner wählen", systemImage: "folder.badge.plus") {
                destination = SavePanel.directory(prompt: localized("Ordner wählen"))
            }
            if destination != nil {
                AnvilButton("Wieder neben das Original", systemImage: "arrow.uturn.backward") {
                    destination = nil
                }
            }
        }

        if let listing = selected?.listing {
            InspectorSection(
                "Was drin ist",
                systemImage: "chart.pie",
                footnote: "Die häufigsten Endungen — meistens die schnellste Antwort auf die Frage, was für ein Archiv das ist."
            ) {
                KeyValueList(listing.kinds.prefix(8).map { kind in
                    KeyValueList.Item(kind.name, "\(kind.count)")
                })
            }

            if !listing.largest.isEmpty {
                InspectorSection(
                    "Die größten Dateien",
                    systemImage: "arrow.up.right",
                    footnote: "Ausgepackte Größe. Was ein Archiv groß macht, sind fast immer drei Dateien und nicht dreitausend."
                ) {
                    KeyValueList(listing.largest.prefix(5).map { entry in
                        KeyValueList.Item(entry.name, StoredData.size(entry.size))
                    })
                }
            }

            if listing.scatters {
                InspectorSection(
                    "Kein gemeinsamer Ordner",
                    systemImage: "square.grid.3x3",
                    footnote: "Dieses Archiv hat oben mehrere Einträge. Doppelklick im Finder verteilt sie über den Zielordner — Anvil legt deshalb immer einen eigenen an."
                ) {
                    KeyValueList(listing.roots.prefix(8).map { root in
                        KeyValueList.Item(root, "")
                    })
                }
            }

            if !listing.risky.isEmpty {
                InspectorSection(
                    "Auffällige Pfade",
                    systemImage: "exclamationmark.triangle",
                    footnote: "Diese Einträge zeigen aus dem Zielordner heraus. `ditto` weigert sich, sie so zu schreiben — wissen will man es trotzdem vorher."
                ) {
                    KeyValueList(listing.risky.prefix(10).map { entry in
                        KeyValueList.Item(
                            entry.path,
                            entry.risk?.title ?? "",
                            tone: .danger
                        )
                    })
                }
            }
        }

        InspectorNote(
            "Wie gepackt wird",
            systemImage: "info.circle",
            footnote: "Gepackt und entpackt wird mit `ditto` — demselben Werkzeug, das der Finder benutzt. Rechte, Symlinks und Ressourcenzweige bleiben dabei erhalten; ein Archiv aus Anvil kommt auf einem Mac an wie eines aus dem Finder."
        )
    }
}
