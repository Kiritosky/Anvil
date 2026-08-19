import AnvilAI
import AnvilKit
import AnvilToolbox
import AnvilUI
import AppKit
import SwiftUI

/// The app.
@main
struct AnvilApp: App {
    /// Die Kennung der Fenstergruppe für einzelne Werkzeuge.
    static let toolWindowID = "anvil.tool"

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
                .frame(minWidth: AnvilSize.windowMinWidth, minHeight: AnvilSize.windowMinHeight)
                .task { await environment.refreshModelStatus() }
        }
        .defaultSize(width: 1_180, height: 760)
        .commands { AnvilCommands(environment: environment) }

        WindowGroup(id: Self.toolWindowID, for: ToolIdentifier.self) { $toolID in
            ToolWindow(toolID: toolID)
                .environment(environment)
                .environment(environment.router)
        }
        .defaultSize(width: 900, height: 640)

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

    @Environment(\.openWindow) private var openWindow

    private func openToolWindow(_ id: ToolIdentifier) {
        openWindow(id: AnvilApp.toolWindowID, value: id)
    }

    /// Fills in the standard About panel.
    private func showAboutPanel() {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

        let credits = NSMutableAttributedString(
            string: localized("Werkzeugkasten für den Alltag und fürs Entwickeln.\n\nSprache, Text und Bild laufen auf diesem Mac. Externe Anbieter sind möglich, aber nie Voraussetzung.\n\nGNU GPL v3"),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Anvil",
            .applicationVersion: version,
            .version: build,
            .credits: credits
        ])
    }

    /// Translates a recorded combination into the one SwiftUI understands.
    private func menuShortcut(for setting: ShortcutSetting) -> KeyboardShortcut? {
        guard setting.scope == .app,
              let shortcut = setting.shortcut,
              let key = shortcut.keyEquivalent
        else { return nil }
        return KeyboardShortcut(key, modifiers: shortcut.eventModifiers)
    }

    /// Die Zifferntasten für den Schnellzugriff.
    private static let digitKeys: [KeyEquivalent] = [
        "1", "2", "3", "4", "5", "6", "7", "8", "9"
    ]

    private var quickAccessTools: [ToolMetadata] {
        Array(environment.registry.quickAccessTools.prefix(Self.digitKeys.count))
    }

    var body: some Commands {
        CommandMenu("Aktionen") {
            ForEach(environment.shortcuts.all) { action in
                let setting = environment.shortcuts.setting(for: action.id)
                Button(action.title) {
                    environment.shortcuts.perform(action.id)
                }
                .keyboardShortcut(menuShortcut(for: setting))
            }
        }

        CommandMenu("Gehe zu") {
            let tools = quickAccessTools
            ForEach(Array(tools.enumerated()), id: \.element.id) { pair in
                Button(pair.element.title) {
                    environment.open(pair.element.id)
                }
                .keyboardShortcut(Self.digitKeys[pair.offset], modifiers: .command)
            }

            if tools.isEmpty {
                Button("Favoriten landen hier auf ⌘1 bis ⌘9") {}
                    .disabled(true)
            }

            Divider()

            Button("Alle Werkzeuge") {
                environment.selectedToolID = nil
            }
            .keyboardShortcut("0", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("In neuem Fenster öffnen") {
                guard let id = environment.selectedToolID else { return }
                openToolWindow(id)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(environment.selectedToolID == nil)

            Button("Eigene Tools neu laden") {
                environment.customTools.reloadUserTools()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .appInfo) {
            Button("Über Anvil") { showAboutPanel() }
        }

        CommandGroup(replacing: .help) {
            Button("Tool-Store öffnen") {
                environment.open(SystemToolBundle.storeToolID)
            }
        }
    }
}
