import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("In Dateien ersetzen")
struct ReplacePlanTests {
    private func rules(
        _ search: String,
        _ replacement: String,
        regex: Bool = false,
        ignoresCase: Bool = false,
        wholeWords: Bool = false
    ) -> ReplacePlan.Rules {
        var rules = ReplacePlan.Rules()
        rules.search = search
        rules.replacement = replacement
        rules.isRegularExpression = regex
        rules.ignoresCase = ignoresCase
        rules.wholeWords = wholeWords
        return rules
    }

    // MARK: - Ersetzen

    @Test
    func aLiteralIsReplaced() {
        let result = ReplacePlan.apply(rules("alt", "neu"), to: "eins alt zwei")
        #expect(result.text == "eins neu zwei")
        #expect(result.hits.count == 1)
    }

    @Test
    func withoutASearchTermNothingHappens() {
        let result = ReplacePlan.apply(ReplacePlan.Rules(), to: "bleibt")
        #expect(result.text == "bleibt")
        #expect(result.hits.isEmpty)
    }

    /// Die Vorschau zeigt Zeilen, also muss jede Zeile einzeln gezählt werden.
    @Test
    func everyChangedLineIsItsOwnHit() {
        let result = ReplacePlan.apply(rules("a", "b"), to: "a\nx\na")
        #expect(result.hits.count == 2)
        #expect(result.hits[0].line == 1)
        #expect(result.hits[1].line == 3)
        #expect(result.text == "b\nx\nb")
    }

    @Test
    func aHitCarriesBothSides() {
        let result = ReplacePlan.apply(rules("Welt", "Mond"), to: "Hallo Welt")
        #expect(result.hits[0].before == "Hallo Welt")
        #expect(result.hits[0].after == "Hallo Mond")
    }

    @Test
    func aLineWithoutAChangeIsNoHit() {
        let result = ReplacePlan.apply(rules("x", "y"), to: "eins\nzwei")
        #expect(result.hits.isEmpty)
        #expect(result.text == "eins\nzwei")
    }

    @Test
    func caseCanBeIgnored() {
        #expect(ReplacePlan.apply(rules("alt", "neu"), to: "ALT").hits.isEmpty)
        #expect(ReplacePlan.apply(rules("alt", "neu", ignoresCase: true), to: "ALT").text == "neu")
    }

    @Test
    func aRegularExpressionCanUseGroups() {
        let result = ReplacePlan.apply(
            rules("(\\w+)@(\\w+)", "$2 bei $1", regex: true),
            to: "anna@beispiel"
        )
        #expect(result.text == "beispiel bei anna")
    }

    /// Ein unfertiger Ausdruck ist beim Tippen der Normalfall.
    @Test
    func aBrokenExpressionLeavesTheLineAlone() {
        let result = ReplacePlan.apply(rules("(unfertig", "x", regex: true), to: "bleibt so")
        #expect(result.text == "bleibt so")
        #expect(result.hits.isEmpty)
    }

    /// Ohne diesen Schutz würde „$1" im Ersatz als Gruppe gelesen, obwohl
    /// niemand einen Ausdruck eingeschaltet hat.
    @Test
    func aDollarInTheReplacementStaysADollar() {
        let result = ReplacePlan.apply(rules("preis", "$1", wholeWords: true), to: "preis")
        #expect(result.text == "$1")
    }

    /// Und in der einfachen Ersetzung erst recht nicht.
    @Test
    func aDollarSurvivesTheSimplePath() {
        let result = ReplacePlan.apply(rules("preis", "$1"), to: "preis")
        #expect(result.text == "$1")
    }

    @Test
    func wholeWordsDoNotMatchInsideAWord() {
        let plain = ReplacePlan.apply(rules("Datei", "Akte"), to: "Dateiname")
        #expect(plain.text == "Aktename")

        let whole = ReplacePlan.apply(rules("Datei", "Akte", wholeWords: true), to: "Dateiname")
        #expect(whole.hits.isEmpty)

        let hit = ReplacePlan.apply(rules("Datei", "Akte", wholeWords: true), to: "die Datei hier")
        #expect(hit.text == "die Akte hier")
    }

    /// Ein Suchbegriff mit Sonderzeichen darf nicht plötzlich als Muster
    /// gelesen werden, nur weil jemand ganze Wörter angehakt hat.
    @Test
    func specialCharactersStayLiteralWithWholeWords() {
        let result = ReplacePlan.apply(rules("a.b", "x", wholeWords: true), to: "a.b und axb")
        #expect(result.text == "x und axb")
    }

    // MARK: - Zeilenenden

