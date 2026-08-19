import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// The little bubble that appears while dictating.
final class QuickDictationPanel: NSPanel {
    private let controller: QuickDictationController

    init(controller: QuickDictationController) {
        self.controller = controller

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 56),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: QuickDictationView(controller: controller))
        hosting.sizingOptions = [.preferredContentSize]
        contentView = hosting
    }

    /// Deliberately false — see the note above.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Bottom centre of the screen the pointer is on.
    func present() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = frame.size
            setFrameOrigin(
                NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.minY + 120
                )
            )
        }

        orderFrontRegardless()
    }
}
