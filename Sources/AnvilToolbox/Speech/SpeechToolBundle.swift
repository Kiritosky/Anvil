import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// The speech tools.
public enum SpeechToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.speech"
    public static let displayName = "Sprache & Audio"

    public static let studioToolID: ToolIdentifier = "speech.studio"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [speechStudio]
    }

    @MainActor
    private static var speechStudio: ToolRegistration {
        let metadata = ToolMetadata(
            id: studioToolID,
            title: "Speech Studio",
            subtitle: "Diktieren, transkribieren, aufräumen",
            systemImage: "waveform",
            category: .speech,
            keywords: [
                "diktat", "diktieren", "sprache", "transkription", "transcribe",
                "speech to text", "stt", "aufnehmen", "mikrofon", "füllwörter",
                "protokoll", "notiz", "voice"
            ],
            requirements: [.microphone, .speechRecognition, .languageModel],
            badge: "Neu"
        )

        return ToolRegistration(metadata: metadata) { context in
            SpeechStudioView(context: context, metadata: metadata)
        } settings: { context in
            SpeechSettingsView(context: context)
        }
    }
}

/// Preferences for the speech tools.
///
/// The defaults here are what a new recording starts from; the inspector inside
/// the tool changes the current session only.
struct SpeechSettingsView: View {
    let context: ToolContext

    @State private var recordingCount = 0
    @State private var recordingBytes: Int64 = 0

    private var settings: SettingsStore { context.settings }

