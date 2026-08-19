import Carbon.HIToolbox
import Foundation
import Testing

@testable import AnvilKit

@Suite("GlobalShortcut")
struct GlobalShortcutTests {
    @Test
    func writesModifiersInAppleOrder() {
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_D),
            carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey),
            keyLabel: "D"
        )
        #expect(shortcut.displayString == "⌃⌥⇧⌘D")
    }

    @Test
    func showsOnlyTheModifiersThatAreSet() {
        let shortcut = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_D),
            carbonModifiers: UInt32(optionKey | cmdKey),
            keyLabel: "D"
        )
        #expect(shortcut.displayString == "⌥⌘D")
    }

    @Test
    func aShortcutWithoutModifiersStillRenders() {
        let shortcut = GlobalShortcut(keyCode: UInt32(kVK_F5), carbonModifiers: 0, keyLabel: "F5")
        #expect(shortcut.displayString == "F5")
    }

    @Test
    func theDefaultIsOptionCommandD() {
        let shortcut = GlobalShortcut.defaultDictation
        #expect(shortcut.displayString == "⌥⌘D")
        #expect(shortcut.keyCode == UInt32(kVK_ANSI_D))
    }

    @Test
    func roundTripsThroughJSON() throws {
        let shortcut = GlobalShortcut.defaultDictation
        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(GlobalShortcut.self, from: data)
        #expect(decoded == shortcut)
    }

    @Test
    func optionalShortcutsRoundTripToo() throws {
        let values: [GlobalShortcut?] = [GlobalShortcut.defaultDictation, nil]
        for value in values {
            let data = try JSONEncoder().encode([value])
            let decoded = try JSONDecoder().decode([GlobalShortcut?].self, from: data)
            #expect(decoded.first ?? nil == value)
        }
    }

    @Test
    func equalShortcutsHashTheSame() {
        let first = GlobalShortcut.defaultDictation
        let second = GlobalShortcut(
            keyCode: UInt32(kVK_ANSI_D),
            carbonModifiers: UInt32(optionKey | cmdKey),
            keyLabel: "D"
        )
        #expect(first == second)
        #expect(Set([first, second]).count == 1)
    }
}
