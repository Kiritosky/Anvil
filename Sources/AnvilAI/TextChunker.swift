import Foundation

/// Splits long text into pieces a model can actually accept.
///
/// The on-device model has a small context window, and a dictated transcript
/// happily runs past it. Splitting on paragraph and sentence boundaries — never
/// mid-sentence unless a single sentence is itself too long — keeps each chunk
/// independently rewritable, which is what makes chunk-and-rejoin produce
/// readable output instead of visible seams.
public enum TextChunker {
    public struct Chunk: Sendable, Identifiable {
        public let id: Int
        public let text: String

        public init(id: Int, text: String) {
            self.id = id
            self.text = text
        }
    }

    /// Splits `text` into chunks of at most `budget` characters.
    ///
    /// - Parameter budget: characters, not tokens. Callers pass a provider's
    ///   ``AIProvider/approximateInputBudget`` minus room for the instructions.
    public static func split(_ text: String, budget: Int) -> [Chunk] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard budget > 0, trimmed.count > budget else {
            return [Chunk(id: 0, text: trimmed)]
        }

        var chunks: [String] = []
        var current = ""

        for paragraph in paragraphs(of: trimmed) {
            if paragraph.count > budget {
                // Flush what we have, then break the oversized paragraph down.
                if !current.isEmpty { chunks.append(current); current = "" }
                for piece in splitSentences(paragraph, budget: budget) {
                    if current.count + piece.count + 1 > budget, !current.isEmpty {
                        chunks.append(current)
                        current = ""
                    }
                    current += current.isEmpty ? piece : " " + piece
                }
                continue
            }

            if current.count + paragraph.count + 2 > budget, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += current.isEmpty ? paragraph : "\n\n" + paragraph
        }

        if !current.isEmpty { chunks.append(current) }
        return chunks.enumerated().map { Chunk(id: $0.offset, text: $0.element) }
    }

    /// Whether `text` fits in one call to a provider with this budget.
    public static func fits(_ text: String, budget: Int) -> Bool {
        text.count <= budget
    }

    // MARK: - Boundaries

    private static func paragraphs(of text: String) -> [String] {
        text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitSentences(_ text: String, budget: Int) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.bySentences, .localized]
        ) { substring, _, _, _ in
            guard let substring else { return }
            let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { sentences.append(trimmed) }
        }

        if sentences.isEmpty { sentences = [text] }

        // A single sentence longer than the budget only happens with dictated
        // text that never got punctuated — fall back to hard word wrapping.
        return sentences.flatMap { sentence -> [String] in
            sentence.count <= budget ? [sentence] : wrapWords(sentence, budget: budget)
        }
    }

    private static func wrapWords(_ text: String, budget: Int) -> [String] {
        var pieces: [String] = []
        var current = ""

        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
            if current.count + word.count + 1 > budget, !current.isEmpty {
                pieces.append(current)
                current = ""
            }
            current += current.isEmpty ? String(word) : " " + word
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
