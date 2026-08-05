import AVFoundation
import AnvilKit
import Foundation
import Observation

/// Captures the microphone.
///
/// Two jobs: hand every buffer to whoever wants to transcribe it, and keep a
/// cheap level history for the meter. Optionally it also writes the raw audio
/// to disk, so a dictation can be replayed or re-transcribed later with a
/// different language without asking the user to say it all again.
@MainActor
@Observable
public final class AudioRecorder {
    public private(set) var isRecording = false
    public private(set) var isPaused = false
    public private(set) var duration: TimeInterval = 0
    /// Recent peak levels, 0…1, oldest first.
    public private(set) var levels: [Float] = []
    /// Where the raw audio is being written, when recording to a file.
    public private(set) var fileURL: URL?

    /// Called for every captured buffer, on the audio thread.
    ///
    /// Keep the work here short and non-blocking: converting and handing the
    /// buffer to an `AsyncStream` continuation is fine, anything that allocates
    /// heavily or touches the main actor is not.
    @ObservationIgnored
    public nonisolated(unsafe) var bufferHandler: (@Sendable (AVAudioPCMBuffer) -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    // Written from the audio thread, so it cannot be actor-isolated.
    @ObservationIgnored private nonisolated(unsafe) var audioFile: AVAudioFile?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var ticker: Task<Void, Never>?

    private static let levelHistory = 96

    public init() {}

    /// The format the input device is currently running at.
    public var inputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    // MARK: - Control

    /// Starts capture.
    ///
    /// - Parameter recordingURL: when given, raw audio is also written there.
    public func start(recordingURL: URL? = nil) throws {
        guard !isRecording else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw AnvilError.unexpected(
                "Es ist kein Audioeingang verfügbar. Prüfe unter Systemeinstellungen › Ton, ob ein Mikrofon ausgewählt ist."
            )
        }

        if let recordingURL {
            do {
                try FileManager.default.createDirectory(
                    at: recordingURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                audioFile = try AVAudioFile(forWriting: recordingURL, settings: format.settings)
                fileURL = recordingURL
            } catch {
                throw AnvilError.storage(
                    "Die Aufnahmedatei konnte nicht angelegt werden: \(error.localizedDescription)"
                )
            }
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.handleTap(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            audioFile = nil
            fileURL = nil
            throw AnvilError.unexpected("Die Aufnahme konnte nicht gestartet werden: \(error.localizedDescription)")
        }

        isRecording = true
        isPaused = false
        accumulated = 0
        duration = 0
        levels = []
        startedAt = .now
        startTicking()
    }

    public func pause() {
        guard isRecording, !isPaused else { return }
        engine.pause()
        isPaused = true
        accumulated += startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        startedAt = nil
        ticker?.cancel()
    }

    public func resume() throws {
        guard isRecording, isPaused else { return }
        do {
            try engine.start()
        } catch {
            throw AnvilError.unexpected("Die Aufnahme konnte nicht fortgesetzt werden: \(error.localizedDescription)")
        }
        isPaused = false
        startedAt = .now
        startTicking()
    }

    /// Stops capture and returns the file that was written, if any.
    @discardableResult
    public func stop() -> URL? {
        guard isRecording else { return fileURL }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        ticker?.cancel()
        ticker = nil

        accumulated += startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        duration = accumulated
        startedAt = nil
        isRecording = false
        isPaused = false
        audioFile = nil

        return fileURL
    }

    public func reset() {
        stop()
        duration = 0
        accumulated = 0
        levels = []
        fileURL = nil
    }

    // MARK: - Audio thread

    private nonisolated func handleTap(_ buffer: AVAudioPCMBuffer) {
        // Both of these have to happen before the engine reuses the buffer,
        // which rules out hopping to the main actor first.
        bufferHandler?(buffer)
        try? audioFile?.write(from: buffer)

        let level = Self.peakLevel(of: buffer)
        Task { @MainActor [weak self] in
            self?.appendLevel(level)
        }
    }

    private func appendLevel(_ level: Float) {
        levels.append(level)
        if levels.count > Self.levelHistory {
            levels.removeFirst(levels.count - Self.levelHistory)
        }
    }

    /// Peak amplitude, scaled so normal speech fills most of the meter.
    private nonisolated static func peakLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }

        let frames = Int(buffer.frameLength)
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for frame in stride(from: 0, to: frames, by: 8) {
                peak = max(peak, abs(samples[frame]))
            }
        }

        // Speech peaks well below 1.0; a mild curve keeps the meter lively
        // without pinning it at the top the moment someone speaks up.
        let boosted = min(1, peak * 3.2)
        return sqrt(boosted)
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let startedAt = self.startedAt else { continue }
                self.duration = self.accumulated + Date.now.timeIntervalSince(startedAt)
            }
        }
    }
}
