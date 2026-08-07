import AnvilKit
import AnvilUI
import Foundation
import SwiftUI

/// Type a colour in any notation, get it back in all of them — and find out
/// whether text on it is readable.
///
/// The contrast half is the reason this tool exists. Converting hex to rgb is a
/// two-second job; noticing that your brand colour fails WCAG on white is not,
/// and it is the thing that comes back to bite.
public struct ColorToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var input = "#3A7BD5"
    @State private var partnerInput = "#FFFFFF"

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        }
        .onAppear(perform: restore)
        .onDisappear(perform: remember)
    }

    // MARK: - Zurückholen und merken

    private func restore() {
        guard let draft = context.drafts.draft(for: metadata.id) else { return }
        input = draft.input
        let partner = draft.extra("partner")
        if !partner.isEmpty { partnerInput = partner }
    }

    private func remember() {
        context.drafts.save(
            DraftStore.Draft(input: input, extras: ["partner": partnerInput]),
            for: metadata.id,
            allowed: context.settings[.remembersInput]
        )
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: AnvilSpacing.md) {
            inputRow

            if let color {
                notationsPane(for: color)
                contrastPane(for: color)
            } else {
                AnvilPane("Schreibweisen", systemImage: "paintpalette") {
                    EmptyStateView(
                        title: "Keine Farbe erkannt",
                        message: "Zum Beispiel #3A7BD5, rgb(58, 123, 213), hsl(214, 63%, 53%) oder „blau\".",
                        systemImage: "eyedropper",
                        tone: .warning
                    )
                }
            }

            statusBar
        }
    }

    private var inputRow: some View {
        HStack(spacing: AnvilSpacing.sm) {
            swatch(for: color, size: AnvilSize.headerHeight)

            AnvilTextField(text: $input, placeholder: "#3A7BD5", isMonospaced: true)

            Button { input = context.pasteboard.string() ?? input } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Einfügen")
        }
    }

    private func notationsPane(for color: ColorValue) -> some View {
        AnvilPane("Schreibweisen", systemImage: "paintpalette", contentInset: true) {
            VStack(spacing: AnvilSpacing.xs) {
                notationRow("Hex", color.hex)
                notationRow("Hex mit Alpha", color.hexWithAlpha)
                notationRow("RGB", color.rgbNotation)
                notationRow("HSL", color.hslNotation)
                notationRow("SwiftUI", color.swiftUINotation)
                notationRow("AppKit", color.nsColorNotation)
            }
        }
    }

    private func notationRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: AnvilSpacing.sm) {
            Text(label)
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.textTertiary)
                .frame(width: AnvilSize.listFieldWidth * 0.6, alignment: .leading)

            Text(verbatim: value)
                .font(AnvilFont.monoSmall)
                .foregroundStyle(AnvilColor.textPrimary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
            CopyButton(text: value)
        }
    }

    private func contrastPane(for color: ColorValue) -> some View {
        AnvilPane(
            "Kontrast",
            systemImage: "circle.lefthalf.filled",
            tone: rating.tone,
            contentInset: true
        ) {
            VStack(spacing: AnvilSpacing.md) {
                HStack(spacing: AnvilSpacing.sm) {
                    AnvilTextField(text: $partnerInput, placeholder: "#FFFFFF", isMonospaced: true)
                        .frame(width: AnvilSize.listFieldWidth)

                    AnvilButton("Weiß", role: .ghost) { partnerInput = "#FFFFFF" }
                    AnvilButton("Schwarz", role: .ghost) { partnerInput = "#000000" }

                    Spacer(minLength: 0)

                    // A ratio is a number, not text — no translation to make.
                    StatusPill(
                        .resolved("\(String(format: "%.2f", contrastRatio)):1"),
                        systemImage: rating.systemImage,
                        tone: rating.tone
                    )
                }

                sample(background: color, foreground: partner ?? color.readableForeground)

                Text(.resolved(ColorValue.rating(for: contrastRatio).explanation))
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sample(background: ColorValue, foreground: ColorValue) -> some View {
        Text("Der schnelle braune Fuchs springt über den faulen Hund.")
            .font(AnvilFont.body)
            .foregroundStyle(foreground.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AnvilSpacing.md)
            .background {
                RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                    .fill(background.color)
            }
    }

    private var statusBar: some View {
        ToolStatusBar {
            if let color {
                StatusMetric(color.hex, label: "Hex", systemImage: "number")
                StatusMetric(
                    "\(Int((color.relativeLuminance * 100).rounded()))%",
                    label: "Helligkeit",
                    systemImage: "sun.max"
                )
            }
        } trailing: {
            StatusPill(.resolved(rating.title), tone: rating.tone)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Abstufungen",
            systemImage: "square.stack.3d.up",
            footnote: "Anklicken übernimmt die Abstufung als Farbe."
        ) {
            if let color {
                FlowLayout(spacing: AnvilSpacing.xs, lineSpacing: AnvilSpacing.xs) {
                    ForEach(Array(steps(of: color).enumerated()), id: \.offset) { _, step in
                        Button { input = step.hex } label: {
                            swatch(for: step, size: AnvilSize.toolIcon)
                        }
                        .buttonStyle(.plain)
                        .anvilHelp(.resolved(step.hex))
                    }
                }
            }
        }

        InspectorSection(
            "Wird gelesen",
            systemImage: "text.magnifyingglass",
            footnote: "Hex mit und ohne Raute, rgb(), rgba(), hsl(), hsla() und gängige Farbnamen auf Deutsch und Englisch."
        ) {
            EmptyView()
        }
    }

    // MARK: - Pieces

    private func swatch(for color: ColorValue?, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
            .fill(color?.color ?? AnvilColor.field)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                    .strokeBorder(AnvilColor.border, lineWidth: 1)
            }
    }


    /// Nine steps from nearly black to nearly white, through the colour itself.
    private func steps(of color: ColorValue) -> [ColorValue] {
        let (hue, saturation, _) = color.hsl
        return stride(from: 0.1, through: 0.9, by: 0.1).map { lightness in
            ColorValue(hue: hue, saturation: saturation, lightness: lightness)
        }
    }

    // MARK: - Derived

    private var color: ColorValue? {
        ColorValue(parsing: input)
    }

    private var partner: ColorValue? {
        ColorValue(parsing: partnerInput)
    }

    private var contrastRatio: Double {
        guard let color else { return 1 }
        return color.contrast(with: partner ?? color.readableForeground)
    }

    private var rating: ColorValue.ContrastRating {
        ColorValue.rating(for: contrastRatio)
    }
}

extension ColorValue.ContrastRating {
    var tone: AnvilTone {
        switch self {
        case .failed: .danger
        case .largeTextOnly: .warning
        case .aa: .success
        case .aaa: .success
        }
    }

    var systemImage: String {
        switch self {
        case .failed: "xmark.circle"
        case .largeTextOnly: "exclamationmark.triangle"
        case .aa, .aaa: "checkmark.circle"
        }
    }
}
