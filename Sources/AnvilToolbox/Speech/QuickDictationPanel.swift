import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// The floating strip that appears when the dictation shortcut is pressed.
///
/// An `NSPanel` rather than a SwiftUI `Window` because it has to behave like
/// Spotlight: appear over full-screen apps, on whichever Space is showing, take
/// the keyboard so ⎋ works — and all of that *without* activating Anvil, so the
/// app you were typing in stays where the text should end up.
final class QuickDictationPanel: NSPanel {
    private let controller: QuickDictationController

    init(controller: QuickDictationController) {
        self.controller = controller

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 132),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Closing the panel must never look like quitting the app.
        isReleasedWhenClosed = false

        contentView = NSHostingView(
            rootView: QuickDictationView(controller: controller)
                .frame(width: 460)
        )
    }

    /// Panels normally refuse the keyboard; this one needs ⎋ and ⏎.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Places the panel near the top of the screen the mouse is on.
    ///
    /// Top-centre rather than dead centre: it has to stay out of the way of the
    /// text field you are dictating into.
    func present() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = frame.size
            setFrameOrigin(
                NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.maxY - size.height - 120
                )
            )
        }

        orderFrontRegardless()
        makeKey()
    }

    override func cancelOperation(_ sender: Any?) {
        Task { await controller.cancel() }
    }

    override func keyDown(with event: NSEvent) {
        // ⏎ finishes, ⎋ discards — the two things you reach for without
        // looking. Everything else is ignored so stray keys cannot disturb a
        // running dictation.
        switch event.keyCode {
        case 36, 76:
            Task { await controller.finish() }
        case 53:
            Task { await controller.cancel() }
        default:
            break
        }
    }
}