    var body: some View {
        SettingsPage(
            "Sprache & Audio",
            description: "Standardwerte für neue Aufnahmen im Speech Studio."
        ) {
            quickDictationGroup

            SettingsGroup("Aufnahme") {
                SettingsRow(
                    "Aufnahme behalten",
                    help: "Legt das Audio unter Anvil › Recordings ab, damit du es später erneut transkribieren kannst.",
                    systemImage: "waveform.circle"
                ) {
                    Toggle("", isOn: binding(.keepAudio))
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    "Nach dem Stoppen automatisch aufräumen",
                    help: "Startet den Modell-Durchlauf, sobald die Aufnahme endet.",
                    systemImage: "wand.and.stars"
                ) {
                    Toggle("", isOn: binding(.autoRefineOnStop))
                        .toggleStyle(.switch)
                }

                SettingsRow(
                    "Modell verwenden",
                    help: "Aus bedeutet: nur die deterministische Füllwort-Bereinigung, kein Sprachmodell.",
                    systemImage: "sparkles"
                ) {
                    Toggle("", isOn: binding(.useAIRefinement))
                        .toggleStyle(.switch)
                }
            }

            SettingsGroup("Füllwörter") {
                SettingsWideRow(
                    "Stärke",
                    help: "Gilt für neue Sitzungen. Im Tool selbst lässt sich das jederzeit umstellen."
                ) {
                    Picker("", selection: binding(.fillerStrength)) {
                        ForEach(FillerCleaner.Strength.allCases) { strength in
                            Text(strength.title).tag(strength)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                SettingsRow(
                    "Wortdoppelungen zusammenfassen",
                    help: "Aus „das das\" wird „das\". Beabsichtigte Doppelungen wie „sehr sehr\" bleiben.",
                    systemImage: "repeat"
                ) {
                    Toggle("", isOn: binding(.collapseRepeats))
                        .toggleStyle(.switch)
                }
            }

            SettingsGroup(
                "Ablage",
                footnote: "Aufnahmen werden nie automatisch gelöscht — hier siehst du, wie viel liegen geblieben ist."
            ) {
                SettingsRow(
                    "Aufnahmen",
                    help: "\(recordingCount) Dateien · \(formattedSize)",
                    systemImage: "folder"
                ) {
                    AnvilButton("Öffnen", role: .secondary) {
                        AppPaths.bootstrap()
                        NSWorkspace.shared.open(AppPaths.recordings)
                    }
                }
            }
        }
        .task { measureRecordings() }
    }

    /// Everything about dictating without opening the app.
    ///
    /// Kept in one group because the parts only make sense together: a shortcut
    /// without the feature switched on does nothing, and auto-paste without the
    /// Accessibility permission silently would not work.
    @ViewBuilder
    private var quickDictationGroup: some View {
        SettingsGroup(
            "Schnell-Diktat",
            footnote: "Kürzel drücken, sprechen, Kürzel noch einmal drücken. Der aufgeräumte Text geht ins Textfeld, in dem der Cursor steht — sonst in die Zwischenablage. ⎋ verwirft. Das Hauptfenster bleibt zu."
        ) {
            SettingsRow(
                "Von überall diktieren",
                help: "Meldet das Tastenkürzel systemweit an.",
                systemImage: "mic.badge.plus"
            ) {
                Toggle("", isOn: quickDictationBinding)
                    .toggleStyle(.switch)
            }

            SettingsWideRow(
                "Tastenkürzel",
                help: shortcutHelp
            ) {
                ShortcutRecorder(shortcut: shortcutBinding)
                    .disabled(!settings[.quickDictationEnabled])
            }

            SettingsWideRow(
                "Stil",
                help: "Wie das Modell das Diktat aufbereitet, bevor es kopiert wird."
            ) {
                Picker("", selection: binding(.quickDictationStyle)) {
                    ForEach(RefinementStyle.offered) { style in
                        Text(style.title).tag(style)
                    }
                }
            }

            SettingsRow(
                "In Textfelder einfügen",
                help: pasteHelp,
                systemImage: "arrow.down.doc"
            ) {
                HStack(spacing: AnvilSpacing.sm) {
                    if settings[.quickDictationPastes], !PasteService.isTrusted {
                        AnvilButton("Erlauben", role: .secondary) {
                            PasteService.requestTrust()
                            PasteService.openAccessibilitySettings()
                        }
                    }
                    Toggle("", isOn: pasteBinding)
                        .toggleStyle(.switch)
                }
            }
        }
    }

    // MARK: - Quick dictation plumbing

    private var quickDictation: QuickDictationController? {
        context.resolve()
    }

    /// Toggling the feature has to re-register the shortcut, so it does not go
    /// through the plain settings binding.
    private var quickDictationBinding: Binding<Bool> {
        Binding(
            get: { settings[.quickDictationEnabled] },
            set: { newValue in
                settings[.quickDictationEnabled] = newValue
                quickDictation?.syncShortcut()
            }
        )
    }

    private var shortcutBinding: Binding<GlobalShortcut?> {
        Binding(
            get: { settings[.quickDictationShortcut] },
            set: { newValue in
                settings[.quickDictationShortcut] = newValue
                quickDictation?.syncShortcut()
            }
        )
    }

    private var pasteBinding: Binding<Bool> {
        Binding(
            get: { settings[.quickDictationPastes] },
            set: { newValue in
                settings[.quickDictationPastes] = newValue
                // Asking at the moment the switch is flipped is the only point
                // where the request is not a surprise.
                if newValue, !PasteService.isTrusted { PasteService.requestTrust() }
            }
        )
    }

    private var shortcutHelp: LocalizedStringKey {
        if let error = quickDictation?.registrationError {
            return .resolved(error)
        }
        if !settings[.quickDictationEnabled] {
            return "Erst oben einschalten."
        }
        return "Funktioniert auch, während eine andere App vorne ist."
    }

    private var pasteHelp: LocalizedStringKey {
        guard settings[.quickDictationPastes] else {
            return "Aus: der Text liegt immer nur in der Zwischenablage."
        }
        return PasteService.isTrusted
            ? "Steht der Cursor in einem Textfeld, tippt Anvil den Text dort hinein. Sonst bleibt er in der Zwischenablage."
            : "Dafür fehlt noch die Bedienungshilfen-Berechtigung — bis dahin nur Zwischenablage."
    }

    private func binding<Value>(_ key: SettingKey<Value>) -> Binding<Value> {
        Binding(
            get: { settings[key] },
            set: { settings[key] = $0 }
        )
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: recordingBytes, countStyle: .file)
    }

    private func measureRecordings() {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: AppPaths.recordings,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            recordingCount = 0
            recordingBytes = 0
            return
        }

        recordingCount = files.count
        recordingBytes = files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }
}
