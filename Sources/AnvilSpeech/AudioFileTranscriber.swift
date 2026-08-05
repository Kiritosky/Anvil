import AVFoundation
import AnvilKit
import Foundation
import Observation
import Speech

/// Transcribes an audio file that already exists.
///
/// Same analyser as the live path, fed from disk instead of the microphone.
/// Reading the file in blocks rather than all at once keeps memory flat for
/// hour-long recordings and gives progress worth showing.
@MainActor
@Observable
public final class AudioFileTranscriber {
    public private(set) var isTranscribing = false
    public private(set) var progress: Double = 0
    public private(set) var transcript = Transcript()

    @ObservationIgnored private let catalog: TranscriptionModelCatalog
    @ObservationIgnored private let converter = BufferConverter()

    private static let blockSize: AVAudioFrameCount = 16_384

    public init(catalog: TranscriptionModelCatalog? = nil) {
        self.catalog = catalog ?? TranscriptionModelCatalog()
    }

    /// Transcribes `url` and returns the finished transcript.
    public func transcribe(url: URL, locale: Locale) async throws -> Transcript {
        guard !isTranscribing else { throw AnvilError.invalidInput(localized("Es läuft bereits eine Transkription.")) }

        isTranscribing = true
        progress = 0
        transcript.clear()
        defer { isTranscribing = false }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AnvilError.invalidInput(
                localized("Die Datei konnte nicht gelesen werden: \(error.localizedDescription)")
            )
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        try await catalog.prepare(transcriber: transcriber, locale: locale)

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw AnvilError.unexpected(localized("Kein passendes Audioformat für die Spracherkennung."))
        }
        converter.reset()

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let collector = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results where result.isFinal {
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        self.transcript.append(TranscriptSegment(text: text))
                    }
                }
            } catch {
                // Handled by the throw from `finalizeAndFinishThroughEndOfInput`.
            }
        }

        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            continuation.finish()
            collector.cancel()
            throw AnvilError.unexpected(
                localized("Die Spracherkennung konnte nicht gestartet werden: \(error.localizedDescription)")
            )
        }

        let totalFrames = max(1, file.length)
        while file.framePosition < file.length {
            try Task.checkCancellation()

            guard let block = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: Self.blockSize
            ) else { break }

            try file.read(into: block, frameCount: Self.blockSize)
            guard block.frameLength > 0 else { break }

            let converted = try converter.convert(block, to: analyzerFormat)
            continuation.yield(AnalyzerInput(buffer: converted))
            progress = Double(file.framePosition) / Double(totalFrames)
        }

        continuation.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        _ = await collector.result

        progress = 1
        return transcript
    }
}
