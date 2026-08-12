import AnvilKit
import SwiftUI

/// Werkzeuge, die Dateien anfassen statt ihren Inhalt.
public enum FileToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.files"
    public static let displayName = "Dateien"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [rename, replace]
    }

    @MainActor
    private static var replace: ToolRegistration {
        let metadata = ToolMetadata(
            id: "files.replace",
            title: "In Dateien ersetzen",
            subtitle: "Über viele Dateien, mit Vorschau",
            systemImage: "text.badge.checkmark",
            category: .coding,
            keywords: [
                "ersetzen", "replace", "suchen", "search", "sed", "stapel",
                "batch", "regex", "dateien", "vorschau", "rückgängig"
            ]
        )

        return ToolRegistration(metadata: metadata) { context in
            ReplaceToolView(context: context, metadata: metadata)
        }
    }

    @MainActor
    private static var rename: ToolRegistration {
        let metadata = ToolMetadata(
            id: "files.rename",
            title: "Umbenennen",
            subtitle: "Im Stapel, mit Vorschau",
            systemImage: "square.and.pencil",
            category: .everyday,
            keywords: [
                "umbenennen", "rename", "stapel", "batch", "dateien", "nummerieren",
                "suchen", "ersetzen", "endung", "vorschau"
            ]
        )

        return ToolRegistration(metadata: metadata) { context in
            RenameToolView(context: context, metadata: metadata)
        }
    }
}
