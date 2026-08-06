import Foundation
import Testing

@testable import AnvilKit

@MainActor
@Suite("ShortcutRegistry")
struct ShortcutRegistryTests {
    private let combination = GlobalShortcut(keyCode: 2, carbonModifiers: 256, keyLabel: "D")
    private let other = GlobalShortcut(keyCode: 3, carbonModifiers: 256, keyLabel: "F")

    private func makeRegistry() -> ShortcutRegistry {
        ShortcutRegistry(settings: .ephemeral())
    }

    private func action(
        _ id: ShortcutActionID,
        shortcut: GlobalShortcut? = nil,
        scope: ShortcutScope = .off,
        toolID: ToolIdentifier? = nil,
        onRun: @escaping @MainActor () -> Void = {}
    ) -> ShortcutAction {
        ShortcutAction(
            id: id,
            title: id.rawValue,
            systemImage: "circle",
            toolID: toolID,
            defaultShortcut: shortcut,
            defaultScope: scope,
            handler: onRun
        )
    }

    @Test
    func anActionStartsAtItsDefault() {
        let registry = makeRegistry()
        registry.register(action("a", shortcut: combination, scope: .global))

        #expect(registry.shortcut(for: "a") == combination)
        #expect(registry.scope(for: "a") == .global)
    }

    @Test
    func registeringTwiceReplacesRatherThanDuplicates() {
        let registry = makeRegistry()
        registry.register(action("a"))
        registry.register(action("a", shortcut: combination, scope: .app))

        #expect(registry.all.count == 1)
        #expect(registry.shortcut(for: "a") == combination)
    }

    @Test
    func aChosenShortcutWinsOverTheDefault() {
        let registry = makeRegistry()
        registry.register(action("a", shortcut: combination, scope: .app))
        registry.setShortcut(other, for: "a")

        #expect(registry.shortcut(for: "a") == other)
    }

    @Test
    func assigningToASwitchedOffActionSwitchesItOn() {
        let registry = makeRegistry()
        registry.register(action("a", shortcut: nil, scope: .off))
        registry.setShortcut(combination, for: "a")

        #expect(registry.scope(for: "a") == .app)
    }

    @Test
    func anActionThatDefaultsToGlobalComesBackAsGlobal() {
        let registry = makeRegistry()
        registry.register(action("a", shortcut: combination, scope: .global))
        registry.setScope(.off, for: "a")
        registry.setShortcut(other, for: "a")

        #expect(registry.scope(for: "a") == .global)
    }

    @Test
    func clearingTheShortcutSwitchesTheActionOff() {
        let registry = makeRegistry()
        registry.register(action("a", shortcut: combination, scope: .global))
        registry.setShortcut(nil, for: "a")

        #expect(registry.scope(for: "a") == .off)
        #expect(registry.shortcut(for: "a") == nil)
    }

    @Test
    func resettingRestoresTheDefault() {
        let registry = makeRegistry()
        registry.register(action("a", shortcut: combination, scope: .global))
        registry.setShortcut(other, for: "a")
        registry.reset("a")

        #expect(registry.shortcut(for: "a") == combination)
        #expect(registry.scope(for: "a") == .global)
    }

    // MARK: - Conflicts

    @Test
    func twoActionsOnTheSameKeysConflict() {
        let registry = makeRegistry()
        registry.register(action("a", shortcut: combination, scope: .app))
        registry.register(action("b", shortcut: combination, scope: .app))

        #expect(registry.conflicts(for: "a").map(\.id) == ["b"])
        #expect(registry.hasConflicts)
    }

    @Test
    func aSwitchedOffActionCannotConflict() {
        let registry = makeRegistry()
        registry.register(action("a", shortcut: combination, scope: .app))
        registry.register(action("b", shortcut: combination, scope: .off))

        #expect(registry.conflicts(for: "a").isEmpty)
        #expect(!registry.hasConflicts)
    }

    @Test
    func anInAppAndAGlobalShortcutStillConflict() {
        // The global registration swallows the key before the menu sees it.
        let registry = makeRegistry()
        registry.register(action("a", shortcut: combination, scope: .app))
        registry.register(action("b", shortcut: combination, scope: .global))

        #expect(registry.conflicts(for: "a").count == 1)
    }

    @Test
    func differentKeysDoNotConflict() {
        let registry = makeRegistry()
        registry.register(action("a", shortcut: combination, scope: .app))
        registry.register(action("b", shortcut: other, scope: .app))

        #expect(registry.conflicts(for: "a").isEmpty)
    }

    // MARK: - Running

    @Test
    func performingAnActionCallsItsHandler() {
        let registry = makeRegistry()
        let box = Box()
        registry.register(action("a") { box.count += 1 })

        registry.perform("a")
        registry.perform("a")
        #expect(box.count == 2)
    }

    @Test
    func performingAnUnknownActionDoesNothing() {
        makeRegistry().perform("nope")
    }

    // MARK: - Grouping

    @Test
    func actionsAreGroupedByTool() {
        let registry = makeRegistry()
        registry.register(action("app"))
        registry.register(action("one", toolID: "tool.one"))
        registry.register(action("two", toolID: "tool.one"))
        registry.register(action("three", toolID: "tool.two"))

        let groups = registry.grouped()
        #expect(groups.count == 3)
        #expect(groups[0].toolID == nil)
        #expect(groups[1].actions.count == 2)
    }

    @MainActor
    private final class Box {
        var count = 0
    }
}

@MainActor
@Suite("ShortcutScope")
struct ShortcutScopeTests {
    @Test
    func everyScopeExplainsItself() {
        for scope in ShortcutScope.allCases {
            #expect(!scope.title.isEmpty)
            #expect(!scope.explanation.isEmpty)
            #expect(!scope.systemImage.isEmpty)
        }
    }

    @Test
    func settingsRoundTripThroughJSON() throws {
        let setting = ShortcutSetting(
            shortcut: GlobalShortcut(keyCode: 2, carbonModifiers: 256, keyLabel: "D"),
            scope: .global
        )
        let data = try JSONEncoder().encode(["a": setting])
        let decoded = try JSONDecoder().decode([String: ShortcutSetting].self, from: data)
        #expect(decoded["a"] == setting)
    }
}
