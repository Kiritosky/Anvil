import AnvilKit
import AnvilUI
import Foundation
import SwiftUI

/// The screen every deterministic text tool gets.
///
/// Runs the active mode on every keystroke — these transforms are microseconds
/// of work, and a live result is far more useful than a "Convert" button. Errors
/// appear in place of the output rather than as an alert, because with live
/// running you are constantly in a half-typed, temporarily invalid state.
public struct TextToolView: View {
    private let tool: TextTool
    private let context: ToolContext

    @State private var input = ""
    @State private var output = ""
    @State private var failure: String?
    @State private var dropError: AnvilError?
    @State private var file: LoadedFile?
    @State private var isWorking = false
    @State private var modeID: String
    @State private var orientation: WorkbenchOrientation = .horizontal

    /// Eine Datei, die statt des getippten Textes durchgerechnet wird.
    struct LoadedFile: Equatable {
        let url: URL
        let size: Int64
    }

    public init(tool: TextTool, context: ToolContext) {
        self.tool = tool
        self.context = context
        _modeID = State(initialValue: tool.modes[0].id)
    }

    public var body: some View {
        ToolScaffold(metadata: tool.metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            actions
        }
        .onAppear(perform: run)
        .anvilErrorBanner($dropError)
        // Werkzeuge, die über Bytes rechnen, wollen die Datei selbst; alle
        // anderen deren Text. Beides über denselben Empfänger, damit es für den
        // Benutzer keinen Unterschied macht, wo er loslässt.
        .anvilFileDrop(acceptsFiles ? .file : .text, error: $dropError) { dropped in
            switch dropped {
            case let .text(text, _):
                file = nil
                input = text
            case let .file(url):
                file = LoadedFile(url: url, size: FileDigest.size(of: url))
            case .image:
                return
            }
            run()
        }
    }

    /// Ob dieses Werkzeug mit einer Datei überhaupt etwas anfangen kann.
    private var acceptsFiles: Bool {
        tool.modes.contains { $0.runOnFile != nil }
    }

