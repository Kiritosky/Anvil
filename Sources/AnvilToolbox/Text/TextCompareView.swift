import AnvilKit
import AnvilUI
import SwiftUI

/// Compare two texts and see what actually changed.
///
/// Two inputs rather than one, which is why it is a view of its own rather than
/// a `TextTool`. The diff itself is the same word-level machinery the Speech
/// Studio uses to show what a cleanup pass touched.
public struct TextCompareView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var left = ""
    @State private var right = ""
    @State private var showsRemovals = true
    @State private var ignoresCase = false
    @State private var ignoresWhitespace = true
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
            AnvilButton("Tauschen", systemImage: "arrow.left.arrow.right", role: .secondary) {
                let previous = left
                left = right
                right = previous
            }
            .disabled(left.isEmpty && right.isEmpty)

            WorkbenchOrientationPicker(orientation: $orientation)
        }
        .anvilErrorBanner($dropError)
        .onAppear(perform: restore)
        .onDisappear(perform: remember)
    }

    // MARK: - Zurückholen und merken

    private func restore() {
        guard let draft = context.drafts.draft(for: metadata.id) else { return }
        left = draft.input
        right = draft.extra("right")
    }

    /// Beide Seiten werden geprüft, nicht nur die erste. Wer einen Schlüssel
    /// rechts einfügt, um zwei Fassungen zu vergleichen, hätte ihn sonst
    /// ungeprüft auf der Platte.
    private func remember() {
        context.drafts.save(
            DraftStore.Draft(input: left, extras: ["right": right]),
            for: metadata.id,
            allowed: context.settings[.remembersInput]
        )
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: AnvilSpacing.md) {
            // Hier trägt die Werkbank nur die beiden Eingaben; das Ergebnis
            // steht darunter über der ganzen Breite, weil ein Vergleich sonst
            // in einer halben Spalte landet.
            ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
                inputPane(
                    title: "Vorher",
                    systemImage: "doc",
                    text: $left,
                    placeholder: "Ursprünglicher Text …"
                )
            } secondary: {
                inputPane(
                    title: "Nachher",
                    systemImage: "doc.badge.gearshape",
                    text: $right,
                    placeholder: "Geänderter Text …"
                )
            }

            resultPane
                .frame(minHeight: AnvilSize.resultMinHeight)

            statusBar
        }
    }

    private func inputPane(
        title: LocalizedStringKey,
        systemImage: String,
        text: Binding<String>,
        placeholder: LocalizedStringKey
    ) -> some View {
        AnvilPane(title, systemImage: systemImage) {
            AnvilTextEditor(text: text, placeholder: placeholder, isMonospaced: true)
        } accessory: {
            Button { text.wrappedValue = context.pasteboard.string() ?? text.wrappedValue } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Einfügen")

            Button { text.wrappedValue = "" } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Leeren")
            .disabled(text.wrappedValue.isEmpty)
        }
        // Pro Bereich statt für das ganze Werkzeug: bei einem Vergleich ist die
        // Seite, auf der man loslässt, die Antwort auf „welche der beiden?".
        .anvilFileDrop(.text, error: $dropError) { dropped in
            guard case let .text(loaded, _) = dropped else { return }
            text.wrappedValue = loaded
        }
    }

    private var resultPane: some View {
        AnvilPane("Unterschiede", systemImage: "plusminus", tone: hasContent ? .accent : .neutral) {
            if !hasContent {
                EmptyStateView(
                    title: "Noch nichts zu vergleichen",
                    message: "Oben zwei Fassungen einfügen — der Vergleich läuft mit.",
                    systemImage: "plusminus"
                )
            } else if segments.allSatisfy({ $0.kind == .unchanged }) {
                EmptyStateView(
                    title: "Kein Unterschied",
                    message: "Beide Fassungen sind Wort für Wort gleich.",
                    systemImage: "equal.circle",
                    tone: .success
                )
            } else {
                DiffTextView(segments: segments, showsRemovals: showsRemovals)
            }
        } accessory: {
            CopyButton(text: right)
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(wordCount(.removed))", label: "entfernt", systemImage: "minus", tone: .danger)
            StatusMetric("\(wordCount(.inserted))", label: "ergänzt", systemImage: "plus", tone: .success)
            StatusMetric("\(wordCount(.unchanged))", label: "unverändert", systemImage: "equal")
        } trailing: {
            if hasContent {
                StatusMetric(
                    "\(Int(similarity * 100)) %",
                    label: "Übereinstimmung",
                    systemImage: "percent",
                    tone: similarity > 0.8 ? .success : .warning
                )
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection("Anzeige", systemImage: "eye") {
            Toggle("Entferntes zeigen", isOn: $showsRemovals)
                .font(AnvilFont.body)
        }

        InspectorSection(
            "Vergleich",
            systemImage: "slider.horizontal.3",
            footnote: "Verglichen wird Wort für Wort, nicht Zeile für Zeile — bei umformuliertem Text ist das deutlich lesbarer."
        ) {
            Toggle("Groß-/Kleinschreibung egal", isOn: $ignoresCase)
                .font(AnvilFont.body)
            Toggle("Mehrfache Leerzeichen ignorieren", isOn: $ignoresWhitespace)
                .font(AnvilFont.body)
        }
    }

    // MARK: - Diff

    private var hasContent: Bool {
        !left.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !right.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var segments: [TextDiff.Segment] {
        TextDiff.words(from: normalise(left), to: normalise(right))
    }

    private var similarity: Double {
        TextDiff.similarity(from: normalise(left), to: normalise(right))
    }

    private func normalise(_ text: String) -> String {
        var result = text
        if ignoresCase { result = result.lowercased() }
        if ignoresWhitespace {
            result = result.replacingOccurrences(
                of: " +",
                with: " ",
                options: .regularExpression
            )
        }
        return result
    }

    private func wordCount(_ kind: TextDiff.Segment.Kind) -> Int {
        segments
            .filter { $0.kind == kind }
            .reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
}
