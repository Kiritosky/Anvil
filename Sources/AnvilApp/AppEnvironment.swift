import AnvilAI
import AnvilKit
import AnvilToolbox
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
    /// Dictation from anywhere, driven by the global shortcut.
    public let quickDictation: QuickDictationController

    /// The tool currently shown in the detail pane.
    public var selectedToolID: ToolIdentifier?
    /// Whether the command palette is open.
    public var isCommandPaletteOpen = false

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

        let quickDictation = QuickDictationController(context: context)
        self.quickDictation = quickDictation
        context.register(quickDictation)

        registerBundles()
        customTools.reloadUserTools()
        restoreSelection()
        quickDictation.syncShortcut()
        clipboard.syncWatching()
    }

    /// The tool bundles the app ships with, in sidebar order.
    private func registerBundles() {
        let bundles: [any ToolBundle.Type] = [
            SpeechToolBundle.self,
            AIToolBundle.self,
            TextToolBundle.self,
            EverydayToolBundle.self,
            SystemToolBundle.self
        ]
        for bundle in bundles {
            registry.register(bundle: bundle)
        }
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
