import AppKit
import Carbon.HIToolbox
import Foundation

/// A key combination that works while another app is frontmost.
///
/// Deliberately not SwiftUI's `KeyboardShortcut`: that one describes a menu
/// item inside this app. This one is handed to Carbon's hot-key API, which
/// wants a virtual key code and its own modifier mask.
///
/// The key's label is stored alongside the code rather than derived from it.
/// Translating a key code back to a character means going through
/// `UCKeyTranslate` and the current input source — on a German keyboard, key
/// code 6 is "Y" but on a US layout it is "Z". Recording what the user actually
/// pressed sidesteps the whole problem.
public struct GlobalShortcut: Codable, Sendable, Hashable {
    /// Virtual key code, as reported by `NSEvent.keyCode`.
    public let keyCode: UInt32
    /// Carbon modifier mask (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    public let carbonModifiers: UInt32
    /// What to draw for the key itself: "D", "Leertaste", "F5".
    public let keyLabel: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    /// Builds a shortcut from a key-down event, or returns `nil` when the event
    /// is not usable as a global hot key.
    public init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }

        let label = Self.label(for: event)

        // A bare letter would swallow that key in every other app. Function keys
        // and Escape are the usual exceptions people expect to work alone.
        let isFunctionKey = flags.contains(.function) || label.hasPrefix("F")
        guard modifiers != 0 || isFunctionKey else { return nil }
        guard !label.isEmpty else { return nil }

        self.init(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: modifiers,
            keyLabel: label
        )
    }

    /// How the combination is written in menus: ⌃⌥⇧⌘ in Apple's order, then
    /// the key.
    public var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }

    /// The combination people get when they have not chosen one.
    ///
    /// ⌥⌘D is free on a stock macOS install and sits under the left hand while
    /// the right one is still on the mouse.
    public static let defaultDictation = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(optionKey | cmdKey),
        keyLabel: "D"
    )

    // MARK: - Key labels

    private static func label(for event: NSEvent) -> String {
        if let named = namedKeys[Int(event.keyCode)] { return named }

        let characters = event.charactersIgnoringModifiers ?? ""
        guard let first = characters.first, !first.isWhitespace else { return "" }
        return String(first).uppercased()
    }

    /// Keys that have no sensible character, plus the function row.
    private static let namedKeys: [Int: String] = [
        kVK_Space: "Leertaste",
        kVK_Return: "⏎",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16"
    ]
}
