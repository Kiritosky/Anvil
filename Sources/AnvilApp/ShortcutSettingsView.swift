import AnvilKit
import AnvilUI
import SwiftUI

/// Every key combination in the app, in one list.
///
/// One screen rather than a shortcut field buried in each tool's settings: the
/// question people have is "what is ⌥⌘4 doing", and that cannot be answered by
/// a setting that only knows about itself.
struct ShortcutSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    private var registry: ShortcutRegistry { environment.shortcuts }

    var body: some View {
        SettingsPage(
            "Tastenkürzel",
            description: "Jedes Kürzel lässt sich ändern, abschalten, oder darauf umstellen, ob es nur in Anvil oder überall gilt."
        ) {
            ForEach(Array(registry.grouped().enumerated()), id: \.offset) { _, group in
                SettingsGroup(.resolved(title(for: group.toolID))) {
                    ForEach(group.actions) { action in
                        row(for: action)
                    }
                }
            }

            SettingsGroup(
                "Zurücksetzen",
                footnote: "Setzt jedes Kürzel auf den Wert, mit dem Anvil ausgeliefert wird."
            ) {
                SettingsRow(
                    "Alle Kürzel",
                    help: conflictHelp,
                    systemImage: "arrow.counterclockwise"
                ) {
                    AnvilButton("Auf Vorgabe", role: .secondary) {
                        registry.resetAll()
                    }
                }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for action: ShortcutAction) -> some View {
        let setting = registry.setting(for: action.id)
        let conflicts = registry.conflicts(for: action.id)

        SettingsWideRow(
            .resolved(action.title),
            help: help(for: action, setting: setting, conflicts: conflicts)
        ) {
            HStack(spacing: AnvilSpacing.sm) {
                ShortcutRecorder(shortcut: shortcutBinding(for: action.id))
                    .frame(width: 150)

                Picker("", selection: scopeBinding(for: action.id)) {
                    ForEach(ShortcutScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(setting.shortcut == nil)

                if setting != action.defaultSetting {
                    Button { registry.reset(action.id) } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(AnvilIconButtonStyle())
                    .anvilHelp("Auf Vorgabe zurücksetzen")
                }

                Spacer(minLength: 0)

                if !conflicts.isEmpty {
                    StatusPill("Doppelt belegt", systemImage: "exclamationmark.triangle", tone: .warning)
                } else if registry.failures[action.id] != nil {
                    StatusPill("Belegt", systemImage: "xmark.octagon", tone: .danger)
                }
            }
        }
    }

    private func help(
        for action: ShortcutAction,
        setting: ShortcutSetting,
        conflicts: [ShortcutAction]
    ) -> LocalizedStringKey {
        if let failure = registry.failures[action.id] {
            return .resolved(failure)
        }
        if let other = conflicts.first {
            return .resolved(localized("Dieselbe Kombination benutzt auch „\(other.title)\"."))
        }
        if setting.shortcut == nil {
            return "Kein Kürzel vergeben."
        }
        return .resolved(action.subtitle.isEmpty ? setting.scope.explanation : action.subtitle)
    }

    private var conflictHelp: LocalizedStringKey {
        registry.hasConflicts
            ? "Mindestens zwei Kürzel sind doppelt belegt."
            : "Keine Kollisionen."
    }

    // MARK: - Bindings

    private func shortcutBinding(for id: ShortcutActionID) -> Binding<GlobalShortcut?> {
        Binding(
            get: { registry.shortcut(for: id) },
            set: { registry.setShortcut($0, for: id) }
        )
    }

    private func scopeBinding(for id: ShortcutActionID) -> Binding<ShortcutScope> {
        Binding(
            get: { registry.scope(for: id) },
            set: { registry.setScope($0, for: id) }
        )
    }

    private func title(for toolID: ToolIdentifier?) -> String {
        guard let toolID else { return localized("Programm") }
        return environment.registry.tool(id: toolID)?.metadata.title ?? toolID.rawValue
    }
}
