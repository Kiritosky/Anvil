import AVFoundation
import AnvilKit
import Foundation
import Observation

/// Recording and transcription as one unit.
///
/// This is the object a speech tool actually drives: press record, get a live
/// transcript, press stop, get a finished one plus the audio file. Both the
/// full Speech Studio and the menu-bar quick capture use it, so the two can
/// never behave differently.
@MainActor
@Observable
public final class DictationSession {
    public enum State: Sendable, Equatable {
        case idle
        case preparing
        case recording
        case paused
        /// Stopped, waiting for the recogniser to finalise the tail.
        case finishing
        case finished
    }

    public private(set) var state: State = .idle
    public private(set) var error: AnvilError?

    public let recorder = AudioRecorder()
    public let transcription: LiveTranscriptionSession
    public let catalog: TranscriptionModelCatalog

    /// Where the audio of the last (or current) recording lives.
    public private(set) var recordingURL: URL?

    /// The catalogue is built in the body for the same reason as elsewhere: a
    /// default argument would be evaluated outside the main actor.
    public init(catalog: TranscriptionModelCatalog? = nil) {
        let catalog = catalog ?? TranscriptionModelCatalog()
        self.catalog = catalog
        self.transcription = LiveTranscriptionSession(catalog: catalog)
    }

    // MARK: - Derived state

    public var transcript: Transcript { transcription.transcript }
    public var isBusy: Bool { state == .preparing || state == .finishing }
    public var isActive: Bool { state == .recording || state == .paused }
    public var duration: TimeInterval { recorder.duration }
    public var levels: [Float] { recorder.levels }

    // MARK: - Control

    /// Requests permission, prepares the language assets, and starts recording.
    ///
    /// - Parameters:
    ///   - locale: language to transcribe in.
    ///   - keepAudio: whether to keep the recording on disk afterwards.
    public func start(locale: Locale, keepAudio: Bool = true) async {
        guard state == .idle || state == .finished else { return }

        state = .preparing
        error = nil

        do {
            try await SpeechPermissions.requestAll()

            let url = keepAudio ? Self.makeRecordingURL() : nil
            try await transcription.start(locale: locale)

            // The tap feeds the analyser directly; the session converts each
            // buffer to the analyser's format on the way through.
            recorder.bufferHandler = { [weak transcription] buffer in
                transcription?.feed(buffer)
            }
            transcription.elapsedTimeProvider = { [weak recorder] in
                recorder?.duration
            }

            try recorder.start(recordingURL: url)
            recordingURL = url
            state = .recording
        } catch {
            let wrapped = AnvilError.wrapping(error)
            self.error = wrapped
            await transcription.cancel()
            recorder.reset()
            state = .idle
        }
    }

    public func pause() {
        guard state == .recording else { return }
        recorder.pause()
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        do {
            try recorder.resume()
            state = .recording
        } catch {
            self.error = AnvilError.wrapping(error)
        }
    }

    /// Stops recording and waits for the final words to arrive.
    public func stop() async {
        guard isActive else { return }

        state = .finishing
        recorder.bufferHandler = nil
        recordingURL = recorder.stop()
        await transcription.finish()
        state = .finished
    }

    /// Throws the recording away and returns to idle.
    public func discard() async {
        recorder.bufferHandler = nil
        recorder.stop()
        await transcription.cancel()

        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        recorder.reset()
        state = .idle
        error = nil
    }

    /// Clears the last result so the next recording starts from a clean slate,
    /// keeping the audio file on disk.
    public func reset() async {
        await transcription.cancel()
        recorder.reset()
        recordingURL = nil
        state = .idle
        error = nil
    }

    // MARK: - Files

    private static func makeRecordingURL() -> URL {
        AppPaths.bootstrap()
        let stamp = Self.filenameFormatter.string(from: .now)
        return AppPaths.recordings.appending(path: "Diktat \(stamp).caf")
    }

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter
    }()
}
