import AnvilKit
import SwiftUI

/// The deterministic developer tools, registered from ``DevToolCatalog``.
public enum DevToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.dev"
    public static let displayName = "Coding"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        DevToolCatalog.all.map { tool in
            ToolRegistration(metadata: tool.metadata) { context in
                TextToolView(tool: tool, context: context)
            }
        }
    }
}
