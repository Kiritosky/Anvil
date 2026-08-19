import AnvilKit
import SwiftUI

/// Renders a word-level diff.
public struct DiffTextView: View {
    private let segments: [TextDiff.Segment]
    private let showsRemovals: Bool

    public init(from old: String, to new: String, showsRemovals: Bool = true) {
        self.segments = TextDiff.words(from: old, to: new)
        self.showsRemovals = showsRemovals
    }

    public init(segments: [TextDiff.Segment], showsRemovals: Bool = true) {
        self.segments = segments
        self.showsRemovals = showsRemovals
    }

    public var body: some View {
        ScrollView(.vertical) {
            Text(attributed)
                .font(AnvilFont.body)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AnvilSpacing.md)
                .padding(.vertical, AnvilSpacing.sm)
        }
    }

    private var attributed: AttributedString {
        var result = AttributedString()

        for segment in segments {
            if segment.kind == .removed, !showsRemovals { continue }

            var piece = AttributedString(segment.text + " ")
            switch segment.kind {
            case .unchanged:
                piece.foregroundColor = AnvilColor.textPrimary
            case .inserted:
                piece.foregroundColor = AnvilColor.success
                piece.backgroundColor = AnvilColor.success.opacity(0.14)
            case .removed:
                piece.foregroundColor = AnvilColor.danger
                piece.backgroundColor = AnvilColor.danger.opacity(0.12)
                piece.strikethroughStyle = .single
            }
            result.append(piece)
        }

        return result
    }
}

/// The legend that explains the diff colours, plus a change count.
public struct DiffLegend: View {
    private let segments: [TextDiff.Segment]

    public init(from old: String, to new: String) {
        self.segments = TextDiff.words(from: old, to: new)
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.md) {
            StatusPill(
                "\(wordCount(.removed)) entfernt",
                systemImage: "minus",
                tone: .danger
            )
            StatusPill(
                "\(wordCount(.inserted)) ergänzt",
                systemImage: "plus",
                tone: .success
            )
            StatusPill(
                "\(wordCount(.unchanged)) unverändert",
                systemImage: "equal",
                tone: .neutral
            )
        }
    }

    private func wordCount(_ kind: TextDiff.Segment.Kind) -> Int {
        segments
            .filter { $0.kind == kind }
            .reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
}
