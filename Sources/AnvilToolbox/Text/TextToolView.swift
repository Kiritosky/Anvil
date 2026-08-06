import AnvilKit
import AnvilUI
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
    @State private var modeID: String
    @State private var orientation: WorkbenchOrientation = .horizontal

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
        AnvilPane("Eingabe", systemImage: "square.and.pencil") {
            AnvilTextEditor(
                text: $input,
                placeholder: .resolved(tool.placeholder),
                isMonospaced: tool.isMonospaced
            )
            .onChange(of: input) { _, _ in run() }
        } accessory: {
            Button {
                input = context.pasteboard.string() ?? input
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Aus der Zwischenablage einfügen")

            Button { input = ""; run() } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .anvilHelp("Leeren")
            .disabled(input.isEmpty)
        }
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
            } else if output.isEmpty {
                EmptyStateView(
                    title: tool.generatesWithoutInput ? "Bereit" : "Noch keine Eingabe",
                    message: tool.generatesWithoutInput
                        ? "Wähle rechts eine Variante."
                        : "Links etwas einfügen — das Ergebnis erscheint sofort.",
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
            StatusMetric("\(input.count)", label: "Zeichen rein", systemImage: "character")
            StatusMetric("\(output.count)", label: "raus", systemImage: "character.cursor.ibeam")
            if input.count > 0, output.count > 0 {
                let delta = Int(Double(output.count) / Double(input.count) * 100)
                StatusMetric("\(delta) %", label: "Größe", systemImage: "arrow.up.arrow.down")
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

            AnvilButton("Zwischenablage einfügen", systemImage: "doc.on.clipboard", role: .secondary) {
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

    private func swap() {
        input = output
        run()
    }
}
