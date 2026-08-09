import AnvilKit
import SwiftUI

/// Werkzeuge für Zeit.
public enum TimeToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.time"
    public static let displayName = "Zeit"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [timeTool]
    }

    @MainActor
    private static var timeTool: ToolRegistration {
        let metadata = ToolMetadata(
            id: "time.math",
            title: "Zeitrechner",
            subtitle: "Dauern, Zeitstempel, Abstände",
            systemImage: "clock",
            category: .everyday,
            keywords: [
                "zeit", "dauer", "duration", "timestamp", "zeitstempel", "unix",
                "epoch", "iso 8601", "kalenderwoche", "arbeitstage", "zeitzone"
            ]
        )

        return ToolRegistration(metadata: metadata) { context in
            TimeToolView(context: context, metadata: metadata)
        }
    }
}
