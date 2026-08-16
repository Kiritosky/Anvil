import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// Aus einer Vorlage den ganzen Satz App-Symbole machen.
public struct IconSetToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    /// Eine Vorlage in der Liste.
    private struct Source: Identifiable {
        let image: NSImage
        let name: String
        let id = UUID()

        var pixelSize: Int {
            guard let rep = image.representations.first else { return 0 }
            return min(rep.pixelsWide, rep.pixelsHigh)
        }
    }

    @State private var sources: [Source] = []
    @State private var platform = IconSet.Platform.macOS
    @State private var isWorking = false
    @State private var error: AnvilError?
    @State private var note: String?
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

            if !sources.isEmpty {
                AnvilButton(
                    "Satz schreiben",
                    systemImage: "square.and.arrow.down",
                    role: .primary,
                    isBusy: isWorking
                ) {
                    writeAll()
                }
                .disabled(isWorking)
            }
        }
        .anvilErrorBanner($error)
        .anvilFilesDrop(.image, error: $error) { dropped in
            add(dropped)
        }
    }

    // MARK: - Vorlagen

    private func add(_ dropped: [DroppedFile]) {
        for file in dropped {
            guard case let .image(image, url) = file else { continue }
            sources.append(
                Source(
                    image: image,
                    name: url?.deletingPathExtension().lastPathComponent ?? localized("Symbol")
                )
            )
        }
    }

    private func clear() {
        sources = []
        note = nil
    }

    /// Vorlagen, die kleiner sind als die größte verlangte Größe.
    private var tooSmall: [Source] {
        sources.filter { $0.pixelSize < IconSet.largestPixelSize(for: platform) }
    }

    // MARK: - Schreiben

    private func writeAll() {
        guard !sources.isEmpty, !isWorking else { return }
        guard let folder = SavePanel.directory(prompt: localized("Ordner wählen")) else { return }

        Task {
            isWorking = true
            defer { isWorking = false }
            note = nil

            var written: [URL] = []
            for source in sources {
                do {
                    written.append(try write(source, into: folder))
                } catch {
                    self.error = AnvilError.wrapping(error)
                    break
                }
            }

            guard !written.isEmpty else { return }
            note = localized("\(written.count) Sätze geschrieben.")
            NSWorkspace.shared.activateFileViewerSelecting(written)
        }
    }

    /// Schreibt einen `.appiconset`-Ordner.
    ///
    /// Jede Bildpunktgröße wird einmal gezeichnet, auch wenn zwei Einträge sie
    /// verlangen: `32x32@1x` und `16x16@2x` sind dieselben zweiunddreißig
    /// Bildpunkte, und ein zweiter Durchlauf durch die Skalierung ergäbe
    /// dieselben Bytes.
    private func write(_ source: Source, into folder: URL) throws -> URL {
        let name = sources.count == 1
            ? IconSet.folderName
            : "\(ExportFile.sanitize(source.name)).appiconset"
        let destination = ExportFile.uniqueFolderURL(in: folder, named: name)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        var drawn: [Int: Data] = [:]
        for size in IconSet.pixelSizes(for: platform) {
            let output = try ImageConversion.convert(
                source.image,
                to: .png,
                scale: .longestEdge,
                longestEdge: size
            )
            drawn[size] = output.data
        }

        for item in IconSet.items(for: platform) {
            guard let data = drawn[item.pixels] else { continue }
            try data.write(to: destination.appending(path: item.fileName))
        }

        try Data(IconSet.contentsJSON(for: platform).utf8)
            .write(to: destination.appending(path: "Contents.json"))

        return destination
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            sourcePane
        } secondary: {
            listPane
        } status: {
            statusBar
        }
    }

    @ViewBuilder
    private var sourcePane: some View {
        AnvilPane("Vorlagen", systemImage: "photo") {
            if sources.isEmpty {
                EmptyStateView(
                    title: "Noch keine Vorlage",
                    message: "Zieh ein quadratisches Bild hinein — am besten 1024 × 1024. Mehrere gehen auch, jedes wird ein eigener Satz.",
                    systemImage: "app.dashed"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AnvilSpacing.xs) {
                        ForEach(sources) { source in
                            row(source)
                        }
                    }
                    .padding(AnvilSpacing.md)
                }
            }
        } accessory: {
            if !sources.isEmpty {
                ClearButton { clear() }
            }
        }
    }

    private func row(_ source: Source) -> some View {
        HStack(spacing: AnvilSpacing.sm) {
            Image(nsImage: source.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: AnvilSize.toolIconLarge, height: AnvilSize.toolIconLarge)
                .clipShape(RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                Text.raw(source.name)
                    .font(AnvilFont.rowTitle)
                    .foregroundStyle(AnvilColor.textPrimary)
                    .lineLimit(1)
                Text(.resolved(localized("\(source.pixelSize) Bildpunkte")))
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
            }

            Spacer(minLength: 0)

            if source.pixelSize < IconSet.largestPixelSize(for: platform) {
                StatusPill("Zu klein", systemImage: "exclamationmark.triangle", tone: .warning)
            }
        }
        .padding(AnvilSpacing.sm)
        .anvilCard()
    }

    @ViewBuilder
    private var listPane: some View {
        AnvilPane("Der Satz", systemImage: "square.grid.2x2", tone: .neutral) {
            DataGrid(header: IconSet.reportColumns, rows: IconSet.rows(for: platform))
        } accessory: {
            CopyButton(text: IconSet.contentsJSON(for: platform))
        }

        if let note {
            AnvilBanner(title: .resolved(note), tone: .success, onDismiss: { self.note = nil })
                .padding(AnvilSpacing.md)
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(sources.count)", label: "Vorlagen", systemImage: "photo")
            StatusMetric(
                "\(IconSet.items(for: platform).count)",
                label: "Einträge",
                systemImage: "list.bullet",
                tone: .accent
            )
            StatusMetric(
                "\(IconSet.pixelSizes(for: platform).count)",
                label: "Größen",
                systemImage: "square.on.square"
            )
            if !tooSmall.isEmpty {
                StatusMetric(
                    "\(tooSmall.count)",
                    label: "zu klein",
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            }
        } trailing: {
            StatusPill(
                .resolved(localized("größte Kante \(IconSet.largestPixelSize(for: platform))")),
                systemImage: "arrow.up.left.and.arrow.down.right",
                tone: .neutral
            )
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Wofür",
            systemImage: "square.grid.2x2",
            footnote: "macOS braucht zehn Einträge, iOS siebzehn. Gezeichnet werden weniger: Zwei Einträge derselben Bildpunktgröße bekommen dieselbe Datei."
        ) {
            ChipPicker(
                selection: $platform,
                options: IconSet.Platform.allCases,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
        }

        if !tooSmall.isEmpty {
            InspectorSection(
                "Zu klein",
                systemImage: "exclamationmark.triangle",
                footnote: "Anvil vergrößert nie. Eine Vorlage unter der größten verlangten Kante ergibt einen Satz, in dem die oberen Größen fehlen — besser eine größere Vorlage."
            ) {
                KeyValueList(tooSmall.map { source in
                    KeyValueList.Item(source.name, "\(source.pixelSize)", tone: .warning)
                })
            }
        }

        InspectorSection(
            "Was geschrieben wird",
            systemImage: "folder.badge.plus",
            footnote: "Ein Ordner `AppIcon.appiconset` mit allen PNG-Dateien und der `Contents.json`. In Xcode gehört er in einen Asset-Katalog — hineinziehen genügt."
        ) {
            AnvilButton("Contents.json kopieren", systemImage: "doc.on.clipboard") {
                context.pasteboard.copy(IconSet.contentsJSON(for: platform))
            }
        }

        InspectorNote(
            "Wie gezeichnet wird",
            systemImage: "info.circle",
            footnote: "Jede Größe wird aus der Vorlage neu gezeichnet, nicht aus der nächstgrößeren — sonst summierten sich die Rundungsfehler über zehn Schritte. Metadaten der Vorlage gehen dabei verloren, was hier keine Nebenwirkung ist, sondern richtig so."
        )
    }
}
