import AnvilKit
import AnvilUI
import SwiftUI

/// JSON, YAML und TOML ineinander umwandeln.
public struct StructuredToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    /// Der Formattyp liegt im Modell: Der Stapel braucht ihn genauso.
    typealias Format = StructuredFormat

    @State private var input = ""
    @State private var chosenInput: Format?
    @State private var output: Format = .json
    @State private var value: StructuredValue?
    @State private var error: AnvilError?
    @State private var detected: Format = .json
    @State private var dropError: AnvilError?
    @State private var orientation: WorkbenchOrientation = .horizontal

    /// Der Stapel. Leer heißt: Es geht um den Text im Feld.
    @State private var batch = StructuredBatch.empty
    /// Was der letzte Durchgang angelegt hat, zum Zurücknehmen.
    @State private var created: [URL] = []
    @State private var note: String?

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

            if !batch.isEmpty {
                if !created.isEmpty {
                    AnvilButton("Rückgängig", systemImage: "arrow.uturn.backward") { revertBatch() }
                }

                AnvilButton("Alle schreiben", systemImage: "square.and.arrow.down", role: .primary) {
                    writeBatch()
                }
                .disabled(!batch.isReady)
            }
        }
        .anvilErrorBanner($dropError)
        .anvilFilesDrop(.text, error: $dropError) { dropped in
            open(dropped)
        }
        .onAppear {
            restore()
            read()
        }
        .onDisappear(perform: remember)
        .onChange(of: input) { read() }
        .onChange(of: chosenInput) { read() }
        .onChange(of: output) { replan() }
    }

    // MARK: - Hereingezogenes

    private func open(_ dropped: [DroppedFile]) {
        // Eine Datei bleibt eine Eingabe — der Stapel lohnt erst ab zwei, und
        // die Einzelansicht kann mehr.
        if dropped.count == 1, case let .text(text, _) = dropped[0] {
            batch = .empty
            created = []
            note = nil
            input = text
            chosenInput = nil
            return
        }

        // Für den Stapel braucht es Pfade: Geschrieben wird neben die Quelle,
        // und ein Text ohne Herkunft hat keine.
        let urls = dropped.compactMap(\.url)
        guard urls.count > 1 else { return }
        created = []
        note = nil
        batch = StructuredBatch(urls: urls, target: output)
    }

    private func replan() {
        guard !batch.isEmpty else { return }
        batch = StructuredBatch(urls: batch.entries.map(\.url), target: output)
    }

    private func writeBatch() {
        note = nil
        do {
            let outcome = try batch.execute()
            created = outcome.created
            note = localized("\(outcome.written) Dateien geschrieben.")
            replan()
        } catch {
            dropError = AnvilError.wrapping(error)
        }
    }

    private func revertBatch() {
        do {
            try StructuredBatch.revert(created)
            created = []
            note = localized("Zurückgenommen.")
            replan()
        } catch {
            dropError = AnvilError.wrapping(error)
        }
    }

    private func restore() {
        if let handed = context.handoff.take(for: metadata.id) {
            input = handed
            // Ein hereingereichter Text bringt sein eigenes Format mit; eine
            // Wahl von vorhin wäre jetzt die falsche.
            chosenInput = nil
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

    // MARK: - Lesen

    private func read() {
        detected = Format.detect(input)
        let format = chosenInput ?? detected

        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            value = nil
            error = nil
            return
        }

        do {
            value = try format.read(input)
            error = nil
        } catch {
            value = nil
            self.error = AnvilError.wrapping(error)
        }
    }

    private var outputText: String {
        guard let value else { return "" }
        return output.write(value)
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
        AnvilPane(.resolved((chosenInput ?? detected).title), systemImage: (chosenInput ?? detected).systemImage) {
            AnvilTextEditor(
                text: $input,
                placeholder: "name: Anvil\nwerkzeuge:\n  - Tabellen\n  - Netzrechner",
                isMonospaced: true
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
        AnvilPane(
            batch.isEmpty ? .resolved(output.title) : "Stapel",
            systemImage: batch.isEmpty ? output.systemImage : "doc.on.doc",
            tone: .neutral
        ) {
            if !batch.isEmpty {
                DataGrid(
                    header: StructuredBatch.reportColumns,
                    rows: batch.entries.map { batch.row($0) }
                )
            } else if let error {
                VStack {
                    AnvilBanner(error: error)
                    Spacer(minLength: 0)
                }
                .padding(AnvilSpacing.md)
            } else if value == nil {
                EmptyStateView(
                    title: "Noch nichts da",
                    message: "JSON, YAML oder TOML einwerfen — das Format erkennt Anvil selbst. Mehrere Dateien auf einmal werden zum Stapel.",
                    systemImage: "arrow.left.arrow.right"
                )
            } else {
                AnvilTextView(outputText, isMonospaced: true)
            }
        } accessory: {
            HStack(spacing: AnvilSpacing.xs) {
                if batch.isEmpty {
                    HandoffMenu(context: context, from: metadata.id, text: outputText)
                    CopyButton(text: outputText)
                } else {
                    ClearButton(help: "Stapel schließen") { batch = .empty }

                    CopyButton(text: batch.report)
                }
            }
        }

        if let note {
            AnvilBanner(title: .resolved(note), tone: .success, onDismiss: { self.note = nil })
                .padding(AnvilSpacing.md)
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if batch.isEmpty {
            ToolStatusBar {
                if let value {
                    StatusMetric("\(value.count)", label: "Werte", systemImage: "number")
                    StatusMetric("\(value.depth)", label: "Ebenen", systemImage: "list.bullet.indent")
                }
            } trailing: {
                StatusPill(
                    .resolved((chosenInput ?? detected).title),
                    systemImage: chosenInput == nil ? "wand.and.rays" : "text.cursor",
                    tone: .neutral
                )
            }
        } else {
            ToolStatusBar {
                StatusMetric("\(batch.entries.count)", label: "Dateien", systemImage: "doc.on.doc")
                StatusMetric(
                    "\(batch.writing.count)",
                    label: "werden geschrieben",
                    systemImage: "square.and.arrow.down",
                    tone: .accent
                )
                if !batch.blocked.isEmpty {
                    StatusMetric(
                        "\(batch.blocked.count)",
                        label: "im Weg",
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
            } trailing: {
                StatusPill(
                    .resolved(output.title),
                    systemImage: "arrow.right",
                    tone: .neutral
                )
            }
        }
    }

    // MARK: - Inspector

    /// „Automatisch" steht als leere Wahl vorne.
    private static let inputChoices: [Format?] = [nil] + Format.allCases.map(Optional.init)

    @ViewBuilder
    private var inspector: some View {
        if !batch.isEmpty {
            InspectorSection(
                "Stapel",
                systemImage: "doc.on.doc",
                footnote: "Geschrieben wird neben die Quelle, mit neuer Endung. Die Quelldateien bleiben, wie sie sind — und was am Ziel schon liegt, wird nicht überschrieben."
            ) {
                KeyValueList(batch.blocked.prefix(20).map { entry in
                    KeyValueList.Item(entry.name, entry.problem?.detail ?? "", tone: .warning)
                })
            }
        }

        InspectorSection(
            "Eingabe",
            systemImage: "arrow.down.doc",
            footnote: "Eine Klammer am Anfang ist JSON, eine Zeile in eckigen Klammern TOML, sonst YAML. Bei einer Datei entscheidet die Endung."
        ) {
            ChipPicker(
                selection: $chosenInput,
                options: Self.inputChoices,
                title: { $0?.title ?? localized("Automatisch") }
            )
        }

        InspectorSection(
            "Ausgabe",
            systemImage: "arrow.up.doc",
            footnote: "Nicht ausgelegt werden: YAML-Anker und -Verweise (& und *) und Typangaben (!!); Datum und Uhrzeit aus TOML bleiben Text, weil JSON dafür nichts hat. Verloren geht davon nichts — es bleibt stehen, wie es dasteht."
        ) {
            ChipPicker(
                selection: $output,
                options: Format.allCases,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
        }
    }
}
