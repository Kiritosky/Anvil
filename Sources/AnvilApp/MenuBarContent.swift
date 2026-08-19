import AnvilAI
import AnvilKit
import AnvilToolbox
import AppKit
import SwiftUI

/// The menu-bar menu.
struct MenuBarContent: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AIRouter.self) private var router: AIRouter?

    var body: some View {
        if let keys = shortcutLabel(QuickDictationController.actionID) {
            Button("Schnell-Diktat  \(keys)") {
                environment.quickDictation.toggle()
            }
        } else {
            Button("Schnell-Diktat") {
                environment.quickDictation.toggle()
            }
        }

        if let keys = shortcutLabel(ScreenshotToolBundle.regionActionID) {
            Button("Ausschnitt aufnehmen  \(keys)") {
                Task { await environment.screenshots.capture(.region) }
            }
        } else {
            Button("Ausschnitt aufnehmen") {
                Task { await environment.screenshots.capture(.region) }
            }
        }

        if let keys = shortcutLabel(ScreenshotToolBundle.textActionID) {
            Button("Text vom Bildschirm kopieren  \(keys)") {
                Task { await environment.screenshots.captureText() }
            }
        } else {
            Button("Text vom Bildschirm kopieren") {
                Task { await environment.screenshots.captureText() }
            }
        }

        Button("Speech Studio öffnen") {
            open(SpeechToolBundle.studioToolID)
        }

        Button("Alles finden …") {
            activate()
            environment.isCommandPaletteOpen = true
        }

        Divider()

        if !environment.registry.favouriteTools.isEmpty {
            ForEach(environment.registry.favouriteTools) { tool in
                Button(tool.title) { open(tool.id) }
            }
            Divider()
        }

        if let router {
            Text(router.statusSummary)
        }

        Button("Tool-Store") {
            open(SystemToolBundle.storeToolID)
        }

        Divider()

        Button("Anvil beenden") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// The key combination to print next to a menu entry, when the action has
    /// one that actually fires.
    private func shortcutLabel(_ id: ShortcutActionID) -> String? {
        let setting = environment.shortcuts.setting(for: id)
        guard setting.scope != .off, let shortcut = setting.shortcut else { return nil }
        return shortcut.displayString
    }

    private func open(_ id: ToolIdentifier) {
        activate()
        environment.open(id)
    }

    /// Brings the main window forward — the menu bar can be used while another
    /// app is frontmost, and opening a tool nobody can see helps no one.
    private func activate() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows
            .first { $0.isVisible && $0.canBecomeMain }?
            .makeKeyAndOrderFront(nil)
    }
}
