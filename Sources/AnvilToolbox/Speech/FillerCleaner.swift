import AnvilKit
import Foundation

/// Removes the noise of speaking from a transcript, without a model.
///
/// This runs before any AI pass and matters for two reasons. It works when no
/// model is available at all, and it is *predictable*: "äh" is always deleted,
/// nothing is ever reworded, and nothing can be invented. The model is then
/// left with the job it is actually good at — grammar and phrasing — on much
/// cleaner input.
public struct FillerCleaner: Sendable {
    /// How much to take out.
    public enum Strength: String, Codable, CaseIterable, Sendable, Identifiable {
        /// Only sounds that are never words: äh, ähm, uh, um.
        case gentle
        /// Also verbal tics: halt, quasi, sozusagen, you know, kind of.
        case thorough

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .gentle: localized("Nur Verzögerungslaute")
            case .thorough: localized("Auch Floskeln")
            }
        }

        public var explanation: String {
            switch self {
            case .gentle: localized("Entfernt „äh\", „ähm\", „hm\" und Wortdoppelungen.")
            case .thorough: localized("Entfernt zusätzlich Floskeln wie „halt\", „quasi\", „sozusagen\".")
            }
        }
    }

    public struct Result: Sendable, Equatable {
        public var text: String
        public var removedFillers: Int
        public var collapsedRepeats: Int

        public var changeCount: Int { removedFillers + collapsedRepeats }
        public var isUnchanged: Bool { changeCount == 0 }

        public init(text: String, removedFillers: Int = 0, collapsedRepeats: Int = 0) {
            self.text = text
            self.removedFillers = removedFillers
            self.collapsedRepeats = collapsedRepeats
        }
    }

    public var languageCode: String
    public var strength: Strength
    /// Collapse "das das" into "das". Off for text where doubling is meaningful.
    public var collapsesRepeats: Bool

    public init(languageCode: String = "de", strength: Strength = .gentle, collapsesRepeats: Bool = true) {
        self.languageCode = String(languageCode.prefix(2)).lowercased()
        self.strength = strength
        self.collapsesRepeats = collapsesRepeats
    }

    // MARK: - Cleaning

    public func clean(_ text: String) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result(text: "") }

        var removed = 0
        var collapsed = 0

        let paragraphs = trimmed.components(separatedBy: "\n").map { paragraph -> String in
            var tokens = paragraph.split(whereSeparator: \.isWhitespace).map(String.init)
            tokens = removePhrases(from: tokens, removed: &removed)
            tokens = removeWords(from: tokens, removed: &removed)
            if collapsesRepeats {
                tokens = collapseRepeats(in: tokens, collapsed: &collapsed)
            }
            return tokens.joined(separator: " ")
        }

        let joined = paragraphs.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")

        return Result(
            text: Self.normalisePunctuation(joined),
            removedFillers: removed,
            collapsedRepeats: collapsed
        )
    }

    // MARK: - Steps

    private func removeWords(from tokens: [String], removed: inout Int) -> [String] {
        let fillers = wordFillers
        var result: [String] = []

        for token in tokens {
            let core = Self.core(of: token)
            guard !core.isEmpty, fillers.contains(core) else {
                result.append(token)
                continue
            }

            removed += 1
            // "…, ähm, weiter" — the filler goes, its punctuation stays, so the
            // sentence does not silently lose a comma or a full stop.
            let trailing = Self.trailingPunctuation(of: token)
            if !trailing.isEmpty, var previous = result.popLast() {
                if Self.trailingPunctuation(of: previous).isEmpty {
                    previous += trailing
                }
                result.append(previous)
            }
        }

        return result
    }

    private func removePhrases(from tokens: [String], removed: inout Int) -> [String] {
        let phrases = phraseFillers
        guard !phrases.isEmpty else { return tokens }

        var result: [String] = []
        var index = 0

        while index < tokens.count {
            var matched = false

            for phrase in phrases where phrase.count <= tokens.count - index {
                let window = tokens[index..<(index + phrase.count)].map(Self.core(of:))
                if window == phrase {
                    removed += 1
                    index += phrase.count
                    matched = true
                    break
                }
            }

            if !matched {
                result.append(tokens[index])
                index += 1
            }
        }

        return result
    }

    private func collapseRepeats(in tokens: [String], collapsed: inout Int) -> [String] {
        var result: [String] = []

        for token in tokens {
            let core = Self.core(of: token)
            if let previous = result.last,
               !core.isEmpty,
               core.count > 1,
               Self.core(of: previous) == core,
               !intentionalDoubles.contains(core) {
                collapsed += 1
                // Keep whichever of the two carries the punctuation.
                if Self.trailingPunctuation(of: token).isEmpty == false {
                    result[result.count - 1] = token
                }
                continue
            }
            result.append(token)
        }

        return result
    }

    // MARK: - Word lists

    private var wordFillers: Set<String> {
        var fillers = Self.hardFillers[languageCode] ?? Self.hardFillers["en"] ?? []
        // Hesitation sounds are the same noise whatever the language, and
        // recognisers routinely spell them the other language's way.
        fillers.formUnion(Self.universalHardFillers)
        if strength == .thorough {
            fillers.formUnion(Self.softFillers[languageCode] ?? [])
        }
        return fillers
    }

    private var phraseFillers: [[String]] {
        guard strength == .thorough else { return [] }
        return (Self.softPhrases[languageCode] ?? []).map { $0.split(separator: " ").map(String.init) }
    }

    private var intentionalDoubles: Set<String> {
        Self.intentionalDoubles[languageCode] ?? []
    }

    /// A token reduced to comparable form: lowercased, no surrounding
    /// punctuation. `"Ähm,"` and `"ähm"` have to look the same here.
    static func core(of token: String) -> String {
        token
            .trimmingCharacters(in: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "äöüßÄÖÜ'’-")).inverted)
            .lowercased()
    }

    static func trailingPunctuation(of token: String) -> String {
        let punctuation = CharacterSet(charactersIn: ".,;:!?…")
        var result = ""
        for scalar in token.unicodeScalars.reversed() {
            guard punctuation.contains(scalar) else { break }
            result = String(scalar) + result
        }
        return result
    }

    // MARK: - Punctuation

    /// Fixes the spacing damage removing words leaves behind.
    static func normalisePunctuation(_ text: String) -> String {
        var result = text

        let replacements: [(String, String)] = [
            (" +", " "),          // runs of spaces
            (" +([,.;:!?…])", "$1"), // space before punctuation
            ("([,;:]){2,}", "$1"),   // doubled commas from deleted fillers
            ("([.!?])\\1{2,}", "$1"), // "..." stays, "....." does not
            ("^[,;:]\\s*", ""),      // a sentence starting with a comma
            ("\\s+$", "")
        ]

        for (pattern, template) in replacements {
            result = result.replacingOccurrences(
                of: pattern,
                with: template,
                options: [.regularExpression],
                range: nil
            )
        }

        return Self.capitaliseSentences(result.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Upper-cases the first letter of the text and of every sentence after a
    /// full stop — recognisers are inconsistent about this, and a dropped
    /// filler at the start of a sentence makes it worse.
    private static func capitaliseSentences(_ text: String) -> String {
        var result = ""
        var capitaliseNext = true

        for character in text {
            if capitaliseNext, character.isLetter {
                result.append(contentsOf: String(character).uppercased())
                capitaliseNext = false
            } else {
                result.append(character)
            }

            if character == "." || character == "!" || character == "?" || character == "\n" {
                capitaliseNext = true
            }
        }

        return result
    }

    // MARK: - Data

    private static let universalHardFillers: Set<String> = [
        "äh", "ähm", "ähh", "öh", "öhm", "hm", "hmm", "mhm", "mh",
        "uh", "uhm", "um", "umm", "erm", "eh", "ah", "er"
    ]

    private static let hardFillers: [String: Set<String>] = [
        "de": ["ähem", "hä", "tja", "nunja"],
        "en": ["uhh", "mmm", "hmmm"]
    ]

    private static let softFillers: [String: Set<String>] = [
        "de": [
            "halt", "quasi", "sozusagen", "irgendwie", "eben", "eigentlich",
            "praktisch", "gewissermaßen", "im-prinzip"
        ],
        "en": [
            "basically", "literally", "actually", "like", "anyway", "honestly"
        ]
    ]

    private static let softPhrases: [String: [String]] = [
        "de": ["weißt du", "ich mein", "ich meine", "sag ich mal", "und so weiter und so fort"],
        "en": ["you know", "i mean", "sort of", "kind of", "or something"]
    ]

    /// Words a speaker genuinely says twice for emphasis.
    private static let intentionalDoubles: [String: Set<String>] = [
        "de": ["sehr", "ganz", "nein", "ja", "immer", "nie"],
        "en": ["very", "no", "yes", "never", "really"]
    ]
}
