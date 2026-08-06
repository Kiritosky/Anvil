import AnvilKit
import SwiftUI

/// Tools that read pictures.
public enum VisionToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.vision"
    public static let displayName = "Bild & Text"

    public static let recognizerToolID: ToolIdentifier = "vision.text"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [textRecognizer]
    }

    @MainActor
    private static var textRecognizer: ToolRegistration {
        let metadata = ToolMetadata(
            id: recognizerToolID,
            title: "Text aus Bild",
            subtitle: "Bildschirmausschnitt, Screenshot oder Datei",
            systemImage: "text.viewfinder",
            category: .everyday,
            keywords: [
                "ocr", "texterkennung", "screenshot", "bildschirmfoto", "abtippen",
                "scannen", "bild", "vision", "erkennen", "auslesen"
            ],
            badge: "Neu"
        )

        return ToolRegistration(metadata: metadata) { context in
            TextRecognizerToolView(context: context, metadata: metadata)
        }
    }
}
