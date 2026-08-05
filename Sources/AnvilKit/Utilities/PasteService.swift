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

    /// Whether the keyboard focus is currently sitting in something editable.
    ///
    /// Asked *before* Anvil shows anything, because the moment a panel appears
    /// the focused element would be Anvil's own. The answer decides whether the
    /// finished dictation gets pasted or only copied — pressing ⌘V into a
    /// Finder window or a game does nothing good.
    ///
    /// Returns `false` without the Accessibility permission, which is the safe
    /// answer: the text still reaches the clipboard.
    public static func focusedElementIsEditable() -> Bool {
        guard isTrusted else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success else { return false }

        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        // swiftlint:disable:next force_cast
        let element = focused as! AXUIElement

        // Two questions, either of which is a good enough yes: does it call
        // itself a text control, and can its value actually be written?
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           let roleName = role as? String,
           editableRoles.contains(roleName) {
            return true
        }

        var isSettable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &isSettable
        ) == .success else { return false }
        return isSettable.boolValue
    }

    private static let editableRoles: Set<String> = [
        kAXTextFieldRole,
        kAXTextAreaRole,
        kAXComboBoxRole,
        "AXSearchField"
    ]

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