    /// Eine Datei mit CRLF zurückzuschreiben, in der überall LF steht, wäre im
    /// Diff eine Änderung an jeder Zeile.
    @Test
    func windowsLineEndingsSurvive() {
        let result = ReplacePlan.apply(rules("a", "b"), to: "a\r\nx\r\na")
        #expect(result.text == "b\r\nx\r\nb")
        #expect(result.hits.count == 2)
    }

    @Test
    func unixLineEndingsStayUnix() {
        let result = ReplacePlan.apply(rules("a", "b"), to: "a\nx")
        #expect(!result.text.contains("\r"))
    }

    @Test
    func aTrailingNewlineIsNotEaten() {
        let result = ReplacePlan.apply(rules("a", "b"), to: "a\n")
        #expect(result.text == "b\n")
    }

    // MARK: - Einträge

    private let url = URL(fileURLWithPath: "/tmp/anvil/datei.txt")

    @Test
    func aFileWithoutAHitIsSkipped() {
        let entry = ReplacePlan.entry(for: url, text: "nichts", rules: rules("x", "y"))
        #expect(entry.skip == .noMatch)
        #expect(entry.willChange == false)
        #expect(entry.updated == nil)
    }

    /// Nullbytes bedeuten: Das ist kein Text, und ein Ersetzen darin macht die
    /// Datei kaputt.
    @Test
    func aBinaryFileIsNeverTouched() {
        let entry = ReplacePlan.entry(for: url, text: "a\0b", rules: rules("a", "c"))
        #expect(entry.skip == .binary)
        #expect(entry.updated == nil)
    }

    @Test
    func aFileWithAHitCarriesItsNewContent() {
        let entry = ReplacePlan.entry(for: url, text: "alt", rules: rules("alt", "neu"))
        #expect(entry.skip == nil)
        #expect(entry.willChange)
        #expect(entry.updated == "neu")
    }

    @Test
    func onlyRealProblemsAreWorthMentioning() {
        #expect(ReplacePlan.Skip.noMatch.isWorthMentioning == false)
        #expect(ReplacePlan.Skip.binary.isWorthMentioning)
        #expect(ReplacePlan.Skip.tooLarge.isWorthMentioning)
        #expect(ReplacePlan.Skip.unreadable.isWorthMentioning)
    }

    @Test
    func anEmptyPlanIsNeverReady() {
        #expect(ReplacePlan.empty.isReady == false)
        #expect(ReplacePlan.empty.hitCount == 0)
        #expect(ReplacePlan.empty.changing.isEmpty)
    }

    // MARK: - Auf der Platte

    private func makeFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "anvil-replace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func write(_ text: String, to folder: URL, as name: String) throws -> URL {
        let url = folder.appending(path: name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test
    func theWholeWayThroughAndBackAgain() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = try write("alt und alt", to: folder, as: "a.txt")
        let second = try write("nichts davon", to: folder, as: "b.txt")

        let plan = ReplacePlan(files: [first, second], rules: rules("alt", "neu"))
        #expect(plan.changing.count == 1)
        #expect(plan.isReady)

        let outcome = try plan.execute()
        #expect(outcome.changedFiles == 1)
        #expect(try String(contentsOf: first, encoding: .utf8) == "neu und neu")
        #expect(try String(contentsOf: second, encoding: .utf8) == "nichts davon")

        try ReplacePlan.revert(outcome.undo)
        #expect(try String(contentsOf: first, encoding: .utf8) == "alt und alt")
    }

    /// Zwischen Vorschau und Klick können Minuten liegen. Was ein Editor in
    /// dieser Zeit gespeichert hat, darf nicht verloren gehen.
    @Test
    func aFileThatChangedInTheMeantimeIsLeftAlone() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = try write("alt", to: folder, as: "a.txt")
        let plan = ReplacePlan(files: [url], rules: rules("alt", "neu"))

        try "etwas ganz anderes".write(to: url, atomically: true, encoding: .utf8)

        let outcome = try plan.execute()
        #expect(outcome.changedFiles == 0)
        #expect(try String(contentsOf: url, encoding: .utf8) == "etwas ganz anderes")
    }

    @Test
    func aFileThatIsTooLargeIsSkipped() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = try write(String(repeating: "alt ", count: 100), to: folder, as: "a.txt")
        let plan = ReplacePlan(files: [url], rules: rules("alt", "neu"), maxBytes: 10)

        #expect(plan.entries.first?.skip == .tooLarge)
        #expect(plan.isReady == false)
    }

    @Test
    func aPlanWithNothingToDoRefusesToRun() throws {
        let plan = ReplacePlan(files: [], rules: rules("a", "b"))
        #expect(throws: AnvilError.self) { try plan.execute() }
    }
}
