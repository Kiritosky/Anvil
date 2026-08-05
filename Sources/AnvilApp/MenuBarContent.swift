import AnvilAI
import AnvilKit
import AnvilToolbox
import AppKit
import SwiftUI

/// The menu-bar menu.
///
/// Kept to jumps and status. Anything that needs a text field belongs in the
/// window, and a menu that tries to be an app is worse than both.
struct MenuBarContent: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AIRouter.self) private var router: AIRouter?

    var body: some View {
        // The quick capture comes first: it is the reason the menu-bar item
        // exists at all, and the one thing you reach for without a window.
        if let shortcut = environment.quickDictation.registeredShortcut {
            Button("Schnell-Diktat  \(shortcut.displayString)") {
                environment.quickDictation.toggle()
            }
        } else {
            Button("Schnell-Diktat") {
                environment.quickDictation.toggle()
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
