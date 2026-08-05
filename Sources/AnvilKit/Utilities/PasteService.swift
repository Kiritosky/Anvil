import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Types ⌘V into whichever app was in front.
///
/// This is the only thing in Anvil that needs the Accessibility permission, and
/// it is strictly optional: without it the text still lands on the clipboard,
/// the user just presses ⌘V themselves. Nothing here ever runs unless the user
/// switched auto-paste on.
public enum PasteService {
    /// Whether macOS currently lets Anvil post keyboard events.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks the system to show the "allow Accessibility" prompt.
    ///
    /// The prompt only ever appears once per app; afterwards macOS silently
    /// returns the stored answer, which is why ``openAccessibilitySettings()``
    /// exists as the follow-up.
    @discardableResult
    public static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Brings `application` back to the front and posts ⌘V.
    ///
    /// - Parameter application: the app that was frontmost before Anvil's panel
    ///   appeared. Captured beforehand, because by the time the text is ready
    ///   the frontmost app is Anvil itself.
    public static func paste(into application: NSRunningApplication?) async {
        guard isTrusted else { return }

        application?.activate()
        // The target needs a moment to take focus; posting into a window that
        // is not key yet does nothing at all.
        try? await Task.sleep(for: .milliseconds(150))

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let keyCode = CGKeyCode(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
