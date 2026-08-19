import AVFoundation
import AnvilKit
import Foundation
import Observation
import Speech

/// A running `SpeechAnalyzer` you can push microphone buffers into.
@MainActor
@Observable
public final class LiveTranscriptionSession {
    public private(set) var transcript = Transcript()
    public private(set) var isRunning = false
    public private(set) var locale: Locale = Locale(identifier: "en-US")

    /// Asked for the current recording position when a segment is finalised, so
    /// segments carry timings without decoding attributed-string metadata.
    @ObservationIgnored
    public var elapsedTimeProvider: (() -> TimeInterval?)?

    @ObservationIgnored private var transcriber: SpeechTranscriber?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var resultsTask: Task<Void, Never>?
    @ObservationIgnored private let catalog: TranscriptionModelCatalog
    /// Where the previous finalised segment ended, for the next segment's start.
    @ObservationIgnored private var lastSegmentEnd: TimeInterval?

    @ObservationIgnored
    private nonisolated(unsafe) var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private nonisolated(unsafe) var analyzerFormat: AVAudioFormat?
    @ObservationIgnored private nonisolated let converter = BufferConverter()

    public init(catalog: TranscriptionModelCatalog) {
        self.catalog = catalog
    }

    /// The format buffers are converted to before being fed in.
    public nonisolated var requiredFormat: AVAudioFormat? { analyzerFormat }

    // MARK: - Lifecycle

    /// Prepares assets, starts the analyser and begins draining results.
    public func start(locale: Locale) async throws {
        guard !isRunning else { return }

        self.locale = locale
        transcript.clear()
        lastSegmentEnd = nil

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber

        try await catalog.prepare(transcriber: transcriber, locale: locale)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        else {
            throw AnvilError.unexpected(
                localized("Für \(catalog.displayName(for: locale)) ist kein passendes Audioformat verfügbar.")
            )
        }
        analyzerFormat = format
        converter.reset()

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        resultsTask = Task { [weak self] in
            await self?.drainResults(from: transcriber)
        }

        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            await teardown()
            throw AnvilError.unexpected(
                localized("Die Spracherkennung konnte nicht gestartet werden: \(error.localizedDescription)")
            )
        }

        isRunning = true
    }

    /// Feeds one microphone buffer in. Safe to call from the audio thread.
    public nonisolated func feed(_ buffer: AVAudioPCMBuffer) {
        guard let inputContinuation, let analyzerFormat else { return }
        guard let converted = try? converter.convert(buffer, to: analyzerFormat) else { return }
        inputContinuation.yield(AnalyzerInput(buffer: converted))
    }

    /// Closes the input, waits for the tail of the transcript, then tears down.
    public func finish() async {
        guard isRunning else { return }

        inputContinuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await teardown()
    }

    /// Stops immediately, discarding anything not yet finalised.
    public func cancel() async {
        inputContinuation?.finish()
        await teardown()
    }

    private func teardown() async {
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        inputContinuation = nil
        analyzerFormat = nil
        converter.reset()
        transcript.volatileText = ""
        isRunning = false
    }

    // MARK: - Results

    private func drainResults(from transcriber: SpeechTranscriber) async {
        do {
            for try await result in transcriber.results {
                let text = String(result.text.characters)

                guard result.isFinal else {
                    transcript.volatileText = text
                    continue
                }

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let end = elapsedTimeProvider?()
                    transcript.append(
                        TranscriptSegment(text: trimmed, start: lastSegmentEnd, end: end)
                    )
                    lastSegmentEnd = end
                }
                transcript.volatileText = ""
            }
        } catch {
            transcript.volatileText = ""
        }
    }
}
