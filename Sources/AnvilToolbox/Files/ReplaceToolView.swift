import AnvilKit
import AnvilUI
import SwiftUI

/// Suchen und Ersetzen über viele Dateien, mit Vorschau jeder Zeile.
public struct ReplaceToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var files: [URL] = []
    @State private var rules = ReplacePlan.Rules()
    @State private var extensions = ""
    @State private var plan = ReplacePlan.empty
    @State private var undo: [(url: URL, text: String)] = []
    @State private var isWorking = false
    @State private var error: AnvilError?
    @State private var note: String?
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

            if !undo.isEmpty {
                AnvilButton("Rückgängig", systemImage: "arrow.uturn.backward") { revert() }
            }

            AnvilButton(
                "Ersetzen",
                systemImage: "text.badge.checkmark",
                role: .primary,
                isBusy: isWorking
            ) {
                replace()
            }
            .disabled(!plan.isReady || isWorking)
        }
        .anvilErrorBanner($error)
        .anvilFilesDrop(.file, error: $error) { dropped in
            add(dropped.compactMap(\.url))
        }
        .onChange(of: rules) { replan() }
        .onChange(of: extensions) { reread() }
    }

    // MARK: - Dateien

    private func add(_ urls: [URL]) {
        var collected: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                collected += FileWalk.urls(in: url)
            } else {
                collected.append(url)
            }
        }

        var seen = Set(files.map(\.path))
        for url in collected where seen.insert(url.path).inserted {
            files.append(url)
        }
        reread()
    }

    private func chooseFolder() {
        guard let folder = SavePanel.directory(prompt: localized("Ordner wählen")) else { return }
        files = []
        undo = []
        add([folder])
    }

    /// Welche Dateien nach dem Endungsfilter übrig bleiben.
    private var wanted: [URL] {
        let allowed = extensions
            .components(separatedBy: CharacterSet(charactersIn: ", "))
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard !allowed.isEmpty else { return files }
        return files.filter { allowed.contains($0.pathExtension.lowercased()) }
    }

    /// Liest die Dateien neu ein. Teuer genug, um es nicht bei jedem
    /// Tastendruck zu tun — deshalb nur, wenn sich die Auswahl ändert.
    private func reread() {
        replan()
    }

    private func replan() {
        plan = ReplacePlan(files: wanted, rules: rules)
    }

    // MARK: - Tun

    private func replace() {
        isWorking = true
        note = nil
        do {
            let outcome = try plan.execute()
            undo = outcome.undo
            note = localized("\(outcome.changedLines) Stellen in \(outcome.changedFiles) Dateien ersetzt.")
            replan()
        } catch {
            self.error = AnvilError.wrapping(error)
        }
        isWorking = false
    }

    private func revert() {
        isWorking = true
        do {
            try ReplacePlan.revert(undo)
            note = localized("Zurückgenommen.")
            undo = []
            replan()
        } catch {
            self.error = AnvilError.wrapping(error)
        }
        isWorking = false
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            filePane
        } secondary: {
            hitPane
        } status: {
            statusBar
        }
    }

    @ViewBuilder
    private var filePane: some View {
        AnvilPane("Dateien", systemImage: "doc.on.doc") {
            if files.isEmpty {
                EmptyStateView(
                    title: "Noch keine Dateien",
                    message: "Dateien oder einen Ordner ins Fenster ziehen. Unterordner kommen mit.",
                    systemImage: "folder",
                    actions: {
                        AnvilButton("Ordner wählen", systemImage: "folder") { chooseFolder() }
                    }
                )
            } else {
                DataGrid(header: Self.fileColumns, rows: fileRows)
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
    }

    private static let fileColumns = [
        localized("Datei"),
        localized("Treffer"),
        localized("Hinweis")
    ]

    private var fileRows: [[String]] {
        // Ohne Suchbegriff gibt es keinen Plan — die Dateien liegen aber
        // trotzdem da und sollen zu sehen sein.
        guard !rules.isEmpty else {
            return wanted.map { [$0.lastPathComponent, "—", "—"] }
        }
        return plan.entries.map { entry in
            [entry.name, "\(entry.hits.count)", entry.skip?.title ?? "—"]
        }
    }

    @ViewBuilder
    private var hitPane: some View {
        AnvilPane("Vorschau", systemImage: "eye", tone: .neutral) {
            if rules.isEmpty {
                EmptyStateView(
                    title: "Nichts gesucht",
                    message: "Trag rechts ein, wonach gesucht wird. Bis dahin wird keine Datei angefasst.",
                    systemImage: "magnifyingglass"
                )
            } else if plan.hitCount == 0 {
                EmptyStateView(
                    title: "Kein Treffer",
                    message: "In keiner der Dateien steht, wonach du suchst.",
                    systemImage: "questionmark.circle"
                )
            } else {
                DataGrid(header: Self.hitColumns, rows: hitRows)
            }
        } accessory: {
            if plan.hitCount > 0 {
                CopyButton(text: report)
            }
        }

        if let note {
            AnvilBanner(title: .resolved(note), tone: .success, onDismiss: { self.note = nil })
                .padding(AnvilSpacing.md)
        }
    }

    private static let hitColumns = [
        localized("Datei"),
        localized("Zeile"),
        localized("Vorher"),
        localized("Nachher")
    ]

    /// Höchstens so viele Zeilen in der Vorschau.
    ///
    /// Bei einem großen Projekt sind es schnell zehntausend, und keine davon
    /// liest jemand. Die Zahl in der Statuszeile stimmt trotzdem.
    private static let previewLimit = 500

    private var hitRows: [[String]] {
        var rows: [[String]] = []
        for entry in plan.changing {
            for hit in entry.hits {
                guard rows.count < Self.previewLimit else { return rows }
                rows.append([entry.name, "\(hit.line)", hit.before, hit.after])
            }
        }
        return rows
    }

    /// Alle Treffer als Text — das, was man in eine Notiz klebt, bevor man
    /// etwas ändert.
    private var report: String {
        let header = Self.hitColumns.joined(separator: "\t")
        let rows = plan.changing.flatMap { entry in
            entry.hits.map { hit in
                [entry.name, "\(hit.line)", hit.before, hit.after].joined(separator: "\t")
            }
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(wanted.count)", label: "Dateien", systemImage: "doc.on.doc")
            StatusMetric(
                "\(plan.changing.count)",
                label: "ändern sich",
                systemImage: "square.and.pencil",
                tone: .accent
            )
            StatusMetric("\(plan.hitCount)", label: "Stellen", systemImage: "text.magnifyingglass")
            if !plan.skipped.isEmpty {
                StatusMetric(
                    "\(plan.skipped.count)",
                    label: "ausgelassen",
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

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Suchen und ersetzen",
            systemImage: "magnifyingglass",
            footnote: "Ersetzt wird zeilenweise — ein Ausdruck über mehrere Zeilen greift nicht. Ein unfertiger Ausdruck lässt die Zeile einfach, wie sie ist."
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
            Toggle("Nur ganze Wörter", isOn: $rules.wholeWords)
                .font(AnvilFont.body)
        }

        InspectorSection(
            "Nur diese Endungen",
            systemImage: "line.3.horizontal.decrease.circle",
            footnote: "Mit Komma getrennt, ohne Punkt. Leer heißt: alle Dateien."
        ) {
            AnvilTextField(text: $extensions, placeholder: "swift, md, json", isMonospaced: true)
        }

        if !plan.skipped.isEmpty {
            InspectorSection(
                "Ausgelassen",
                systemImage: "exclamationmark.triangle",
                footnote: "Diese Dateien werden nicht angefasst."
            ) {
                KeyValueList(plan.skipped.prefix(20).map { entry in
                    KeyValueList.Item(entry.name, entry.skip?.title ?? "", tone: .warning)
                })
            }
        }

        InspectorSection(
            "Wie ausgeführt wird",
            systemImage: "info.circle",
            footnote: "Vor dem Schreiben wird jede Datei noch einmal gelesen. Was sich seit der Vorschau geändert hat, bleibt unangetastet — ein Editor, der zwischendurch gespeichert hat, überschreibt niemanden."
        ) {
            AnvilButton("Ordner wählen", systemImage: "folder") { chooseFolder() }
        }
    }
}
