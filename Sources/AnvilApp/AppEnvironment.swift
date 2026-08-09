import AnvilAI
import AnvilKit
import AnvilToolbox
import Carbon.HIToolbox
import Foundation
import Observation

/// Everything the app owns, wired together once at launch.
///
/// This is the only place that knows the full list of tool bundles. Adding a
/// bundle is one line here; nothing else in the shell changes.
@MainActor
@Observable
public final class AppEnvironment {
    public let settings: SettingsStore
    public let history: HistoryStore
    public let registry: ToolRegistry
    public let router: AIRouter
    public let context: ToolContext
    public let customTools: CustomToolStore
    /// The user's own spellings, enforced on every transcript.
    public let vocabulary: VocabularyStore
    /// Everything that passed through the clipboard this session.
    public let clipboard: ClipboardHistory
    /// Every key combination in the app.
    public let shortcuts: ShortcutRegistry
    /// Screenshots and what happens to them.
    public let screenshots: ScreenshotController
    /// Dictation from anywhere, driven by the global shortcut.
    public let quickDictation: QuickDictationController

    /// The tool currently shown in the detail pane.
    public var selectedToolID: ToolIdentifier?
    /// Whether the command palette is open.
    public var isCommandPaletteOpen = false
    /// Whether the introduction is showing. Opens itself once, on first run.
    public var isOnboardingOpen = false

    public init() {
        AppPaths.bootstrap()

        let settings = SettingsStore()
        let history = HistoryStore(limit: settings[.historyLimitPerTool])

        let registry = ToolRegistry(settings: settings)
        let router = AIRouter(settings: settings)

        self.settings = settings
        self.history = history
        self.registry = registry
        self.router = router

        let context = ToolContext(settings: settings, history: history)
        context.register(registry)
        context.register(router)
        context.register(DraftStore())
        self.context = context

        let customTools = CustomToolStore(registry: registry)
        self.customTools = customTools
        context.register(customTools, as: (any ToolLibraryReloading).self)

        let vocabulary = VocabularyStore(settings: settings)
        self.vocabulary = vocabulary
        context.register(vocabulary)

        let clipboard = ClipboardHistory(pasteboard: context.pasteboard, settings: settings)
        self.clipboard = clipboard
        context.register(clipboard)

        let shortcuts = ShortcutRegistry(settings: settings)
        self.shortcuts = shortcuts
        context.register(shortcuts)

        let quickDictation = QuickDictationController(context: context)
        self.quickDictation = quickDictation
        context.register(quickDictation)

        let screenshots = ScreenshotController(context: context)
        self.screenshots = screenshots
        context.register(screenshots)

        registerBundles()
        registerShortcutActions()
        customTools.reloadUserTools()
        restoreSelection()
        clipboard.syncWatching()
        isOnboardingOpen = !settings[.hasSeenOnboarding]

        // A shot taken by shortcut, with the window closed, should be the
        // thing on screen the next time the window opens.
        screenshots.onCaptured = { [weak self] _ in
            guard let self, self.registry.isActive(ScreenshotToolBundle.toolID) else { return }
            self.selectedToolID = ScreenshotToolBundle.toolID
        }
    }

    /// The tool bundles the app ships with, in sidebar order.
    private func registerBundles() {
        let bundles: [any ToolBundle.Type] = [
            SpeechToolBundle.self,
            AIToolBundle.self,
            TextToolBundle.self,
            DevToolBundle.self,
            DataToolBundle.self,
            NetToolBundle.self,
            EverydayToolBundle.self,
            ScreenshotToolBundle.self,
            SystemToolBundle.self
        ]
        for bundle in bundles {
            registry.register(bundle: bundle)
        }
    }

    /// Everything that can be triggered by a key combination.
    ///
    /// Declared here rather than by the tools themselves: a global shortcut has
    /// to work while its tool is closed, so what it calls has to be owned by
    /// the app.
    private func registerShortcutActions() {
        shortcuts.register([
            ShortcutAction(
                id: "app.commandPalette",
                title: "Alles finden",
                subtitle: "Öffnet die Suche über alle Werkzeuge",
                systemImage: "magnifyingglass",
                defaultShortcut: GlobalShortcut(
                    keyCode: UInt32(kVK_ANSI_K),
                    carbonModifiers: UInt32(cmdKey),
                    keyLabel: "K"
                ),
                defaultScope: .app
            ) { [weak self] in
                self?.isCommandPaletteOpen = true
            },
            quickDictation.makeAction()
        ])
        shortcuts.register(ScreenshotToolBundle.makeActions(controller: screenshots))
        shortcuts.sync()
    }

    private func restoreSelection() {
        let stored = settings[.lastOpenedTool]
        guard !stored.isEmpty else { return }
        let identifier = ToolIdentifier(stored)
        if registry.isActive(identifier) {
            selectedToolID = identifier
        }
    }

    // MARK: - Navigation

    public func open(_ id: ToolIdentifier) {
        guard registry.isActive(id) else { return }
        selectedToolID = id
        settings[.lastOpenedTool] = id.rawValue
        registry.markUsed(id)
        isCommandPaletteOpen = false
    }

    public var selectedTool: ToolRegistration? {
        selectedToolID.flatMap { registry.tool(id: $0) }
    }

    /// Refreshes model availability. Called at launch and when settings change.
    public func refreshModelStatus() async {
        await router.refreshAvailability()
    }
}
