import AnvilKit
import AnvilUI
import Foundation
import SwiftUI

/// The screen every deterministic text tool gets.
public struct TextToolView: View {
    private let tool: TextTool
    private let context: ToolContext

    @State private var input = ""
    @State private var output = ""
    @State private var failure: String?
    @State private var dropError: AnvilError?
    @State private var files: [LoadedFile] = []
    @State private var isWorking = false
    @State private var modeID: String
    @State private var orientation: WorkbenchOrientation = .horizontal

    /// Eine Datei, die statt des getippten Textes durchgerechnet wird.
    struct LoadedFile: Equatable, Identifiable {
        let url: URL
        let size: Int64

        var id: URL { url }
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
        .onAppear(perform: restore)
        .onDisappear(perform: remember)
        .anvilErrorBanner($dropError)
        .anvilFilesDrop(acceptsFiles ? .file : .text, error: $dropError) { dropped in
            let urls = dropped.compactMap { item -> URL? in
                if case let .file(url) = item { return url }
                return nil
            }

            if urls.isEmpty {
                if case let .text(text, _)? = dropped.first {
                    files = []
                    input = text
                }
            } else {
                add(urls)
            }
            run()
        }
    }

    /// Ob dieses Werkzeug mit einer Datei überhaupt etwas anfangen kann.
    private var acceptsFiles: Bool {
        tool.modes.contains { $0.runOnFiles != nil }
    }

    /// Nimmt Dateien in die Liste, ohne Doppelte.
    private func add(_ urls: [URL]) {
        let known = Set(files.map(\.url))
        files += urls
            .filter { !known.contains($0) }
            .map { LoadedFile(url: $0, size: FileDigest.size(of: $0)) }
    }

    // MARK: - Zurückholen und merken

    /// Holt zurück, was beim letzten Mal drinstand.
    private func restore() {
        if let handed = context.handoff.take(for: tool.id) {
            input = handed
            run()
            return
        }
        if let draft = context.drafts.draft(for: tool.id) {
            input = draft.input
            if let modeID = draft.modeID, tool.modes.contains(where: { $0.id == modeID }) {
                self.modeID = modeID
            }
        }
        run()
    }

    /// Merkt sich den Stand beim Verlassen.
    private func remember() {
        guard files.isEmpty else {
            context.drafts.forget(tool.id)
            return
        }

        context.drafts.save(
            DraftStore.Draft(input: input, modeID: modeID),
            for: tool.id,
            allowed: !tool.handlesSecrets && context.settings[.remembersInput]
        )
    }

    private var emptyMessage: LocalizedStringKey {
        if tool.generatesWithoutInput { return "Wähle rechts eine Variante." }
        if acceptsFiles {
            return "Links etwas einfügen — oder Dateien ins Fenster ziehen, auch viele."
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
            files.isEmpty ? "Eingabe" : "Dateien",
            systemImage: files.isEmpty ? "square.and.pencil" : "doc.on.doc",
            tone: files.isEmpty ? .neutral : .accent
        ) {
            if !files.isEmpty {
                fileList
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
                files = []
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
            .disabled(input.isEmpty && files.isEmpty)
        }
    }

    /// Was statt des Editors steht, solange Dateien geladen sind.
    private var fileList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: AnvilSpacing.xxs) {
                ForEach(files) { file in
                    HStack(spacing: AnvilSpacing.sm) {
                        Image(systemName: "doc")
                            .foregroundStyle(AnvilColor.accent)

                        Text(verbatim: file.url.lastPathComponent)
                            .font(AnvilFont.rowTitle)
                            .foregroundStyle(AnvilColor.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 0)

                        Text(verbatim: ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                            .font(AnvilFont.caption.monospacedDigit())
                            .foregroundStyle(AnvilColor.textTertiary)

                        Button { remove(file) } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(AnvilIconButtonStyle())
                        .anvilHelp("Aus der Liste nehmen")
                    }
                    .padding(.horizontal, AnvilSpacing.sm)
                    .padding(.vertical, AnvilSpacing.xs)
                }
            }
            .padding(.vertical, AnvilSpacing.xxs)
        }
    }

    private func remove(_ file: LoadedFile) {
        files.removeAll { $0.url == file.url }
        run()
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

            HandoffMenu(context: context, from: tool.id, text: output)
            CopyButton(text: output)
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            if !files.isEmpty {
                StatusMetric("\(files.count)", label: "Dateien", systemImage: "doc.on.doc")
                StatusMetric(
                    ByteCountFormatter.string(
                        fromByteCount: files.reduce(0) { $0 + $1.size },
                        countStyle: .file
                    ),
                    label: "gesamt",
                    systemImage: "externaldrive"
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
                files = []
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
        if !files.isEmpty {
            runOnFiles(files)
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

    private func runOnFiles(_ files: [LoadedFile]) {
        Task { await compute(files) }
    }

    /// Rechnet die Dateien durch — abseits des Hauptthreads, weil ein
    /// Betriebssystem-Image nichts ist, was zwischen zwei Bildaufbauten passt.
    private func compute(_ files: [LoadedFile]) async {
        guard let handler = activeMode.runOnFiles else {
            output = ""
            failure = localized("„\(activeMode.title)\" gibt es für Dateien nicht.")
            return
        }

        isWorking = true
        defer { isWorking = false }

        let urls = files.map(\.url)
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try handler(urls)
            }.value
            guard self.files == files else { return }
            output = result
            failure = nil
        } catch let error as AnvilError {
            guard self.files == files else { return }
            output = ""
            failure = error.message
        } catch {
            guard self.files == files else { return }
            output = ""
            failure = error.localizedDescription
        }
    }

    private func clear() {
        files = []
        input = ""
        run()
    }

    /// Sichert das Ergebnis als Datei.
    private func save() {
        let suggestion: String
        switch files.count {
        case 0: suggestion = "\(tool.title) \(activeMode.title)"
        case 1: suggestion = "\(files[0].url.lastPathComponent) \(activeMode.title)"
        default: suggestion = "\(activeMode.title) \(localized("Prüfsummen"))"
        }
        do {
            try SavePanel.write(output, suggestedName: suggestion)
        } catch {
            dropError = AnvilError.wrapping(error)
        }
    }

    private func swap() {
        files = []
        input = output
        run()
    }
}
