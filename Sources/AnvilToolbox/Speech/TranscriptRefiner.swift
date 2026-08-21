import AnvilAI
import AnvilKit
import Foundation

/// Runs a ``RefinementStyle`` over a transcript.
@MainActor
public final class TranscriptRefiner {
    /// Room reserved for the instructions inside the model's input budget.
    private static let instructionAllowance = 1_200

    private let router: AIRouter

    public init(router: AIRouter) {
        self.router = router
    }

    public struct Progress: Sendable, Equatable {
        public var chunkIndex: Int
        public var chunkCount: Int

        public var fraction: Double {
            chunkCount <= 1 ? 0 : Double(chunkIndex) / Double(chunkCount)
        }

        public var isChunked: Bool { chunkCount > 1 }
    }

    /// Refines `text` and returns the finished result.
    public func refine(
        _ text: String,
        style: RefinementStyle,
        languageName: String,
        customInstruction: String = "",
        vocabulary: [String] = [],
        target: AITarget = .standard,
        onProgress: (@MainActor (Progress) -> Void)? = nil,
        onPartial: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            throw AnvilError.invalidInput(localized("Es gibt noch keinen Text zum Aufräumen."))
        }

        let instructions = style.instructions(
            languageName: languageName,
            customInstruction: customInstruction,
            vocabulary: vocabulary
        )
        let options = AIOptions(temperature: style.temperature)

        let allowance = Self.instructionAllowance + vocabulary.reduce(0) { $0 + $1.count + 3 }
        let budget = max(1_000, await router.inputBudget() - allowance)
        let chunks = TextChunker.split(source, budget: budget)
        guard !chunks.isEmpty else { return "" }

        var completed: [String] = []

        for chunk in chunks {
            try Task.checkCancellation()
            onProgress?(Progress(chunkIndex: chunk.id, chunkCount: chunks.count))

            let request = AIRequest(
                instructions: instructions,
                prompt: Self.prompt(
                    for: chunk,
                    of: chunks.count,
                    previous: completed.last
                ),
                options: options
            )

            var latest = ""
            for try await snapshot in router.stream(request, target: target) {
                try Task.checkCancellation()
                latest = snapshot
                onPartial?(join(completed + [latest], style: style))
            }

            completed.append(Self.stripWrapping(latest))
        }

        onProgress?(Progress(chunkIndex: chunks.count, chunkCount: chunks.count))
        let result = join(completed, style: style)
        onPartial?(result)
        return result
    }

    // MARK: - Prompting

    /// Builds the prompt for one chunk.
    nonisolated static func prompt(
        for chunk: TextChunker.Chunk,
        of total: Int,
        previous: String?
    ) -> String {
        guard total > 1 else { return chunk.text }

        var prompt = """
        Das ist Teil \(chunk.id + 1) von \(total) eines längeren Diktats. \
        Bearbeite nur diesen Teil. Schreibe weder Einleitung noch Fazit für das Gesamtdokument \
        und wiederhole nichts aus anderen Teilen.
        """

        let tail = previous.map { Self.tail(of: $0) } ?? ""
        if !tail.isEmpty {
            prompt += """

            Der vorherige Teil endete so — nur zur Orientierung, nicht wiederholen \
            und nicht mit ausgeben:
            \(tail)
            """
        }

        return prompt + "\n\n" + chunk.text
    }

    /// The last sentence or two of the previous chunk.
    nonisolated static func tail(of text: String, limit: Int = 240) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }

        let excerpt = String(trimmed.suffix(limit))
        if let boundary = excerpt.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }),
           excerpt.index(after: boundary) < excerpt.endIndex {
            return String(excerpt[excerpt.index(after: boundary)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return excerpt
    }

    private func join(_ pieces: [String], style: RefinementStyle) -> String {
        let cleaned = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let separator = (style == .bullets || style == .actionItems) ? "\n" : "\n\n"
        return cleaned.joined(separator: separator)
    }

    /// Strips the wrapping models add despite being told not to.
    nonisolated static func stripWrapping(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if result.hasPrefix("```") {
            var lines = result.components(separatedBy: .newlines)
            lines.removeFirst()
            if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                lines.removeLast()
            }
            result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let quotePairs: [(Character, Character)] = [("\"", "\""), ("„", "“"), ("»", "«")]
        for (open, close) in quotePairs where result.count > 2 {
            if result.first == open, result.last == close {
                let inner = result.dropFirst().dropLast()
                if !inner.contains(open), !inner.contains(close) {
                    result = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        return result
    }
}
