import SwiftUI
import Testing

@testable import AnvilKit

@MainActor
private func makeRegistry() -> ToolRegistry {
    ToolRegistry(settings: .ephemeral())
}

private func makeTool(
    _ id: String,
    title: String,
    category: ToolCategory = .text,
    keywords: [String] = []
) -> ToolRegistration {
    ToolRegistration(
        metadata: ToolMetadata(
            id: ToolIdentifier(id),
            title: title,
            subtitle: "",
            systemImage: "circle",
            category: category,
            keywords: keywords
        )
    ) { _ in
        Text(title)
    }
}

@Suite("ToolRegistry")
struct ToolRegistryTests {
    @Test @MainActor
    func registersAndFindsTools() {
        let registry = makeRegistry()
        registry.register(makeTool("text.json", title: "JSON"))

        #expect(registry.allTools.count == 1)
        #expect(registry.tool(id: "text.json")?.metadata.title == "JSON")
    }

    @Test @MainActor
    func laterRegistrationReplacesEarlierOne() {
        let registry = makeRegistry()
        registry.register(makeTool("text.json", title: "JSON"))
        registry.register(makeTool("text.json", title: "JSON Pro"))

        #expect(registry.allTools.count == 1)
        #expect(registry.tool(id: "text.json")?.metadata.title == "JSON Pro")
    }

    @Test @MainActor
    func disabledToolsDisappearFromTheActiveSet() {
        let registry = makeRegistry()
        registry.register(makeTool("a", title: "Alpha"))
        registry.register(makeTool("b", title: "Beta"))

        registry.activation.setEnabled(false, for: "b")

        #expect(registry.allTools.count == 2)
        #expect(registry.tools.map(\.id) == ["a"])
        #expect(registry.isActive("b") == false)
    }

    @Test @MainActor
    func disablingABundleDisablesItsTools() {
        let registry = makeRegistry()
        let origin = ToolOrigin(bundleIdentifier: "test.bundle", displayName: "Test")
        registry.register(makeTool("a", title: "Alpha"), origin: origin)

        registry.activation.setBundleEnabled(false, for: origin)
        #expect(registry.tools.isEmpty)

        registry.activation.setBundleEnabled(true, for: origin)
        #expect(registry.tools.count == 1)
    }

    @Test @MainActor
    func essentialToolsCannotBeSwitchedOff() {
        let registry = makeRegistry()
        registry.register(makeTool("system.store", title: "Store"), origin: .system)

        registry.activation.setEnabled(false, for: "system.store")
        registry.activation.setBundleEnabled(false, for: .system)

        #expect(registry.tools.count == 1)
    }

    @Test @MainActor
    func replacingABundleLeavesOtherToolsAlone() {
        let registry = makeRegistry()
        let user = ToolOrigin.userDefined(fileURL: URL(filePath: "/tmp/a.json"))
        registry.register(makeTool("builtin", title: "Builtin"))
        registry.register(makeTool("user.one", title: "One"), origin: user)

        registry.replaceTools(
            fromBundle: user.bundleIdentifier,
            with: [makeTool("user.two", title: "Two")]
        )

        #expect(registry.allTools.map(\.id).sorted { $0.rawValue < $1.rawValue }
            == [ToolIdentifier("builtin"), ToolIdentifier("user.two")])
    }

    @Test @MainActor
    func searchRanksTitleMatchesFirst() {
        let registry = makeRegistry()
        registry.register(makeTool("a", title: "Zeilen", keywords: ["json"]))
        registry.register(makeTool("b", title: "JSON"))

        #expect(registry.search("json").first?.title == "JSON")
    }

    @Test @MainActor
    func searchSkipsDisabledToolsUnlessAsked() {
        let registry = makeRegistry()
        registry.register(makeTool("a", title: "JSON"))
        registry.activation.setEnabled(false, for: "a")

        #expect(registry.search("json").isEmpty)
        #expect(registry.search("json", includeInactive: true).count == 1)
    }

    @Test @MainActor
    func favouritesAndRecentsIgnoreDisabledTools() {
        let registry = makeRegistry()
        registry.register(makeTool("a", title: "Alpha"))
        registry.toggleFavourite("a")
        registry.markUsed("a")

        #expect(registry.favouriteTools.count == 1)
        #expect(registry.recentTools.count == 1)

        registry.activation.setEnabled(false, for: "a")
        #expect(registry.favouriteTools.isEmpty)
        #expect(registry.recentTools.isEmpty)
    }

    @Test @MainActor
    func categoriesOnlyIncludeOnesWithActiveTools() {
        let registry = makeRegistry()
        registry.register(makeTool("a", title: "Alpha", category: .coding))
        registry.register(makeTool("b", title: "Beta", category: .text))
        registry.activation.setEnabled(false, for: "b")

        #expect(registry.categories == [.coding])
    }
}

@Suite("ToolActivationStore")
struct ToolActivationStoreTests {
    @Test @MainActor
    func everythingIsEnabledByDefault() {
        let store = ToolActivationStore(settings: .ephemeral())
        #expect(store.isEnabled("anything"))
        #expect(store.hasDisabledAnything == false)
    }

    @Test @MainActor
    func resetSwitchesEverythingBackOn() {
        let store = ToolActivationStore(settings: .ephemeral())
        store.setEnabled(false, for: "a")
        store.setBundleEnabled(false, for: ToolOrigin(bundleIdentifier: "b", displayName: "B"))
        #expect(store.hasDisabledAnything)

        store.reset()
        #expect(store.hasDisabledAnything == false)
        #expect(store.isEnabled("a"))
    }
}
