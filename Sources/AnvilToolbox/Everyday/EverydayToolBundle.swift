import AnvilKit
import SwiftUI

/// The everyday tools, registered from ``EverydayToolCatalog``.
public enum EverydayToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.everyday"
    public static let displayName = "Alltag"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        EverydayToolCatalog.all.map { tool in
            ToolRegistration(metadata: tool.metadata) { context in
                TextToolView(tool: tool, context: context)
            }
        }
    }
}
