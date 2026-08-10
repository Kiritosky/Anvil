import AnvilKit
import SwiftUI

/// Werkzeuge für Änderungen zwischen zwei Fassungen.
public enum DiffToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.diff"
    public static let displayName = "Patches"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [patchTool]
    }

    @MainActor
    private static var patchTool: ToolRegistration {
        let metadata = ToolMetadata(
            id: "diff.patch",
            title: "Patch",
            subtitle: "Diff lesen, anwenden, umkehren",
            systemImage: "doc.text.below.ecg",
            category: .coding,
            keywords: [
                "diff", "patch", "unified", "hunk", "abschnitt", "anwenden",
                "apply", "umkehren", "revert", "git"
            ],
            acceptsText: true
        )

        return ToolRegistration(metadata: metadata) { context in
            PatchToolView(context: context, metadata: metadata)
        }
    }
}
