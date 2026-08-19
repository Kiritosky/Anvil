import Foundation
import Testing

@testable import AnvilToolbox

@Suite("VocabularyCorrector")
struct VocabularyCorrectorTests {
    private func correct(
        _ text: String,
        _ entries: [VocabularyEntry],
        sensitivity: VocabularyCorrector.Sensitivity = .balanced
    ) -> VocabularyCorrector.Result {
        VocabularyCorrector(entries: entries, sensitivity: sensitivity).correct(text)
    }

    private var anvil: VocabularyEntry {
        VocabularyEntry(term: "Anvil", variants: ["Amboss"])
    }

    private var swiftUI: VocabularyEntry {
        VocabularyEntry(term: "SwiftUI")
    }

    @Test
    func leavesTextAloneWithoutEntries() {
        let result = correct("Anvil ist fertig", [])
        #expect(result.text == "Anvil ist fertig")
        #expect(result.isUnchanged)
    }

    @Test
    func reportsNothingWhenTheTermIsAlreadyRight() {
        let result = correct("Anvil ist fertig", [anvil])
        #expect(result.text == "Anvil ist fertig")
        #expect(result.count == 0)
    }

    @Test
    func replacesAnExplicitVariant() {
        let result = correct("Der Amboss läuft", [anvil])
        #expect(result.text == "Der Anvil läuft")
        #expect(result.corrections.first?.kind == .variant)
    }

    @Test
    func fixesCaseOnly() {
        let result = correct("Das ist swiftui", [swiftUI])
        #expect(result.text == "Das ist SwiftUI")
        #expect(result.corrections.first?.kind == .spelling)
    }

    @Test
    func joinsWordsTheRecogniserSplitApart() {
        let result = correct("Das ist Swift UI", [swiftUI])
        #expect(result.text == "Das ist SwiftUI")
    }

    @Test
    func correctsAMisrecognitionByDistance() {
        let result = correct("Ich baue Anwil weiter", [anvil])
        #expect(result.text == "Ich baue Anvil weiter")
        #expect(result.corrections.first?.kind == .fuzzy)
    }

    @Test
    func keepsPunctuationAroundTheTerm() {
        let result = correct("Fertig ist (anwil).", [anvil])
        #expect(result.text == "Fertig ist (Anvil).")
    }

    @Test
    func exactSensitivityNeverGuesses() {
        let result = correct("Ich baue Anwil weiter", [anvil], sensitivity: .exact)
        #expect(result.text == "Ich baue Anwil weiter")
    }

    @Test
    func exactSensitivityStillFixesCaseAndVariants() {
        let result = correct("Der Amboss und swiftui", [anvil, swiftUI], sensitivity: .exact)
        #expect(result.text == "Der Anvil und SwiftUI")
        #expect(result.count == 2)
    }

    @Test
    func leavesShortEverydayWordsAlone() {
        let result = correct("Das Haus ist groß", [VocabularyEntry(term: "Maus")])
        #expect(result.text == "Das Haus ist groß")
    }

    @Test
    func keepsTheFirstLetterUnlessAskedNotTo() {
        let entries = [VocabularyEntry(term: "Server")]
        #expect(correct("Der Nerver läuft", entries).text == "Der Nerver läuft")
        #expect(correct("Der Nerver läuft", entries, sensitivity: .thorough).text == "Der Server läuft")
    }

    @Test
    func ignoresDisabledEntries() {
        let entry = VocabularyEntry(term: "Anvil", variants: ["Amboss"], isEnabled: false)
        let corrector = VocabularyCorrector(entries: [entry].filter(\.isEnabled))
        #expect(corrector.corrected("Der Amboss läuft") == "Der Amboss läuft")
    }

    @Test
    func replacesAMultiWordVariant() {
        let entry = VocabularyEntry(term: "ToolRegistration", variants: ["Tool Registrierung"])
        let result = correct("Eine Tool Registrierung fehlt", [entry])
        #expect(result.text == "Eine ToolRegistration fehlt")
    }

