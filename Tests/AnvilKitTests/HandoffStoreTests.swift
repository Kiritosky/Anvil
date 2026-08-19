import Foundation
import Testing

@testable import AnvilKit

@MainActor
@Suite("Weitergeben")
struct HandoffStoreTests {
    private let netz = ToolIdentifier("net.subnet")
    private let zeit = ToolIdentifier("time.math")

    @Test
    func whatWasSentComesOutAtTheOtherEnd() {
        let store = HandoffStore()
        store.send("10.0.0.0/8", to: netz)
        #expect(store.take(for: netz) == "10.0.0.0/8")
    }

    /// Einmalig mit Absicht: Wer ein Werkzeug ein zweites Mal öffnet, will
    /// seinen eigenen Stand sehen.
    @Test
    func takingItOnceIsEnough() {
        let store = HandoffStore()
        store.send("x", to: netz)
        #expect(store.take(for: netz) == "x")
        #expect(store.take(for: netz) == nil)
    }

    @Test
    func everyToolHasItsOwnSlot() {
        let store = HandoffStore()
        store.send("Netz", to: netz)
        store.send("Zeit", to: zeit)
        #expect(store.take(for: zeit) == "Zeit")
        #expect(store.take(for: netz) == "Netz")
    }

    /// Bereitgelegt ist immer das Letzte, nicht eine Schlange.
    @Test
    func sendingTwiceKeepsTheSecond() {
        let store = HandoffStore()
        store.send("alt", to: netz)
        store.send("neu", to: netz)
        #expect(store.take(for: netz) == "neu")
        #expect(store.take(for: netz) == nil)
    }

    @Test
    func lookingDoesNotTake() {
        let store = HandoffStore()
        store.send("x", to: netz)
        #expect(store.hasPending(for: netz))
        #expect(store.hasPending(for: zeit) == false)
        #expect(store.take(for: netz) == "x")
    }

    /// Die Shell braucht das Ziel, um es zu öffnen — und setzt es danach
    /// zurück, sonst öffnet sich dasselbe Werkzeug bei jeder Änderung wieder.
    @Test
    func theTargetIsRememberedUntilTheShellHasFollowedIt() {
        let store = HandoffStore()
        #expect(store.lastTarget == nil)
        store.send("x", to: netz)
        #expect(store.lastTarget == netz)
        store.clearTarget()
        #expect(store.lastTarget == nil)
        #expect(store.take(for: netz) == "x")
    }

    @Test
    func forgettingClearsBoth() {
        let store = HandoffStore()
        store.send("x", to: netz)
        store.forget(netz)
        #expect(store.take(for: netz) == nil)
        #expect(store.lastTarget == nil)
    }

    @Test
    func nothingWasSentToAToolThatWasNeverATarget() {
        let store = HandoffStore()
        #expect(store.take(for: netz) == nil)
        #expect(!store.hasPending(for: netz))
    }
}

@Suite("Welche Werkzeuge Text annehmen")
struct AcceptsTextTests {
    /// Der Standard ist aus: ein Werkzeug, das Dateien einsammelt oder ein
    /// Mikrofon aufmacht, kann mit einer Zeichenkette nichts anfangen.
    @Test
    func theDefaultIsOff() {
        let metadata = ToolMetadata(
            id: "test.tool",
            title: "Test",
            subtitle: "",
            systemImage: "gear",
            category: .coding
        )
        #expect(!metadata.acceptsText)
    }

    @Test
    func itCanBeSwitchedOn() {
        let metadata = ToolMetadata(
            id: "test.tool",
            title: "Test",
            subtitle: "",
            systemImage: "gear",
            category: .coding,
            acceptsText: true
        )
        #expect(metadata.acceptsText)
    }
}
