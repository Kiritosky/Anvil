import AVFoundation
import AnvilKit
import Foundation

/// Converts microphone buffers into the format the analyser asked for.
///
/// The input node hands out whatever the current input device runs at; the
/// speech modules want a specific sample rate and channel count. One converter
/// is kept alive across buffers because rebuilding it per buffer both wastes
/// work and drops the resampler's internal state, which is audible as clicks.
public final class BufferConverter {
    private var converter: AVAudioConverter?
    private var currentInputFormat: AVAudioFormat?
    private var currentOutputFormat: AVAudioFormat?

    public init() {}

    public func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        if inputFormat == format { return buffer }

        if converter == nil || currentInputFormat != inputFormat || currentOutputFormat != format {
            guard let created = AVAudioConverter(from: inputFormat, to: format) else {
                throw AnvilError.unexpected(
                    localized("Das Audioformat des Mikrofons lässt sich nicht in das Format der Spracherkennung umwandeln.")
                )
            }
            created.primeMethod = .none
            converter = created
            currentInputFormat = inputFormat
            currentOutputFormat = format
        }

        guard let converter else {
            throw AnvilError.unexpected(localized("Audio-Konverter fehlt."))
        }

        let ratio = format.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64

        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AnvilError.unexpected(localized("Zielpuffer für die Audioumwandlung konnte nicht angelegt werden."))
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            throw AnvilError.unexpected(localized("Audioumwandlung fehlgeschlagen: \(conversionError.localizedDescription)"))
        }
        guard status != .error else {
            throw AnvilError.unexpected(localized("Audioumwandlung fehlgeschlagen."))
        }

        return output
    }

    /// Drops the cached converter — call when the input device changes.
    public func reset() {
        converter = nil
        currentInputFormat = nil
        currentOutputFormat = nil
    }
}
