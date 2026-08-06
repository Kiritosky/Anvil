import AnvilKit
import AnvilUI
import AVFoundation
import CoreGraphics
import Speech
import SwiftUI

/// What the system has and has not let Anvil do.
///
/// Every one of these is asked for at the moment it is first needed, which is
/// the right time — but that also means a refusal disappears into a dialog
/// nobody remembers dismissing. This screen is where you find out that
/// dictation is silent because the microphone was denied three weeks ago.
struct PermissionsSettingsView: View {
    /// Bumped to re-read the statuses; none of them post a notification.
    @State private var revision = 0

    var body: some View {
        // The two system calls answer on their own queue, and a closure that
        // escaped this view cannot write to its state directly — the binding
        // can, because its setter does not mutate the view.
        let refresh = $revision

        SettingsPage(
            "Berechtigungen",
            description: "Anvil fragt jede Berechtigung erst, wenn sie gebraucht wird. Hier steht, was davon erteilt ist."
        ) {
            SettingsGroup(
                "Sprache",
                footnote: "Ohne Mikrofon kein Diktat; ohne Spracherkennung keine Umsetzung in Text."
            ) {
                row(
                    "Mikrofon",
                    systemImage: "mic",
                    state: microphoneState,
                    settingsPane: "Privacy_Microphone"
                ) {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        Task { @MainActor in refresh.wrappedValue += 1 }
                    }
                }

                row(
                    "Spracherkennung",
                    systemImage: "waveform",
                    state: speechState,
                    settingsPane: "Privacy_SpeechRecognition"
                ) {
                    SFSpeechRecognizer.requestAuthorization { _ in
                        Task { @MainActor in refresh.wrappedValue += 1 }
                    }
                }
            }

            SettingsGroup(
                "Bildschirm und Tastatur",
                footnote: "Bildschirmaufnahme braucht das Bildschirmfoto-Werkzeug. Die Bedienungshilfen braucht nur das Einfügen in fremde Textfelder — ohne sie landet Diktiertes in der Zwischenablage."
            ) {
                row(
                    "Bildschirmaufnahme",
                    systemImage: "camera.viewfinder",
                    state: screenRecordingState,
                    settingsPane: "Privacy_ScreenCapture"
                ) {
                    // Returns immediately; the system shows its own dialog and
                    // wants a restart before it reports the new answer.
                    _ = CGRequestScreenCaptureAccess()
                    revision += 1
                }

                row(
                    "Bedienungshilfen",
                    systemImage: "keyboard",
                    state: accessibilityState,
                    settingsPane: "Privacy_Accessibility"
                ) {
                    _ = PasteService.requestTrust()
                    revision += 1
                }
            }

            SettingsGroup(
                "Nachsehen",
                footnote: "Manche Berechtigungen melden ihren neuen Zustand erst nach einem Neustart von Anvil."
            ) {
                SettingsRow(
                    "Erneut prüfen",
                    help: "Liest den Stand noch einmal aus.",
                    systemImage: "arrow.clockwise"
                ) {
                    AnvilButton("Prüfen", role: .secondary) { revision += 1 }
                }
            }
        }
    }

    // MARK: - Rows

    /// What a permission can be. Deliberately three states, not two: "not asked
    /// yet" is not the same problem as "denied", and only one of them can be
    /// fixed from inside the app.
    ///
    /// Not called `State`: that name is taken by the property wrapper this very
    /// view uses, and shadowing it inside the type is a trap for the next
    /// person.
    private enum Permission {
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

    @ViewBuilder
    private func row(
        _ title: LocalizedStringKey,
        systemImage: String,
        state: Permission,
        settingsPane: String,
        request: @escaping () -> Void
    ) -> some View {
        SettingsRow(title, help: help(for: state), systemImage: systemImage) {
            HStack(spacing: AnvilSpacing.sm) {
                StatusPill(state.title, systemImage: state.systemImage, tone: state.tone)

                switch state {
                case .notAsked:
                    AnvilButton("Fragen", role: .primary, action: request)
                case .denied:
                    // Once denied, the dialog never comes back — only System
                    // Settings can change the answer.
                    AnvilButton("Einstellungen öffnen", role: .secondary) {
                        openSystemSettings(pane: settingsPane)
                    }
                case .granted:
                    EmptyView()
                }
            }
        }
    }

    private func help(for state: Permission) -> LocalizedStringKey {
        switch state {
        case .granted: "Alles da."
        case .denied: "Lässt sich nur noch in den Systemeinstellungen ändern."
        case .notAsked: "Wird beim ersten Mal automatisch gefragt."
        }
    }

    private func openSystemSettings(pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Statuses

    private var microphoneState: Permission {
        _ = revision
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    private var speechState: Permission {
        _ = revision
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    private var screenRecordingState: Permission {
        _ = revision
        // There is no "not asked" here — the system only ever answers yes or no.
        return CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    private var accessibilityState: Permission {
        _ = revision
        return PasteService.isTrusted ? .granted : .denied
    }
}
