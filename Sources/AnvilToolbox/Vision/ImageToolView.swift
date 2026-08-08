import AnvilKit
import AnvilUI
import AppKit
import Foundation
import SwiftUI

/// Bild rein, kleineres Bild in einem anderen Format raus.
public struct ImageToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var image: NSImage?
    @State private var sourceData: Data?
    @State private var sourceName = ""
    @State private var output: ImageConversion.Output?
    @State private var error: AnvilError?
    @State private var isWorking = false

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
            AnvilButton("Aus Zwischenablage", systemImage: "doc.on.clipboard") {
                readFromPasteboard()
            }

            AnvilButton(
                "Sichern …",
                systemImage: "square.and.arrow.down",
                role: .primary
            ) {
                save()
            }
            .disabled(output == nil)
        }
        .anvilErrorBanner($error)
        .anvilFileDrop(.image, error: $error) { dropped in
            guard case let .image(dropped, url) = dropped else { return }
            load(dropped, url: url)
        }
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(storageKey: metadata.id.rawValue) {
            sourcePane
        } secondary: {
            resultPane
        } status: {
            statusBar
        }
    }

    private var sourcePane: some View {
        AnvilPane("Bild", systemImage: "photo") {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(AnvilSpacing.md)
            } else {
                EmptyStateView(
                    title: "Kein Bild",
                    message: "Zieh ein Bild ins Fenster oder hol eines aus der Zwischenablage.",
                    systemImage: "photo.on.rectangle.angled"
                )
            }
        } accessory: {
            if image != nil {
                Button { clear() } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Bild entfernen")
            }
        }
    }

    private var resultPane: some View {
        AnvilPane(
            "Ergebnis",
            systemImage: "arrow.down.circle",
            tone: output == nil ? .neutral : .success
        ) {
            if isWorking {
                EmptyStateView(
                    title: "Wird umgewandelt …",
                    message: "Bei großen Bildern dauert das einen Moment.",
                    systemImage: "hourglass"
                )
            } else if let output, let preview = NSImage(data: output.data) {
                VStack(spacing: AnvilSpacing.md) {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        // Das fertige Bild lässt sich direkt in den Finder
                        // ziehen — der kürzeste Weg von hier nach dort.
                        .anvilDragOut(name: exportName) {
                            .image(preview)
                        }

                    savingsLabel(for: output)
                }
                .padding(AnvilSpacing.md)
            } else {
                EmptyStateView(
                    title: "Noch nichts umgewandelt",
                    message: "Rechts Format und Größe wählen — das Ergebnis erscheint sofort.",
                    systemImage: "arrow.down.circle"
                )
            }
        } accessory: {
            if let output {
                Button { copyResult(output) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Ergebnis kopieren")
            }
        }
    }

    /// Was die Umwandlung gebracht hat — und ehrlich auch, wenn sie nichts
    /// gebracht hat: ein PNG-Bildschirmfoto wird als PNG gern größer.
    @ViewBuilder
    private func savingsLabel(for output: ImageConversion.Output) -> some View {
        if let sourceData {
            let saved = sourceData.count - output.byteCount
            StatusPill(
                .resolved(savingsText(saved: saved, of: sourceData.count)),
                systemImage: saved > 0 ? "arrow.down" : "arrow.up",
                tone: saved > 0 ? .success : .warning
            )
        }
    }

    private func savingsText(saved: Int, of original: Int) -> String {
        guard saved > 0 else {
            let grown = ByteCountFormatter.string(fromByteCount: Int64(-saved), countStyle: .file)
            return localized("\(grown) größer")
        }
        let share = Int(Double(saved) / Double(max(original, 1)) * 100)
        return localized("\(share) % kleiner")
    }

    private var statusBar: some View {
        ToolStatusBar {
            if let image {
                StatusMetric(
                    "\(Int(pixelSize(of: image).width))×\(Int(pixelSize(of: image).height))",
                    label: "Original",
                    systemImage: "photo"
                )
            }
            if let sourceData {
                StatusMetric(
                    ByteCountFormatter.string(fromByteCount: Int64(sourceData.count), countStyle: .file),
                    label: "vorher",
                    systemImage: "externaldrive"
                )
            }
            if let output {
                StatusMetric(
                    "\(Int(output.pixelSize.width))×\(Int(output.pixelSize.height))",
                    label: "nachher",
                    systemImage: "arrow.right"
                )
                StatusMetric(
                    ByteCountFormatter.string(fromByteCount: Int64(output.byteCount), countStyle: .file),
                    label: "Größe",
                    systemImage: "externaldrive.badge.checkmark"
                )
            }
        } trailing: {
            StatusPill(.resolved(format.title), tone: .accent)
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
                Slider(
                    value: settings.bind(.imageQuality) { _ in convert() },
                    in: 0.3...1.0,
                    step: 0.05
                )
                Text(verbatim: "\(Int(settings[.imageQuality] * 100)) %")
                    .font(AnvilFont.caption.monospacedDigit())
                    .foregroundStyle(AnvilColor.textTertiary)
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
            footnote: "Das Bild wird neu gezeichnet und neu kodiert. EXIF, Aufnahmeort und Gerätename bleiben dabei zurück — nicht als Schalter, sondern als Folge."
        ) {
            if metadataFound.isEmpty {
                Text("In diesem Bild steckt nichts Auffälliges.")
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

    private func load(_ dropped: NSImage, url: URL?) {
        image = dropped
        sourceName = url?.deletingPathExtension().lastPathComponent ?? localized("Bild")
        sourceData = url.flatMap { try? Data(contentsOf: $0) } ?? dropped.tiffRepresentation
        convert()
    }

    private func readFromPasteboard() {
        let objects = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage]
        guard let pasted = objects?.first else {
            error = .invalidInput(localized("In der Zwischenablage liegt kein Bild."))
            return
        }
        load(pasted, url: nil)
    }

    private func convert() {
        guard let image else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            output = try ImageConversion.convert(
                image,
                to: format,
                scale: scale,
                longestEdge: settings[.imageLongestEdge],
                quality: settings[.imageQuality]
            )
        } catch {
            self.error = AnvilError.wrapping(error)
            output = nil
        }
    }

    private func save() {
        guard let output,
              let url = SavePanel.url(suggestedName: exportName, type: format.type)
        else { return }

        do {
            try output.data.write(to: url)
        } catch {
            self.error = .storage(
                localized("Sichern nach „\(url.lastPathComponent)\" ist fehlgeschlagen: \(error.localizedDescription)")
            )
        }
    }

    private func copyResult(_ output: ImageConversion.Output) {
        guard let image = NSImage(data: output.data) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func clear() {
        image = nil
        sourceData = nil
        output = nil
        sourceName = ""
    }

    // MARK: - Abgeleitet

    private var exportName: String {
        let base = sourceName.isEmpty ? localized("Bild") : sourceName
        return "\(base) \(format.title)"
    }

    private var metadataFound: [String] {
        sourceData.map { ImageConversion.metadataSummary(of: $0) } ?? []
    }

    private func pixelSize(of image: NSImage) -> CGSize {
        guard let representation = image.representations.first else { return image.size }
        return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
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
