import AnvilKit
import AnvilUI
import AppKit
import Foundation
import SwiftUI

/// Bilder rein, kleinere Bilder in einem anderen Format raus — eines oder
/// dreißig.
///
/// Ein Bildwerkzeug, das immer nur ein Bild kann, ist ein halbes: Wer
/// umwandelt, hat fast nie genau eine Datei, sondern den Inhalt eines Ordners.
public struct ImageToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var batch = ImageBatch()
    @State private var selectedID: ImageBatch.Entry.ID?
    @State private var error: AnvilError?

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    private var settings: SettingsStore { context.settings }

    private var format: ImageConversion.Format { settings[.imageFormat] }
    private var scale: ImageConversion.Scale { settings[.imageScale] }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            AnvilButton("Bilder wählen …", systemImage: "folder") { chooseFiles() }

            AnvilButton(
                "Umwandeln",
                systemImage: "arrow.triangle.2.circlepath",
                role: .primary,
                isBusy: batch.isWorking
            ) {
                convert()
            }
            .disabled(batch.isEmpty || batch.isWorking)

            AnvilButton("Alle sichern …", systemImage: "square.and.arrow.down") { saveAll() }
                .disabled(batch.successCount == 0)
        }
        .anvilErrorBanner($error)
        .anvilFilesDrop(.image, error: $error) { files in
            batch.load(files.compactMap(\.url))
            convert()
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: AnvilSpacing.md) {
            if let progress = batch.progress {
                ProgressStrip("Bilder werden umgewandelt", progress: progress, tone: .accent)
            }

            ToolWorkbench(storageKey: metadata.id.rawValue) {
                listPane
            } secondary: {
                previewPane
            } status: {
                statusBar
            }
        }
    }

    private var listPane: some View {
        AnvilPane("Bilder", systemImage: "photo.stack", contentInset: true) {
            if batch.isEmpty {
                EmptyStateView(
                    title: "Keine Bilder",
                    message: "Zieh Bilder ins Fenster — auch einen ganzen Schwung auf einmal.",
                    systemImage: "photo.on.rectangle.angled"
                ) {
                    AnvilButton("Bilder wählen …", systemImage: "folder", role: .secondary) {
                        chooseFiles()
                    }
                }
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: AnvilSpacing.xxs) {
                        ForEach(batch.entries) { entry in
                            row(entry)
                        }
                    }
                    .padding(.vertical, AnvilSpacing.xxs)
                }
            }
        } accessory: {
            if !batch.isEmpty {
                Text(verbatim: "\(batch.entries.count)")
                    .font(AnvilFont.caption.monospacedDigit())
                    .foregroundStyle(AnvilColor.textTertiary)

                Button { batch.clear() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(AnvilIconButtonStyle(tone: .danger))
                .anvilHelp("Liste leeren")
            }
        }
    }

    private func row(_ entry: ImageBatch.Entry) -> some View {
        Button { selectedID = entry.id } label: {
            HStack(spacing: AnvilSpacing.sm) {
                Image(systemName: icon(for: entry))
                    .foregroundStyle(tone(for: entry).color)

                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: entry.url.lastPathComponent)
                        .font(AnvilFont.rowTitle)
                        .foregroundStyle(AnvilColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(verbatim: detail(for: entry))
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button { batch.remove(entry) } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Aus der Liste nehmen")
            }
            .padding(.horizontal, AnvilSpacing.sm)
            .padding(.vertical, AnvilSpacing.xs)
            .background {
                RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                    .fill(selectedID == entry.id ? AnvilColor.accent.opacity(0.15) : .clear)
            }
        }
        .buttonStyle(.plain)
    }

    private var previewPane: some View {
        AnvilPane(
            "Vorschau",
            systemImage: "eye",
            tone: selected?.output == nil ? .neutral : .success
        ) {
            if let entry = selected, let output = entry.output,
               let preview = NSImage(data: output.data) {
                VStack(spacing: AnvilSpacing.md) {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        // Ein einzelnes Ergebnis lässt sich direkt in den
                        // Finder ziehen, ohne den Umweg über „alle sichern".
                        .anvilDragOut(name: "\(entry.name) \(format.title)") {
                            .image(preview)
                        }

                    Text(verbatim: "\(Int(output.pixelSize.width))×\(Int(output.pixelSize.height)) · \(bytes(output.byteCount))")
                        .font(AnvilFont.caption.monospacedDigit())
                        .foregroundStyle(AnvilColor.textTertiary)
                }
                .padding(AnvilSpacing.md)
            } else if let entry = selected, let failure = entry.failure {
                EmptyStateView(
                    title: "Ging nicht",
                    message: .resolved(failure),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            } else {
                EmptyStateView(
                    title: batch.isEmpty ? "Noch nichts" : "Nichts ausgewählt",
                    message: batch.isEmpty
                        ? "Links Bilder hineinziehen, rechts Format und Größe wählen."
                        : "Wähl links ein Bild, um das Ergebnis zu sehen.",
                    systemImage: "eye"
                )
            }
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(batch.entries.count)", label: "Bilder", systemImage: "photo.stack")

            if batch.successCount > 0 {
                StatusMetric(
                    bytes(batch.totalOriginalBytes),
                    label: "vorher",
                    systemImage: "externaldrive"
                )
                StatusMetric(
                    bytes(batch.totalOutputBytes),
                    label: "nachher",
                    systemImage: "externaldrive.badge.checkmark"
                )
            }

            if batch.failureCount > 0 {
                StatusMetric(
                    "\(batch.failureCount)",
                    label: "fehlgeschlagen",
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            }
        } trailing: {
            if batch.successCount > 0 {
                StatusPill(.resolved(savingsText), tone: savedBytes > 0 ? .success : .warning)
            } else {
                StatusPill(.resolved(format.title), tone: .accent)
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Format",
            systemImage: "doc",
            footnote: .resolved(format.explanation)
        ) {
            ChipPicker(
                selection: settings.bind(.imageFormat) { _ in convert() },
                options: ImageConversion.Format.allCases,
                title: \.title
            )
        }

        if format.isLossy {
            InspectorSection(
                "Güte",
                systemImage: "dial.medium",
                footnote: "Unter 60 % sieht man es, über 90 % bringt es kaum noch etwas."
            ) {
                AnvilSlider(
                    value: settings.bind(.imageQuality),
                    in: 0.3...1.0,
                    step: 0.05,
                    format: AnvilSlider.percent,
                    onEditingChanged: { isEditing in if !isEditing { convert() } }
                )
            }
        }

        InspectorSection(
            "Größe",
            systemImage: "arrow.down.right.and.arrow.up.left",
            footnote: "Vergrößert wird nie — das macht die Datei größer, ohne einen einzigen Bildpunkt hinzuzufügen."
        ) {
            ChipPicker(
                selection: settings.bind(.imageScale) { _ in convert() },
                options: ImageConversion.Scale.allCases,
                title: \.title
            )

            if scale == .longestEdge {
                OptionRow("Pixel") {
                    Picker("", selection: settings.bind(.imageLongestEdge) { _ in convert() }) {
                        ForEach([640, 1024, 1600, 2000, 3000], id: \.self) { value in
                            Text(verbatim: "\(value)").tag(value)
                        }
                    }
                    .labelsHidden()
                }
            }
        }

        InspectorSection(
            "Metadaten",
            systemImage: "eye.slash",
            footnote: "Jedes Bild wird neu gezeichnet und neu kodiert. EXIF, Aufnahmeort und Gerätename bleiben dabei zurück — nicht als Schalter, sondern als Folge."
        ) {
            if metadataFound.isEmpty {
                Text("In den gewählten Bildern steckt nichts Auffälliges.")
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
            } else {
                ForEach(metadataFound, id: \.self) { entry in
                    Label {
                        Text(verbatim: entry)
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textSecondary)
                }
            }
        }
    }

    // MARK: - Arbeit

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = localized("Hinzufügen")

        guard panel.runModal() == .OK else { return }
        batch.load(panel.urls)
        convert()
    }

    private func convert() {
        guard !batch.isEmpty else { return }
        Task {
            await batch.convert(
                to: format,
                scale: scale,
                longestEdge: settings[.imageLongestEdge],
                quality: settings[.imageQuality]
            )
            if selectedID == nil { selectedID = batch.entries.first?.id }
        }
    }

    private func saveAll() {
        guard let directory = SavePanel.directory(prompt: localized("Hierhin sichern")) else {
            return
        }
        do {
            try batch.write(into: directory)
        } catch {
            self.error = AnvilError.wrapping(error)
        }
    }

    // MARK: - Abgeleitet

    private var selected: ImageBatch.Entry? {
        batch.entries.first { $0.id == selectedID } ?? batch.entries.first
    }

    private var savedBytes: Int {
        batch.totalOriginalBytes - batch.totalOutputBytes
    }

    private var savingsText: String {
        guard savedBytes > 0 else {
            return localized("\(bytes(-savedBytes)) größer")
        }
        let share = Int(Double(savedBytes) / Double(max(batch.totalOriginalBytes, 1)) * 100)
        return localized("\(share) % kleiner")
    }

    /// Was in den Bildern steckt, über den ganzen Stapel gesehen — sonst
    /// stünde bei dreißig Fotos dreißigmal „Aufnahmeort".
    private var metadataFound: [String] {
        var seen: [String] = []
        for entry in batch.entries.prefix(20) {
            guard let data = try? Data(contentsOf: entry.url) else { continue }
            for item in ImageConversion.metadataSummary(of: data) where !seen.contains(item) {
                seen.append(item)
            }
        }
        return seen
    }

    private func icon(for entry: ImageBatch.Entry) -> String {
        if entry.failure != nil { return "exclamationmark.triangle" }
        return entry.output == nil ? "photo" : "checkmark.circle"
    }

    private func tone(for entry: ImageBatch.Entry) -> AnvilTone {
        if entry.failure != nil { return .warning }
        return entry.output == nil ? .neutral : .success
    }

    private func detail(for entry: ImageBatch.Entry) -> String {
        if let failure = entry.failure { return failure }
        guard let output = entry.output else { return bytes(entry.originalBytes) }
        let arrow = entry.savedBytes > 0 ? "↓" : "↑"
        return "\(bytes(entry.originalBytes)) → \(bytes(output.byteCount)) \(arrow)"
    }

    private func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

// MARK: - Settings keys

extension SettingKey {
    public static var imageFormat: SettingKey<ImageConversion.Format> {
        SettingKey<ImageConversion.Format>("image.format", default: .jpeg)
    }

    public static var imageScale: SettingKey<ImageConversion.Scale> {
        SettingKey<ImageConversion.Scale>("image.scale", default: .original)
    }

    public static var imageQuality: SettingKey<Double> {
        SettingKey<Double>("image.quality", default: 0.85)
    }

    public static var imageLongestEdge: SettingKey<Int> {
        SettingKey<Int>("image.longestEdge", default: 2000)
    }
}
