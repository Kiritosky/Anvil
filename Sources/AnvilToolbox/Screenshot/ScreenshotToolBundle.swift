import AnvilKit
import Carbon.HIToolbox
import SwiftUI

/// The screenshot tool and the actions its shortcuts trigger.
public enum ScreenshotToolBundle: ToolBundle {
    public static let bundleIdentifier = "dev.anvil.screenshot"
    public static let displayName = "Bildschirm"

    public static let toolID: ToolIdentifier = "screen.shot"

    public static let regionActionID: ShortcutActionID = "screenshot.region"
    public static let windowActionID: ShortcutActionID = "screenshot.window"
    public static let fullScreenActionID: ShortcutActionID = "screenshot.fullScreen"
    public static let textActionID: ShortcutActionID = "screenshot.text"

    public static let actionIDs: [ShortcutActionID] = [
        regionActionID, windowActionID, fullScreenActionID, textActionID
    ]

    @MainActor
    public static func makeTools() -> [ToolRegistration] {
        [screenshot]
    }

    @MainActor
    private static var screenshot: ToolRegistration {
        let metadata = ToolMetadata(
            id: toolID,
            title: "Bildschirmfoto",
            subtitle: "Aufnehmen, lesen, weitergeben",
            systemImage: "camera.viewfinder",
            category: .everyday,
            keywords: [
                "screenshot", "bildschirmfoto", "aufnahme", "bildschirm", "ausschnitt",
                "fenster", "abfotografieren", "capture", "ocr", "text"
            ],
            badge: "Neu"
        )

        return ToolRegistration(metadata: metadata) { context in
            ScreenshotToolView(context: context, metadata: metadata)
        }
    }

    /// The shortcut actions, built against a controller the app owns.
    ///
    /// Defaults deliberately shifted one modifier away from the system's own
    /// ⇧⌘3/4/5: close enough to remember, far enough not to fight over.
    @MainActor
    public static func makeActions(controller: ScreenshotController) -> [ShortcutAction] {
        [
            ShortcutAction(
                id: regionActionID,
                title: "Ausschnitt aufnehmen",
                subtitle: "Rechteck aufziehen, Leertaste wechselt zum Fenster",
                systemImage: "rectangle.dashed",
                toolID: toolID,
                defaultShortcut: GlobalShortcut(
                    keyCode: UInt32(kVK_ANSI_4),
                    carbonModifiers: UInt32(optionKey | cmdKey),
                    keyLabel: "4"
                ),
                defaultScope: .global
            ) {
                Task { await controller.capture(.region) }
            },
            ShortcutAction(
                id: windowActionID,
                title: "Fenster aufnehmen",
                subtitle: "Fenster anklicken",
                systemImage: "macwindow",
                toolID: toolID,
                defaultShortcut: GlobalShortcut(
                    keyCode: UInt32(kVK_ANSI_5),
                    carbonModifiers: UInt32(optionKey | cmdKey),
                    keyLabel: "5"
                ),
                defaultScope: .off
            ) {
                Task { await controller.capture(.window) }
            },
            ShortcutAction(
                id: fullScreenActionID,
                title: "Ganzen Bildschirm aufnehmen",
                subtitle: "Alle Bildschirme, sofort",
                systemImage: "menubar.dock.rectangle",
                toolID: toolID,
                defaultShortcut: GlobalShortcut(
                    keyCode: UInt32(kVK_ANSI_3),
                    carbonModifiers: UInt32(optionKey | cmdKey),
                    keyLabel: "3"
                ),
                defaultScope: .off
            ) {
                Task { await controller.capture(.fullScreen) }
            },
            ShortcutAction(
                id: textActionID,
                title: "Text vom Bildschirm kopieren",
                subtitle: "Ausschnitt wählen, Text landet in der Zwischenablage",
                systemImage: "text.viewfinder",
                toolID: toolID,
                defaultShortcut: GlobalShortcut(
                    keyCode: UInt32(kVK_ANSI_T),
                    carbonModifiers: UInt32(optionKey | cmdKey),
                    keyLabel: "T"
                ),
                defaultScope: .global
            ) {
                Task { await controller.captureText() }
            }
        ]
    }
}
