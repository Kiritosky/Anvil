import AnvilAI
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("FillerCleaner")
struct FillerCleanerTests {
    private func clean(
        _ text: String,
        language: String = "de",
        strength: FillerCleaner.Strength = .gentle,
        repeats: Bool = true
    ) -> FillerCleaner.Result {
        FillerCleaner(languageCode: language, strength: strength, collapsesRepeats: repeats)
            .clean(text)
    }

    @Test
    func removesHesitationSounds() {
        let result = clean("Also ähm das ist äh ziemlich gut")
        #expect(result.text == "Also das ist ziemlich gut")
        #expect(result.removedFillers == 2)
    }

    @Test
    func removesHesitationSoundsInEnglishToo() {
        let result = clean("So um this is uh pretty good", language: "en")
        #expect(result.text == "So this is pretty good")
    }

    @Test
    func keepsPunctuationWhenTheFillerCarriedIt() {
        let result = clean("Das war gut, ähm, weiter geht es")
        #expect(result.text.contains("gut,"))
        #expect(result.text.contains("ähm") == false)
    }

    @Test
    func collapsesStutteredRepeats() {
        let result = clean("Ich ich wollte das das machen")
        #expect(result.text == "Ich wollte das machen")
        #expect(result.collapsedRepeats == 2)
    }

    @Test
    func keepsDeliberateDoubling() {
        let result = clean("Das war sehr sehr gut")
        #expect(result.text == "Das war sehr sehr gut")
        #expect(result.collapsedRepeats == 0)
    }

    @Test
    func repeatCollapsingCanBeSwitchedOff() {
        let result = clean("Ich ich wollte", repeats: false)
        #expect(result.text == "Ich ich wollte")
    }

    @Test
    func gentleModeKeepsRealWords() {
        let result = clean("Das ist halt quasi sozusagen fertig")
        #expect(result.text == "Das ist halt quasi sozusagen fertig")
    }

    @Test
    func thoroughModeRemovesVerbalTics() {
        let result = clean("Das ist halt quasi fertig", strength: .thorough)
        #expect(result.text == "Das ist fertig")
    }

    @Test
    func thoroughModeRemovesMultiWordPhrases() {
        let result = clean("Das ist, weißt du, ziemlich gut", strength: .thorough)
        #expect(result.text.contains("weißt du") == false)
        #expect(result.text.contains("ziemlich gut"))
    }

    @Test
    func capitalisesTheStartOfSentences() {
        let result = clean("ähm das ist gut. äh das auch.")
        #expect(result.text.hasPrefix("Das ist gut."))
        #expect(result.text.contains("Das auch."))
    }

    @Test
    func emptyInputStaysEmpty() {
        let result = clean("   \n  ")
        #expect(result.text.isEmpty)
        #expect(result.isUnchanged)
    }

    @Test
    func cleanTextIsLeftAlone() {
        let input = "Dieser Satz ist bereits sauber."
        let result = clean(input)
        #expect(result.text == input)
        #expect(result.isUnchanged)
    }

    @Test
    func keepsParagraphBreaks() {
        let result = clean("Erster Absatz.\nZweiter ähm Absatz.")
        #expect(result.text == "Erster Absatz.\nZweiter Absatz.")
    }
}

@Suite("RefinementStyle")
struct RefinementStyleTests {
    @Test
    func instructionsNameTheOutputLanguage() {
        let instructions = RefinementStyle.verbatim.instructions(languageName: "Deutsch")
        #expect(instructions.contains("Deutsch"))
    }

    @Test
    func customStyleUsesTheGivenInstruction() {
        let instructions = RefinementStyle.custom.instructions(
            languageName: "Deutsch",
            customInstruction: "Mach daraus ein Haiku"
        )
        #expect(instructions.contains("Haiku"))
    }

    @Test
    func customStyleFallsBackWhenNothingWasTyped() {
        let instructions = RefinementStyle.custom.instructions(languageName: "Deutsch")
        #expect(instructions.contains("Aufgabe:"))
    }

    @Test
    func onlyVerbatimPromisesToKeepTheWording() {
        #expect(RefinementStyle.verbatim.preservesWording)
        #expect(RefinementStyle.polished.preservesWording == false)
    }
}

@Suite("TranscriptRefiner")
struct TranscriptRefinerTests {
    @Test
    func stripsFencedCodeBlocks() {
        let text = "```\nHallo Welt\n```"
        #expect(TranscriptRefiner.stripWrapping(text) == "Hallo Welt")
    }

    @Test
    func stripsWrappingQuotationMarks() {
        #expect(TranscriptRefiner.stripWrapping("\"Hallo Welt\"") == "Hallo Welt")
        #expect(TranscriptRefiner.stripWrapping("„Hallo Welt“") == "Hallo Welt")
    }

    @Test
    func keepsQuotationMarksThatBelongToTheText() {
        let text = "Er sagte \"hallo\" und ging"
        #expect(TranscriptRefiner.stripWrapping(text) == text)
    }

    // MARK: - Chunk seams

    private func chunk(_ text: String, id: Int = 0) -> TextChunker.Chunk {
        TextChunker.Chunk(id: id, text: text)
    }

    @Test
    func aSingleChunkIsSentAsItIs() {
        let prompt = TranscriptRefiner.prompt(for: chunk("Hallo Welt"), of: 1, previous: nil)
        #expect(prompt == "Hallo Welt")
    }

    @Test
    func aChunkedRunSaysWhichPartItIs() {
        let prompt = TranscriptRefiner.prompt(for: chunk("Zweiter Teil", id: 1), of: 3, previous: nil)
        #expect(prompt.contains("Teil 2 von 3"))
        #expect(prompt.hasSuffix("Zweiter Teil"))
    }

    @Test
    func theTailOfThePreviousChunkComesAlong() {
        let prompt = TranscriptRefiner.prompt(
            for: chunk("Zweiter Teil", id: 1),
            of: 2,
            previous: "Der erste Teil endete mit diesem Satz."
        )
        #expect(prompt.contains("Der erste Teil endete mit diesem Satz."))
        #expect(prompt.contains("nicht wiederholen"))
    }

    @Test
    func onlyTheTailComesAlongNotTheWholeChunk() {
        let long = String(repeating: "Ein Satz über irgendetwas. ", count: 40)
        let prompt = TranscriptRefiner.prompt(for: chunk("Weiter", id: 1), of: 2, previous: long)
        #expect(prompt.count < 700)
    }

    @Test
    func theTailStartsAtASentenceBoundary() {
        let text = String(repeating: "x", count: 300) + ". Der letzte Satz."
        #expect(TranscriptRefiner.tail(of: text) == "Der letzte Satz.")
    }

    @Test
    func aShortPreviousChunkIsPassedWhole() {
        #expect(TranscriptRefiner.tail(of: "  Kurz.  ") == "Kurz.")
    }
}
