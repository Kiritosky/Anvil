import AnvilKit
import AnvilUI
import SwiftUI

/// The contents of the dictation bubble: one row, read at a glance.
///
/// No transcript, no buttons beyond a way out. While talking you are looking at
/// the text field, not at this — so it answers exactly two questions: *is it
/// hearing me* (the meter moves) and *how long have I been going*.
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
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Verwerfen (⎋)")
            }
        }
        .padding(.horizontal, AnvilSpacing.md)
        .padding(.vertical, AnvilSpacing.sm)
        .frame(width: 300, height: 56)
        .background {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(AnvilColor.border, lineWidth: 1)
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
                .frame(width: 10, height: 10)
        case .delivered:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(AnvilColor.success)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
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
                .frame(height: 20)
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
