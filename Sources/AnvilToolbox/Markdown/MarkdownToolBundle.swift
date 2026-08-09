import AnvilKit
import SwiftUI

/// Alles rund um Markdown.
public enum MarkdownToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.markdown"
    public static let displayName = "Markdown"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [markdownTool]
    }

    @MainActor
    private static var markdownTool: ToolRegistration {
        let metadata = ToolMetadata(
            id: "markdown.document",
            title: "Markdown",
            subtitle: "Gliedern, prüfen, nach HTML",
            systemImage: "text.alignleft",
            category: .text,
            keywords: [
                "markdown", "md", "html", "readme", "überschrift", "heading",
                "inhaltsverzeichnis", "toc", "link", "lesezeit"
            ]
        )

        return ToolRegistration(metadata: metadata) { context in
            MarkdownToolView(context: context, metadata: metadata)
        }
    }
}
