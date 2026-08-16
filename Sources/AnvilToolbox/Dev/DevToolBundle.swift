import AnvilKit
import SwiftUI

/// The deterministic developer tools, registered from ``DevToolCatalog``.
public enum DevToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.dev"
    public static let displayName = "Coding"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        DevToolCatalog.all.map { tool in
            ToolRegistration(metadata: tool.metadata) { context in
                TextToolView(tool: tool, context: context)
            }
        } + [environment, codeCount]
    }

    @MainActor
    private static var codeCount: ToolRegistration {
        let metadata = ToolMetadata(
            id: "dev.lines",
            title: "Codezeilen",
            subtitle: "Woraus ein Projekt besteht",
            systemImage: "chart.bar",
            category: .coding,
            keywords: [
                "zeilen", "lines", "loc", "cloc", "statistik", "sprachen",
                "projekt", "repository", "umfang", "diagramm"
            ],
            badge: "Neu"
        )

        return ToolRegistration(metadata: metadata) { context in
            CodeCountToolView(context: context, metadata: metadata)
        }
    }

    /// Der eine Coding-Werkzeugkasten, der keine Textumwandlung ist: Er
    /// vergleicht Dateien miteinander statt eine umzuformen.
    @MainActor
    private static var environment: ToolRegistration {
        let metadata = ToolMetadata(
            id: "dev.env",
            title: "Umgebungsdateien",
            subtitle: "Was wo fehlt, ohne Werte zu zeigen",
            systemImage: "list.bullet.rectangle",
            category: .coding,
            keywords: [
                "env", "umgebung", "environment", "dotenv", "variablen",
                "vergleichen", "geheim", "secrets", "konfiguration", "config"
            ],
            badge: "Neu"
        )

        return ToolRegistration(metadata: metadata) { context in
            EnvToolView(context: context, metadata: metadata)
        }
    }
}
