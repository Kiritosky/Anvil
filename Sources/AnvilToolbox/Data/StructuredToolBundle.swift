import AnvilKit
import SwiftUI

/// Formate, die dasselbe meinen.
public enum StructuredToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.structured"
    public static let displayName = "Formate"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [converter]
    }

    @MainActor
    private static var converter: ToolRegistration {
        let metadata = ToolMetadata(
            id: "data.structured",
            title: "JSON, YAML, TOML",
            subtitle: "Ineinander umwandeln",
            systemImage: "arrow.left.arrow.right",
            category: .coding,
            keywords: [
                "json", "yaml", "yml", "toml", "umwandeln", "convert",
                "konfiguration", "config", "formatieren"
            ],
            acceptsText: true
        )

        return ToolRegistration(metadata: metadata) { context in
            StructuredToolView(context: context, metadata: metadata)
        }
    }
}
