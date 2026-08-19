import AnvilKit
import SwiftUI

/// The everyday tools, registered from ``EverydayToolCatalog``.
public enum EverydayToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.everyday"
    public static let displayName = "Alltag"

    public static let clipboardToolID: ToolIdentifier = "everyday.clipboard"

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        let converters = EverydayToolCatalog.all.map { tool in
            ToolRegistration(metadata: tool.metadata) { context in
                TextToolView(tool: tool, context: context)
            }
        }
        return [clipboard, color, colorPalette, qrCode] + converters
    }

    @MainActor
    private static var clipboard: ToolRegistration {
        let metadata = ToolMetadata(
            id: clipboardToolID,
            title: "Zwischenablage",
            subtitle: "Alles, was du kopiert hast",
            systemImage: "doc.on.clipboard",
            category: .everyday,
            keywords: [
                "zwischenablage", "clipboard", "verlauf", "history", "kopiert",
                "einfügen", "paste", "wiederherstellen"
            ]
        )

        return ToolRegistration(metadata: metadata) { context in
            ClipboardToolView(context: context, metadata: metadata)
        }
    }

    @MainActor
    private static var color: ToolRegistration {
        let metadata = ToolMetadata(
            id: "everyday.color",
            title: "Farben",
            subtitle: "Umrechnen und Kontrast prüfen",
            systemImage: "paintpalette",
            category: .everyday,
            keywords: [
                "farbe", "farben", "color", "hex", "rgb", "hsl", "kontrast",
                "wcag", "barrierefrei", "palette", "abstufung"
            ]
        )

        return ToolRegistration(metadata: metadata) { context in
            ColorToolView(context: context, metadata: metadata)
        }
    }

    @MainActor
    private static var colorPalette: ToolRegistration {
        let metadata = ToolMetadata(
            id: "everyday.palette",
            title: "Farbliste",
            subtitle: "Ganze Paletten prüfen und ausgeben",
            systemImage: "swatchpalette",
            category: .everyday,
            keywords: [
                "palette", "farbliste", "farben", "colors", "css", "variablen",
                "styleguide", "doppelt", "kontrast", "swiftui"
            ],
            acceptsText: true
        )

        return ToolRegistration(metadata: metadata) { context in
            ColorPaletteToolView(context: context, metadata: metadata)
        }
    }

    @MainActor
    private static var qrCode: ToolRegistration {
        let metadata = ToolMetadata(
            id: "everyday.qr",
            title: "QR-Code",
            subtitle: "Erzeugen und aus Bildern lesen",
            systemImage: "qrcode",
            category: .everyday,
            keywords: ["qr", "qr-code", "barcode", "scannen", "wlan", "vcard", "visitenkarte"]
        )

        return ToolRegistration(metadata: metadata) { context in
            QRCodeToolView(context: context, metadata: metadata)
        }
    }
}
