import SwiftUI

/// A scrolling bar meter driven by recent audio levels.
public struct LevelMeter: View {
    private let levels: [Float]
    private let isActive: Bool
    private let tone: AnvilTone
    private let barCount: Int

    public init(
        levels: [Float],
        isActive: Bool = true,
        tone: AnvilTone = .accent,
        barCount: Int = 48
    ) {
        self.levels = levels
        self.isActive = isActive
        self.tone = tone
        self.barCount = barCount
    }

    public var body: some View {
        GeometryReader { proxy in
            let padded = padded(to: barCount)
            let spacing = max(1.5, proxy.size.width / CGFloat(barCount) * 0.28)
            let barWidth = max(1.5, (proxy.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(padded.enumerated()), id: \.offset) { index, level in
                    Capsule()
                        .fill(color(for: level, index: index, total: padded.count))
                        .frame(
                            width: barWidth,
                            height: max(2, CGFloat(level) * proxy.size.height)
                        )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            .animation(AnvilMotion.quick, value: levels.count)
        }
        .frame(height: 44)
        .accessibilityLabel(isActive ? "Aufnahmepegel" : "Aufnahme pausiert")
    }

    /// Right-aligns the samples so new bars appear on the trailing edge.
    private func padded(to count: Int) -> [Float] {
        if levels.count >= count { return Array(levels.suffix(count)) }
        return Array(repeating: 0, count: count - levels.count) + levels
    }

    private func color(for level: Float, index: Int, total: Int) -> Color {
        guard isActive else { return AnvilColor.textTertiary.opacity(0.5) }
        let age = Double(index) / Double(max(1, total - 1))
        let base = level > 0.92 ? AnvilColor.warning : tone.color
        return base.opacity(0.35 + 0.65 * age)
    }
}
