import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Types ⌘V into whichever app was in front.
public enum PasteService {
    /// Whether macOS currently lets Anvil post keyboard events.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks the system to show the "allow Accessibility" prompt.
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
        let element = focused as! AXUIElement

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
    public static func paste(into application: NSRunningApplication?) async {
        guard isTrusted else { return }

        application?.activate()
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
