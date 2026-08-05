import AnvilAI
import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// The screen every prompt-driven tool gets.
///
/// Input on one side, streamed answer on the other, the tool's own options in
/// the inspector. Because it is driven entirely by ``AIPromptTool``, the tools a
/// user writes as JSON look and behave exactly like the built-in ones.
public struct AIPromptToolView: View {
    private let tool: AIPromptTool
    private let metadata: ToolMetadata
    private let context: ToolContext

    @State private var input = ""
    @State private var output = ""
    @State private var optionValues: [String: String] = [:]
    @State private var isRunning = false
    @State private var error: AnvilError?
    @State private var runTask: Task<Void, Never>?
    @State private var orientation: WorkbenchOrientation = .horizontal
    @State private var repositoryURL: URL?
    @State private var lastDuration: TimeInterval?

    public init(tool: AIPromptTool, metadata: ToolMetadata, context: ToolContext) {
        self.tool = tool
        self.metadata = metadata
        self.context = context
        _optionValues = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: tool.options.map { ($0.id, $0.defaultValue) }
            )
        )
    }

    public var body: some View {
        ToolScaffold(metadata: metadata, tone: .ai) {
            content
        } inspector: {
            inspector
        } actions: {
            actions
        }
        .onDisappear { runTask?.cancel() }
    }

    // MARK: - Header

    @ViewBuilder
    private var actions: some View {
        if isRunning {
            AnvilButton("Abbrechen", systemImage: "stop.fill", role: .secondary) {
                runTask?.cancel()
                isRunning = false
            }
        } else {
            AnvilButton("Ausführen", systemImage: "play.fill", role: .primary, action: run)
                .disabled(!canRun)
                .keyboardShortcut(.return, modifiers: .command)
        }

        WorkbenchOrientationPicker(orientation: $orientation)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: AnvilSpacing.md) {
            if let error {
                AnvilBanner(error: error, onDismiss: { self.error = nil })
            }

            WorkbenchLayout(orientation: $orientation, storageKey: metadata.id.rawValue) {
                inputPane
                    .padding(.trailing, orientation == .horizontal ? AnvilSpacing.sm : 0)
                    .padding(.bottom, orientation == .vertical ? AnvilSpacing.sm : 0)
            } secondary: {
                outputPane
                    .padding(.leading, orientation == .horizontal ? AnvilSpacing.sm : 0)
                    .padding(.top, orientation == .vertical ? AnvilSpacing.sm : 0)
            }

            statusBar
        }
    }

    private var inputPane: some View {
        AnvilPane(.resolved(inputPaneTitle), systemImage: tool.inputSource == .gitDiff ? "arrow.triangle.branch" : "square.and.pencil") {
            if tool.inputSource == .gitDiff, input.isEmpty {
                EmptyStateView(
                    title: "Kein Diff geladen",
                    message: "Wähle ein Git-Repository — Anvil liest die vorgemerkten Änderungen (`git diff --staged`).",
                    systemImage: "arrow.triangle.branch"
                ) {
                    AnvilButton("Repository wählen", systemImage: "folder", role: .secondary) {
                        chooseRepository()
                    }
                }
            } else {
                AnvilTextEditor(
                    text: $input,
                    placeholder: .resolved(tool.inputPlaceholder),
                    isMonospaced: tool.isMonospacedInput
                )
            }
        } accessory: {
            if tool.inputSource == .gitDiff {
                Button { chooseRepository() } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .help("Anderes Repository wählen")

                Button { Task { await loadDiff() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .help("Diff neu laden")
                .disabled(repositoryURL == nil)
            }

            Button { input = context.pasteboard.string() ?? input } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .help("Einfügen")

            Button { input = "" } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(AnvilIconButtonStyle())
            .help("Leeren")
            .disabled(input.isEmpty)
        }
    }

    private var inputPaneTitle: String {
        guard tool.inputSource == .gitDiff else { return "Eingabe" }
        return repositoryURL.map { "Diff · \($0.lastPathComponent)" } ?? "Diff"
    }

    private var outputPane: some View {
        AnvilPane("Ergebnis", systemImage: tool.systemImage, tone: .ai) {
            if output.isEmpty, !isRunning {
                EmptyStateView(
                    title: "Noch nichts erzeugt",
                    message: .resolved(tool.subtitle),
                    systemImage: tool.systemImage,
                    tone: .ai
                ) {
                    AnvilButton("Ausführen", systemImage: "play.fill", role: .primary, action: run)
                        .disabled(!canRun)
                }
            } else {
                AnvilTextView(output, isMonospaced: tool.isMonospacedInput, followsTail: isRunning)
            }
        } accessory: {
            if isRunning {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            }
            CopyButton(text: output)
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(input.count)", label: "Zeichen", systemImage: "character")
            if !output.isEmpty {
                StatusMetric(
                    "\(output.split(whereSeparator: \.isWhitespace).count)",
                    label: "Wörter",
                    systemImage: "text.word.spacing"
                )
            }
            if let lastDuration {
                StatusMetric(String(format: "%.1fs", lastDuration), systemImage: "clock")
            }
        } trailing: {
            ModelStatusPill()
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if !tool.options.isEmpty {
            InspectorSection("Optionen", systemImage: "slider.horizontal.3") {
                ForEach(tool.options) { option in
                    optionControl(option)
                }
            }
        }

        InspectorSection(
            "Was dieses Tool macht",
            systemImage: "info.circle",
            footnote: .resolved(tool.subtitle)
        ) {
            Text(tool.instructions)
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.textTertiary)
                .lineLimit(8)
                .textSelection(.enabled)
        }

        InspectorSection("Verlauf", systemImage: "clock.arrow.circlepath") {
            let entries = context.history.entries(for: metadata.id)
            if entries.isEmpty {
                Text("Noch nichts gespeichert.")
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
            } else {
                ForEach(entries.prefix(5)) { entry in
                    Button {
                        input = entry.input
                        output = entry.output
                    } label: {
                        Text(entry.preview)
                            .font(AnvilFont.caption)
                            .foregroundStyle(AnvilColor.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func optionControl(_ option: AIPromptOption) -> some View {
        let binding = Binding(
            get: { optionValues[option.id] ?? option.defaultValue },
            set: { optionValues[option.id] = $0 }
        )

        switch option.kind {
        case .choice:
            OptionRow(.resolved(option.label), help: .resolvedIfPresent(option.help)) {
                ChipPicker(
                    selection: binding,
                    options: option.choices,
                    tone: .ai,
                    title: { $0 }
                )
            }
        case .text:
            OptionRow(.resolved(option.label), help: .resolvedIfPresent(option.help)) {
                AnvilTextField(text: binding, placeholder: .resolved(option.defaultValue))
            }
        case .toggle:
            Toggle(
                option.label,
                isOn: Binding(
                    get: { binding.wrappedValue == "true" },
                    set: { binding.wrappedValue = $0 ? "true" : "false" }
                )
            )
            .font(AnvilFont.body)
        }
    }

    // MARK: - Running

    private var canRun: Bool {
        !isRunning && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func run() {
        guard canRun else { return }

        runTask?.cancel()
        error = nil
        output = ""
        isRunning = true
        let startedAt = Date.now

        let request = AIRequest(
            instructions: tool.buildInstructions(optionValues: optionValues),
            prompt: tool.buildPrompt(input: input, optionValues: optionValues),
            options: AIOptions(temperature: tool.temperature)
        )

        runTask = Task { @MainActor in
            do {
                for try await snapshot in context.ai.stream(request) {
                    output = snapshot
                }
                lastDuration = Date.now.timeIntervalSince(startedAt)
                saveToHistory()
                if context.settings[.autoCopyResults], !output.isEmpty {
                    context.pasteboard.copy(output)
                }
            } catch {
                let wrapped = AnvilError.wrapping(error)
                if !wrapped.isCancellation { self.error = wrapped }
            }
            isRunning = false
        }
    }

    private func saveToHistory() {
        guard !output.isEmpty else { return }
        context.history.record(
            HistoryEntry(
                toolID: metadata.id,
                title: String(output.prefix(60)),
                input: input,
                output: output,
                attributes: optionValues
            )
        )
    }

    // MARK: - Git

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Repository verwenden"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        repositoryURL = url
        Task { await loadDiff() }
    }

    private func loadDiff() async {
        guard let repositoryURL else { return }
        do {
            let runner = ProcessRunner()
            var diff = try await runner.git(["diff", "--staged"], in: repositoryURL)
            if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Nothing staged is the common case when someone just wants a
                // message for what they have been working on.
                diff = try await runner.git(["diff"], in: repositoryURL)
            }
            guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                error = .invalidInput(localized("In diesem Repository gibt es keine Änderungen."))
                return
            }
            input = diff
        } catch {
            self.error = AnvilError.wrapping(error)
        }
    }
}
