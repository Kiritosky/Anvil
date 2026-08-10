import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Sätze trennen")
struct SentenceSplittingTests {
    @Test
    func plainSentencesAreSplitAtThePunctuation() {
        let sentences = Readability.sentences(in: "Eins. Zwei! Drei?")
        #expect(sentences == ["Eins.", "Zwei!", "Drei?"])
    }

    /// Ohne diese Ausnahme zerfällt jeder deutsche Text in doppelt so viele
    /// Sätze, wie er hat — und alle Werte darunter sind zu gut.
    @Test
    func abbreviationsDoNotEndASentence() {
        #expect(Readability.sentences(in: "Das gilt z. B. für Anvil.").count == 1)
        #expect(Readability.sentences(in: "Etwa 5 Stück, bzw. mehr davon.").count == 1)
        #expect(Readability.sentences(in: "Vgl. dazu die Tabelle oben.").count == 1)
    }

    @Test
    func aDotBetweenDigitsIsNoSentenceEnd() {
        #expect(Readability.sentences(in: "Das kostet 1.500 Euro im Jahr.").count == 1)
    }

    @Test
    func severalPunctuationMarksAreOneEnding() {
        #expect(Readability.sentences(in: "Wirklich?! Ja.").count == 2)
        #expect(Readability.sentences(in: "Warte ... jetzt.").count == 1)
    }

    @Test
    func aSentenceWithoutAFullStopStillCounts() {
        #expect(Readability.sentences(in: "Ohne Punkt am Ende").count == 1)
        #expect(Readability.sentences(in: "").isEmpty)
        #expect(Readability.sentences(in: "   \n  ").isEmpty)
    }
}

@Suite("Wörter und Silben")
struct SyllableTests {
    @Test
    func hyphensAndApostrophesHoldAWordTogether() {
        #expect(Readability.words(in: "E-Mail und Anvil's Werkzeug") == ["E-Mail", "und", "Anvil's", "Werkzeug"])
    }

    @Test
    func numbersCountAsWords() {
        #expect(Readability.words(in: "im Jahr 2026") == ["im", "Jahr", "2026"])
    }

    /// Vokalgruppen, keine Vokale: „Haus" hat eine Silbe.
    @Test(arguments: [
        ("Haus", 1), ("Hause", 2), ("Straße", 2), ("Werkzeug", 2),
        ("Anvil", 2), ("Eingabe", 3), ("Übersetzung", 4), ("und", 1)
    ])
    func germanSyllablesAreCountedAsVowelGroups(_ word: String, _ expected: Int) {
        #expect(Readability.syllables(in: word, language: .german) == expected)
    }

    /// Englisches Schluss-e ist stumm.
    @Test(arguments: [
        ("name", 1), ("table", 2), ("see", 1), ("readable", 3), ("the", 1)
    ])
    func englishSilentEIsNotASyllable(_ word: String, _ expected: Int) {
        #expect(Readability.syllables(in: word, language: .english) == expected)
    }

    @Test
    func everyWordHasAtLeastOneSyllable() {
        #expect(Readability.syllables(in: "sms", language: .german) == 1)
        #expect(Readability.syllables(in: "2026", language: .german) == 1)
        #expect(Readability.syllables(in: "", language: .german) == 0)
    }
}

@Suite("Lesbarkeit rechnen")
struct ReadabilityScoreTests {
    /// Kurze Sätze aus kurzen Wörtern sind leicht, lange aus langen schwer —
    /// mehr misst die Formel nicht, und genau das soll herauskommen.
    @Test
    func shortAndSimpleScoresHigherThanLongAndComplicated() {
        let easy = Readability("Der Hund ist da. Er ist froh. Wir gehen raus.")
        let hard = Readability(
            "Die verwaltungsrechtliche Zuständigkeitsregelung erfordert eine "
                + "verhältnismäßigkeitsorientierte Gesamtbetrachtung sämtlicher "
                + "entscheidungserheblicher Tatbestandsvoraussetzungen unter "
                + "Berücksichtigung höchstrichterlicher Rechtsprechung."
        )
        #expect(easy.flesch > hard.flesch)
        #expect(easy.level == .veryEasy)
        #expect(hard.level == .veryHard)
    }

