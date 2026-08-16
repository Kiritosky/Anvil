import AnvilKit
import SwiftUI

/// Werkzeuge für Daten, die als Text ankommen.
public enum DataToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.data"
    public static let displayName = "Daten"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [tableTool, modelTool]
    }

    @MainActor
    private static var modelTool: ToolRegistration {
        let metadata = ToolMetadata(
            id: "data.model",
            title: "JSON zu Typen",
            subtitle: "Aus einer Beispielantwort werden Modelle",
            systemImage: "cube",
            category: .coding,
            keywords: [
                "json", "typ", "type", "modell", "model", "struct", "codable",
                "swift", "typescript", "interface", "api", "antwort"
            ],
            badge: "Neu",
            acceptsText: true
        )

        return ToolRegistration(metadata: metadata) { context in
            ModelToolView(context: context, metadata: metadata)
        }
    }

    @MainActor
    private static var tableTool: ToolRegistration {
        let metadata = ToolMetadata(
            id: "data.table",
            title: "Tabellen",
            subtitle: "CSV ansehen, sortieren, umwandeln",
            systemImage: "tablecells",
            category: .coding,
            keywords: [
                "csv", "tsv", "tabelle", "table", "spalte", "column", "excel",
                "trennzeichen", "delimiter", "semikolon", "json", "markdown", "sql"
            ],
            acceptsText: true
        )

        return ToolRegistration(metadata: metadata) { context in
            CSVToolView(context: context, metadata: metadata)
        }
    }
}
