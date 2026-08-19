import Foundation

/// Subsequence matching with the usual quality-of-life bonuses.
public enum FuzzyMatch {
    /// Returns a score, or `nil` when `query` is not a subsequence of `text`.
    public static func score(query: String, in text: String) -> Int? {
        let needle = Array(query.lowercased().unicodeScalars.filter { $0 != " " })
        guard !needle.isEmpty else { return 0 }

        let haystack = Array(text.lowercased().unicodeScalars)
        let original = Array(text.unicodeScalars)
        guard haystack.count >= needle.count else { return nil }

        var score = 0
        var needleIndex = 0
        var previousMatch = -2
        var isWordStart = true

        for (position, scalar) in haystack.enumerated() {
            let boundary = isWordStart
            isWordStart = scalar == " " || scalar == "-" || scalar == "_" || scalar == "."
                || scalar == "/"

            guard needleIndex < needle.count, scalar == needle[needleIndex] else { continue }

            score += 10
            if position == previousMatch + 1 { score += 12 }
            if boundary { score += 15 }
            if position < original.count, CharacterSet.uppercaseLetters.contains(original[position]) {
                score += 5
            }
            if position == 0 { score += 10 }

            previousMatch = position
            needleIndex += 1
            if needleIndex == needle.count { break }
        }

        guard needleIndex == needle.count else { return nil }

        score -= max(0, (haystack.count - needle.count) / 8)
        return score
    }

    public static func matches(query: String, in text: String) -> Bool {
        score(query: query, in: text) != nil
    }
}