    /// Der Wert wird begrenzt: „112 von 100" ist keine Auskunft, sondern ein
    /// Rechenartefakt.
    @Test
    func theScoreStaysBetweenZeroAndOneHundred() {
        let trivial = Readability("Ja. Nein. Gut.")
        #expect(trivial.flesch <= 100)
        #expect(trivial.flesch >= 0)
    }

    @Test
    func anEmptyTextHasNoScoreAndDoesNotDivideByZero() {
        let nothing = Readability("")
        #expect(nothing.wordCount == 0)
        #expect(nothing.sentenceCount == 0)
        #expect(nothing.flesch == 0)
        #expect(nothing.averageSentenceLength == 0)
        #expect(nothing.averageSyllablesPerWord == 0)
        #expect(nothing.longWordShare == 0)
        #expect(nothing.gradeLevel == 0)
    }

    /// Dieselbe Formel für beide Sprachen gäbe für jeden deutschen Text zu
    /// schlechte Werte.
    @Test
    func germanAndEnglishUseDifferentFormulas() {
        let text = "Das ist ein Satz mit einigen Wörtern darin."
        let german = Readability(text, language: .german)
        let english = Readability(text, language: .english)
        #expect(german.flesch != english.flesch)
    }

    @Test
    func readingTimeIsNeverZero() {
        #expect(Readability("eins").readingMinutes == 1)
        let long = Array(repeating: "Wort", count: 400).joined(separator: " ") + "."
        #expect(Readability(long).readingMinutes == 2)
    }

    @Test
    func theAveragesAreWhatTheySay() {
        let reading = Readability("Eins zwei drei. Vier fünf sechs.")
        #expect(reading.sentenceCount == 2)
        #expect(reading.wordCount == 6)
        #expect(reading.averageSentenceLength == 3)
    }
}

@Suite("Wo es schwer wird")
struct LongestPartsTests {
    private let text = """
    Kurz. Das hier ist ein Satz mit deutlich mehr Wörtern darin als der davor \
    und auch als der danach. Wieder kurz.
    """

    @Test
    func theLongestSentenceComesFirst() {
        let longest = Readability(text).longestSentences()
        #expect(longest.count == 3)
        #expect(longest[0].words > longest[1].words)
        #expect(longest[1].words > longest[2].words)
        // „Kurz." ist der kürzeste Satz und steht deshalb hinten.
        #expect(longest.last?.words == 1)
    }

    @Test
    func askingForMoreThanThereAreGivesWhatThereIs() {
        #expect(Readability(text).longestSentences(99).count == 3)
        #expect(Readability("").longestSentences().isEmpty)
    }

    /// Dasselbe Wort zweimal ist nicht zwei lange Wörter.
    @Test
    func theLongestWordsHaveNoRepeats() {
        let words = Readability("Übersetzung und Übersetzung und Werkzeug.").longestWords()
        #expect(words.filter { $0.lowercased() == "übersetzung" }.count == 1)
        #expect(words.first == "Übersetzung")
    }

    @Test
    func aLongSentenceIsMarkedAndAVeryLongOneToo() {
        let short = Readability("Eins zwei drei.").measuredSentences[0]
        #expect(!short.isLong)

        let long = Readability(Array(repeating: "Wort", count: 25).joined(separator: " ") + ".")
        #expect(long.measuredSentences[0].isLong)
        #expect(!long.measuredSentences[0].isVeryLong)

        let veryLong = Readability(Array(repeating: "Wort", count: 35).joined(separator: " ") + ".")
        #expect(veryLong.measuredSentences[0].isVeryLong)
    }
}
