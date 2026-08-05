import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// The little bubble that appears while dictating.
///
/// Two properties matter more than anything about how it looks:
///
/// - It **never takes keyboard focus**. The caret has to stay exactly where it
///   was, in the text field the result is meant to land in. A panel that
///   becomes key would move focus away and, in some apps, drop the selection —
///   and then ⌘V goes nowhere useful. Escape is handled by borrowing the key
///   globally while recording instead (see `QuickDictationController`).
/// - It floats above everything, including full-screen apps, on whichever
///   Space is currently showing.
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
        // Closing the bubble must never look like quitting the app.
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: QuickDictationView(controller: controller))
        hosting.sizingOptions = [.preferredContentSize]
        contentView = hosting
    }

    /// Deliberately false — see the note above.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Bottom centre of the screen the pointer is on.
    ///
    /// Low rather than high: while dictating you are usually looking at the
    /// text field you are dictating into, and that is rarely at the bottom.
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

        // Not `makeKeyAndOrderFront`: showing it must not disturb whatever has
        // the keyboard.
        orderFrontRegardless()
    }
}
