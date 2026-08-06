import AnvilKit
import AnvilUI
import AppKit
import Foundation
import SwiftUI

/// The screenshot workbench: take one, look at it, do something with it.
///
/// What separates this from pressing ⇧⌘4 is everything after the shutter — the
/// shot stays here, with its text already read if you asked for that, and the
/// four things you actually want to do with it are one click away instead of
/// a trip through the Finder.
public struct ScreenshotToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    /// The mark being dragged right now. Committed on release.
    @State private var draft: Annotation?

    private var controller: ScreenshotController { context.screenshots }
    private var settings: SettingsStore { context.settings }

    public var body: some View {
        @Bindable var controller = controller

        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            ForEach(ScreenCapture.Target.allCases) { target in
                AnvilButton(
                    .resolved(target.title),
                    systemImage: target.systemImage,
                    role: target == .region ? .primary : .secondary,
                    isBusy: controller.isCapturing && target == .region
                ) {
                    Task { await controller.capture(target) }
                }
                .disabled(controller.isCapturing)
            }
        }
        .anvilErrorBanner($controller.error)
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(storageKey: metadata.id.rawValue) {
            previewPane
        } secondary: {
            sidePane
        } status: {
            statusBar
        }
    }

    private var previewPane: some View {
        AnvilPane(
            "Aufnahme",
            systemImage: "camera.viewfinder",
            tone: controller.selected == nil ? .neutral : .accent
        ) {
            if let shot = controller.selected {
                annotatableImage(shot)
                    .padding(AnvilSpacing.md)
            } else {
                EmptyStateView(
                    title: "Noch keine Aufnahme",
                    message: "Oben auswählen, was aufgenommen werden soll — oder das Tastenkürzel benutzen, dann bleibt dieses Fenster zu.",
                    systemImage: "camera.viewfinder"
                ) {
                    AnvilButton("Ausschnitt aufnehmen", systemImage: "rectangle.dashed", role: .primary) {
                        Task { await controller.capture(.region) }
                    }
                }
            }
        } accessory: {
            if let shot = controller.selected {
                if shot.isAnnotated {
                    Button { controller.undoAnnotation(on: shot) } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(AnvilIconButtonStyle())
                    .anvilHelp("Letzte Markierung zurücknehmen")

                    Button { controller.clearAnnotations(on: shot) } label: {
                        Image(systemName: "eraser")
                    }
                    .buttonStyle(AnvilIconButtonStyle())
                    .anvilHelp("Alle Markierungen entfernen")
                }

                Button { controller.copyImage(shot) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Bild kopieren")

                Button { controller.keep(shot) } label: {
                    Image(systemName: shot.fileURL == nil ? "square.and.arrow.down" : "checkmark.circle")
                }
                .buttonStyle(AnvilIconButtonStyle(isActive: shot.fileURL != nil, tone: .success))
                .anvilHelp(shot.fileURL == nil ? "Als PNG sichern" : "Ist gesichert")

                Button { controller.reveal(shot) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Im Finder zeigen")

                Button { controller.remove(shot) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(AnvilIconButtonStyle(tone: .danger))
                .anvilHelp("Verwerfen")
            }
        }
    }

    /// The picture with a drawing surface over it.
    ///
    /// The drag is translated into image coordinates rather than view ones, so
    /// a mark stays where it was put when the window is resized — and lands in
    /// the right place when the export is rendered at full resolution.
    private func annotatableImage(_ shot: Screenshot) -> some View {
        GeometryReader { proxy in
            let imageSize = shot.pixelSize
            let frame = AnnotationRenderer.fittedRect(
                for: imageSize,
                in: proxy.size
            )

            ZStack(alignment: .topLeading) {
                Image(nsImage: shot.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                ForEach(shot.annotations) { annotation in
                    AnnotationShape(annotation: annotation, frame: frame)
                }

                if let draft {
                    AnnotationShape(annotation: draft, frame: frame)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard let start = AnnotationRenderer.normalize(
                            value.startLocation,
                            imageSize: imageSize,
                            containerSize: proxy.size
                        ),
                        let end = AnnotationRenderer.normalize(
                            value.location,
                            imageSize: imageSize,
                            containerSize: proxy.size
                        ) else { return }

                        draft = Annotation(
                            kind: settings[.annotationKind],
                            start: start,
                            end: end,
                            color: annotationColor,
                            lineWidth: CGFloat(settings[.annotationWidth])
                        )
                    }
                    .onEnded { _ in
                        if let draft { controller.add(draft, to: shot) }
                        draft = nil
                    }
            )
        }
    }

    private var annotationColor: ColorValue {
        ColorValue(parsing: settings[.annotationColor]) ?? ColorValue(red255: 255, green255: 59, blue255: 48)
    }

    private var sidePane: some View {
        VStack(spacing: AnvilSpacing.md) {
            textPane
            historyPane
        }
    }

    private var textPane: some View {
        AnvilPane("Text in der Aufnahme", systemImage: "text.viewfinder") {
            if let shot = controller.selected, let text = shot.text, !text.isEmpty {
                AnvilTextView(text)
            } else if let shot = controller.selected {
                EmptyStateView(
                    title: "Noch nicht gelesen",
                    message: "Der Text wird auf diesem Mac erkannt, nichts geht ins Netz.",
                    systemImage: "text.viewfinder"
                ) {
                    AnvilButton("Text lesen", systemImage: "text.viewfinder") {
                        controller.readText(shot)
                    }
                }
            } else {
                EmptyStateView(
                    title: "Kein Bild",
                    message: "Sobald eine Aufnahme da ist, steht ihr Text hier.",
                    systemImage: "text.viewfinder"
                )
            }
        } accessory: {
            if let text = controller.selected?.text, !text.isEmpty {
                CopyButton(text: text)
            }
        }
    }

    private var historyPane: some View {
        AnvilPane("Diese Sitzung", systemImage: "clock.arrow.circlepath", contentInset: true) {
            if controller.shots.isEmpty {
                EmptyStateView(
                    title: "Leer",
                    message: "Aufnahmen dieser Sitzung sammeln sich hier.",
                    systemImage: "photo.stack"
                )
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: AnvilSpacing.sm) {
                        ForEach(controller.shots) { shot in
                            thumbnail(shot)
                        }
                    }
                    .padding(.vertical, AnvilSpacing.xxs)
                }
            }
        } accessory: {
            if !controller.shots.isEmpty {
                Button { controller.clear() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(AnvilIconButtonStyle(tone: .danger))
                .anvilHelp("Alle verwerfen")
            }
        }
        .frame(height: AnvilSize.secondaryListHeight)
    }

    private func thumbnail(_ shot: Screenshot) -> some View {
        Button { controller.selectedID = shot.id } label: {
            VStack(spacing: AnvilSpacing.xxs) {
                Image(nsImage: shot.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: AnvilSize.thumbnailWidth, height: AnvilSize.thumbnailHeight)
                    .clipShape(RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous))

                Text(verbatim: shot.takenAt.formatted(date: .omitted, time: .standard))
                    .font(AnvilFont.caption.monospacedDigit())
                    .foregroundStyle(AnvilColor.textTertiary)
            }
            .padding(AnvilSpacing.xxs)
            .background {
                RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                    .fill(controller.selected?.id == shot.id ? AnvilColor.accent.opacity(0.15) : .clear)
            }
        }
        .buttonStyle(.plain)
        .anvilHelp(.resolved(shot.target.title))
    }

    private var statusBar: some View {
        ToolStatusBar {
            if let shot = controller.selected {
                StatusMetric(
                    "\(Int(shot.pixelSize.width)) × \(Int(shot.pixelSize.height))",
                    label: "Pixel",
                    systemImage: "aspectratio"
                )
                if let text = shot.text, !text.isEmpty {
                    StatusMetric("\(text.count)", label: "Zeichen", systemImage: "character", tone: .success)
                }
                if shot.fileURL != nil {
                    StatusMetric("PNG", label: "Gesichert", systemImage: "checkmark.seal", tone: .success)
                }
            }
            StatusMetric("\(controller.shots.count)", label: "Aufnahmen", systemImage: "photo.stack")
        } trailing: {
            if settings[.screenshotDelay] > 0 {
                StatusPill(
                    .resolved("\(settings[.screenshotDelay]) s"),
                    systemImage: "timer",
                    tone: .warning
                )
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Markieren",
            systemImage: "pencil.tip",
            footnote: .resolved(settings[.annotationKind].explanation)
        ) {
            ChipPicker(
                selection: settings.bind(.annotationKind),
                options: Annotation.Kind.allCases,
                title: \.title,
                systemImage: { $0.systemImage }
            )

            OptionRow("Farbe") {
                HStack(spacing: AnvilSpacing.xs) {
                    ForEach(Self.markerColors, id: \.self) { hex in
                        Button { settings[.annotationColor] = hex } label: {
                            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                                .fill(Color(parsing: hex))
                                .frame(width: AnvilSize.toolIcon, height: AnvilSize.toolIcon)
                                .overlay {
                                    RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                                        .strokeBorder(
                                            settings[.annotationColor] == hex
                                                ? AnvilColor.textPrimary
                                                : AnvilColor.border,
                                            lineWidth: settings[.annotationColor] == hex ? 2 : 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .anvilHelp(.resolved(hex))
                    }
                }
            }

            OptionRow("Strichstärke") {
                Picker("", selection: settings.bind(.annotationWidth)) {
                    ForEach([2, 4, 8], id: \.self) { width in
                        Text(verbatim: "\(width)").tag(width)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }

        InspectorSection(
            "Danach",
            systemImage: "arrow.right.circle",
            footnote: "Gilt für jede Aufnahme, auch die per Tastenkürzel."
        ) {
            Toggle("Bild in die Zwischenablage", isOn: settings.bind(.screenshotCopiesImage))
                .font(AnvilFont.body)
            Toggle("Als PNG behalten", isOn: settings.bind(.screenshotKeepsFile))
                .font(AnvilFont.body)
            Toggle("Text gleich mitlesen", isOn: settings.bind(.screenshotReadsText))
                .font(AnvilFont.body)
            Toggle("Text statt Bild kopieren", isOn: settings.bind(.screenshotCopiesText))
                .font(AnvilFont.body)
                .disabled(!settings[.screenshotReadsText])
        }

        InspectorSection(
            "Aufnahme",
            systemImage: "camera",
            footnote: "Die Verzögerung gilt nur für den ganzen Bildschirm — beim Ausschnitt wartest du ohnehin selbst."
        ) {
            OptionRow("Verzögerung") {
                Picker("", selection: settings.bind(.screenshotDelay)) {
                    ForEach([0, 3, 5, 10], id: \.self) { seconds in
                        Text(verbatim: seconds == 0 ? "—" : "\(seconds) s").tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if ScreenCapture.displayCount > 1 {
                OptionRow(
                    "Bildschirm",
                    help: "Gilt für die Vollbildaufnahme — mit einem Dateinamen kann immer nur ein Bildschirm gemeint sein."
                ) {
                    Picker("", selection: settings.bind(.screenshotDisplay)) {
                        ForEach(1...ScreenCapture.displayCount, id: \.self) { index in
                            Text(verbatim: "\(index)").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            Toggle("Mauszeiger mit aufnehmen", isOn: settings.bind(.screenshotIncludesCursor))
                .font(AnvilFont.body)
            Toggle("Fensterschatten behalten", isOn: settings.bind(.screenshotIncludesShadow))
                .font(AnvilFont.body)
            Toggle("Auslöseton", isOn: settings.bind(.screenshotPlaysSound))
                .font(AnvilFont.body)
        }

        InspectorSection(
            "Ablage",
            systemImage: "folder",
            footnote: "Gesicherte Aufnahmen liegen unter Anvil › Screenshots."
        ) {
            AnvilButton("Ordner öffnen", systemImage: "folder", role: .secondary) {
                AppPaths.bootstrap()
                NSWorkspace.shared.open(AppPaths.screenshots)
            }
        }

        InspectorSection(
            "Tastenkürzel",
            systemImage: "command",
            footnote: "Jede Aufnahmeart hat ihr eigenes Kürzel — in den Einstellungen unter „Tastenkürzel\"."
        ) {
            ForEach(shortcutSummaries, id: \.0) { title, keys in
                HStack {
                    Text(verbatim: title)
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textSecondary)
                    Spacer(minLength: AnvilSpacing.sm)
                    Text(verbatim: keys)
                        .font(AnvilFont.monoSmall)
                        .foregroundStyle(AnvilColor.textTertiary)
                }
            }
        }
    }

    // MARK: - Derived

    private var shortcutSummaries: [(String, String)] {
        ScreenshotToolBundle.actionIDs.compactMap { id in
            guard let action = context.shortcuts.action(id) else { return nil }
            let setting = context.shortcuts.setting(for: id)
            guard setting.scope != .off, let shortcut = setting.shortcut else {
                return (action.title, localized("aus"))
            }
            return (action.title, shortcut.displayString)
        }
    }

    /// Colours that stay visible on a screenshot: strong, saturated, and not
    /// something an interface is likely to already be full of.
    private static let markerColors = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#000000"]


}
