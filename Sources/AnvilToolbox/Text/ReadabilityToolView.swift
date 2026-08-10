import AnvilKit
import AnvilUI
import SwiftUI

/// Wie schwer ein Text zu lesen ist — und an welchen Sätzen es liegt.
public struct ReadabilityToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var input = ""
    @State private var language: Readability.Language = .german
    /// Einmal gemessen statt bei jedem Zugriff: Silben zählen heißt, jedes
    /// Wort Zeichen für Zeichen durchzugehen.
    @State private var reading = Readability("")
    @State private var dropError: AnvilError?
    @State private var orientation: WorkbenchOrientation = .horizontal

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            WorkbenchOrientationPicker(orientation: $orientation)
        }
        .anvilErrorBanner($dropError)
        .anvilFileDrop(.text, error: $dropError) { dropped in
            guard case let .text(text, _) = dropped else { return }
            input = text
        }
        .onAppear {
            restore()
            measure()
        }
        .onDisappear(perform: remember)
        .onChange(of: input) { measure() }
        .onChange(of: language) { measure() }
    }

    private func measure() {
        reading = Readability(input, language: language)
    }

    private func restore() {
        if let handed = context.handoff.take(for: metadata.id) {
            input = handed
            return
        }
        guard let draft = context.drafts.draft(for: metadata.id) else { return }
        input = draft.input
    }

    private func remember() {
        context.drafts.save(
            DraftStore.Draft(input: input),
            for: metadata.id,
            allowed: context.settings[.remembersInput]
        )
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            inputPane
        } secondary: {
            resultPane
        } status: {
            statusBar
        }
    }

    private var inputPane: some View {
        AnvilPane("Text", systemImage: "text.alignleft") {
            AnvilTextEditor(
                text: $input,
                placeholder: "Text einfügen — oder eine Datei ins Fenster ziehen."
            )
        } accessory: {
            Button { input = context.pasteboard.string() ?? input } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Einfügen")
        }
    }

    @ViewBuilder
    private var resultPane: some View {
        AnvilPane("Lesbarkeit", systemImage: "gauge.medium", tone: .neutral) {
            if reading.wordCount == 0 {
                EmptyStateView(
                    title: "Noch kein Text",
                    message: "Lesbarkeit misst Satz- und Wortlängen. Ab etwa hundert Wörtern wird die Zahl belastbar.",
                    systemImage: "gauge.medium"
                )
            } else {
                scoreAndSentences
            }
        } accessory: {
            HStack(spacing: AnvilSpacing.xs) {
                HandoffMenu(context: context, from: metadata.id, text: report)
                CopyButton(text: report)
            }
        }
    }

    private var scoreAndSentences: some View {
        let longest = reading.longestSentences()

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: AnvilSpacing.lg) {
                score(reading)

                if reading.wordCount < 100 {
                    AnvilBanner(
                        title: "Für eine belastbare Zahl noch zu kurz",
                        message: "Unter hundert Wörtern schlägt jeder einzelne lange Satz voll durch.",
                        tone: .info
                    )
                }

                AnvilSection("Die längsten Sätze", subtitle: "Hier fängt man beim Kürzen an") {
                    VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
                        ForEach(longest) { sentence in
                            sentenceRow(sentence)
                        }
                    }
                }

                AnvilSection("Die längsten Wörter") {
                    FlowLayout(spacing: AnvilSpacing.xs, lineSpacing: AnvilSpacing.xs) {
                        ForEach(reading.longestWords(), id: \.self) { word in
                            StatusPill(.resolved(word), tone: .neutral)
                        }
                    }
                }
            }
            .padding(AnvilSpacing.md)
        }
    }

    private func score(_ reading: Readability) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AnvilSpacing.lg) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: String(Int(reading.flesch.rounded())))
                    .font(AnvilFont.display.monospacedDigit())
                    .foregroundStyle(reading.level.tone.uiTone.color)
                Text("von 100")
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
            }

            VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                StatusPill(
                    .resolved(reading.level.title),
                    tone: reading.level.tone.uiTone,
                    isProminent: true
                )
                Text(.resolved(reading.level.audience))
                    .font(AnvilFont.body)
                    .foregroundStyle(AnvilColor.textSecondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func sentenceRow(_ sentence: Readability.Sentence) -> some View {
        HStack(alignment: .top, spacing: AnvilSpacing.sm) {
            StatusPill(
                .resolved("\(sentence.words)"),
                tone: sentence.isVeryLong ? .danger : (sentence.isLong ? .warning : .neutral)
            )
            Text(verbatim: sentence.text)
                .font(AnvilFont.body)
                .foregroundStyle(AnvilColor.textPrimary)
                .lineLimit(3)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(AnvilSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .fill(AnvilColor.surface)
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(reading.wordCount)", label: "Wörter", systemImage: "text.word.spacing")
            StatusMetric("\(reading.sentenceCount)", label: "Sätze", systemImage: "text.justify")
            StatusMetric(
                Self.decimal(reading.averageSentenceLength),
                label: "Wörter je Satz",
                systemImage: "ruler"
            )
            StatusMetric("\(reading.readingMinutes)", label: "Min. Lesezeit", systemImage: "clock")
        } trailing: {
            StatusPill(.resolved(reading.level.title), tone: reading.level.tone.uiTone)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Sprache",
            systemImage: "character.book.closed",
            footnote: "Deutsch rechnet nach Amstad, Englisch nach Flesch. Dieselbe Formel für beide gäbe für jeden deutschen Text zu schlechte Werte."
        ) {
            ChipPicker(
                selection: $language,
                options: Readability.Language.allCases,
                title: { $0.title }
            )
        }

        InspectorSection("Zahlen", systemImage: "chart.bar") {
            KeyValueList([
                KeyValueList.Item(localized("Flesch"), Self.decimal(reading.flesch)),
                KeyValueList.Item(localized("Schuljahre"), Self.decimal(reading.gradeLevel)),
                KeyValueList.Item(localized("Wörter je Satz"), Self.decimal(reading.averageSentenceLength)),
                KeyValueList.Item(localized("Silben je Wort"), Self.decimal(reading.averageSyllablesPerWord)),
                KeyValueList.Item(localized("Lange Wörter"), Self.percent(reading.longWordShare)),
                KeyValueList.Item(localized("Silben"), "\(reading.syllables)")
            ])
        }

        InspectorSection(
            "Was die Zahl kann",
            systemImage: "info.circle",
            footnote: "Gemessen werden Satz- und Wortlängen, sonst nichts. Ein Text aus lauter kurzen Sätzen kann unverständlich sein und trotzdem gut abschneiden — der Wert taugt zum Vergleichen zweier Fassungen, nicht als Urteil."
        ) {
            KeyValueList([
                KeyValueList.Item("80–100", localized("Sehr leicht")),
                KeyValueList.Item("60–80", localized("Leicht")),
                KeyValueList.Item("40–60", localized("Mittel")),
                KeyValueList.Item("20–40", localized("Schwer")),
                KeyValueList.Item("0–20", localized("Sehr schwer"))
            ])
        }
    }

    // MARK: - Kleinkram

    private var report: String {
        let rows = [
            (localized("Flesch"), Self.decimal(reading.flesch)),
            (localized("Einstufung"), reading.level.title),
            (localized("Wörter"), "\(reading.wordCount)"),
            (localized("Sätze"), "\(reading.sentenceCount)"),
            (localized("Wörter je Satz"), Self.decimal(reading.averageSentenceLength)),
            (localized("Silben je Wort"), Self.decimal(reading.averageSyllablesPerWord)),
            (localized("Lange Wörter"), Self.percent(reading.longWordShare)),
            (localized("Lesezeit"), "\(reading.readingMinutes)")
        ]
        return rows.map { "\($0.0)\t\($0.1)" }.joined(separator: "\n")
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f", value * 100) + " %"
    }
}

extension ReadabilityTone {
    /// Die Einstufung kennt das Design-System nicht — hier wird übersetzt.
    var uiTone: AnvilTone {
        switch self {
        case .success: .success
        case .accent: .accent
        case .warning: .warning
        case .danger: .danger
        }
    }
}
