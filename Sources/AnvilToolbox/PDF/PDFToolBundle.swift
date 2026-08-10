import AnvilKit
import SwiftUI

/// Werkzeuge für PDFs.
public enum PDFToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.pdf"
    public static let displayName = "PDF"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [pdfTool]
    }

    @MainActor
    private static var pdfTool: ToolRegistration {
        let metadata = ToolMetadata(
            id: "pdf.pages",
            title: "PDF",
            subtitle: "Zusammenführen, teilen, drehen, auslesen",
            systemImage: "doc.richtext",
            category: .everyday,
            keywords: [
                "pdf", "seiten", "zusammenführen", "merge", "teilen", "split",
                "drehen", "rotate", "text", "auslesen", "stapel"
            ]
        )

        return ToolRegistration(metadata: metadata) { context in
            PDFToolView(context: context, metadata: metadata)
        }
    }
}
