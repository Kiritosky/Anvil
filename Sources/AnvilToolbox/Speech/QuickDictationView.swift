import AnvilKit
import AnvilUI
import SwiftUI

/// The contents of the dictation bubble: one row, read at a glance.
struct QuickDictationView: View {
    let controller: QuickDictationController

    var body: some View {
        HStack(spacing: AnvilSpacing.sm) {
            indicator

            Text(title)
                .font(AnvilFont.body.weight(.medium))
                .foregroundStyle(AnvilColor.textPrimary)
                .fixedSize()

            content

            if controller.phase == .recording {
                Text(verbatim: timecode)
                    .font(AnvilFont.caption.monospacedDigit())
                    .foregroundStyle(AnvilColor.textSecondary)

                Button {
                    Task { await controller.cancel() }
                } label: {
                    Image(systemName: "xmark")
                        .font(AnvilFont.micro)
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Verwerfen (⎋)")
            }
        }
        .padding(.horizontal, AnvilSpacing.md)
        .padding(.vertical, AnvilSpacing.sm)
        .frame(width: AnvilSize.bubbleWidth, height: AnvilSize.bubbleHeight)
        .background {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(AnvilColor.border, lineWidth: AnvilSize.hairline)
        }
        .animation(AnvilMotion.standard, value: controller.phase)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var indicator: some View {
        switch controller.phase {
        case .refining, .starting:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: AnvilSize.dot, height: AnvilSize.dot)
        case .delivered:
            Image(systemName: "checkmark.circle.fill")
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.warning)
        case .recording, .idle:
            ActivityDot(tone: .danger, isActive: controller.phase == .recording)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .recording:
            LevelMeter(levels: controller.levels, tone: .danger, barCount: 26)
                .frame(height: AnvilSize.meterHeight)
                .frame(maxWidth: .infinity)
        case let .failed(message):
            Text(.resolved(message))
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Spacer(minLength: 0)
        }
    }

    // MARK: - Presentation

    private var title: LocalizedStringKey {
        switch controller.phase {
        case .idle: ""
        case .starting: "Moment …"
        case .recording: "Ich höre zu"
        case .refining: "Räume auf"
        case let .delivered(didPaste): didPaste ? "Eingefügt" : "Kopiert"
        case .failed: "Ging nicht"
        }
    }

    private var timecode: String {
        let total = Int(controller.duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
