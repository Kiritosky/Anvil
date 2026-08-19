import AnvilKit
import SwiftUI

/// The tools that belong to the app itself.
public enum SystemToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.system"
    public static let displayName = "System"
    public static let isEssential = true

    public static let storeToolID: ToolIdentifier = "system.store"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [toolStore]
    }

    @MainActor
    private static var toolStore: ToolRegistration {
        let metadata = ToolMetadata(
            id: storeToolID,
            title: "Tool-Store",
            subtitle: "Werkzeuge ein- und ausschalten",
            systemImage: "square.grid.2x2",
            category: .system,
            keywords: ["store", "tools", "aktivieren", "deaktivieren", "verwalten", "library", "plugins"]
        )

        return ToolRegistration(metadata: metadata) { context in
            ToolStoreView(context: context, metadata: metadata)
        }
    }
}
