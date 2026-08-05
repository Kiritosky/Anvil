import AnvilAI
import AnvilKit
import AnvilSpeech
import Foundation
import Observation

/// The state and behaviour behind the Speech Studio.
///
/// Deliberately separate from the view: recording, cleaning and refining are
/// three stages with their own failure modes, and keeping them out of SwiftUI
/// makes them straightforward to reason about — and to test.
@MainActor
@Observable
public final class SpeechStudioModel {
    // MARK: Stages

    /// Straight from the recogniser, before anything touched it.
    public var rawText: String = ""
    /// After the deterministic filler pass.
    public private(set) var cleanedText: String = ""
    /// After the model pass. Empty until a refinement has run.
    public private(set) var refinedText: String = ""

    public private(set) var cleanerResult = FillerCleaner.Result(text: "")
    public private(set) var isRefining = false
    public private(set) var refinementProgress: TranscriptRefiner.Progress?
    public var error: AnvilError?
    public private(set) var lastRunDuration: TimeInterval?

    /// Whether the result pane shows a diff instead of the text.
    public var showsDiff = false

    public let session: DictationSession
    @ObservationIgnored private let refiner: TranscriptRefiner
    @ObservationIgnored private let context: ToolContext
    @ObservationIgnored private let toolID: ToolIdentifier
    @ObservationIgnored private var refinementTask: Task<Void, Never>?
    @ObservationIgnored private let fileTranscriber: AudioFileTranscriber

    public init(context: ToolContext, toolID: ToolIdentifier) {
        self.context = context
        self.toolID = toolID
        let session = DictationSession()
        self.session = session
        self.fileTranscriber = AudioFileTranscriber(catalog: session.catalog)
        self.refiner = TranscriptRefiner(router: context.ai)
    }

    // MARK: - Preferences

    private var settings: SettingsStore { context.settings }

    public var localeIdentifier: String {
        get { settings[.speechLocale] }
        set { settings[.speechLocale] = newValue }
    }

    public var locale: Locale {
        localeIdentifier.isEmpty ? session.catalog.preferredLocale() : Locale(identifier: localeIdentifier)
    }

    public var style: RefinementStyle {
        get { settings[.refinementStyle] }
        set { settings[.refinementStyle] = newValue }
    }

    public var cleanerStrength: FillerCleaner.Strength {
        get { settings[.fillerStrength] }
        set {
            settings[.fillerStrength] = newValue
            recompute()
        }
    }

    public var collapsesRepeats: Bool {
        get { settings[.collapseRepeats] }
        set {
            settings[.collapseRepeats] = newValue
            recompute()
        }
    }

    public var usesAI: Bool {
        get { settings[.useAIRefinement] }
        set { settings[.useAIRefinement] = newValue }
    }

    public var refinesAutomatically: Bool {
        get { settings[.autoRefineOnStop] }
        set { settings[.autoRefineOnStop] = newValue }
    }

    public var keepsAudio: Bool {
        get { settings[.keepAudio] }
        set { settings[.keepAudio] = newValue }
    }

    public var customInstruction: String {
        get { settings[.customRefinementInstruction] }
        set { settings[.customRefinementInstruction] = newValue }
    }

    // MARK: - Derived

    /// What the result pane shows: the model output when there is one, the
    /// deterministic cleanup otherwise.
    public var resultText: String {
        refinedText.isEmpty ? cleanedText : refinedText
    }

    public var hasResult: Bool { !resultText.isEmpty }
    public var isRecording: Bool { session.state == .recording }
    public var isPaused: Bool { session.state == .paused }
    public var canRefine: Bool { !rawText.isEmpty && !isRefining }

    public var languageName: String {
        session.catalog.displayName(for: locale)
    }

    public var wordCount: Int {
        resultText.split(whereSeparator: \.isWhitespace).count
    }

    public var rawWordCount: Int {
        rawText.split(whereSeparator: \.isWhitespace).count
    }

    // MARK: - Recording

    public func prepare() async {
        await session.catalog.refresh()
        if localeIdentifier.isEmpty {
            localeIdentifier = session.catalog.preferredLocale().identifier
        }
        await context.ai.refreshAvailability()
    }

    public func toggleRecording() async {
        switch session.state {
        case .idle, .finished:
            await startRecording()
        case .recording:
            await stopRecording()
        case .paused:
            session.resume()
        case .preparing, .finishing:
            break
        }
    }

    public func startRecording() async {
        error = nil
        refinedText = ""
        refinementProgress = nil
        await session.start(locale: locale, keepAudio: keepsAudio)

        if let sessionError = session.error {
            error = sessionError
            return
        }
        observeLiveTranscript()
    }

    public func stopRecording() async {
        await session.stop()
        syncFromTranscript()

        if refinesAutomatically, usesAI, !rawText.isEmpty {
            await refine()
        }
    }

    public func pauseOrResume() {
        session.state == .paused ? session.resume() : session.pause()
    }

    public func discardRecording() async {
        cancelRefinement()
        await session.discard()
        rawText = ""
        cleanedText = ""
        refinedText = ""
        cleanerResult = FillerCleaner.Result(text: "")
        error = nil
    }

