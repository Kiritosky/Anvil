import AnvilKit
import SwiftUI

/// Werkzeuge, die Daten erfinden statt sie umzuformen.
public enum SampleDataToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.sample"
    public static let displayName = "Testdaten"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [sampleData]
    }

    @MainActor
    private static var sampleData: ToolRegistration {
        let metadata = ToolMetadata(
            id: "sample.data",
            title: "Testdaten",
            subtitle: "Namen, Adressen, IBAN — reproduzierbar",
            systemImage: "die.face.5",
            category: .coding,
            keywords: [
                "testdaten", "sample", "fake", "mock", "namen", "adressen",
                "iban", "csv", "json", "sql", "startwert", "seed"
            ]
        )

        return ToolRegistration(metadata: metadata) { context in
            SampleDataToolView(context: context, metadata: metadata)
        }
    }
}
