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
        VStack(spacing: AnvilSpacing.md) {
            WorkbenchLayout(orientation: .constant(.horizontal), storageKey: metadata.id.rawValue) {
                previewPane
                    .padding(.trailing, AnvilSpacing.sm)
            } secondary: {
                sidePane
                    .padding(.leading, AnvilSpacing.sm)
            }

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
                Image(nsImage: shot.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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
                Button { controller.copyImage(shot) } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .help("Bild kopieren")

                Button { controller.keep(shot) } label: {
                    Image(systemName: shot.fileURL == nil ? "square.and.arrow.down" : "checkmark.circle")
                }
                .buttonStyle(AnvilIconButtonStyle(isActive: shot.fileURL != nil, tone: .success))
                .help(shot.fileURL == nil ? "Als PNG sichern" : "Ist gesichert")

                Button { controller.reveal(shot) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .help("Im Finder zeigen")

                Button { controller.remove(shot) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(AnvilIconButtonStyle(tone: .danger))
                .help("Verwerfen")
            }
        }
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
                .help("Alle verwerfen")
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
        .help(.resolved(shot.target.title))
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
            "Danach",
            systemImage: "arrow.right.circle",
            footnote: "Gilt für jede Aufnahme, auch die per Tastenkürzel."
        ) {
            Toggle("Bild in die Zwischenablage", isOn: binding(.screenshotCopiesImage))
                .font(AnvilFont.body)
            Toggle("Als PNG behalten", isOn: binding(.screenshotKeepsFile))
                .font(AnvilFont.body)
            Toggle("Text gleich mitlesen", isOn: binding(.screenshotReadsText))
                .font(AnvilFont.body)
            Toggle("Text statt Bild kopieren", isOn: binding(.screenshotCopiesText))
                .font(AnvilFont.body)
                .disabled(!settings[.screenshotReadsText])
        }

        InspectorSection(
            "Aufnahme",
            systemImage: "camera",
            footnote: "Die Verzögerung gilt nur für den ganzen Bildschirm — beim Ausschnitt wartest du ohnehin selbst."
        ) {
            OptionRow("Verzögerung") {
                Picker("", selection: binding(.screenshotDelay)) {
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
                    Picker("", selection: binding(.screenshotDisplay)) {
                        ForEach(1...ScreenCapture.displayCount, id: \.self) { index in
                            Text(verbatim: "\(index)").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            Toggle("Mauszeiger mit aufnehmen", isOn: binding(.screenshotIncludesCursor))
                .font(AnvilFont.body)
            Toggle("Fensterschatten behalten", isOn: binding(.screenshotIncludesShadow))
                .font(AnvilFont.body)
            Toggle("Auslöseton", isOn: binding(.screenshotPlaysSound))
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

    private func binding<Value>(_ key: SettingKey<Value>) -> Binding<Value> {
        Binding(
            get: { settings[key] },
            set: { settings[key] = $0 }
        )
    }
}
