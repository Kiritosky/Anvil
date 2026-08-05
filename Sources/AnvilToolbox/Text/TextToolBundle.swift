import AnvilKit
import SwiftUI

/// Every deterministic converter, registered from ``TextToolCatalog``.
///
/// The bundle is three lines because the catalog does the work — which is the
/// point of the generic engine.
public enum TextToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.text"
    public static let displayName = "Text & Daten"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        TextToolCatalog.all.map { tool in
            ToolRegistration(metadata: tool.metadata) { context in
                TextToolView(tool: tool, context: context)
            }
        }
    }
}
