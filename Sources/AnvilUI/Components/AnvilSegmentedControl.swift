import SwiftUI

/// A row of mutually exclusive choices, drawn as a filled pill inside a track.
/// Used where a page has two or three faces — not for options, which belong in
/// the inspector.
public struct AnvilSegmentedControl<Value: Hashable>: View {
    public struct Segment: Identifiable {
        public let id: Value
        public let title: LocalizedStringKey
        public let systemImage: String?

        public init(_ value: Value, title: LocalizedStringKey, systemImage: String? = nil) {
            self.id = value
            self.title = title
            self.systemImage = systemImage
        }
    }

    @Binding private var selection: Value
    private let segments: [Segment]
    @Namespace private var pill

    public init(selection: Binding<Value>, segments: [Segment]) {
        self._selection = selection
        self.segments = segments
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.xxs) {
            ForEach(segments) { segment in
                Button {
                    selection = segment.id
                } label: {
                    HStack(spacing: AnvilSpacing.xs) {
                        if let systemImage = segment.systemImage {
                            Image(systemName: systemImage)
                                .font(AnvilFont.caption)
                        }
                        Text(segment.title)
                            .font(AnvilFont.rowTitle)
                    }
                    .foregroundStyle(
                        selection == segment.id ? AnvilColor.textOnAccent : AnvilColor.textSecondary
                    )
                    .padding(.horizontal, AnvilSpacing.md)
                    .frame(height: AnvilSize.controlHeight)
                    .background {
                        if selection == segment.id {
                            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                                .fill(AnvilColor.selectionStrong)
                                .matchedGeometryEffect(id: "anvil.segment", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AnvilSpacing.xxs)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .fill(AnvilColor.elevated)
        }
        .animation(AnvilMotion.springy, value: selection)
    }
}
