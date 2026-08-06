import AnvilKit
import AnvilUI
import Foundation
import SwiftUI

/// The editor for the words dictation keeps getting wrong.
///
/// Built around the test field on the right: a word list is guesswork until you
/// can paste a botched transcript in and watch what the rules actually do with
/// it. Every change to the list re-runs the test immediately.
public struct VocabularyToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var newTerm = ""
    @State private var testText = ""
    @State private var orientation: WorkbenchOrientation = .horizontal
    @FocusState private var isAddFieldFocused: Bool

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    private var store: VocabularyStore { context.vocabulary }
    private var settings: SettingsStore { context.settings }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            WorkbenchOrientationPicker(orientation: $orientation)
        }
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            listPane
        } secondary: {
            testColumn
        } status: {
            statusBar
        }
    }

    private var listPane: some View {
        AnvilPane("Begriffe", systemImage: "character.book.closed", contentInset: true) {
            VStack(spacing: AnvilSpacing.sm) {
                addRow

                if store.entries.isEmpty {
                    EmptyStateView(
                        title: "Noch keine Begriffe",
                        message: "Trag ein, was die Spracherkennung bei dir immer wieder falsch schreibt: Produktnamen, Namen von Leuten, Fachbegriffe, Code-Bezeichner.",
                        systemImage: "character.book.closed"
                    )
                } else {
                    entryList
                }
            }
        } accessory: {
            if !store.entries.isEmpty {
                Text(verbatim: "\(store.activeEntries.count)/\(store.entries.count)")
                    .font(AnvilFont.caption.monospacedDigit())
                    .foregroundStyle(AnvilColor.textTertiary)
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: AnvilSpacing.sm) {
            AnvilTextField(text: $newTerm, placeholder: "Neuer Begriff, z. B. SwiftUI")
                .focused($isAddFieldFocused)
                .onSubmit(addTerm)

            AnvilButton("Hinzufügen", systemImage: "plus", role: .primary, action: addTerm)
                .disabled(trimmedNewTerm.isEmpty)
        }
    }

    private var entryList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: AnvilSpacing.xs) {
                ForEach(store.entries) { entry in
                    entryRow(binding(for: entry))
                }
            }
            .padding(.vertical, AnvilSpacing.xxs)
        }
    }

    private func entryRow(_ entry: Binding<VocabularyEntry>) -> some View {
        HStack(spacing: AnvilSpacing.sm) {
            Toggle("", isOn: entry.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .anvilHelp("Begriff berücksichtigen")

            AnvilTextField(text: entry.term, placeholder: "Begriff")
                .frame(width: AnvilSize.listFieldWidth)

            AnvilTextField(text: variantsBinding(for: entry), placeholder: "Verhörer, mit Komma getrennt")

            Button { store.remove(entry.wrappedValue) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(AnvilIconButtonStyle(tone: .danger))
            .anvilHelp("Löschen")
        }
        .opacity(entry.wrappedValue.isEnabled ? 1 : 0.5)
        .padding(.horizontal, AnvilSpacing.xs)
        .padding(.vertical, AnvilSpacing.xxs)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .fill(AnvilColor.surface)
        }
    }

    // MARK: - Test

    private var testColumn: some View {
        VStack(spacing: AnvilSpacing.md) {
            AnvilPane("Probetext", systemImage: "text.cursor") {
                AnvilTextEditor(
                    text: $testText,
                    placeholder: "Ein Satz, wie die Spracherkennung ihn geschrieben hat …"
                )
            } accessory: {
                Button { testText = context.pasteboard.string() ?? testText } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Einfügen")
            }

            AnvilPane(
                "Danach",
                systemImage: "checkmark.seal",
                tone: result.isUnchanged ? .neutral : .success
            ) {
                if testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyStateView(
                        title: "Nichts zu prüfen",
                        message: "Schreib links oben etwas hinein — die Korrektur läuft sofort mit.",
                        systemImage: "text.cursor"
                    )
                } else {
                    resultBody
                }
            } accessory: {
                CopyButton(text: result.text)
            }
        }
    }

    private var resultBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            AnvilTextView(result.text)

            if !result.corrections.isEmpty {
                Divider()
                corrections
            }
        }
    }

    private var corrections: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
                ForEach(result.corrections) { correction in
                    HStack(spacing: AnvilSpacing.sm) {
                        Text(verbatim: correction.original)
                            .font(AnvilFont.monoSmall)
                            .foregroundStyle(AnvilColor.textTertiary)
                            .strikethrough()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AnvilColor.textTertiary)
                        Text(verbatim: correction.replacement)
                            .font(AnvilFont.monoSmall)
                            .foregroundStyle(AnvilColor.textPrimary)
                        Spacer(minLength: 0)
                        StatusPill(.resolved(title(for: correction.kind)), tone: tone(for: correction.kind))
                    }
                }
            }
            .padding(AnvilSpacing.md)
        }
        .frame(maxHeight: AnvilSize.secondaryListHeight)
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(store.activeEntries.count)", label: "Aktiv", systemImage: "checkmark.circle")
            StatusMetric("\(variantCount)", label: "Verhörer", systemImage: "arrow.triangle.branch")
            if !testText.isEmpty {
                StatusMetric("\(result.count)", label: "Korrekturen", systemImage: "wand.and.stars")
            }
        } trailing: {
            StatusPill(.resolved(sensitivity.title), systemImage: "dial.medium", tone: .accent)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection("Erkennung", systemImage: "dial.medium", footnote: .resolved(sensitivity.explanation)) {
            Picker("", selection: sensitivityBinding) {
                ForEach(VocabularyCorrector.Sensitivity.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        InspectorSection(
            "Modell",
            systemImage: "sparkles",
            footnote: "Ohne das schreibt das Modell unbekannte Namen gern wieder in ein Wort um, das es kennt."
        ) {
            Toggle("Begriffe an das Modell geben", isOn: settings.bind(.vocabularyInPrompt))
                .font(AnvilFont.body)
        }

        InspectorSection(
            "Liste",
            systemImage: "list.bullet.rectangle",
            footnote: "Eine Zeile je Begriff. Verhörer stehen nach einem Doppelpunkt, mit Komma getrennt."
        ) {
            AnvilButton("Aus Zwischenablage laden", systemImage: "square.and.arrow.down") {
                importFromPasteboard()
            }
            AnvilButton("In Zwischenablage kopieren", systemImage: "square.and.arrow.up") {
                context.pasteboard.copy(exportedList)
            }
            .disabled(store.entries.isEmpty)
        }
    }

    // MARK: - Actions

    private var trimmedNewTerm: String {
        newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTerm() {
        let term = trimmedNewTerm
        guard !term.isEmpty else { return }
        store.add(VocabularyEntry(term: term))
        newTerm = ""
        isAddFieldFocused = true
    }

    /// Reads a pasted list, one term per line, `Begriff: verhört, verhört`.
    ///
    /// Additive on purpose: importing is how a list moves between machines, and
    /// silently dropping what is already there would be the one mistake that
    /// cannot be undone.
    private func importFromPasteboard() {
        guard let text = context.pasteboard.string() else { return }

        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let term = parts.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !term.isEmpty else { continue }
            guard !store.entries.contains(where: { $0.term.caseInsensitiveCompare(term) == .orderedSame })
            else { continue }

            let variants = parts.count > 1 ? Self.splitVariants(String(parts[1])) : []
            store.add(VocabularyEntry(term: term, variants: variants))
        }
    }

    private var exportedList: String {
        store.entries
            .map { $0.variants.isEmpty ? $0.term : "\($0.term): \($0.variants.joined(separator: ", "))" }
            .joined(separator: "\n")
    }

    // MARK: - Derived

    private var sensitivity: VocabularyCorrector.Sensitivity {
        settings[.vocabularySensitivity]
    }

    private var result: VocabularyCorrector.Result {
        store.corrector().correct(testText)
    }

    private var variantCount: Int {
        store.entries.reduce(0) { $0 + $1.variants.count }
    }

    private func title(for kind: VocabularyCorrector.Kind) -> String {
        switch kind {
        case .variant: localized("Eingetragen")
        case .spelling: localized("Schreibweise")
        case .fuzzy: localized("Ähnlich")
        }
    }

    private func tone(for kind: VocabularyCorrector.Kind) -> AnvilTone {
        switch kind {
        case .variant, .spelling: .success
        case .fuzzy: .warning
        }
    }

    // MARK: - Bindings

    private func binding(for entry: VocabularyEntry) -> Binding<VocabularyEntry> {
        Binding(
            get: { store.entries.first { $0.id == entry.id } ?? entry },
            set: { store.update($0) }
        )
    }

    /// Variants edited as one comma-separated field — a nested list editor for
    /// two or three words each would be more UI than the content deserves.
    private func variantsBinding(for entry: Binding<VocabularyEntry>) -> Binding<String> {
        Binding(
            get: { entry.wrappedValue.variants.joined(separator: ", ") },
            set: { entry.wrappedValue.variants = Self.splitVariants($0) }
        )
    }

    private var sensitivityBinding: Binding<VocabularyCorrector.Sensitivity> {
        settings.bind(.vocabularySensitivity)
    }


    static func splitVariants(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
