import AnvilKit
import SwiftUI

/// The everyday tools, registered from ``EverydayToolCatalog``.
public enum EverydayToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.everyday"
    public static let displayName = "Alltag"

    public static let clipboardToolID: ToolIdentifier = "everyday.clipboard"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        let converters = EverydayToolCatalog.all.map { tool in
            ToolRegistration(metadata: tool.metadata) { context in
                TextToolView(tool: tool, context: context)
            }
        }
        // The clipboard history has no input pane — it is a live list, not a
        // function over a string.
        return [clipboard] + converters
    }

    @MainActor
    private static var clipboard: ToolRegistration {
        let metadata = ToolMetadata(
            id: clipboardToolID,
            title: "Zwischenablage",
            subtitle: "Alles, was du kopiert hast",
            systemImage: "doc.on.clipboard",
            category: .everyday,
            keywords: [
                "zwischenablage", "clipboard", "verlauf", "history", "kopiert",
                "einfügen", "paste", "wiederherstellen"
            ]
        )

        return ToolRegistration(metadata: metadata) { context in
            ClipboardToolView(context: context, metadata: metadata)
        }
    }
}