    /// Mirrors the live transcript into `rawText` while recording.
    ///
    /// A polling loop rather than an observer: `Transcript` changes on nearly
    /// every audio buffer, and repainting the editor that often is wasted work.
    private func observeLiveTranscript() {
        Task { @MainActor [weak self] in
            while let self, self.session.isActive {
                self.syncFromTranscript()
                try? await Task.sleep(for: .milliseconds(250))
            }
            self?.syncFromTranscript()
        }
    }

    private func syncFromTranscript() {
        let text = session.transcript.displayText
        guard text != rawText else { return }
        rawText = text
        recompute()
    }

    // MARK: - Cleaning

    /// Re-runs the deterministic pass. Cheap, so it runs on every edit.
    public func recompute() {
        let cleaner = FillerCleaner(
            languageCode: locale.language.languageCode?.identifier ?? "de",
            strength: cleanerStrength,
            collapsesRepeats: collapsesRepeats
        )
        cleanerResult = cleaner.clean(rawText)
        cleanedText = cleanerResult.text
    }

    // MARK: - Refining

    public func refine() async {
        guard canRefine else { return }

        cancelRefinement()
        error = nil
        isRefining = true
        refinedText = ""
        let startedAt = Date.now

        // The model gets the deterministically cleaned text, not the raw one:
        // it has less noise to wade through and cannot "fix" a filler by
        // turning it into a real word.
        let input = cleanedText.isEmpty ? rawText : cleanedText

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await self.refiner.refine(
                    input,
                    style: self.style,
                    languageName: self.languageName,
                    customInstruction: self.customInstruction,
                    onProgress: { [weak self] progress in
                        self?.refinementProgress = progress
                    },
                    onPartial: { [weak self] partial in
                        self?.refinedText = partial
                    }
                )
                self.refinedText = result
                self.lastRunDuration = Date.now.timeIntervalSince(startedAt)
                self.record(result: result)
            } catch {
                let wrapped = AnvilError.wrapping(error)
                if !wrapped.isCancellation { self.error = wrapped }
                self.refinedText = ""
            }
            self.isRefining = false
            self.refinementProgress = nil
        }

        refinementTask = task
        await task.value
    }

    public func cancelRefinement() {
        refinementTask?.cancel()
        refinementTask = nil
        isRefining = false
        refinementProgress = nil
    }

    // MARK: - Files

    /// Transcribes an audio file the user picked, replacing the current text.
    public func transcribeFile(at url: URL) async {
        error = nil
        do {
            let transcript = try await fileTranscriber.transcribe(url: url, locale: locale)
            rawText = transcript.finalizedText
            recompute()
            if refinesAutomatically, usesAI { await refine() }
        } catch {
            self.error = AnvilError.wrapping(error)
        }
    }

    public var fileTranscriptionProgress: Double? {
        fileTranscriber.isTranscribing ? fileTranscriber.progress : nil
    }

    /// Writes the current result next to the recording and returns its URL.
    @discardableResult
    public func export() throws -> URL {
        guard hasResult else {
            throw AnvilError.invalidInput(localized("Es gibt noch kein Ergebnis zum Sichern."))
        }
        AppPaths.bootstrap()

        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let url = AppPaths.exports.appending(path: "Diktat \(stamp).md")

        let document = """
        # Diktat vom \(Date.now.formatted(date: .abbreviated, time: .shortened))

        _Sprache: \(languageName) · Stil: \(style.title)_

        \(resultText)

        ---

        ## Rohtranskript

        \(rawText)
        """

        do {
            try document.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AnvilError.storage(localized("Der Export ist fehlgeschlagen: \(error.localizedDescription)"))
        }
        return url
    }

    public func copyResult() {
        guard hasResult else { return }
        context.pasteboard.copy(resultText)
    }

    // MARK: - History

    private func record(result: String) {
        guard !result.isEmpty else { return }
        context.history.record(
            HistoryEntry(
                toolID: toolID,
                title: String(result.prefix(60)),
                input: rawText,
                output: result,
                attributes: [
                    "style": style.rawValue,
                    "locale": locale.identifier,
                    "provider": context.ai.activeProviderName
                ]
            )
        )
    }

    public var history: [HistoryEntry] {
        context.history.entries(for: toolID)
    }

    public func restore(_ entry: HistoryEntry) {
        rawText = entry.input
        refinedText = entry.output
        recompute()
    }
}

// MARK: - Settings keys

extension SettingKey {
    public static var speechLocale: SettingKey<String> {
        SettingKey<String>("speech.locale", default: "")
    }

    public static var refinementStyle: SettingKey<RefinementStyle> {
        SettingKey<RefinementStyle>("speech.style", default: .verbatim)
    }

    public static var fillerStrength: SettingKey<FillerCleaner.Strength> {
        SettingKey<FillerCleaner.Strength>("speech.fillerStrength", default: .gentle)
    }

    public static var collapseRepeats: SettingKey<Bool> {
        SettingKey<Bool>("speech.collapseRepeats", default: true)
    }

    public static var useAIRefinement: SettingKey<Bool> {
        SettingKey<Bool>("speech.useAI", default: true)
    }

    public static var autoRefineOnStop: SettingKey<Bool> {
        SettingKey<Bool>("speech.autoRefine", default: true)
    }

    public static var keepAudio: SettingKey<Bool> {
        SettingKey<Bool>("speech.keepAudio", default: true)
    }

    public static var customRefinementInstruction: SettingKey<String> {
        SettingKey<String>("speech.customInstruction", default: "")
    }
}
