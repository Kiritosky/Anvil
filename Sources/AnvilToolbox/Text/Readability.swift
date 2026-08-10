import AnvilKit
import Foundation

/// Wie schwer ein Text zu lesen ist.
///
/// Alle Lesbarkeitsformeln messen dasselbe: lange Sätze und lange Wörter. Sie
/// wissen nichts über Inhalt, Aufbau oder Sinn — ein Text aus lauter kurzen
/// Sätzen kann völlig unverständlich sein und trotzdem gut abschneiden. Was
/// sie können, ist etwas anderes und trotzdem nützlich: sie zeigen, **wo** ein
/// Text schwer wird, und zwei Fassungen desselben Textes lassen sich damit
/// ehrlich vergleichen.
public struct Readability: Sendable {
    /// Für welche Sprache gerechnet wird.
    ///
    /// Deutsch braucht eine eigene Formel: dieselbe Rechnung wie fürs
    /// Englische ergäbe für jeden deutschen Text zu schlechte Werte, weil
    /// deutsche Wörter im Schnitt länger sind, ohne deshalb schwerer zu sein.
    public enum Language: String, Hashable, Sendable, CaseIterable, Identifiable {
        case german
        case english

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .german: localized("Deutsch")
            case .english: localized("Englisch")
            }
        }

        /// Vokale, die als Silbenkern zählen.
        var vowels: Set<Character> {
            switch self {
            case .german: ["a", "e", "i", "o", "u", "ä", "ö", "ü", "y"]
            case .english: ["a", "e", "i", "o", "u", "y"]
            }
        }
    }

    public let language: Language
    public let sentences: [String]
    public let words: [String]
    public let syllables: Int

    public init(_ text: String, language: Language = .german) {
        self.language = language
        self.sentences = Self.sentences(in: text)
        let words = Self.words(in: text)
        self.words = words
        self.syllables = words.reduce(0) { $0 + Self.syllables(in: $1, language: language) }
    }

    // MARK: - Zerlegen

    /// Sätze.
    ///
    /// Getrennt an `.`, `!`, `?` — aber nicht an Abkürzungen wie „z. B." und
    /// nicht an Zahlen wie „1.500". Ohne diese beiden Ausnahmen zerfällt jeder
    /// deutsche Text in doppelt so viele Sätze, wie er hat, und alle Werte
    /// darunter sind zu gut.
    public static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: Character?

        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            guard character == "." || character == "!" || character == "?" else {
                if !character.isWhitespace { previous = character }
                continue
            }

            let next = index + 1 < characters.count ? characters[index + 1] : nil
            // „1.500" — ein Punkt zwischen Ziffern trennt keinen Satz.
            if character == ".", let previous, previous.isNumber, let next, next.isNumber {
                continue
            }
            // „z. B." — ein einzelner Buchstabe vor dem Punkt ist eine
            // Abkürzung und kein Satzende.
            if character == ".", isAbbreviation(current) {
                continue
            }
            // Mehrere Satzzeichen hintereinander sind ein Ende, nicht drei.
            if let next, next == "." || next == "!" || next == "?" {
                continue
            }
            // Geht es klein weiter, war das kein Satzende: „Warte … jetzt."
            // ist ein Satz. Im Deutschen wie im Englischen fängt ein Satz groß
            // an, und das ist hier das verlässlichere Zeichen als der Punkt.
            if let following = characters[(index + 1)...].first(where: { !$0.isWhitespace }),
               following.isLowercase {
                continue
            }

            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(trimmed) }
            current = ""
            previous = nil
        }

        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    /// Ob der Punkt am Ende zu einer Abkürzung gehört.
    static func isAbbreviation(_ upToDot: String) -> Bool {
        let body = upToDot.dropLast()
        guard let last = body.last, last.isLetter else { return false }
        // Das letzte „Wort" vor dem Punkt.
        let token = String(body.reversed().prefix { $0.isLetter }.reversed())
        if token.count == 1 { return true }
        return abbreviations.contains(token.lowercased())
    }

    /// Die Abkürzungen, die in deutschen und englischen Texten ständig
    /// vorkommen. Keine vollständige Liste — eine vollständige gibt es nicht.
    static let abbreviations: Set<String> = [
        "bzw", "ca", "usw", "usf", "vgl", "evtl", "ggf", "inkl", "exkl",
        "bspw", "sog", "u", "z", "d", "b", "h", "nr", "abs", "art", "bd",
        "dr", "prof", "hr", "fr", "st", "mio", "mrd", "tsd", "jh", "jhd",
        "etc", "eg", "ie", "vs", "mr", "mrs", "ms", "approx", "dept", "est"
    ]

    /// Wörter.
    ///
    /// Zahlen zählen mit: „2026" ist ein Wort, das man liest. Bindestriche und
    /// Apostrophe halten ein Wort zusammen — „E-Mail" ist eins, nicht zwei.
    public static func words(in text: String) -> [String] {
        text.split { character in
            !(character.isLetter || character.isNumber || character == "-" || character == "'"
                || character == "\u{2019}")
        }
        .map(String.init)
        .filter { $0.contains { $0.isLetter || $0.isNumber } }
    }

    /// Silben eines Wortes.
    ///
    /// Gezählt werden Vokalgruppen, nicht Vokale: „Haus" hat eine Silbe und
    /// nicht zwei. Das ist eine Schätzung und keine Silbentrennung — für einen
    /// Durchschnitt über hunderte Wörter reicht sie, für ein einzelnes Wort
    /// nicht.
    public static func syllables(in word: String, language: Language) -> Int {
        let clean = word.lowercased().filter { $0.isLetter }
        guard !clean.isEmpty else {
            // Eine reine Zahl liest man als mindestens eine Silbe.
            return word.contains(where: \.isNumber) ? 1 : 0
        }

        let vowels = language.vowels
        let characters = Array(clean)
        var count = 0
        var index = 0

        while index < characters.count {
            guard vowels.contains(characters[index]) else {
                index += 1
                continue
            }
            count += 1
            // Die ganze Vokalgruppe überspringen: „ei", „eau", „ieu" sind je
            // ein Kern.
            while index < characters.count, vowels.contains(characters[index]) {
                index += 1
            }
        }

        // Englisches Schluss-e ist stumm: „name" hat eine Silbe, nicht zwei.
        if language == .english, clean.hasSuffix("e"), count > 1,
           !clean.hasSuffix("le"), !clean.hasSuffix("ee"), !clean.hasSuffix("ye") {
            count -= 1
        }

        return max(1, count)
    }

    // MARK: - Kennzahlen

    public var wordCount: Int { words.count }
    public var sentenceCount: Int { sentences.count }
    public var characterCount: Int { words.reduce(0) { $0 + $1.count } }

    public var averageSentenceLength: Double {
        sentenceCount == 0 ? 0 : Double(wordCount) / Double(sentenceCount)
    }

    public var averageSyllablesPerWord: Double {
        wordCount == 0 ? 0 : Double(syllables) / Double(wordCount)
    }

    /// Anteil der Wörter mit drei oder mehr Silben.
    public var longWordShare: Double {
        guard wordCount > 0 else { return 0 }
        let long = words.filter { Self.syllables(in: $0, language: language) >= 3 }.count
        return Double(long) / Double(wordCount)
    }

    /// Flesch-Lesbarkeit: 0 bis 100, hoch heißt leicht.
    ///
    /// Fürs Deutsche in der Fassung von Toni Amstad, fürs Englische die
    /// ursprüngliche von Rudolf Flesch. Der Wert wird auf 0…100 begrenzt: die
    /// Formel kann darüber hinausschießen, aber „112 von 100" ist keine
    /// Auskunft, sondern ein Rechenartefakt.
    public var flesch: Double {
        guard wordCount > 0, sentenceCount > 0 else { return 0 }
        let sentenceLength = averageSentenceLength
        let syllablesPerWord = averageSyllablesPerWord
        let raw: Double
        switch language {
        case .german:
            raw = 180 - sentenceLength - (58.5 * syllablesPerWord)
        case .english:
            raw = 206.835 - (1.015 * sentenceLength) - (84.6 * syllablesPerWord)
        }
        return min(100, max(0, raw))
    }

    /// Die Schuljahre, die man für den Text gebraucht hätte.
    ///
    /// Amerikanische Klassenstufen — im deutschen Schulsystem gibt es keine
    /// Entsprechung, deshalb steht der Wert hier als Zahl und nicht als
    /// Empfehlung.
    public var gradeLevel: Double {
        guard wordCount > 0, sentenceCount > 0 else { return 0 }
        return max(0, 0.39 * averageSentenceLength + 11.8 * averageSyllablesPerWord - 15.59)
    }

    /// Bei 200 Wörtern je Minute, aufgerundet und nie null.
    public var readingMinutes: Int {
        max(1, Int((Double(wordCount) / 200).rounded(.up)))
    }

    /// Was der Flesch-Wert bedeutet.
    public enum Level: String, Hashable, Sendable, CaseIterable {
        case veryEasy
        case easy
        case medium
        case hard
        case veryHard

        public var title: String {
            switch self {
            case .veryEasy: localized("Sehr leicht")
            case .easy: localized("Leicht")
            case .medium: localized("Mittel")
            case .hard: localized("Schwer")
            case .veryHard: localized("Sehr schwer")
            }
        }

        public var audience: String {
            switch self {
            case .veryEasy: localized("Verstehen alle")
            case .easy: localized("Zeitung, Erzählung")
            case .medium: localized("Sachtext, Bericht")
            case .hard: localized("Fachtext, Studium")
            case .veryHard: localized("Wissenschaft, Verwaltung")
            }
        }

        public var tone: ReadabilityTone {
            switch self {
            case .veryEasy, .easy: .success
            case .medium: .accent
            case .hard: .warning
            case .veryHard: .danger
            }
        }
    }

    public var level: Level {
        switch flesch {
        case 80...: .veryEasy
        case 60..<80: .easy
        case 40..<60: .medium
        case 20..<40: .hard
        default: .veryHard
        }
    }

    // MARK: - Wo es schwer wird

    /// Ein Satz mit seinen Zahlen.
    public struct Sentence: Sendable, Identifiable {
        public let id: Int
        public let text: String
        public let words: Int
        public let syllables: Int

        /// Ab hier wird ein Satz zäh. Keine Regel, sondern eine Faustzahl aus
        /// der Redaktionspraxis — deshalb steht sie hier und nicht in einer
        /// Formel.
        public var isLong: Bool { words > 20 }
        public var isVeryLong: Bool { words > 30 }
    }

    /// Die Sätze, einzeln vermessen.
    ///
    /// Der eigentliche Nutzen des ganzen Werkzeugs: eine Zahl fürs Dokument
    /// sagt einem nicht, was man ändern soll — die drei längsten Sätze schon.
    public var measuredSentences: [Sentence] {
        sentences.enumerated().map { index, text in
            let words = Self.words(in: text)
            return Sentence(
                id: index,
                text: text,
                words: words.count,
                syllables: words.reduce(0) { $0 + Self.syllables(in: $1, language: language) }
            )
        }
    }

    /// Die längsten Sätze zuerst.
    public func longestSentences(_ limit: Int = 5) -> [Sentence] {
        measuredSentences.sorted { $0.words > $1.words }.prefix(limit).map { $0 }
    }

    /// Die längsten Wörter, ohne Wiederholungen.
    public func longestWords(_ limit: Int = 8) -> [String] {
        var seen: Set<String> = []
        return words
            .sorted { $0.count > $1.count }
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(limit)
            .map { $0 }
    }
}

/// Welche Farbe eine Einstufung bekommt.
///
/// Ein eigener Typ, damit die Rechnerei ohne das Design-System auskommt und in
/// einem Test ohne Fenster läuft.
public enum ReadabilityTone: String, Hashable, Sendable {
    case success
    case accent
    case warning
    case danger
}
