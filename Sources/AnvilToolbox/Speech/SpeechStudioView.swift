import AnvilAI
import AnvilKit
import AnvilSpeech
import AnvilUI
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Dictate, transcribe, clean up.
///
/// The screen is deliberately two panes: what was said on the left, what you
/// can actually use on the right. Everything else — language, style, how hard
/// to scrub — sits in the inspector, because those are settings you change
/// once a month, not once a sentence.
public struct SpeechStudioView: View {
    @State private var model: SpeechStudioModel
    @State private var orientation: WorkbenchOrientation = .horizontal
    @State private var isShowingHistory = false
    @State private var exportedURL: URL?

    private let metadata: ToolMetadata

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.metadata = metadata
        _model = State(initialValue: SpeechStudioModel(context: context, toolID: metadata.id))
    }

    public var body: some View {
        @Bindable var model = model

        ToolScaffold(metadata: metadata, tone: .ai) {
            content
        } inspector: {
            inspector
        } actions: {
            headerActions
        }
        .task { await model.prepare() }
        .onDisappear {
            model.cancelRefinement()
            Task { await model.releaseSpeechAssets() }
        }
        .sheet(isPresented: $isShowingHistory) {
            HistorySheet(entries: model.history) { entry in
                model.restore(entry)
                isShowingHistory = false
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerActions: some View {
        if model.isRefining {
            AnvilButton("Abbrechen", systemImage: "stop.fill", role: .secondary) {
                model.cancelRefinement()
            }
        } else {
            AnvilButton(
                "Aufräumen",
                systemImage: "wand.and.stars",
                role: .secondary
            ) {
                Task { await model.refine() }
            }
            .disabled(!model.canRefine || !model.usesAI)
            .anvilHelp(model.usesAI ? "Mit dem Modell aufräumen" : "KI-Aufbereitung ist in den Optionen aus")
        }

        recordButton

        Divider().frame(height: 18)

        WorkbenchOrientationPicker(orientation: $orientation)

        Button { isShowingHistory = true } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .buttonStyle(AnvilIconButtonStyle())
        .anvilHelp("Verlauf")
    }

    private var recordButton: some View {
        AnvilButton(
            recordButtonTitle,
            systemImage: model.isRecording ? "stop.fill" : "mic.fill",
            role: .primary,
            isBusy: model.session.isBusy
        ) {
            Task { await model.toggleRecording() }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
    }

    private var recordButtonTitle: LocalizedStringKey {
        switch model.session.state {
        case .recording: "Stoppen"
        case .paused: "Weiter"
        case .preparing: "Startet …"
        case .finishing: "Schließt ab …"
        case .idle, .finished: "Aufnehmen"
        }
    }

    // MARK: - Content

    private var content: some View {
        @Bindable var model = model

        return VStack(spacing: AnvilSpacing.md) {
            if let error = model.error {
                AnvilBanner(error: error, onDismiss: { model.error = nil })
            }

            if let url = exportedURL {
                AnvilBanner(
                    title: "Gesichert",
                    message: .resolved(url.lastPathComponent),
                    tone: .success,
                    actionTitle: "Im Finder zeigen",
                    action: { NSWorkspace.shared.activateFileViewerSelecting([url]) },
                    onDismiss: { exportedURL = nil }
                )
            }

            if model.session.isActive || model.session.state == .preparing {
                recordingStrip
            }

            if let progress = model.fileTranscriptionProgress {
                ProgressStrip("Datei wird transkribiert", progress: progress, tone: .accent)
            }

            ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
                transcriptPane
            } secondary: {
                resultPane
            } status: {
                statusBar
            }
        }
    }

    private var recordingStrip: some View {
        HStack(spacing: AnvilSpacing.md) {
            ActivityDot(tone: .danger, isActive: model.isRecording)

            Text(Self.timecode(model.session.duration))
                .font(AnvilFont.mono)
                .monospacedDigit()
                .foregroundStyle(AnvilColor.textPrimary)

            LevelMeter(levels: model.session.levels, isActive: model.isRecording, tone: .danger)
                .frame(maxWidth: .infinity)

            Button { model.pauseOrResume() } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp(model.isPaused ? "Weiter aufnehmen" : "Pause")

            Button { Task { await model.discardRecording() } } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(AnvilIconButtonStyle(tone: .danger))
            .anvilHelp("Aufnahme verwerfen")
        }
        .padding(.horizontal, AnvilSpacing.md)
        .padding(.vertical, AnvilSpacing.sm)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .fill(AnvilColor.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .strokeBorder(AnvilColor.border, lineWidth: 1)
        }
    }

    // MARK: - Panes

    private var transcriptPane: some View {
        @Bindable var model = model

        return AnvilPane("Diktat", systemImage: "mic") {
            if model.rawText.isEmpty, !model.session.isActive {
                EmptyStateView(
                    title: "Noch nichts aufgenommen",
                    message: "Drück auf Aufnehmen und sprich einfach los — ⌘⇧R geht auch. Alternativ eine vorhandene Audiodatei öffnen.",
                    systemImage: "waveform",
                    tone: .ai
                ) {
                    AnvilButton("Audiodatei öffnen", systemImage: "folder", role: .secondary) {
                        openAudioFile()
                    }
                }
            } else {
                AnvilTextEditor(
                    text: $model.rawText,
                    placeholder: "Hier erscheint, was erkannt wurde.",
                    isEditable: !model.session.isActive
                )
                .onChange(of: model.rawText) { _, _ in
                    guard !model.session.isActive else { return }
                    model.recompute()
                }
            }
        } accessory: {
            if model.rawWordCount > 0 {
                Text("\(model.rawWordCount) Wörter")
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
            }
            Button { openAudioFile() } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Audiodatei transkribieren")

            CopyButton(text: model.rawText)
        }
    }

    private var resultPane: some View {
        AnvilPane(
            model.refinedText.isEmpty ? "Bereinigt" : .resolved("Ergebnis · \(model.style.title)"),
            systemImage: model.refinedText.isEmpty ? "eraser" : model.style.systemImage,
            tone: model.refinedText.isEmpty ? .neutral : .ai
        ) {
            resultContent
        } accessory: {
            if model.isRefining {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            }

            Button { model.showsDiff.toggle() } label: {
                Image(systemName: "plusminus")
            }
            .buttonStyle(AnvilIconButtonStyle(isActive: model.showsDiff))
            .anvilHelp("Änderungen hervorheben")
            .disabled(!model.hasResult)

            Button {
                exportedURL = try? model.export()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Als Markdown sichern")
            .disabled(!model.hasResult)

            CopyButton(text: model.resultText)
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        if !model.hasResult {
            EmptyStateView(
                title: "Noch kein Ergebnis",
                message: "Sobald etwas diktiert ist, räumt Anvil Füllwörter weg — und mit „Aufräumen\" macht das Modell daraus \(model.style.title.lowercased()).",
                systemImage: model.style.systemImage
            )
        } else if model.showsDiff {
            DiffTextView(from: model.rawText, to: model.resultText)
        } else {
            AnvilTextView(model.resultText, followsTail: model.isRefining)
        }
    }

    // MARK: - Status

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric(model.languageName, systemImage: "globe")

            if model.cleanerResult.changeCount > 0 {
                StatusMetric(
                    "\(model.cleanerResult.removedFillers)",
                    label: "Füllwörter",
                    systemImage: "eraser",
                    tone: .success
                )
                if model.cleanerResult.collapsedRepeats > 0 {
                    StatusMetric(
                        "\(model.cleanerResult.collapsedRepeats)",
                        label: "Doppelungen",
                        systemImage: "repeat",
                        tone: .success
                    )
                }
            }

            if model.vocabularyCorrectionCount > 0 {
                StatusMetric(
                    "\(model.vocabularyCorrectionCount)",
                    label: "Vokabular",
                    systemImage: "character.book.closed",
                    tone: .success
                )
            }

            if model.hasResult {
                StatusMetric("\(model.wordCount)", label: "Wörter", systemImage: "text.word.spacing")
            }

            if let progress = model.refinementProgress, progress.isChunked {
                StatusMetric(
                    "\(progress.chunkIndex + 1)/\(progress.chunkCount)",
                    label: "Abschnitte",
                    systemImage: "square.stack",
                    tone: .ai
                )
            }
        } trailing: {
            if let duration = model.lastRunDuration {
                StatusMetric(
                    String(format: "%.1fs", duration),
                    systemImage: "clock",
                    tone: .neutral
                )
            }
            ModelStatusPill()
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        @Bindable var model = model

        InspectorSection("Sprache", systemImage: "globe") {
            Picker("Sprache", selection: $model.localeIdentifier) {
                ForEach(model.session.catalog.supportedLocales, id: \.identifier) { locale in
                    Text(model.session.catalog.displayName(for: locale))
                        .tag(locale.identifier)
                }
            }
            .labelsHidden()
            .disabled(model.session.isActive)

            if model.session.catalog.isPreparing {
                ProgressStrip(
                    "Sprachpaket wird geladen",
                    progress: model.session.catalog.downloadProgress,
                    tone: .accent
                )
            } else if !model.session.catalog.isInstalled(model.locale) {
                Text("Wird beim ersten Start dieser Sprache heruntergeladen.")
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
            }
        }

        InspectorSection(
            "Stil",
            systemImage: "wand.and.stars",
            footnote: .resolved(model.style.explanation)
        ) {
            ChipPicker(
                selection: $model.style,
                options: RefinementStyle.offered,
                tone: .ai,
                title: \.title,
                systemImage: { $0.systemImage }
            )

            if model.style == .custom {
                AnvilTextEditor(
                    text: $model.customInstruction,
                    placeholder: "Was soll das Modell mit dem Text machen?"
                )
                .frame(height: 80)
                .background(AnvilColor.field)
                .clipShape(RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                        .strokeBorder(AnvilColor.border, lineWidth: 1)
                }
            }
        }

        InspectorSection(
            "Füllwörter",
            systemImage: "eraser",
            footnote: .resolved(model.cleanerStrength.explanation)
        ) {
            ChipPicker(
                selection: $model.cleanerStrength,
                options: FillerCleaner.Strength.allCases,
                title: \.title
            )
            Toggle("Wortdoppelungen zusammenfassen", isOn: $model.collapsesRepeats)
                .font(AnvilFont.body)
        }

        InspectorSection(
            "Vokabular",
            systemImage: "character.book.closed",
            footnote: vocabularyFootnote
        ) {
            ChipPicker(
                selection: $model.vocabularySensitivity,
                options: VocabularyCorrector.Sensitivity.allCases,
                title: \.title
            )
            .disabled(model.vocabularyTermCount == 0)
        }

        InspectorSection("Ablauf", systemImage: "slider.horizontal.3") {
            Toggle("Modell verwenden", isOn: $model.usesAI)
                .font(AnvilFont.body)
            Toggle("Nach dem Stoppen automatisch aufräumen", isOn: $model.refinesAutomatically)
                .font(AnvilFont.body)
                .disabled(!model.usesAI)
            Toggle("Aufnahme behalten", isOn: $model.keepsAudio)
                .font(AnvilFont.body)
        }
    }

    // MARK: - Helpers

    /// Points at the vocabulary tool while the list is still empty — the
    /// sensitivity chips mean nothing until there is something to enforce.
    private var vocabularyFootnote: LocalizedStringKey {
        guard model.vocabularyTermCount > 0 else {
            return "Noch keine Begriffe — anzulegen im Werkzeug „Diktat-Vokabular\"."
        }
        return .resolved(model.vocabularySensitivity.explanation)
    }

    private func openAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .wav, .aiff, .mp3]
        panel.allowsMultipleSelection = false
        panel.prompt = "Transkribieren"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.transcribeFile(at: url) }
    }

    static func timecode(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// The run history of a tool, as a picker sheet.
struct HistorySheet: View {
    let entries: [HistoryEntry]
    let onSelect: (HistoryEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ToolHeaderBar(
                title: localized("Verlauf"),
                subtitle: localized("\(entries.count) gespeicherte Durchläufe"),
                systemImage: "clock.arrow.circlepath"
            ) {
                AnvilButton("Fertig", role: .secondary) { dismiss() }
            }

            Divider()

            if entries.isEmpty {
                EmptyStateView(
                    title: "Noch nichts im Verlauf",
                    message: "Jeder abgeschlossene Durchlauf landet hier.",
                    systemImage: "clock"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AnvilSpacing.sm) {
                        ForEach(entries) { entry in
                            Button { onSelect(entry) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(AnvilFont.caption)
                                        .foregroundStyle(AnvilColor.textTertiary)
                                    Text(entry.preview)
                                        .font(AnvilFont.body)
                                        .foregroundStyle(AnvilColor.textPrimary)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(AnvilSpacing.md)
                                .background {
                                    RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                                        .fill(AnvilColor.surface)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(AnvilSpacing.lg)
                }
            }
        }
        .frame(width: 520, height: 460)
    }
}
