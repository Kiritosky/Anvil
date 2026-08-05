import AnvilKit
import SwiftUI

/// The built-in prompt tools.
public enum AIToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.ai"
    public static let displayName = "KI-Werkzeuge"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        AIPromptCatalog.all.map(registration(for:))
    }

    /// Shared with the user-tool loader so built-in and user tools are built by
    /// exactly the same code path.
    @MainActor
    static func registration(for tool: AIPromptTool, origin: ToolOrigin = .unspecified) -> ToolRegistration {
        let metadata = tool.metadata()
        return ToolRegistration(metadata: metadata, origin: origin) { context in
            AIPromptToolView(tool: tool, metadata: metadata, context: context)
        }
    }
}
