import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@MainActor
@Suite("ClipboardHistory")
struct ClipboardHistoryTests {
    private func makeHistory(limit: Int = 100) -> (ClipboardHistory, RecordingPasteboard, SettingsStore) {
        let pasteboard = RecordingPasteboard()
        let settings = SettingsStore.ephemeral()
        settings[.clipboardHistoryLimit] = limit
        return (ClipboardHistory(pasteboard: pasteboard, settings: settings), pasteboard, settings)
    }

    @Test
    func recordsNewestFirst() {
        let (history, _, _) = makeHistory()
        history.record("eins")
        history.record("zwei")
        #expect(history.entries.map(\.text) == ["zwei", "eins"])
    }

    @Test
    func ignoresEmptyCopies() {
        let (history, _, _) = makeHistory()
        history.record("   \n ")
        #expect(history.entries.isEmpty)
    }

    @Test
    func copyingTheSameThingTwiceMovesItUp() {
        let (history, _, _) = makeHistory()
        history.record("eins")
        history.record("zwei")
        history.record("eins")

        #expect(history.entries.map(\.text) == ["eins", "zwei"])
        #expect(history.entries.count == 2)
    }

    @Test
    func aRepeatKeepsItsPin() {
        let (history, _, _) = makeHistory()
        history.record("eins")
        history.record("zwei")
        history.togglePin(history.entries[1])
        history.record("eins")

        #expect(history.entries.first?.text == "eins")
        #expect(history.entries.first?.isPinned == true)
    }

    @Test
    func dropsTheOldestOncePastTheLimit() {
        let (history, _, _) = makeHistory(limit: 10)
        for index in 0..<15 {
            history.record("Eintrag \(index)")
        }

        #expect(history.entries.count == 10)
        #expect(history.entries.first?.text == "Eintrag 14")
        #expect(history.entries.last?.text == "Eintrag 5")
    }

    @Test
    func pinnedEntriesNeverAgeOut() {
        let (history, _, _) = makeHistory(limit: 10)
        history.record("wichtig")
        history.togglePin(history.entries[0])

        for index in 0..<20 {
            history.record("Eintrag \(index)")
        }

        #expect(history.entries.contains { $0.text == "wichtig" })
        #expect(history.entries.filter { !$0.isPinned }.count == 10)
    }

    @Test
    func clearingKeepsWhatWasPinned() {
        let (history, _, _) = makeHistory()
        history.record("weg")
        history.record("bleibt")
        history.togglePin(history.entries[0])

        history.clear()
        #expect(history.entries.map(\.text) == ["bleibt"])
    }

    @Test
    func searchFindsPartsOfAnEntry() {
        let (history, _, _) = makeHistory()
        history.record("Der Termin ist am Dienstag")
        history.record("etwas ganz anderes")

        #expect(history.search("dienstag").count == 1)
        #expect(history.search("").count == 2)
    }

    @Test
    func searchIsNotFuzzy() {
        let (history, _, _) = makeHistory()
        history.record("Der Termin ist am Dienstag")
        // The letters are all there in order — a subsequence match would hit.
        #expect(history.search("dta").isEmpty)
    }

    @Test
    func searchPutsPinnedFirst() {
        let (history, _, _) = makeHistory()
        history.record("Notiz eins")
        history.record("Notiz zwei")
        history.togglePin(history.entries[1])

        #expect(history.search("notiz").first?.text == "Notiz eins")
    }

    @Test
    func pollingPicksUpACopy() {
        let (history, pasteboard, _) = makeHistory()
        pasteboard.copy("frisch kopiert")
        history.poll()

        #expect(history.entries.first?.text == "frisch kopiert")
    }

    @Test
    func pollingTwiceRecordsOnce() {
        let (history, pasteboard, _) = makeHistory()
        pasteboard.copy("frisch kopiert")
        history.poll()
        history.poll()

        #expect(history.entries.count == 1)
    }

    @Test
    func concealedContentIsNeverRecorded() {
        let (history, pasteboard, _) = makeHistory()
        pasteboard.isConcealedContent = true
        pasteboard.copy("hunter2")
        history.poll()

        #expect(history.entries.isEmpty)
    }

    @Test
    func whatWasOnTheClipboardAtLaunchIsNotAnEntry() {
        let pasteboard = RecordingPasteboard()
        pasteboard.copy("von vorhin")

        let history = ClipboardHistory(pasteboard: pasteboard, settings: .ephemeral())
        history.poll()

        #expect(history.entries.isEmpty)
    }

    @Test
    func copyingBackDoesNotDuplicate() {
        let (history, pasteboard, _) = makeHistory()
        history.record("eins")
        history.record("zwei")

        history.copy(history.entries[1])
        history.poll()

        #expect(history.entries.map(\.text) == ["eins", "zwei"])
        #expect(pasteboard.copied == ["eins"])
    }

    @Test
    func previewCollapsesWhitespace() {
        let entry = ClipboardEntry(text: "  mehrere\n\nZeilen   mit\tLücken ")
        #expect(entry.preview == "mehrere Zeilen mit Lücken")
        #expect(entry.lineCount == 3)
    }
}
