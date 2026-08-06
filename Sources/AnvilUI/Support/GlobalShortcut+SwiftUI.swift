import AnvilKit
import Carbon.HIToolbox
import SwiftUI

extension GlobalShortcut {
    /// The same combination as a SwiftUI menu shortcut, or `nil` when SwiftUI
    /// has no way to express the key.
    ///
    /// The function row is the gap: `KeyEquivalent` has no F5, so an action
    /// bound to one can be global but not a menu item. Worth knowing rather
    /// than worth working around — the menu is not where anybody presses F5.
    public var keyEquivalent: KeyEquivalent? {
        if let named = Self.namedEquivalents[keyLabel] { return named }
        guard keyLabel.count == 1, let character = keyLabel.lowercased().first else { return nil }
        return KeyEquivalent(character)
    }

    public var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if carbonModifiers & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        return modifiers
    }

    /// Keyed by the label the recorder stored, so this stays in step with what
    /// the user sees rather than with a key code table.
    private static let namedEquivalents: [String: KeyEquivalent] = [
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
