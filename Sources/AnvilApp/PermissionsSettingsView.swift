import AnvilKit
import AnvilUI
import SwiftUI

/// What the system has and has not let Anvil do.
///
/// Every one of these is asked for at the moment it is first needed, which is
/// the right time — but that also means a refusal disappears into a dialog
/// nobody remembers dismissing. This screen is where you find out that
/// dictation is silent because the microphone was denied three weeks ago.
struct PermissionsSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Bumped to re-read the statuses; none of them post a notification.
    @State private var revision = 0

    var body: some View {
        SettingsPage(
            "Berechtigungen",
            description: "Anvil fragt jede Berechtigung erst, wenn sie gebraucht wird. Hier steht, was davon erteilt ist."
        ) {
            SettingsGroup(
                "Erteilt oder nicht",
                footnote: "Was optional ist, macht Anvil nur bequemer — der Rest schaltet ein Werkzeug ganz ab."
            ) {
                ForEach(SystemPermission.allCases) { permission in
                    row(permission)
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

                SettingsRow(
                    "Einführung",
                    help: "Zeigt die Schritte vom ersten Start noch einmal.",
                    systemImage: "sparkles"
                ) {
                    AnvilButton("Erneut zeigen", role: .secondary) {
                        environment.isOnboardingOpen = true
                    }
                }
            }
        }
    }

    private func row(_ permission: SystemPermission) -> some View {
        let status = statusOf(permission)

        return SettingsRow(
            permission.title,
            help: permission.purpose,
            systemImage: permission.systemImage
        ) {
            HStack(spacing: AnvilSpacing.sm) {
                StatusPill(status.title, systemImage: status.systemImage, tone: status.tone)

                switch status {
                case .notAsked:
                    AnvilButton("Fragen", role: .primary) {
                        permission.request { revision += 1 }
                    }
                case .denied:
                    // Once denied, the dialog never comes back — only System
                    // Settings can change the answer.
                    AnvilButton("Einstellungen öffnen", role: .secondary) {
                        permission.openSystemSettings()
                    }
                case .granted:
                    EmptyView()
                }
            }
        }
    }

    private func statusOf(_ permission: SystemPermission) -> SystemPermission.Status {
        _ = revision
        return permission.status
    }
}
