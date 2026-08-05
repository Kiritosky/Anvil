import SwiftUI

/// A small tinted capsule: model status, "on-device", "3 Fehler".
public struct StatusPill: View {
    private let text: LocalizedStringKey
    private let systemImage: String?
    private let tone: AnvilTone
    private let isProminent: Bool

    public init(
        _ text: LocalizedStringKey,
        systemImage: String? = nil,
        tone: AnvilTone = .neutral,
        isProminent: Bool = false
    ) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
        self.isProminent = isProminent
    }

    public var body: some View {
        HStack(spacing: AnvilSpacing.xxs + 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(AnvilFont.caption.weight(.medium))
        }
        .foregroundStyle(isProminent ? AnvilColor.textOnAccent : tone.color)
        .padding(.horizontal, AnvilSpacing.sm)
        .padding(.vertical, 3)
        .background {
            Capsule().fill(isProminent ? tone.color : tone.fill)
        }
        .fixedSize()
    }
}

/// A pulsing dot for "recording", "streaming", "listening".
public struct ActivityDot: View {
    private let tone: AnvilTone
    private let isActive: Bool
    @State private var isPulsing = false

    public init(tone: AnvilTone = .danger, isActive: Bool = true) {
        self.tone = tone
        self.isActive = isActive
    }

    public var body: some View {
        Circle()
            .fill(isActive ? tone.color : AnvilColor.textTertiary)
            .frame(width: 8, height: 8)
            .scaleEffect(isActive && isPulsing ? 1.35 : 1)
            .opacity(isActive && isPulsing ? 0.55 : 1)
            .onAppear {
                guard isActive else { return }
                withAnimation(AnvilMotion.pulse) { isPulsing = true }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    withAnimation(AnvilMotion.pulse) { isPulsing = true }
                } else {
                    withAnimation(AnvilMotion.quick) { isPulsing = false }
                }
            }
            .accessibilityHidden(true)
    }
}

/// A determinate or indeterminate progress strip used while a model streams
/// or an asset downloads.
public struct ProgressStrip: View {
    private let title: LocalizedStringKey
    private let progress: Double?
    private let tone: AnvilTone

    public init(_ title: LocalizedStringKey, progress: Double? = nil, tone: AnvilTone = .ai) {
        self.title = title
        self.progress = progress
        self.tone = tone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
            HStack(spacing: AnvilSpacing.xs) {
                Image(systemName: tone.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tone.color)
                Text(title)
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textSecondary)
                Spacer(minLength: 0)
                if let progress {
                    Text("\(Int(progress * 100)) %")
                        .font(AnvilFont.caption.monospacedDigit())
                        .foregroundStyle(AnvilColor.textTertiary)
                }
            }

            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(tone.color)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(tone.color)
            }
        }
    }
}
