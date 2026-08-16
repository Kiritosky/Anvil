import AnvilKit
import AnvilUI
import SwiftUI

/// Dateien im Stapel umbenennen — mit Vorschau, bevor etwas passiert.
public struct RenameToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var files: [URL] = []
    @State private var existingNames: Set<String> = []
    @State private var rules = RenamePlan.Rules()
    @State private var plan = RenamePlan(files: [], rules: RenamePlan.Rules())
    @State private var undo: [(from: URL, to: URL)] = []
    @State private var isWorking = false
    @State private var error: AnvilError?
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
            if !undo.isEmpty {
                AnvilButton("Rückgängig", systemImage: "arrow.uturn.backward") { revert() }
            }

            AnvilButton(
                "Umbenennen",
                systemImage: "square.and.pencil",
                role: .primary,
                isBusy: isWorking
            ) {
                rename()
            }
            .disabled(!plan.isReady || isWorking)
        }
        .anvilErrorBanner($error)
        .anvilFilesDrop(.any, error: $error) { dropped in
            add(dropped.compactMap(\.url))
        }
        .onChange(of: rules) { replan() }
    }

    // MARK: - Dateien

    private func add(_ urls: [URL]) {
        // Ordner werden aufgeklappt: Wer einen Ordner hineinzieht, meint das,
        // was darin liegt.
        var collected: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                collected += FileWalk.shallow(url)
            } else {
                collected.append(url)
            }
        }

        var seen = Set(files.map(\.path))
        for url in collected where seen.insert(url.path).inserted {
            files.append(url)
        }
        readExistingNames()
        replan()
    }

    /// Was sonst noch im Ordner liegt — nur so kann der Plan sehen, dass ein
    /// Name schon vergeben ist.
    private func readExistingNames() {
        var names: Set<String> = []
        for folder in Set(files.map { $0.deletingLastPathComponent() }) {
            for url in FileWalk.shallow(folder) {
                names.insert(url.lastPathComponent)
            }
        }
        existingNames = names
    }

    private func replan() {
        plan = RenamePlan(files: files, rules: rules, existingNames: existingNames)
    }

    private func chooseFolder() {
        guard let folder = SavePanel.directory(prompt: localized("Ordner wählen")) else { return }
        files = []
        add([folder])
    }

    // MARK: - Tun

    private func rename() {
        isWorking = true
        note = nil
        do {
            let outcome = try plan.execute()
            undo = outcome.undo
            files = plan.entries.map { $0.willChange ? $0.destination : $0.url }
            readExistingNames()
            replan()
            note = localized("\(String(outcome.renamed)) Dateien umbenannt.")
        } catch {
            self.error = AnvilError.wrapping(error)
        }
        isWorking = false
    }

    private func revert() {
        isWorking = true
        do {
            for step in undo {
                try FileManager.default.moveItem(at: step.from, to: step.to)
            }
            files = undo.map(\.to)
            undo = []
            readExistingNames()
            replan()
            note = localized("Zurückgenommen.")
        } catch {
            self.error = AnvilError.wrapping(error)
        }
        isWorking = false
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            AnvilPane("Vorschau", systemImage: "list.bullet.rectangle", tone: .neutral) {
                if files.isEmpty {
                    EmptyStateView(
                        title: "Noch keine Dateien",
                        message: "Dateien oder einen Ordner ins Fenster ziehen.",
                        systemImage: "folder",
                        actions: {
                            AnvilButton("Ordner wählen", systemImage: "folder") { chooseFolder() }
                        }
                    )
                } else {
                    DataGrid(header: Self.columns, rows: rows)
                }
            } accessory: {
                if !files.isEmpty {
                    ClearButton {
                        files = []
                        undo = []
                        replan()
                    }
                }
            }

            if let note {
                AnvilBanner(title: .resolved(note), tone: .success, onDismiss: { self.note = nil })
                    .padding(AnvilSpacing.md)
            }

            ToolStatusBar {
                StatusMetric("\(files.count)", label: "Dateien", systemImage: "doc.on.doc")
                StatusMetric(
                    "\(plan.changing.count)",
                    label: "ändern sich",
                    systemImage: "square.and.pencil",
                    tone: .accent
                )
                if !plan.blocked.isEmpty {
                    StatusMetric(
                        "\(plan.blocked.count)",
                        label: "im Weg",
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                }
            } trailing: {
                StatusPill(
                    plan.isReady ? "bereit" : "noch nicht",
                    systemImage: plan.isReady ? "checkmark" : "hand.raised",
                    tone: plan.isReady ? .success : .neutral
                )
            }
        }
    }

    private static let columns = [localized("Bisher"), localized("Neu"), localized("Hinweis")]

    private var rows: [[String]] {
        plan.entries.map { entry in
            [entry.currentName, entry.newName, entry.problem?.title ?? "—"]
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Suchen und ersetzen",
            systemImage: "magnifyingglass",
            footnote: "Wirkt auf den Namen ohne Endung. Ein unfertiger regulärer Ausdruck lässt den Namen einfach, wie er ist."
        ) {
            OptionRow("Suchen") {
                AnvilTextField(text: $rules.search, placeholder: "Text oder Muster", isMonospaced: true)
            }
            OptionRow("Ersetzen durch") {
                AnvilTextField(text: $rules.replacement, placeholder: "", isMonospaced: true)
            }
            Toggle("Regulärer Ausdruck", isOn: $rules.isRegularExpression)
                .font(AnvilFont.body)
            Toggle("Groß- und Kleinschreibung egal", isOn: $rules.ignoresCase)
                .font(AnvilFont.body)
        }

        InspectorSection(
            "Vorlage",
            systemImage: "text.badge.plus",
            footnote: "{name} ist der bisherige Name, {n} die laufende Nummer, {datum} das heutige Datum, {ext} die Endung. Leer heißt: Namen lassen."
        ) {
            AnvilTextField(text: $rules.pattern, placeholder: "{name}-{n}", isMonospaced: true)
        }

        InspectorSection("Nummerierung", systemImage: "number") {
            OptionRow("Beginnt bei") {
                AnvilStepper(value: $rules.counterStart, in: 0...99_999)
            }
            OptionRow("Schrittweite") {
                AnvilStepper(value: $rules.counterStep, in: 1...100)
            }
            OptionRow("Stellen") {
                AnvilStepper(value: $rules.counterWidth, in: 1...8) { width in
                    RenamePlan.number(rules.counterStart, width: width)
                }
            }
        }

        InspectorSection("Schreibweise", systemImage: "textformat") {
            ChipPicker(
                selection: $rules.casing,
                options: RenamePlan.Rules.Casing.allCases,
                title: { $0.title }
            )

            OptionRow("Leerzeichen ersetzen durch") {
                AnvilTextField(text: $rules.spaceReplacement, placeholder: "-", isMonospaced: true)
            }
            OptionRow("Neue Endung") {
                AnvilTextField(text: $rules.newExtension, placeholder: "txt", isMonospaced: true)
            }
        }

        InspectorSection(
            "Wie ausgeführt wird",
            systemImage: "info.circle",
            footnote: "In zwei Durchgängen über Zwischennamen. Nur so lassen sich zwei Namen tauschen, ohne dass der erste Schritt die zweite Datei überschreibt."
        ) {
            AnvilButton("Ordner wählen", systemImage: "folder") { chooseFolder() }
        }
    }
}
