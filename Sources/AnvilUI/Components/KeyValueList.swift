import SwiftUI

/// A label/value pair, monospaced on the value side and selectable.
public struct KeyValueRow: View {
    private let key: String
    private let value: String
    private let tone: AnvilTone

    public init(_ key: String, _ value: String, tone: AnvilTone = .neutral) {
        self.key = key
        self.value = value
        self.tone = tone
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AnvilSpacing.md) {
            Text(key)
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.textTertiary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(AnvilFont.monoSmall)
                .foregroundStyle(tone == .neutral ? AnvilColor.textPrimary : tone.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A group of ``KeyValueRow``s with separators.
public struct KeyValueList: View {
    public struct Item: Identifiable, Hashable, Sendable {
        public let id = UUID()
        public let key: String
        public let value: String
        public let tone: AnvilTone

        public init(_ key: String, _ value: String, tone: AnvilTone = .neutral) {
            self.key = key
            self.value = value
            self.tone = tone
        }

        public static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.key == rhs.key && lhs.value == rhs.value && lhs.tone == rhs.tone
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(key)
            hasher.combine(value)
        }
    }

    private let items: [Item]

    public init(_ items: [Item]) {
        self.items = items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                KeyValueRow(item.key, item.value, tone: item.tone)
                    .padding(.vertical, AnvilSpacing.xs + 1)
                if index < items.count - 1 {
                    Divider().opacity(0.6)
                }
            }
        }
    }
}
