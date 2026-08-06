import Foundation
import Observation

/// Every key combination in the app, in one place.
///
/// Tools do not register hot keys themselves. They declare actions here, and
/// this decides what is listened for and where — which is the only way the
/// settings screen can show a complete list, spot collisions between two
/// tools, and let every single shortcut be switched off.
@MainActor
@Observable
public final class ShortcutRegistry {
    @ObservationIgnored private var actions: [ShortcutActionID: ShortcutAction] = [:]
    @ObservationIgnored private var order: [ShortcutActionID] = []
    @ObservationIgnored private let settings: SettingsStore

    /// Set when the system refused a global registration — almost always
    /// because another app already holds the combination.
    public private(set) var failures: [ShortcutActionID: String] = [:]

    /// Bumped whenever a setting changes, so views re-read.
    private var revision = 0

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: - Registering

    /// Adds an action, replacing one with the same identifier.
    public func register(_ action: ShortcutAction) {
        if actions[action.id] == nil { order.append(action.id) }
        actions[action.id] = action
        revision &+= 1
    }

    public func register(_ newActions: [ShortcutAction]) {
        for action in newActions { register(action) }
    }

    /// All actions in registration order.
    public var all: [ShortcutAction] {
        _ = revision
        return order.compactMap { actions[$0] }
    }

    public func action(_ id: ShortcutActionID) -> ShortcutAction? {
        actions[id]
    }

    /// Actions belonging to one tool, plus the app-wide ones under `nil`.
    public func grouped() -> [(toolID: ToolIdentifier?, actions: [ShortcutAction])] {
        var groups: [(ToolIdentifier?, [ShortcutAction])] = []
        for action in all {
            if let index = groups.firstIndex(where: { $0.0 == action.toolID }) {
                groups[index].1.append(action)
            } else {
                groups.append((action.toolID, [action]))
            }
        }
        return groups.map { (toolID: $0.0, actions: $0.1) }
    }

    // MARK: - Settings

    public func setting(for id: ShortcutActionID) -> ShortcutSetting {
        _ = revision
        if let stored = settings[.shortcutSettings][id.rawValue] { return stored }
        return actions[id]?.defaultSetting ?? ShortcutSetting(shortcut: nil, scope: .off)
    }

    public func shortcut(for id: ShortcutActionID) -> GlobalShortcut? {
        setting(for: id).shortcut
    }

    public func scope(for id: ShortcutActionID) -> ShortcutScope {
        setting(for: id).scope
    }

    public func setShortcut(_ shortcut: GlobalShortcut?, for id: ShortcutActionID) {
        var setting = setting(for: id)
        setting.shortcut = shortcut
        // A shortcut nobody listens for is a puzzle, not a setting: assigning
        // one to a switched-off action switches it on, in the narrow scope.
        if shortcut != nil, setting.scope == .off {
            setting.scope = actions[id]?.defaultScope == .global ? .global : .app
        }
        if shortcut == nil { setting.scope = .off }
        store(setting, for: id)
    }

    public func setScope(_ scope: ShortcutScope, for id: ShortcutActionID) {
        var setting = setting(for: id)
        setting.scope = scope
        store(setting, for: id)
    }

    public func reset(_ id: ShortcutActionID) {
        var all = settings[.shortcutSettings]
        all.removeValue(forKey: id.rawValue)
        settings[.shortcutSettings] = all
        revision &+= 1
        sync()
    }

    public func resetAll() {
        settings[.shortcutSettings] = [:]
        revision &+= 1
        sync()
    }

    private func store(_ setting: ShortcutSetting, for id: ShortcutActionID) {
        var all = settings[.shortcutSettings]
        all[id.rawValue] = setting
        settings[.shortcutSettings] = all
        revision &+= 1
        sync()
    }

    // MARK: - Conflicts

    /// Other actions that listen for the same combination in a scope that can
    /// fire at the same time.
    ///
    /// Two in-app shortcuts on the same keys are a real conflict; an in-app one
    /// and a global one are too, because the global registration swallows the
    /// key before the menu ever sees it.
    public func conflicts(for id: ShortcutActionID) -> [ShortcutAction] {
        let setting = setting(for: id)
        guard let shortcut = setting.shortcut, setting.scope != .off else { return [] }

        return all.filter { other in
            guard other.id != id else { return false }
            let otherSetting = self.setting(for: other.id)
            guard otherSetting.scope != .off else { return false }
            return otherSetting.shortcut == shortcut
        }
    }

    public var hasConflicts: Bool {
        all.contains { !conflicts(for: $0.id).isEmpty }
    }

    // MARK: - Activating

    /// Registers or removes every global hot key to match the settings.
    ///
    /// Called at launch and after every change. Cheap enough to do wholesale:
    /// re-registering a dozen hot keys is a handful of Carbon calls, and the
    /// alternative — tracking what changed — is where the bugs live.
    public func sync() {
        failures = [:]

        for action in all {
            let owner = Self.owner(for: action.id)
            let setting = setting(for: action.id)

            guard setting.scope == .global, let shortcut = setting.shortcut else {
                HotKeyCenter.shared.unregister(owner: owner)
                continue
            }

            do {
                try HotKeyCenter.shared.register(shortcut, owner: owner) { [weak self] in
                    self?.perform(action.id)
                }
            } catch {
                HotKeyCenter.shared.unregister(owner: owner)
                failures[action.id] = AnvilError.wrapping(error).message
            }
        }
    }

    /// Runs an action by identifier — used by the hot key, the menu item and
    /// the command palette alike.
    public func perform(_ id: ShortcutActionID) {
        actions[id]?.handler()
    }

    private static func owner(for id: ShortcutActionID) -> String {
        "shortcut." + id.rawValue
    }
}

// MARK: - Settings key

extension SettingKey {
    /// Every user-chosen shortcut, keyed by action identifier. Actions that
    /// are not in here use their own default.
    public static var shortcutSettings: SettingKey<[String: ShortcutSetting]> {
        SettingKey<[String: ShortcutSetting]>("shortcuts", default: [:])
    }
}

// MARK: - Tool context

extension ToolContext {
    /// Every key combination, registered by the app at launch.
    public var shortcuts: ShortcutRegistry { require(ShortcutRegistry.self) }
}
