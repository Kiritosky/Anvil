import AnvilKit
import Foundation

/// Puts the user's own words back into a transcript, without a model.
///
/// Speech recognition has never heard of your product, your colleagues or your
/// API. It writes "Anwil", "Swift UI", "tool registrierung" — and a language
/// model asked to fix that will just as happily invent a fourth spelling. So
/// the word list is enforced here, deterministically, before the model ever
/// sees the text: a term on the list either appears exactly as written or not
/// at all.
///
/// Three passes, in decreasing confidence:
/// 1. an explicit variant from the list,
/// 2. the same letters with different case or spacing ("swift ui" → "SwiftUI"),
/// 3. a close-enough match by edit distance, gated by ``Sensitivity``.
public struct VocabularyCorrector: Sendable {
    /// How far from the written term a word may be and still be corrected.
    public enum Sensitivity: String, Codable, CaseIterable, Sendable, Identifiable {
        /// Only what is certain: listed variants, case and spacing.
        case exact
        /// Plus small misrecognitions, with a length guard against false hits.
        case balanced
        /// Plus shorter words and bigger distances. Corrects more, guesses more.
        case thorough

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .exact: localized("Nur exakte Treffer")
            case .balanced: localized("Ausgewogen")
            case .thorough: localized("Großzügig")
            }
        }

        public var explanation: String {
            switch self {
            case .exact:
                localized("Ersetzt nur eingetragene Schreibweisen sowie Groß- und Kleinschreibung.")
            case .balanced:
                localized("Erkennt zusätzlich leichte Verhörer bei Begriffen ab fünf Zeichen.")
            case .thorough:
                localized("Erkennt auch kurze Begriffe und stärkere Abweichungen — mit mehr Fehlgriffen.")
            }
        }

        /// Shortest term that may be matched by edit distance at all. Below
        /// this every second word of ordinary German is a "near miss".
        var minimumFuzzyLength: Int {
            switch self {
            case .exact: Int.max
            case .balanced: 5
            case .thorough: 4
            }
        }

        /// Allowed edit distance for a term of `length` characters.
        func maximumDistance(forLength length: Int) -> Int {
            switch self {
            case .exact:
                return 0
            case .balanced:
                return length >= 9 ? 2 : 1
            case .thorough:
                if length < 6 { return 1 }
                return length < 10 ? 2 : 3
            }
        }

        /// Require the first letter to survive. Recognisers get vowels and
        /// endings wrong far more often than the initial sound, and without
        /// this "Server" happily becomes "Nerver".
        var requiresMatchingInitial: Bool {
            switch self {
            case .exact, .balanced: true
            case .thorough: false
            }
        }
    }

    /// Why a word was replaced. Shown in the vocabulary tool's test field so a
    /// surprising correction can be traced to its rule.
    public enum Kind: String, Sendable, Codable {
        /// An explicitly listed misrecognition.
        case variant
        /// Same letters, other case or spacing.
        case spelling
        /// Close enough by edit distance.
        case fuzzy
    }

    public struct Correction: Sendable, Equatable, Identifiable {
        public var id: Int
        /// What the recogniser wrote.
        public var original: String
        /// What it says now.
        public var replacement: String
        public var kind: Kind

        public init(id: Int, original: String, replacement: String, kind: Kind) {
            self.id = id
            self.original = original
            self.replacement = replacement
            self.kind = kind
        }
    }

    public struct Result: Sendable, Equatable {
        public var text: String
        public var corrections: [Correction]

        public var count: Int { corrections.count }
        public var isUnchanged: Bool { corrections.isEmpty }

        public init(text: String, corrections: [Correction] = []) {
            self.text = text
            self.corrections = corrections
        }
    }

    private let candidates: [Candidate]
    private let sensitivity: Sensitivity
    private let maximumWindow: Int

    public init(entries: [VocabularyEntry], sensitivity: Sensitivity = .balanced) {
        let candidates = Self.candidates(from: entries)
        self.sensitivity = sensitivity
        self.candidates = candidates
        // Long enough for the listed phrases, and always at least three words
        // so a run-together term like "SwiftUI" can be reassembled from
        // "Swift U I".
        let longest = candidates.map(\.wordCount).max() ?? 1
        self.maximumWindow = min(6, max(3, longest))
    }

    // MARK: - Correcting

    public func correct(_ text: String) -> Result {
        guard !candidates.isEmpty, !text.isEmpty else { return Result(text: text) }

        let tokens = Self.tokenize(text)
        var output = ""
        var corrections: [Correction] = []
        var index = 0

        while index < tokens.count {
            guard case .word(let word) = tokens[index] else {
                if case .space(let space) = tokens[index] { output += space }
                index += 1
                continue
            }

            if let match = match(startingAt: index, in: tokens) {
                let last = match.tokenIndices[match.tokenIndices.count - 1]
                let original = tokens[index...last].map(\.text).joined()
                output += word.leading + match.candidate.term + (tokens[last].word?.trailing ?? "")
                corrections.append(
                    Correction(
                        id: corrections.count,
                        original: original,
                        replacement: match.candidate.term,
                        kind: match.kind
                    )
                )
                index = last + 1
                continue
            }

            output += word.text
            index += 1
        }

        return Result(text: output, corrections: corrections)
    }

    /// Convenience for callers that only want the text.
    public func corrected(_ text: String) -> String {
        correct(text).text
    }

    // MARK: - Matching

    private struct Match {
        var candidate: Candidate
        var tokenIndices: [Int]
        var kind: Kind
    }

    private func match(startingAt start: Int, in tokens: [Token]) -> Match? {
        var windows: [[Int]] = []
        for size in 1...maximumWindow {
            guard let window = Self.window(ofSize: size, startingAt: start, in: tokens) else { break }
            windows.append(window)
        }
        guard !windows.isEmpty else { return nil }

        // Longest window first: a listed phrase beats one of its own words.
        for window in windows.reversed() {
            let phrase = Phrase(tokens: window.map { tokens[$0] })
            if let match = strictMatch(for: phrase, window: window) { return match }
        }

        guard sensitivity != .exact else { return nil }

        for window in windows.reversed() {
            let phrase = Phrase(tokens: window.map { tokens[$0] })
            if let match = fuzzyMatch(for: phrase, window: window) { return match }
        }

        return nil
    }

    private func strictMatch(for phrase: Phrase, window: [Int]) -> Match? {
        for candidate in candidates {
            let matches = candidate.normalized == phrase.normalized
                || candidate.compact == phrase.compact
            guard matches else { continue }
            // Already written correctly — nothing to report.
            guard phrase.raw != candidate.term else { return nil }
            return Match(
                candidate: candidate,
                tokenIndices: window,
                kind: candidate.isVariant ? .variant : .spelling
            )
        }
        return nil
    }

    private func fuzzyMatch(for phrase: Phrase, window: [Int]) -> Match? {
        let subject = Array(phrase.compact)
        guard subject.count >= sensitivity.minimumFuzzyLength else { return nil }

        var best: (candidate: Candidate, distance: Int)?

        for candidate in candidates {
            let target = candidate.compactCharacters
            guard target.count >= sensitivity.minimumFuzzyLength else { continue }

            let limit = sensitivity.maximumDistance(forLength: target.count)
            guard limit > 0, abs(target.count - subject.count) <= limit else { continue }
            if sensitivity.requiresMatchingInitial, target.first != subject.first { continue }

            let distance = Self.distance(subject, target, limit: limit)
            guard distance <= limit, distance > 0 else { continue }
            if let current = best, current.distance <= distance { continue }
            best = (candidate, distance)
        }

        guard let best else { return nil }
        return Match(candidate: best.candidate, tokenIndices: window, kind: .fuzzy)
    }

    // MARK: - Candidates

    private struct Candidate {
        var term: String
        var normalized: String
        var compact: String
        var compactCharacters: [Character]
        var wordCount: Int
        var isVariant: Bool
    }

    private static func candidates(from entries: [VocabularyEntry]) -> [Candidate] {
        var result: [Candidate] = []
        var seen: Set<String> = []

        for entry in entries {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }

            for (offset, source) in ([term] + entry.variants).enumerated() {
                let cleaned = source.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { continue }

                let normalized = normalize(cleaned)
                guard !normalized.isEmpty else { continue }

                let compact = normalized.replacingOccurrences(of: " ", with: "")
                // The same written form must not resolve to two terms.
                guard seen.insert(normalized).inserted else { continue }

                result.append(
                    Candidate(
                        term: term,
                        normalized: normalized,
                        compact: compact,
                        compactCharacters: Array(compact),
                        wordCount: normalized.split(separator: " ").count,
                        isVariant: offset > 0
                    )
                )
            }
        }

        // Longer forms first, so "Swift Concurrency" is tried before "Swift".
        return result.sorted { $0.compact.count > $1.compact.count }
    }

    /// Comparable form: case- and accent-folded, stripped of everything that is
    /// not a letter or digit. `"Tool-Registration."` and `"tool registration"`
    /// have to look alike here; the spaces stay so word counts survive.
    static func normalize(_ text: String) -> String {
        // ß first and explicitly: Foundation's folding leaves it alone on some
        // paths, and "Straße" has to compare equal to "Strasse" — recognisers
        // pick between the two by mood.
        let folded = text
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ẞ", with: "ss")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: nil
            )

        var result = ""
        var pendingSpace = false

        for character in folded {
            if character.isWhitespace {
                pendingSpace = !result.isEmpty
                continue
            }
            guard character.isLetter || character.isNumber else { continue }
            if pendingSpace {
                result.append(" ")
                pendingSpace = false
            }
            result.append(character)
        }

        return result
    }

    // MARK: - Tokens

    enum Token {
        case space(String)
        case word(Word)

        var text: String {
            switch self {
            case .space(let value): value
            case .word(let word): word.text
            }
        }

        var word: Word? {
            if case .word(let word) = self { word } else { nil }
        }
    }

    /// A word with its punctuation kept apart, so a replacement can slot into
    /// the sentence without swallowing the comma behind it.
    struct Word {
        var leading: String
        var core: String
        var trailing: String

        var text: String { leading + core + trailing }
    }

    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        var isSpace: Bool?

        func flush() {
            guard !buffer.isEmpty, let isSpace else { return }
            if isSpace {
                tokens.append(.space(buffer))
            } else {
                tokens.append(.word(word(from: buffer)))
            }
            buffer = ""
        }

        for character in text {
            let whitespace = character.isWhitespace
            if whitespace != isSpace {
                flush()
                isSpace = whitespace
            }
            buffer.append(character)
        }
        flush()

        return tokens
    }

    private static func word(from raw: String) -> Word {
        let isCore: (Character) -> Bool = { $0.isLetter || $0.isNumber }

        var leading = ""
        var trailing = ""
        var core = Substring(raw)

        while let first = core.first, !isCore(first) {
            leading.append(first)
            core = core.dropFirst()
        }
        while let last = core.last, !isCore(last) {
            trailing = String(last) + trailing
            core = core.dropLast()
        }

        return Word(leading: leading, core: String(core), trailing: trailing)
    }

    /// The token indices of `size` consecutive words, or `nil` when the run is
    /// broken by a line break or the end of the text. Corrections never reach
    /// across lines — a term is not split over two paragraphs.
    private static func window(ofSize size: Int, startingAt start: Int, in tokens: [Token]) -> [Int]? {
        guard case .word = tokens[start] else { return nil }
        var indices = [start]
        var index = start

        while indices.count < size {
            guard index + 2 < tokens.count,
                  case .space(let space) = tokens[index + 1],
                  !space.contains(where: \.isNewline),
                  case .word = tokens[index + 2]
            else { return nil }
            index += 2
            indices.append(index)
        }

        return indices
    }

    /// A window of words, prepared for comparison once instead of per candidate.
    private struct Phrase {
        var raw: String
        var normalized: String
        var compact: String

        init(tokens: [Token]) {
            var cores: [String] = []
            for case .word(let word) in tokens {
                cores.append(word.core)
            }
            raw = cores.joined(separator: " ")
            normalized = VocabularyCorrector.normalize(raw)
            compact = normalized.replacingOccurrences(of: " ", with: "")
        }
    }

    // MARK: - Edit distance

    /// Levenshtein distance, abandoned as soon as it cannot stay within
    /// `limit`. The early exit matters: this runs over every word of a
    /// transcript against every term of the list.
    static func distance(_ lhs: [Character], _ rhs: [Character], limit: Int) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        if abs(lhs.count - rhs.count) > limit { return limit + 1 }

        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for i in 1...lhs.count {
            current[0] = i
            var rowMinimum = i

            for j in 1...rhs.count {
                let substitution = previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1)
                current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1)
                rowMinimum = min(rowMinimum, current[j])
            }

            if rowMinimum > limit { return limit + 1 }
            swap(&previous, &current)
        }

        return previous[rhs.count]
    }
}