    @Test
    func prefersTheLongerMatch() {
        let entries = [
            VocabularyEntry(term: "Swift"),
            VocabularyEntry(term: "Swift Concurrency", variants: ["Swift Konkurrenz"])
        ]
        let result = correct("Über Swift Konkurrenz reden", entries)
        #expect(result.text == "Über Swift Concurrency reden")
    }

    @Test
    func neverMatchesAcrossALineBreak() {
        let entry = VocabularyEntry(term: "SwiftUI")
        let result = correct("Swift\nUI", [entry])
        #expect(result.text == "Swift\nUI")
    }

    @Test
    func keepsTheOriginalSpacing() {
        let result = correct("  Der   Amboss\tläuft  ", [anvil])
        #expect(result.text == "  Der   Anvil\tläuft  ")
    }

    @Test
    func recordsWhatItChanged() {
        let result = correct("Der Amboss und swiftui", [anvil, swiftUI])
        #expect(result.corrections.map(\.original) == ["Amboss", "swiftui"])
        #expect(result.corrections.map(\.replacement) == ["Anvil", "SwiftUI"])
    }

    @Test
    func normalisationDropsCaseAccentsAndPunctuation() {
        #expect(VocabularyCorrector.normalize("Tool-Registration.") == "toolregistration")
        #expect(VocabularyCorrector.normalize("Café Crème") == "cafe creme")
        #expect(VocabularyCorrector.normalize("Straße") == VocabularyCorrector.normalize("Strasse"))
    }

    @Test
    func editDistanceGivesUpEarly() {
        let lhs = Array("Anvil")
        #expect(VocabularyCorrector.distance(lhs, Array("Anwil"), limit: 1) == 1)
        #expect(VocabularyCorrector.distance(lhs, Array("Tabelle"), limit: 1) > 1)
        #expect(VocabularyCorrector.distance(lhs, lhs, limit: 2) == 0)
    }
}

@Suite("Vokabular im Prompt")
struct VocabularyPromptTests {
    @Test
    func listsTheTermsAsARule() {
        let instructions = RefinementStyle.verbatim.instructions(
            languageName: "Deutsch",
            vocabulary: ["Anvil", "SwiftUI"]
        )
        #expect(instructions.contains("- Anvil"))
        #expect(instructions.contains("- SwiftUI"))
    }

    @Test
    func staysOutOfTheWayWithoutTerms() {
        let plain = RefinementStyle.verbatim.instructions(languageName: "Deutsch")
        #expect(!plain.contains("Eigene Schreibweisen"))
    }

    @Test
    func keepsTheTaskAfterTheWordList() {
        let instructions = RefinementStyle.bullets.instructions(
            languageName: "Deutsch",
            vocabulary: ["Anvil"]
        )
        let listPosition = instructions.range(of: "- Anvil")?.lowerBound
        let taskPosition = instructions.range(of: "Aufgabe:")?.lowerBound
        #expect(listPosition != nil)
        #expect(taskPosition != nil)
        if let listPosition, let taskPosition { #expect(listPosition < taskPosition) }
    }
}

@Suite("VocabularyEntry")
struct VocabularyEntryTests {
    @Test
    func countsWords() {
        #expect(VocabularyEntry(term: "Anvil").wordCount == 1)
        #expect(VocabularyEntry(term: "Swift Concurrency").wordCount == 2)
        #expect(VocabularyEntry(term: "").wordCount == 1)
    }

    @Test
    func roundTripsThroughJSON() throws {
        let entry = VocabularyEntry(term: "Anvil", variants: ["Amboss"], isEnabled: false)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(VocabularyEntry.self, from: data)
        #expect(decoded == entry)
    }

    @Test
    func splitsPastedVariants() {
        #expect(VocabularyToolView.splitVariants("Amboss, amboß ,  ") == ["Amboss", "amboß"])
    }
}
