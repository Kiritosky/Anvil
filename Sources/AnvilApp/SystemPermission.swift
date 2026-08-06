import AnvilKit
import AnvilUI
import AVFoundation
import CoreGraphics
import Speech
import SwiftUI

/// One thing the system can let Anvil do, or not.
///
/// In one place because two screens ask the same questions: the settings pane
/// and the first-run introduction. Two copies of "is the microphone allowed"
/// would drift the day one of them learns something the other does not.
enum SystemPermission: String, CaseIterable, Identifiable {
    case microphone
    case speech
    case screenRecording
    case accessibility

    var id: String { rawValue }

    /// Where the permission stands.
    ///
    /// Three answers, not two: "not asked yet" is a different problem from
    /// "denied", and only the first can be resolved from inside the app —
    /// after a refusal the system dialog never appears again.
    enum Status {
        case granted
        case denied
        case notAsked

        var title: LocalizedStringKey {
            switch self {
            case .granted: "Erteilt"
            case .denied: "Verweigert"
            case .notAsked: "Noch nicht gefragt"
            }
        }

        var tone: AnvilTone {
            switch self {
            case .granted: .success
            case .denied: .danger
            case .notAsked: .neutral
            }
        }

        var systemImage: String {
            switch self {
            case .granted: "checkmark.circle.fill"
            case .denied: "xmark.octagon.fill"
            case .notAsked: "questionmark.circle"
            }
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .microphone: "Mikrofon"
        case .speech: "Spracherkennung"
        case .screenRecording: "Bildschirmaufnahme"
        case .accessibility: "Bedienungshilfen"
        }
    }

    var systemImage: String {
        switch self {
        case .microphone: "mic"
        case .speech: "waveform"
        case .screenRecording: "camera.viewfinder"
        case .accessibility: "keyboard"
        }
    }

    /// What stops working without it — the only sentence that matters when
    /// somebody is deciding whether to say yes.
    var purpose: LocalizedStringKey {
        switch self {
        case .microphone: "Ohne Mikrofon lässt sich nichts diktieren."
        case .speech: "Wandelt die Aufnahme in Text um. Läuft auf diesem Mac."
        case .screenRecording: "Wird fürs Bildschirmfoto und für Text vom Bildschirm gebraucht."
        case .accessibility: "Nur fürs Einfügen in fremde Textfelder. Ohne sie geht Diktiertes in die Zwischenablage."
        }
    }

    /// Whether Anvil is unusable without it, or merely less convenient.
    var isOptional: Bool {
        self == .accessibility
    }

    @MainActor
    var status: Status {
        switch self {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        case .screenRecording:
            // No "not asked" here: the system only ever answers yes or no.
            CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .accessibility:
            PasteService.isTrusted ? .granted : .denied
        }
    }

    /// Asks. `onAnswer` runs on the main actor once the system has replied —
    /// for the two that reply at all.
    @MainActor
    func request(onAnswer: @escaping @MainActor () -> Void) {
        switch self {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in onAnswer() }
            }
        case .speech:
            SFSpeechRecognizer.requestAuthorization { _ in
                Task { @MainActor in onAnswer() }
            }
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
            onAnswer()
        case .accessibility:
            _ = PasteService.requestTrust()
            onAnswer()
        }
    }

    /// Opens the pane of System Settings this permission lives in — the only
    /// way back once it has been denied.
    @MainActor
    func openSystemSettings() {
        let pane = switch self {
        case .microphone: "Privacy_Microphone"
        case .speech: "Privacy_SpeechRecognition"
        case .screenRecording: "Privacy_ScreenCapture"
        case .accessibility: "Privacy_Accessibility"
        }

        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
