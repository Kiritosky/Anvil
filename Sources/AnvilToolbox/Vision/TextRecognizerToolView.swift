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

    @State private var pages: [Page] = []
    @State private var selectedID: Page.ID?
    @State private var isWorking = false
    @State private var error: AnvilError?

    /// Ein Bild und das, was darin stand.
    ///
    /// Mehrere davon, weil man selten genau einen Screenshot ausliest: Eine
    /// Anleitung besteht aus fünf, ein abfotografiertes Dokument aus zehn.
    struct Page: Identifiable {
        let id = UUID()
        let name: String
        let image: NSImage
        var result: TextRecognizer.Result?
        var failure: String?
    }

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
        .anvilFilesDrop(.image, error: $error) { dropped in
            add(dropped.compactMap { item -> Page? in
                guard case let .image(image, url) = item else { return nil }
                return Page(
                    name: url?.lastPathComponent ?? localized("Bild \(pages.count + 1)"),
                    image: image
                )
            })
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
        AnvilPane(
            pages.count > 1 ? "Bilder" : "Bild",
            systemImage: pages.count > 1 ? "photo.stack" : "photo"
        ) {
            if pages.count > 1 {
                pageList
            } else if let image = pages.first?.image {
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
            if !pages.isEmpty {
                if pages.count > 1 {
                    Text(verbatim: "\(pages.count)")
                        .font(AnvilFont.caption.monospacedDigit())
                        .foregroundStyle(AnvilColor.textTertiary)
                }

                Button { clear() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Verwerfen")
            }
        }
    }

    /// Die Liste, sobald es mehr als ein Bild ist.
    ///
    /// Mit Vorschaubild, weil ein Dateiname bei zehn Screenshots aus derselben
    /// Anleitung nichts unterscheidet — das Bild schon.
    private var pageList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: AnvilSpacing.xxs) {
                ForEach(pages) { page in
                    Button { selectedID = page.id } label: {
                        HStack(spacing: AnvilSpacing.sm) {
                            Image(nsImage: page.image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(
                                    width: AnvilSize.thumbnailWidth / 2,
                                    height: AnvilSize.thumbnailHeight / 2
                                )
                                .clipShape(
                                    RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                                )

                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: page.name)
                                    .font(AnvilFont.rowTitle)
                                    .foregroundStyle(AnvilColor.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Text(verbatim: summary(of: page))
                                    .font(AnvilFont.caption)
                                    .foregroundStyle(AnvilColor.textTertiary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Button { remove(page) } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(AnvilIconButtonStyle())
                            .anvilHelp("Aus der Liste nehmen")
                        }
                        .padding(.horizontal, AnvilSpacing.sm)
                        .padding(.vertical, AnvilSpacing.xs)
                        .background {
                            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                                .fill(selectedID == page.id ? AnvilColor.accent.opacity(0.15) : .clear)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, AnvilSpacing.xxs)
        }
    }

    private var textPane: some View {
        AnvilPane(
            "Gelesen",
            systemImage: "text.viewfinder",
            tone: combinedText.isEmpty ? .neutral : .success
        ) {
            if isWorking {
                EmptyStateView(
                    title: "Wird gelesen …",
                    message: "Das läuft auf diesem Mac, nichts geht ins Netz.",
                    systemImage: "sparkles"
                )
            } else if !combinedText.isEmpty {
                AnvilTextView(combinedText)
            } else if !pages.isEmpty {
                EmptyStateView(
                    title: "Kein Text gefunden",
                    message: "In den Bildern ist nichts, was sich als Text lesen ließe.",
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
            if !combinedText.isEmpty {
                CopyButton(text: combinedText)
            }
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            if pages.count > 1 {
                StatusMetric("\(pages.count)", label: "Bilder", systemImage: "photo.stack")
            }
            if !readPages.isEmpty {
                StatusMetric("\(totalLines)", label: "Zeilen", systemImage: "text.alignleft")
                StatusMetric("\(combinedText.count)", label: "Zeichen", systemImage: "character")
                StatusMetric(
                    "\(Int((averageConfidence * 100).rounded()))%",
                    label: "Sicherheit",
                    systemImage: "checkmark.seal",
                    tone: averageConfidence > 0.6 ? .success : .warning
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
            add([Page(name: localized("Ausschnitt \(pages.count + 1)"), image: captured)])
        } catch {
            self.error = AnvilError.wrapping(error)
        }
    }

    /// Nimmt Bilder auf und liest sie gleich aus.
    ///
    /// Angehängt statt ersetzt: Wer zweimal hintereinander einen Ausschnitt
    /// wählt, will beide Texte — sonst müsste er den ersten vorher irgendwo
    /// zwischenlagern.
    private func add(_ newPages: [Page]) {
        guard !newPages.isEmpty else { return }
        pages += newPages
        if selectedID == nil { selectedID = pages.first?.id }
        Task { await recognize() }
    }

    private func remove(_ page: Page) {
        pages.removeAll { $0.id == page.id }
        if selectedID == page.id { selectedID = pages.first?.id }
    }

    private func readFromPasteboard() {
        error = nil
        let images = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage]
        guard let pasted = images?.first else {
            error = .invalidInput(localized("In der Zwischenablage liegt kein Bild."))
            return
        }
        add([Page(name: localized("Zwischenablage \(pages.count + 1)"), image: pasted)])
    }

    /// Liest alle Bilder aus, die noch kein Ergebnis haben.
    ///
    /// Nur die neuen: Ein zehntes Bild dazuzulegen darf nicht heißen, die
    /// neun davor noch einmal durch Vision zu schicken.
    private func recognize(force: Bool = false) async {
        let todo = pages.indices.filter { force || pages[$0].result == nil }
        guard !todo.isEmpty else { return }

        isWorking = true
        defer { isWorking = false }

        for index in todo {
            guard index < pages.count else { continue }
            let image = pages[index].image
            let mode = mode
            do {
                let recognised = try await Task.detached(priority: .userInitiated) {
                    try TextRecognizer.recognize(image, mode: mode)
                }.value
                guard index < pages.count else { continue }
                pages[index].result = recognised
                pages[index].failure = nil
            } catch let failure as AnvilError {
                guard index < pages.count else { continue }
                pages[index].failure = failure.message
            } catch {
                guard index < pages.count else { continue }
                pages[index].failure = error.localizedDescription
            }
        }

        if settings[.ocrAutoCopy], !combinedText.isEmpty {
            context.pasteboard.copy(combinedText)
        }
    }

    private func clear() {
        pages = []
        selectedID = nil
        error = nil
    }

    // MARK: - Derived

    private var readPages: [Page] {
        pages.filter { $0.result?.isEmpty == false }
    }

    /// Der Text aller Bilder, mit Überschriften, sobald es mehr als eines ist.
    private var combinedText: String {
        TextBlocks.combine(pages.map { ($0.name, $0.result?.text ?? "") })
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var totalLines: Int {
        readPages.reduce(0) { $0 + ($1.result?.lines.count ?? 0) }
    }

    private var averageConfidence: Float {
        guard !readPages.isEmpty else { return 0 }
        let sum = readPages.reduce(Float(0)) { $0 + ($1.result?.confidence ?? 0) }
        return sum / Float(readPages.count)
    }

    private func summary(of page: Page) -> String {
        if let failure = page.failure { return failure }
        guard let result = page.result else { return localized("wird gelesen …") }
        return result.isEmpty
            ? localized("kein Text")
            : localized("\(result.lines.count) Zeilen")
    }

    private var mode: TextRecognizer.Mode {
        settings[.ocrMode]
    }

    private var modeBinding: Binding<TextRecognizer.Mode> {
        Binding(
            get: { settings[.ocrMode] },
            set: { newValue in
                settings[.ocrMode] = newValue
                // Die Erkennungsart ändert jedes Ergebnis, auch die schon
                // gelesenen — hier muss alles noch einmal durch.
                Task { await recognize(force: true) }
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
