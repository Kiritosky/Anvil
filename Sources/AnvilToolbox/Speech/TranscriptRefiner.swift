import AnvilAI
import AnvilKit
import Foundation

/// Runs a ``RefinementStyle`` over a transcript.
///
/// The interesting part is length. Dictation routinely produces more text than
/// the on-device model's context window holds, so anything long is split on
/// sentence boundaries, rewritten piece by piece and rejoined. Each piece is
/// streamed straight through to the caller, so the user watches the text appear
/// instead of staring at a spinner for a minute.
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
    ///
    /// - Parameters:
    ///   - onPartial: called with the cumulative text as it arrives.
    ///   - onProgress: called when a new chunk starts.
    public func refine(
        _ text: String,
        style: RefinementStyle,
        languageName: String,
        customInstruction: String = "",
        onProgress: (@MainActor (Progress) -> Void)? = nil,
        onPartial: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            throw AnvilError.invalidInput(localized("Es gibt noch keinen Text zum Aufräumen."))
        }

        let instructions = style.instructions(
            languageName: languageName,
            customInstruction: customInstruction
        )
        let options = AIOptions(temperature: style.temperature)

        let budget = max(1_000, await router.inputBudget() - Self.instructionAllowance)
        let chunks = TextChunker.split(source, budget: budget)
        guard !chunks.isEmpty else { return "" }

        var completed: [String] = []

        for chunk in chunks {
            try Task.checkCancellation()
            onProgress?(Progress(chunkIndex: chunk.id, chunkCount: chunks.count))

            let request = AIRequest(
                instructions: instructions,
                prompt: prompt(for: chunk, of: chunks.count, style: style),
                options: options
            )

            var latest = ""
            for try await snapshot in router.stream(request) {
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

    private func prompt(for chunk: TextChunker.Chunk, of total: Int, style: RefinementStyle) -> String {
        guard total > 1 else { return chunk.text }

        // Chunked runs need the model to know it is not seeing the whole thing,
        // or it writes an introduction for part 3 of 5 and a conclusion for
        // every single piece.
        return """
        Das ist Teil \(chunk.id + 1) von \(total) eines längeren Diktats. \
        Bearbeite nur diesen Teil. Schreibe weder Einleitung noch Fazit für das Gesamtdokument \
        und wiederhole nichts aus anderen Teilen.

        \(chunk.text)
        """
    }

    private func join(_ pieces: [String], style: RefinementStyle) -> String {
        let cleaned = pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Lists join line by line; prose gets a paragraph break between chunks.
        let separator = (style == .bullets || style == .actionItems) ? "\n" : "\n\n"
        return cleaned.joined(separator: separator)
    }

    /// Strips the wrapping models add despite being told not to.
    ///
    /// Small models in particular like to answer with a fenced code block or to
    /// repeat the request before the result. Cheap to undo, annoying to leave in.
    ///
    /// Explicitly `nonisolated`: it is a pure function over a string and has no
    /// business inheriting the class's main-actor isolation — which would stop
    /// tests from calling it without a hop.
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

        // A result wrapped in quotation marks, with none inside it, was quoted
        // by the model rather than by the speaker.
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
