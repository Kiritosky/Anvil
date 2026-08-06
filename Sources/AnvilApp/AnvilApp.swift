import AnvilAI
import AnvilKit
import AnvilToolbox
import AnvilUI
import AppKit
import SwiftUI

/// The app.
///
/// Three scenes: the main window, the settings window, and a menu-bar item for
/// the things you want without bringing a window forward.
@main
struct AnvilApp: App {
    @State private var environment = AppEnvironment()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Backs the "Menüleisten-Symbol" switch in Settings.
    private var showsMenuBarItem: Binding<Bool> {
        Binding(
            get: { environment.settings[.showMenuBarItem] },
            set: { environment.settings[.showMenuBarItem] = $0 }
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.router)
                .frame(minWidth: 900, minHeight: 560)
                .task { await environment.refreshModelStatus() }
        }
        .defaultSize(width: 1_180, height: 760)
        .commands { AnvilCommands(environment: environment) }

        Settings {
            SettingsWindow()
                .environment(environment)
                .environment(environment.router)
        }

        MenuBarExtra("Anvil", systemImage: "hammer", isInserted: showsMenuBarItem) {
            MenuBarContent()
                .environment(environment)
                .environment(environment.router)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// SwiftUI apps built as a plain SwiftPM executable start as an accessory
/// process; without this the window opens behind everything and never takes
/// focus.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// Menu-bar commands and their shortcuts.
struct AnvilCommands: Commands {
    let environment: AppEnvironment

    /// Translates a recorded combination into the one SwiftUI understands.
    ///
    /// Only in-app scope gets a key here. A globally registered hot key never
    /// reaches the menu — the system swallows it first — and giving it to both
    /// would show a shortcut that then fires twice.
    private func menuShortcut(for setting: ShortcutSetting) -> KeyboardShortcut? {
        guard setting.scope == .app,
              let shortcut = setting.shortcut,
              let key = shortcut.keyEquivalent
        else { return nil }
        return KeyboardShortcut(key, modifiers: shortcut.eventModifiers)
    }

    var body: some Commands {
        // Every action the user set to "only in Anvil" becomes a menu item —
        // which is also how SwiftUI is told about the key combination, since a
        // shortcut without a menu entry is not a thing macOS has.
        CommandMenu("Aktionen") {
            ForEach(environment.shortcuts.all) { action in
                let setting = environment.shortcuts.setting(for: action.id)
                Button(action.title) {
                    environment.shortcuts.perform(action.id)
                }
                .keyboardShortcut(menuShortcut(for: setting))
            }
        }

        CommandGroup(after: .newItem) {
            Button("Eigene Tools neu laden") {
                environment.customTools.reloadUserTools()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .help) {
            Button("Tool-Store öffnen") {
                environment.open(SystemToolBundle.storeToolID)
            }
        }
    }
}
