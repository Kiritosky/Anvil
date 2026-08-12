import AnvilKit
import SwiftUI

/// Werkzeuge rund um Git.
public enum GitToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.git"
    public static let displayName = "Git"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [overviewTool]
    }

    @MainActor
    private static var overviewTool: ToolRegistration {
        let metadata = ToolMetadata(
            id: "git.overview",
            title: "Repositories",
            subtitle: "Wo noch Arbeit liegt",
            systemImage: "shippingbox",
            category: .coding,
            keywords: [
                "git", "repository", "repo", "zweig", "branch", "status",
                "commit", "push", "fetch", "aufräumen", "stale"
            ],
            requirements: [.git]
        )

        return ToolRegistration(metadata: metadata) { context in
            GitToolView(context: context, metadata: metadata)
        }
    }
}
