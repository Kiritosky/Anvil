import Foundation

/// One finalised piece of transcript.
///
/// Timing is kept because it is what makes a transcript navigable later —
/// jumping to the spot in the recording where a sentence was said — and because
/// unusually long gaps between segments are a decent signal of where paragraph
/// breaks belong.
public struct TranscriptSegment: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var text: String
    /// Seconds from the start of the recording, when the engine reported them.
    public var start: TimeInterval?
    public var end: TimeInterval?

    public init(id: UUID = UUID(), text: String, start: TimeInterval? = nil, end: TimeInterval? = nil) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval? {
        guard let start, let end else { return nil }
        return max(0, end - start)
    }
}

/// A whole transcript: the finalised segments plus whatever the engine is
/// currently still revising.
public struct Transcript: Sendable, Codable {
    public var segments: [TranscriptSegment]
    /// The unstable tail the recogniser may still change. Shown greyed out.
    public var volatileText: String

    public init(segments: [TranscriptSegment] = [], volatileText: String = "") {
        self.segments = segments
        self.volatileText = volatileText
    }

    public var isEmpty: Bool { segments.isEmpty && volatileText.isEmpty }

    /// Everything that is settled, as one string.
    public var finalizedText: String {
        segments
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Settled text plus the volatile tail — what the live view shows.
    public var displayText: String {
        let tail = volatileText.trimmingCharacters(in: .whitespaces)
        guard !tail.isEmpty else { return finalizedText }
        return finalizedText.isEmpty ? tail : finalizedText + " " + tail
    }

    public var wordCount: Int {
        finalizedText.split(whereSeparator: \.isWhitespace).count
    }

    public mutating func append(_ segment: TranscriptSegment) {
        segments.append(segment)
    }

    public mutating func clear() {
        segments.removeAll()
        volatileText = ""
    }
}
