import AVFoundation
import AnvilKit
import Foundation
import Speech

/// Microphone and speech-recognition authorisation.
///
/// Asked for at the moment the user first presses record, never at launch: a
/// toolbox that demands the microphone before you have opened a speech tool
/// feels like it is taking something.
public enum SpeechPermissions {
    public enum Status: Sendable, Equatable {
        case granted
        case denied
        case undetermined
    }

    // MARK: - Microphone

    public static var microphoneStatus: Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    @discardableResult
    public static func requestMicrophone() async -> Status {
        if microphoneStatus == .granted { return .granted }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }

    // MARK: - Speech recognition

    public static var speechStatus: Status {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .notDetermined: .undetermined
        default: .denied
        }
    }

    @discardableResult
    public static func requestSpeechRecognition() async -> Status {
        if speechStatus == .granted { return .granted }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized ? .granted : .denied)
            }
        }
    }

    /// Requests everything the speech tools need, in one go.
    ///
    /// - Throws: ``AnvilError/permissionDenied(_:)`` naming the missing one, so
    ///   the UI can say exactly which switch to flip in System Settings.
    public static func requestAll() async throws {
        guard await requestMicrophone() == .granted else {
            throw AnvilError.permissionDenied(
                localized("Anvil darf das Mikrofon nicht benutzen.")
            )
        }
        guard await requestSpeechRecognition() == .granted else {
            throw AnvilError.permissionDenied(
                localized("Anvil darf die Spracherkennung nicht benutzen.")
            )
        }
    }
}
