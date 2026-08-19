import AnvilKit
import SwiftUI

/// The built-in prompt tools.
public enum AIToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.ai"
    public static let displayName = "KI-Werkzeuge"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        AIPromptCatalog.all.map { registration(for: $0) } + [builder]
    }

    /// Das Werkzeug, das Werkzeuge anlegt.
    @MainActor
    private static var builder: ToolRegistration {
        let metadata = ToolMetadata(
            id: "custom.builder",
            title: "Eigenes Werkzeug",
            subtitle: "Aus einem Prompt ein Werkzeug machen",
            systemImage: "hammer.circle",
            category: .custom,
            keywords: [
                "eigenes", "werkzeug", "tool", "prompt", "anlegen", "bauen",
                "json", "erweitern", "custom"
            ]
        )

        return ToolRegistration(metadata: metadata) { context in
            CustomToolBuilderView(context: context, metadata: metadata)
        }
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