    private var emptyMessage: LocalizedStringKey {
        if tool.generatesWithoutInput { return "Wähle rechts eine Variante." }
        if acceptsFiles {
            return "Links etwas einfügen — oder eine Datei ins Fenster ziehen."
        }
        return "Links etwas einfügen — das Ergebnis erscheint sofort."
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: tool.id.rawValue) {
            inputPane
        } secondary: {
            outputPane
        } status: {
            statusBar
        }
    }

    private var inputPane: some View {
        AnvilPane(
            file == nil ? "Eingabe" : "Datei",
            systemImage: file == nil ? "square.and.pencil" : "doc",
            tone: file == nil ? .neutral : .accent
        ) {
            if let file {
                loadedFile(file)
            } else {
                AnvilTextEditor(
                    text: $input,
                    placeholder: .resolved(tool.placeholder),
                    isMonospaced: tool.isMonospaced
                )
                .onChange(of: input) { _, _ in run() }
            }
        } accessory: {
            Button {
                file = nil
                input = context.pasteboard.string() ?? input
                run()
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Aus der Zwischenablage einfügen")

            Button { clear() } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Leeren")
            .disabled(input.isEmpty && file == nil)
        }
    }

    /// Was statt des Editors steht, solange eine Datei geladen ist.
    ///
    /// Kein Textfeld mit dem Dateinamen darin: die Prüfsumme gehört zu den
    /// Bytes auf der Platte, nicht zu einer Zeichenkette, die man versehentlich
    /// bearbeiten könnte.
    private func loadedFile(_ file: LoadedFile) -> some View {
        VStack(spacing: AnvilSpacing.md) {
            Spacer(minLength: 0)

            Image(systemName: "doc.text.magnifyingglass")
                .font(AnvilFont.title)
                .foregroundStyle(AnvilColor.accent)

            Text(verbatim: file.url.lastPathComponent)
                .font(AnvilFont.rowTitle)
                .foregroundStyle(AnvilColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(verbatim: ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                .font(AnvilFont.caption.monospacedDigit())
                .foregroundStyle(AnvilColor.textTertiary)

            AnvilButton("Datei entfernen", systemImage: "xmark", role: .ghost) { clear() }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(AnvilSpacing.lg)
    }

    private var outputPane: some View {
        AnvilPane(
            "Ergebnis",
            systemImage: activeMode.systemImage ?? "arrow.right.doc.on.clipboard",
            tone: failure == nil ? .neutral : .danger
        ) {
            if let failure {
                EmptyStateView(
                    title: "Geht so nicht",
                    message: .resolved(failure),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            } else if isWorking {
                EmptyStateView(
                    title: "Wird gerechnet …",
                    message: "Bei großen Dateien dauert das einen Moment.",
                    systemImage: "hourglass"
                )
            } else if output.isEmpty {
                EmptyStateView(
                    title: tool.generatesWithoutInput ? "Bereit" : "Noch keine Eingabe",
                    message: emptyMessage,
                    systemImage: tool.systemImage
                )
            } else {
                AnvilTextView(output, isMonospaced: tool.isMonospaced)
            }
        } accessory: {
            Button { swap() } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Ergebnis als neue Eingabe verwenden")
            .disabled(output.isEmpty)

            CopyButton(text: output)
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            if let file {
                StatusMetric(
                    ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file),
                    label: "Datei",
                    systemImage: "doc"
                )
            } else {
                StatusMetric("\(input.count)", label: "Zeichen rein", systemImage: "character")
                StatusMetric("\(output.count)", label: "raus", systemImage: "character.cursor.ibeam")
                if input.count > 0, output.count > 0 {
                    let delta = Int(Double(output.count) / Double(input.count) * 100)
                    StatusMetric("\(delta) %", label: "Größe", systemImage: "arrow.up.arrow.down")
                }
            }
        } trailing: {
            StatusPill(
                .resolved(activeMode.title),
                systemImage: activeMode.systemImage,
                tone: .accent
            )
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection("Variante", systemImage: "slider.horizontal.3") {
            ChipPicker(
                selection: $modeID,
                options: tool.modes.map(\.id),
                title: { id in tool.modes.first { $0.id == id }?.title ?? id },
                systemImage: { id in tool.modes.first { $0.id == id }?.systemImage }
            )
            .onChange(of: modeID) { _, _ in run() }
        }

        InspectorSection("Aktionen", systemImage: "bolt") {
            AnvilButton("Ergebnis kopieren", systemImage: "doc.on.doc", role: .secondary) {
                context.pasteboard.copy(output)
            }
            .disabled(output.isEmpty)

            AnvilButton("Ergebnis sichern …", systemImage: "square.and.arrow.down", role: .secondary) {
                save()
            }
            .disabled(output.isEmpty)

            AnvilButton("Zwischenablage einfügen", systemImage: "doc.on.clipboard", role: .secondary) {
                file = nil
                input = context.pasteboard.string() ?? input
                run()
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if tool.generatesWithoutInput {
            AnvilButton("Neu erzeugen", systemImage: "arrow.clockwise", role: .primary, action: run)
        }
        WorkbenchOrientationPicker(orientation: $orientation)
    }

    // MARK: - Running

    private var activeMode: TextToolMode {
        tool.modes.first { $0.id == modeID } ?? tool.modes[0]
    }

    private func run() {
        if let file {
            runOnFile(file)
            return
        }

        guard !input.isEmpty || tool.generatesWithoutInput else {
            output = ""
            failure = nil
            return
        }

        do {
            output = try activeMode.run(input)
            failure = nil
        } catch let error as AnvilError {
            output = ""
            failure = error.message
        } catch {
            output = ""
            failure = error.localizedDescription
        }
    }

    private func runOnFile(_ file: LoadedFile) {
        Task { await compute(file) }
    }

    /// Rechnet die Datei durch — abseits des Hauptthreads, weil ein
    /// Betriebssystem-Image nichts ist, was zwischen zwei Bildaufbauten passt.
    private func compute(_ file: LoadedFile) async {
        guard let handler = activeMode.runOnFile else {
            output = ""
            failure = localized("„\(activeMode.title)\" gibt es für Dateien nicht.")
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try handler(file.url)
            }.value
            // Zwischendurch kann die Datei entfernt oder die Variante
            // gewechselt worden sein — dann gehört dieses Ergebnis nicht mehr
            // auf den Bildschirm.
            guard self.file == file else { return }
            output = result
            failure = nil
        } catch let error as AnvilError {
            guard self.file == file else { return }
            output = ""
            failure = error.message
        } catch {
            guard self.file == file else { return }
            output = ""
            failure = error.localizedDescription
        }
    }

    private func clear() {
        file = nil
        input = ""
        run()
    }

    /// Sichert das Ergebnis als Datei.
    ///
    /// Der Vorschlag ist der Name der geladenen Datei plus Variante — wer eine
    /// Prüfsumme über „ubuntu.iso" gerechnet hat, will sie als
    /// „ubuntu.iso SHA-256" ablegen und nicht als „Ergebnis".
    private func save() {
        let suggestion = file.map { "\($0.url.lastPathComponent) \(activeMode.title)" }
            ?? "\(tool.title) \(activeMode.title)"
        do {
            try SavePanel.write(output, suggestedName: suggestion)
        } catch {
            dropError = AnvilError.wrapping(error)
        }
    }

    private func swap() {
        file = nil
        input = output
        run()
    }
}
