import AnvilKit
import Carbon.HIToolbox
import SwiftUI

/// Every SwiftUI type below is spelled out in full: Carbon exports an
/// `EventModifiers` of its own, and this file needs Carbon for the modifier
/// masks the shortcut is stored in.
extension GlobalShortcut {
    /// The same combination as a SwiftUI menu shortcut, or `nil` when SwiftUI
    /// has no way to express the key.
    public var keyEquivalent: SwiftUI.KeyEquivalent? {
        if let named = Self.namedEquivalents[keyLabel] { return named }
        guard keyLabel.count == 1, let character = keyLabel.lowercased().first else { return nil }
        return SwiftUI.KeyEquivalent(character)
    }

    public var eventModifiers: SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if carbonModifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        return modifiers
    }

    /// Keyed by the label the recorder stored, so this stays in step with what
    /// the user sees rather than with a key code table.
    private static let namedEquivalents: [String: SwiftUI.KeyEquivalent] = [
        "Leertaste": .space,
        "⏎": .return,
        "⇥": .tab,
        "⌫": .delete,
        "⌦": .deleteForward,
        "⎋": .escape,
        "←": .leftArrow,
        "→": .rightArrow,
        "↑": .upArrow,
        "↓": .downArrow,
        "↖": .home,
        "↘": .end,
        "⇞": .pageUp,
        "⇟": .pageDown
    ]
}
