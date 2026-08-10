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
        let converters = TextToolCatalog.all.map { tool in
            ToolRegistration(metadata: tool.metadata) { context in
                TextToolView(tool: tool, context: context)
            }
        }
        // Two tools do not fit the one-input/one-output shape: a regex needs a
        // pattern *and* a subject, a comparison needs two texts.
        return converters + [regexTester, textComparison, readability]
    }

    @MainActor
    private static var readability: ToolRegistration {
        let metadata = ToolMetadata(
            id: "text.readability",
            title: "Lesbarkeit",
            subtitle: "Wie schwer ein Text zu lesen ist",
            systemImage: "gauge.medium",
            category: .text,
            keywords: [
                "lesbarkeit", "readability", "flesch", "amstad", "silben",
                "lesezeit", "satzlänge", "verständlich"
            ],
            acceptsText: true
        )

        return ToolRegistration(metadata: metadata) { context in
            ReadabilityToolView(context: context, metadata: metadata)
        }
    }

    @MainActor
    private static var regexTester: ToolRegistration {
        let metadata = ToolMetadata(
            id: "text.regex",
            title: "Regex-Tester",
            subtitle: "Muster live gegen Text prüfen",
            systemImage: "asterisk",
            category: .coding,
            keywords: ["regex", "regulärer ausdruck", "muster", "pattern", "suchen", "ersetzen"],
            acceptsText: true
        )

        return ToolRegistration(metadata: metadata) { context in
            RegexToolView(context: context, metadata: metadata)
        }
    }

    @MainActor
    private static var textComparison: ToolRegistration {
        let metadata = ToolMetadata(
            id: "text.compare",
            title: "Textvergleich",
            subtitle: "Zwei Fassungen gegenüberstellen",
            systemImage: "plusminus",
            category: .text,
            keywords: ["diff", "vergleich", "unterschied", "compare", "änderungen"],
            acceptsText: true
        )

        return ToolRegistration(metadata: metadata) { context in
            TextCompareView(context: context, metadata: metadata)
        }
    }
}
