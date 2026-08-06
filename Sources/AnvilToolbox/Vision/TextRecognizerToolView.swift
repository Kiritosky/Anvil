import AnvilKit
import AnvilUI
import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Text off the screen — from a screenshot, an image file, or a rectangle you
/// drag right now.
///
/// The one tool that beats retyping something out of a screenshot, a PDF page
/// or a video still. Everything it needs is already on the machine: Vision does
/// the reading, `screencapture` does the selecting.
public struct TextRecognizerToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var image: NSImage?
    @State private var result: TextRecognizer.Result?
    @State private var isWorking = false
    @State private var error: AnvilError?

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    private var settings: SettingsStore { context.settings }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            AnvilButton(
                "Ausschnitt wählen",
                systemImage: "viewfinder",
                role: .primary,
                isBusy: isWorking
            ) {
                Task { await capture() }
            }

            AnvilButton("Aus Zwischenablage", systemImage: "doc.on.clipboard") {
                readFromPasteboard()
            }
        }
        .anvilErrorBanner($error)
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            load(from: providers)
            return true
        }
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(storageKey: metadata.id.rawValue) {
            imagePane
        } secondary: {
            textPane
        } status: {
            statusBar
        }
    }

    private var imagePane: some View {
        AnvilPane("Bild", systemImage: "photo") {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(AnvilSpacing.md)
            } else {
                EmptyStateView(
                    title: "Kein Bild",
                    message: "Zieh ein Bild hierher, nimm eines aus der Zwischenablage, oder wähl einen Ausschnitt vom Bildschirm.",
                    systemImage: "photo.on.rectangle.angled"
                ) {
                    AnvilButton("Ausschnitt wählen", systemImage: "viewfinder", role: .primary) {
                        Task { await capture() }
                    }
                }
            }
        } accessory: {
            if image != nil {
                Button { clear() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Verwerfen")
            }
        }
    }

    private var textPane: some View {
        AnvilPane("Gelesen", systemImage: "text.viewfinder", tone: result == nil ? .neutral : .success) {
            if isWorking {
                EmptyStateView(
                    title: "Wird gelesen …",
                    message: "Das läuft auf diesem Mac, nichts geht ins Netz.",
                    systemImage: "sparkles"
                )
            } else if let result, !result.isEmpty {
                AnvilTextView(result.text)
            } else if image != nil {
                EmptyStateView(
                    title: "Kein Text gefunden",
                    message: "In dem Bild ist nichts, was sich als Text lesen ließe.",
                    systemImage: "questionmark.circle",
                    tone: .warning
                )
            } else {
                EmptyStateView(
                    title: "Noch nichts gelesen",
                    message: "Sobald ein Bild da ist, steht der Text hier.",
                    systemImage: "text.viewfinder"
                )
            }
        } accessory: {
            if let result, !result.isEmpty {
                CopyButton(text: result.text)
            }
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            if let result, !result.isEmpty {
                StatusMetric("\(result.lines.count)", label: "Zeilen", systemImage: "text.alignleft")
                StatusMetric("\(result.text.count)", label: "Zeichen", systemImage: "character")
                StatusMetric(
                    "\(Int((result.confidence * 100).rounded()))%",
                    label: "Sicherheit",
                    systemImage: "checkmark.seal",
                    tone: result.confidence > 0.6 ? .success : .warning
                )
            }
        } trailing: {
            StatusPill(.resolved(mode.title), systemImage: "textformat", tone: .neutral)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Erkennung",
            systemImage: "textformat",
            footnote: .resolved(mode.explanation)
        ) {
            ChipPicker(
                selection: modeBinding,
                options: TextRecognizer.Mode.allCases,
                title: \.title
            )
        }

        InspectorSection(
            "Danach",
            systemImage: "arrow.right.doc.on.clipboard",
            footnote: "Der gelesene Text landet dann sofort in der Zwischenablage."
        ) {
            Toggle("Automatisch kopieren", isOn: autoCopyBinding)
                .font(AnvilFont.body)
        }

        InspectorSection(
            "Reihenfolge",
            systemImage: "list.number",
            footnote: "Zeilen kommen von oben nach unten, gleich hohe von links nach rechts — zwei Spalten bleiben zwei Spalten."
        ) {
            EmptyView()
        }
    }

    // MARK: - Actions

    private func capture() async {
        error = nil
        do {
            guard let captured = try await TextRecognizer.captureRegion() else { return }
            image = captured
            await recognize()
        } catch {
            self.error = AnvilError.wrapping(error)
        }
    }

    private func readFromPasteboard() {
        error = nil
        let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage]
        guard let pasted = images?.first else {
            error = .invalidInput(localized("In der Zwischenablage liegt kein Bild."))
            return
        }
        image = pasted
        Task { await recognize() }
    }

    private func load(from providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
            guard let dropped = object as? NSImage else { return }
            Task { @MainActor in
                image = dropped
                await recognize()
            }
        }
    }

    private func recognize() async {
        guard let image else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let recognised = try TextRecognizer.recognize(image, mode: mode)
            result = recognised
            if settings[.ocrAutoCopy], !recognised.isEmpty {
                context.pasteboard.copy(recognised.text)
            }
        } catch {
            self.error = AnvilError.wrapping(error)
            result = nil
        }
    }

    private func clear() {
        image = nil
        result = nil
        error = nil
    }

    // MARK: - Derived

    private var mode: TextRecognizer.Mode {
        settings[.ocrMode]
    }

    private var modeBinding: Binding<TextRecognizer.Mode> {
        Binding(
            get: { settings[.ocrMode] },
            set: { newValue in
                settings[.ocrMode] = newValue
                Task { await recognize() }
            }
        )
    }

    private var autoCopyBinding: Binding<Bool> {
        Binding(
            get: { settings[.ocrAutoCopy] },
            set: { settings[.ocrAutoCopy] = $0 }
        )
    }
}
