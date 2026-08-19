import AnvilKit
import AnvilToolbox
import AnvilUI
import AppKit
import SwiftUI

/// Die Anmeldung bei GitHub, in den Einstellungen.
///
/// Zwei Wege, und beide führen an dieselbe Stelle im Schlüsselbund: die
/// Anmeldung über GitHub selbst, und ein Token von Hand für alle, die keine
/// eigene OAuth-App anlegen wollen.
struct GitHubSettingsView: View {
    let settings: SettingsStore
    /// Mit Modulnamen: `ApplicationServices` bringt über AppKit einen
    /// gleichnamigen Typ mit, und dann weiß der Übersetzer nicht, welcher
    /// gemeint ist.
    let pasteboard: AnvilKit.Pasteboard

    @State private var token = ""
    @State private var status: String?
    @State private var verification: GitHubDeviceLogin.Verification?
    @State private var isSigningIn = false
    @State private var isConnected = false

    private let account = GitHubAccount()

    private var clientID: Binding<String> {
        Binding(
            get: { settings[.githubClientID] },
            set: { settings.set($0, for: .githubClientID) }
        )
    }

    var body: some View {
        SettingsGroup(
            "GitHub",
            footnote: "Für Werkzeuge, die ein Repository holen — ohne Zugang gehen nur öffentliche. Anvil fragt nur nach dem Recht `repo`; das ist das kleinste, mit dem sich ein privates Repository klonen lässt."
        ) {
            SettingsWideRow("Anmeldung", help: .resolvedIfPresent(status)) {
                HStack(spacing: AnvilSpacing.sm) {
                    if isConnected {
                        AnvilButton("Trennen", role: .destructive) { disconnect() }
                    } else {
                        AnvilButton(
                            "Mit GitHub anmelden",
                            systemImage: "person.badge.key",
                            role: .primary,
                            isBusy: isSigningIn
                        ) {
                            signIn()
                        }
                        .disabled(isSigningIn || settings[.githubClientID].isEmpty)
                    }
                }
            }

            if let verification {
                SettingsWideRow(
                    "Code eingeben",
                    help: "Der Code liegt schon in der Zwischenablage. Die Seite dazu ist offen."
                ) {
                    HStack(spacing: AnvilSpacing.sm) {
                        Text.raw(verification.userCode)
                            .font(AnvilFont.display.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(AnvilColor.textPrimary)

                        AnvilButton("Seite öffnen", systemImage: "safari") {
                            _ = NSWorkspace.shared.open(verification.verificationURL)
                        }
                        AnvilButton("Code kopieren", systemImage: "doc.on.doc") {
                            pasteboard.copy(verification.userCode)
                        }
                        AnvilButton("Abbrechen", role: .destructive) { cancel() }
                    }
                }
            }

            SettingsWideRow(
                "Client-ID",
                help: "Aus einer eigenen OAuth-App unter github.com/settings/developers — mit eingeschaltetem Device Flow. Das Client-Geheimnis daneben braucht Anvil nicht; die Client-ID ist öffentlich und steht deshalb hier und nicht im Schlüsselbund."
            ) {
                AnvilTextField(text: clientID, placeholder: "Ov23li…", isMonospaced: true)
            }

            SettingsWideRow(
                "Oder ein Token",
                help: "Statt der Anmeldung: ein persönliches Token mit dem Recht `repo`, anzulegen unter github.com/settings/tokens. Es landet an derselben Stelle im Schlüsselbund."
            ) {
                HStack(spacing: AnvilSpacing.sm) {
                    AnvilTextField(text: $token, placeholder: "ghp_…", isSecure: true)
                    AnvilButton("Sichern", role: .secondary) { save() }
                }
            }
        }
        .task { refresh() }
    }

    // MARK: - Anmelden

    private func refresh() {
        isConnected = account.isConnected
        status = account.status
        token = ""
    }

    /// Holt einen Code, öffnet die Seite und fragt nach, bis GitHub antwortet.
    private func signIn() {
        guard !isSigningIn else { return }
        let login = GitHubDeviceLogin(clientID: settings[.githubClientID])

        Task {
            isSigningIn = true
            defer {
                isSigningIn = false
                verification = nil
            }

            do {
                let started = try await login.start()
                verification = started

                // Beides sofort: Der Code liegt bereit, und die Seite ist
                // offen. Wer sich anmeldet, soll nichts abtippen müssen, was
                // schon auf dem Bildschirm steht.
                pasteboard.copy(started.userCode)
                _ = NSWorkspace.shared.open(started.verificationURL)
                status = localized("Warte auf die Bestätigung bei GitHub …")

                let token = try await wait(for: started, with: login)
                try account.connect(token)
                refresh()
                status = localized("Angemeldet — private Repositories gehen auch.")
            } catch {
                status = AnvilError.wrapping(error).message
            }
        }
    }

    /// Fragt im vorgegebenen Takt nach, bis der Code abgelaufen ist.
    ///
    /// Der Takt kommt von GitHub, und GitHub meint ihn ernst: Wer schneller
    /// fragt, bekommt „slow_down" und danach gar nichts mehr.
    private func wait(
        for verification: GitHubDeviceLogin.Verification,
        with login: GitHubDeviceLogin
    ) async throws -> String {
        var interval = verification.interval
        let deadline = Date().addingTimeInterval(verification.expiresIn)

        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))

            switch try await login.check(verification) {
            case let .token(token):
                return token
            case .pending:
                continue
            case let .slowDown(next):
                interval = next
            }
        }

        throw AnvilError.invalidInput(
            localized("Der Code ist abgelaufen. Fang die Anmeldung noch einmal an.")
        )
    }

    private func cancel() {
        verification = nil
        isSigningIn = false
        status = localized("Abgebrochen.")
    }

    // MARK: - Von Hand

    private func save() {
        do {
            try account.connect(token)
            refresh()
        } catch {
            status = AnvilError.wrapping(error).message
        }
    }

    private func disconnect() {
        do {
            try account.connect(nil)
            refresh()
            status = localized("Getrennt.")
        } catch {
            status = AnvilError.wrapping(error).message
        }
    }
}
