import AnvilKit
import SwiftUI

/// Werkzeuge, die Dateien anfassen statt ihren Inhalt.
public enum FileToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.files"
    public static let displayName = "Dateien"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [rename, replace, duplicates, compare]
    }

    @MainActor
    private static var compare: ToolRegistration {
        let metadata = ToolMetadata(
            id: "files.compare",
            title: "Ordner vergleichen",
            subtitle: "Was fehlt wo, und was ist anders",
            systemImage: "arrow.left.arrow.right",
            category: .everyday,
            keywords: [
                "vergleichen", "compare", "diff", "ordner", "sicherung",
                "backup", "sync", "abgleich", "fehlt"
            ]
        )

        return ToolRegistration(metadata: metadata) { context in
            FolderCompareToolView(context: context, metadata: metadata)
        }
    }

    @MainActor
    private static var duplicates: ToolRegistration {
        let metadata = ToolMetadata(
            id: "files.duplicates",
            title: "Dubletten",
            subtitle: "Was doppelt auf der Platte liegt",
            systemImage: "square.on.square",
            category: .everyday,
            keywords: [
                "dubletten", "doppelt", "duplikate", "duplicates", "platz",
                "speicher", "aufräumen", "prüfsumme", "gleich"
            ]
        )

        return ToolRegistration(metadata: metadata) { context in
            DuplicateToolView(context: context, metadata: metadata)
        }
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
