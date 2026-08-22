import AnvilKit
import AnvilToolbox
import AnvilUI
import SwiftUI

/// The first two minutes.
struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var step = Step.welcome
    /// Bumped after a permission answer; none of them post a notification.
    @State private var revision = 0

    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case permissions
        case shortcuts
        case model

        var id: Int { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .welcome: "Willkommen bei Anvil"
            case .permissions: "Was Anvil braucht"
            case .shortcuts: "Deine Tastenkürzel"
            case .model: "Das Modell"
            }
        }

        var subtitle: LocalizedStringKey {
            switch self {
            case .welcome: "Ein Fenster, viele Werkzeuge."
            case .permissions: "Nichts davon ist Pflicht — ohne das eine oder andere kann nur weniger."
            case .shortcuts: "Alles davon lässt sich später ändern."
            case .model: "Was auf diesem Mac läuft, bleibt auf diesem Mac."
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                content
                    .padding(AnvilSpacing.xxl)
            }
            .frame(maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(width: AnvilSize.onboardingWidth, height: AnvilSize.onboardingHeight)
        .background(AnvilColor.canvas)
    }

    // MARK: - Frame

    private var header: some View {
        HStack(spacing: AnvilSpacing.md) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 22))
                .foregroundStyle(AnvilColor.accent)

            VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                Text(step.title)
                    .font(AnvilFont.title)
                    .foregroundStyle(AnvilColor.textPrimary)
                Text(step.subtitle)
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
            }

            Spacer(minLength: 0)

            HStack(spacing: AnvilSpacing.xs) {
                ForEach(Step.allCases) { candidate in
                    Circle()
                        .fill(candidate == step ? AnvilColor.accent : AnvilColor.border)
                        .frame(width: AnvilSpacing.sm, height: AnvilSpacing.sm)
                }
            }
        }
        .padding(AnvilSpacing.lg)
    }

    private var footer: some View {
        HStack(spacing: AnvilSpacing.sm) {
            AnvilButton("Überspringen", role: .ghost) { finish() }

            Spacer(minLength: 0)

            if step != Step.allCases.first {
                AnvilButton("Zurück", role: .secondary) {
                    step = Step(rawValue: step.rawValue - 1) ?? .welcome
                }
            }

            if step == Step.allCases.last {
                AnvilButton("Los geht's", systemImage: "checkmark", role: .primary) { finish() }
            } else {
                AnvilButton("Weiter", systemImage: "arrow.right", role: .primary) {
                    step = Step(rawValue: step.rawValue + 1) ?? .model
                }
            }
        }
        .padding(AnvilSpacing.lg)
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .permissions: permissionStep
        case .shortcuts: shortcutStep
        case .model: modelStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.lg) {
            ForEach(Array(Self.highlights.enumerated()), id: \.offset) { _, highlight in
                HStack(alignment: .top, spacing: AnvilSpacing.md) {
                    Image(systemName: highlight.systemImage)
                        .font(.system(size: 18))
                        .foregroundStyle(AnvilColor.accent)
                        .frame(width: AnvilSize.toolIcon)

                    VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                        Text(highlight.title)
                            .font(AnvilFont.rowTitle)
                            .foregroundStyle(AnvilColor.textPrimary)
                        Text(highlight.detail)
                            .font(AnvilFont.caption)
                            .foregroundStyle(AnvilColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("\(environment.registry.tools.count) Werkzeuge sind eingeschaltet. Im Tool-Store lässt sich jedes einzeln abschalten.")
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionStep: some View {
        VStack(spacing: AnvilSpacing.sm) {
            ForEach(SystemPermission.allCases) { permission in
                permissionRow(permission)
            }

            Text("Jede davon lässt sich später in den Einstellungen nachholen oder zurücknehmen.")
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AnvilSpacing.sm)
        }
    }

    private func permissionRow(_ permission: SystemPermission) -> some View {
        let status = permissionStatus(permission)

        return AnvilCard {
            HStack(alignment: .top, spacing: AnvilSpacing.md) {
                Image(systemName: permission.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(AnvilColor.textSecondary)
                    .frame(width: AnvilSize.toolIcon)

                VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                    HStack(spacing: AnvilSpacing.sm) {
                        Text(permission.title)
                            .font(AnvilFont.rowTitle)
                            .foregroundStyle(AnvilColor.textPrimary)
                        if permission.isOptional {
                            StatusPill("Optional", tone: .neutral)
                        }
                    }
                    Text(permission.purpose)
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                switch status {
                case .granted:
                    StatusPill(status.title, systemImage: status.systemImage, tone: status.tone)
                case .notAsked:
                    AnvilButton("Erlauben", role: .primary) {
                        permission.request { revision += 1 }
                    }
                case .denied:
                    AnvilButton("Einstellungen", role: .secondary) {
                        permission.openSystemSettings()
                    }
                }
            }
        }
    }

    private var shortcutStep: some View {
        VStack(spacing: AnvilSpacing.sm) {
            ForEach(environment.shortcuts.all) { action in
                let setting = environment.shortcuts.setting(for: action.id)

                AnvilCard {
                    HStack(spacing: AnvilSpacing.md) {
                        Image(systemName: action.systemImage)
                            .foregroundStyle(AnvilColor.textSecondary)
                            .frame(width: AnvilSize.toolIcon)

                        VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                            Text(verbatim: action.title)
                                .font(AnvilFont.rowTitle)
                                .foregroundStyle(AnvilColor.textPrimary)
                            if !action.subtitle.isEmpty {
                                Text(verbatim: action.subtitle)
                                    .font(AnvilFont.caption)
                                    .foregroundStyle(AnvilColor.textTertiary)
                            }
                        }

                        Spacer(minLength: 0)

                        if let shortcut = setting.shortcut {
                            Text(verbatim: shortcut.displayString)
                                .font(AnvilFont.mono)
                                .foregroundStyle(
                                    setting.scope == .off ? AnvilColor.textTertiary : AnvilColor.textPrimary
                                )
                        }

                        Toggle("", isOn: scopeBinding(for: action.id))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }

            Text("Der Schalter entscheidet, ob das Kürzel überall gilt. Feiner einstellen lässt sich das in den Einstellungen unter „Tastenkürzel\".")
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AnvilSpacing.sm)
        }
    }

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.lg) {
            AnvilCard {
                HStack(spacing: AnvilSpacing.md) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                        .foregroundStyle(AnvilColor.ai)
                    VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                        Text("Apple Foundation Models")
                            .font(AnvilFont.rowTitle)
                            .foregroundStyle(AnvilColor.textPrimary)
                        Text("Der Standardweg. Läuft auf diesem Mac, ohne Netz und ohne Konto.")
                            .font(AnvilFont.caption)
                            .foregroundStyle(AnvilColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    ModelStatusPill()
                }
            }

            Text("Wer Claude Code, Codex oder die Gemini CLI installiert hat, kann sie in den Einstellungen einschalten — über die vorhandene Anmeldung, ohne Schlüssel. Jedes Werkzeug wählt danach selbst, wen es fragt. Nötig ist beides nie: Werkzeuge ohne KI arbeiten ohnehin vollständig lokal.")
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    private static let highlights: [(title: LocalizedStringKey, detail: LocalizedStringKey, systemImage: String)] = [
        (
            "Diktieren, überall",
            "Kürzel drücken, sprechen, noch einmal drücken. Der aufgeräumte Text landet dort, wo der Cursor steht.",
            "mic"
        ),
        (
            "Bildschirm aufnehmen und auslesen",
            "Ausschnitt, Fenster oder ganzer Bildschirm — mit Markierungen, und auf Wunsch gleich als Text.",
            "camera.viewfinder"
        ),
        (
            "Werkzeuge für den Rest",
            "Zwischenablage-Verlauf, Farben, Einheiten, JSON, Cron, QR-Codes, Git-Repositories — und KI-Werkzeuge fürs Schreiben und für Code.",
            "wrench.and.screwdriver"
        ),
        (
            "Alles auch im Stapel",
            "Umbenennen, ersetzen, umwandeln, prüfen — über hundert Dateien so wie über eine. Was geschrieben würde, steht vorher da.",
            "square.grid.2x2"
        )
    ]

    private func permissionStatus(_ permission: SystemPermission) -> SystemPermission.Status {
        _ = revision
        return permission.status
    }

    /// The switch is the coarse version of the scope picker: on means
    /// everywhere, off means nothing listens.
    private func scopeBinding(for id: ShortcutActionID) -> Binding<Bool> {
        Binding(
            get: { environment.shortcuts.scope(for: id) != .off },
            set: { environment.shortcuts.setScope($0 ? .global : .off, for: id) }
        )
    }

    private func finish() {
        environment.settings[.hasSeenOnboarding] = true
        dismiss()
    }
}

// MARK: - Settings key

extension SettingKey {
    /// Whether the introduction has been through once.
    public static var hasSeenOnboarding: SettingKey<Bool> {
        SettingKey<Bool>("hasSeenOnboarding", default: false)
    }
}
