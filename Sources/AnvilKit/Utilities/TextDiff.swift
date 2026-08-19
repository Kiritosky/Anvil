import Foundation

/// Word-level diffing, used to show what a cleanup pass actually changed.
public enum TextDiff {
    public struct Segment: Hashable, Sendable, Identifiable {
        public enum Kind: Hashable, Sendable {
            case unchanged
            case inserted
            case removed
        }

        public let id = UUID()
        public let kind: Kind
        public let text: String

        public init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }

        public static func == (lhs: Segment, rhs: Segment) -> Bool {
            lhs.kind == rhs.kind && lhs.text == rhs.text
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(kind)
            hasher.combine(text)
        }
    }

    /// Diffs `old` against `new` on word boundaries.
    public static func words(from old: String, to new: String) -> [Segment] {
        let oldWords = tokenize(old)
        let newWords = tokenize(new)

        guard !oldWords.isEmpty else {
            return newWords.isEmpty ? [] : [Segment(kind: .inserted, text: newWords.joined(separator: " "))]
        }
        guard !newWords.isEmpty else {
            return [Segment(kind: .removed, text: oldWords.joined(separator: " "))]
        }

        let difference = newWords.difference(from: oldWords)
        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removedOffsets.insert(offset)
            case let .insert(offset, _, _): insertedOffsets.insert(offset)
            }
        }

        var segments: [Segment] = []
        var oldIndex = 0
        var newIndex = 0

        while oldIndex < oldWords.count || newIndex < newWords.count {
            if oldIndex < oldWords.count, removedOffsets.contains(oldIndex) {
                segments.append(Segment(kind: .removed, text: oldWords[oldIndex]))
                oldIndex += 1
            } else if newIndex < newWords.count, insertedOffsets.contains(newIndex) {
                segments.append(Segment(kind: .inserted, text: newWords[newIndex]))
                newIndex += 1
            } else if oldIndex < oldWords.count, newIndex < newWords.count {
                segments.append(Segment(kind: .unchanged, text: oldWords[oldIndex]))
                oldIndex += 1
                newIndex += 1
            } else if oldIndex < oldWords.count {
                oldIndex += 1
            } else {
                newIndex += 1
            }
        }

        return coalesce(segments)
    }

    /// How much of `old` survived into `new`, as a fraction between 0 and 1.
    public static func similarity(from old: String, to new: String) -> Double {
        let segments = words(from: old, to: new)
        guard !segments.isEmpty else { return 1 }
        let total = segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
        guard total > 0 else { return 1 }
        let unchanged = segments
            .filter { $0.kind == .unchanged }
            .reduce(0) { $0 + $1.text.split(separator: " ").count }
        return Double(unchanged) / Double(total)
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func coalesce(_ segments: [Segment]) -> [Segment] {
        var result: [Segment] = []
        for segment in segments {
            if let last = result.last, last.kind == segment.kind {
                result[result.count - 1] = Segment(
                    kind: last.kind,
                    text: last.text + " " + segment.text
                )
            } else {
                result.append(segment)
            }
        }
        return result
    }
}
