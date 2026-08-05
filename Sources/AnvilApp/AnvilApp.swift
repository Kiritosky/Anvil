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

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Alles finden …") {
                environment.isCommandPaletteOpen = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

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
