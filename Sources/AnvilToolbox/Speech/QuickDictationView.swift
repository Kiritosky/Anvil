import AnvilKit
import AnvilUI
import SwiftUI

/// What the floating dictation strip shows.
///
/// One line of state, one line of text, one line of hints. It is read at a
/// glance while talking, so there is nothing to click and nothing to decide.
struct QuickDictationView: View {
    @Bindable var controller: QuickDictationController

    var body: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
            header
            body(for: controller.phase)
            hints
        }
        .padding(AnvilSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.xl, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AnvilRadius.xl, style: .continuous)
                .strokeBorder(AnvilColor.border, lineWidth: 1)
        }
        .animation(AnvilMotion.standard, value: controller.phase)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: AnvilSpacing.sm) {
            ActivityDot(tone: tone, isActive: controller.phase == .recording)

            Text(title)
                .font(AnvilFont.body.weight(.semibold))
                .foregroundStyle(AnvilColor.textPrimary)

            Spacer(minLength: AnvilSpacing.sm)

            if controller.phase == .recording {
                Text(verbatim: timecode)
                    .font(AnvilFont.caption.monospacedDigit())
                    .foregroundStyle(AnvilColor.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func body(for phase: QuickDictationController.Phase) -> some View {
        switch phase {
        case .starting:
            ProgressStrip("Mikrofon wird geöffnet", tone: .accent)

        case .recording:
            VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
                LevelMeter(levels: controller.levels, tone: .danger, barCount: 60)
                    .frame(height: 28)

                Text(controller.transcript.isEmpty ? String(localized: "Sprich einfach los …") : controller.transcript)
                    .font(AnvilFont.body)
                    .foregroundStyle(
                        controller.transcript.isEmpty ? AnvilColor.textTertiary : AnvilColor.textPrimary
                    )
                    .lineLimit(2)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .refining:
            ProgressStrip("Wird aufgeräumt", tone: .ai)

        case let .delivered(text):
            Text(text)
                .font(AnvilFont.body)
                .foregroundStyle(AnvilColor.textPrimary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .failed(message):
            Text(.resolved(message))
                .font(AnvilFont.body)
                .foregroundStyle(AnvilColor.danger)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var hints: some View {
        if controller.phase == .recording {
            HStack(spacing: AnvilSpacing.md) {
                hint("⏎", "fertig")
                hint("⎋", "verwerfen")
                if let shortcut = controller.registeredShortcut {
                    hint(shortcut.displayString, "fertig")
                }
            }
        }
    }

    private func hint(_ key: String, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: AnvilSpacing.xxs + 2) {
            Text(verbatim: key)
                .font(AnvilFont.caption.monospaced())
                .padding(.horizontal, AnvilSpacing.xs)
                .padding(.vertical, 1)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AnvilColor.hover)
                }
            Text(label)
                .font(AnvilFont.caption)
        }
        .foregroundStyle(AnvilColor.textTertiary)
    }

    // MARK: - Presentation

    private var title: LocalizedStringKey {
        switch controller.phase {
        case .idle: ""
        case .starting: "Moment …"
        case .recording: "Ich höre zu"
        case .refining: "Räume auf"
        case .delivered: "In der Zwischenablage"
        case .failed: "Hat nicht geklappt"
        }
    }

    private var tone: AnvilTone {
        switch controller.phase {
        case .recording: .danger
        case .refining: .ai
        case .delivered: .success
        case .failed: .warning
        case .idle, .starting: .neutral
        }
    }

    private var timecode: String {
        let total = Int(controller.duration.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
