import AnvilKit
import AnvilUI
import SwiftUI

/// `.env`-Dateien nebeneinanderlegen.
public struct EnvToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var files: [EnvFile] = []
    @State private var sources: [URL] = []
    @State private var filter = EnvComparison.Filter.all
    @State private var error: AnvilError?
    @State private var note: String?
    @State private var orientation: WorkbenchOrientation = .horizontal

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    private var comparison: EnvComparison { EnvComparison(files) }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            WorkbenchOrientationPicker(orientation: $orientation)

            if !files.isEmpty {
                AnvilButton("Vergleich kopieren", systemImage: "doc.on.clipboard", role: .primary) {
                    context.pasteboard.copy(comparison.report(filter))
                    note = localized("Der Vergleich liegt in der Zwischenablage — ohne Werte.")
                }
            }
        }
        .anvilErrorBanner($error)
        .anvilFilesDrop(.text, error: $error) { dropped in
            add(dropped)
        }
    }

    // MARK: - Dateien

    private func add(_ dropped: [DroppedFile]) {
        var added = false
        for file in dropped {
            switch file {
            case let .text(text, url):
                let name = url?.lastPathComponent ?? localized("Eingefügt")
                if let url { sources.append(url) }
                files.append(EnvFile.read(text, name: uniqueName(name)))
                added = true
            case let .file(url):
                // Ein Ordner: Wer ihn hineinzieht, meint die `.env`-Dateien
                // darin und nicht den Ordner.
                added = scan(url) || added
            case .image:
                continue
            }
        }
        if !added {
            error = .invalidInput(localized("Darin stand keine Zuweisung."))
        }
    }

    /// Zwei Dateien heißen fast immer `.env` — die eine im einen Projekt, die
    /// andere im anderen. Ohne einen unterscheidbaren Namen wären die beiden
    /// Spalten nicht auseinanderzuhalten.
    private func uniqueName(_ name: String) -> String {
        guard files.contains(where: { $0.name == name }) else { return name }
        for number in 2...99 {
            let candidate = "\(name) (\(number))"
            if !files.contains(where: { $0.name == candidate }) { return candidate }
        }
        return name
    }

    /// Nimmt jede `.env`-Datei aus einem Ordner mit.
    @discardableResult
    private func scan(_ folder: URL) -> Bool {
        // Versteckte Dateien müssen mitkommen: `.env` fängt mit einem Punkt
        // an, und ohne sie wäre der Ordner immer leer.
        let found = FileWalk.shallow(folder, includingHidden: true)
            .filter { $0.lastPathComponent.hasPrefix(".env") || $0.pathExtension == "env" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var added = false
        for url in found {
            guard let text = try? TextFile.read(at: url) else { continue }
            sources.append(url)
            files.append(EnvFile.read(text, name: uniqueName(url.lastPathComponent)))
            added = true
        }
        return added
    }

    private func chooseFiles() {
        guard let folder = SavePanel.directory(prompt: localized("Ordner wählen")) else { return }
        if !scan(folder) {
            error = .invalidInput(localized("In diesem Ordner liegt keine .env-Datei."))
        }
    }

    private func clear() {
        files = []
        sources = []
        note = nil
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            tablePane
        } secondary: {
            filePane
        } status: {
            statusBar
        }
    }

    @ViewBuilder
    private var tablePane: some View {
        AnvilPane("Vergleich", systemImage: "tablecells") {
            if files.isEmpty {
                EmptyStateView(
                    title: "Noch keine Datei",
                    message: "Zieh zwei oder mehr .env-Dateien hinein — die von hier und die vom Server. Anvil zeigt, welcher Schlüssel wo fehlt, ohne einen Wert anzuzeigen.",
                    systemImage: "list.bullet.rectangle",
                    actions: {
                        AnvilButton("Ordner durchsehen", systemImage: "folder") { chooseFiles() }
                    }
                )
            } else if comparison.filtered(filter).isEmpty {
                EmptyStateView(
                    title: "Nichts in dieser Auswahl",
                    message: "Alles, was hier stehen könnte, ist in Ordnung.",
                    systemImage: "checkmark.circle"
                )
            } else {
                DataGrid(header: comparison.reportColumns, rows: comparison.rows(filter))
            }
        } accessory: {
            if !files.isEmpty {
                HandoffMenu(context: context, from: metadata.id, text: comparison.report(filter))
            }
        }

        if let note {
            AnvilBanner(title: .resolved(note), tone: .success, onDismiss: { self.note = nil })
                .padding(AnvilSpacing.md)
        }
    }

    @ViewBuilder
    private var filePane: some View {
        AnvilPane("Dateien", systemImage: "doc.on.doc", tone: .neutral) {
            if files.isEmpty {
                EmptyStateView(
                    title: "Nichts geladen",
                    message: "Jede Datei bekommt eine eigene Spalte.",
                    systemImage: "doc"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AnvilSpacing.md) {
                        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                            fileCard(index: index, file: file)
                        }
                    }
                    .padding(AnvilSpacing.md)
                }
            }
        } accessory: {
            if !files.isEmpty {
                ClearButton { clear() }
            }
        }
    }

    private func fileCard(index: Int, file: EnvFile) -> some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
            HStack(spacing: AnvilSpacing.xs) {
                Text.raw(file.name)
                    .font(AnvilFont.rowTitle)
                    .foregroundStyle(AnvilColor.textPrimary)
                Spacer(minLength: 0)
                StatusPill(
                    .resolved(localized("\(file.entries.count) Schlüssel")),
                    systemImage: "key",
                    tone: .neutral
                )
            }

            let own = comparison.onlyIn(index)
            if !own.isEmpty {
                // Erst zusammensetzen, dann einsetzen: Ein Anführungszeichen
                // innerhalb einer Interpolation beendet für jedes Werkzeug,
                // das den Quelltext liest, den Text davor — auch für die
                // Übersetzungsprüfung.
                let names = own.prefix(6).map(\.key).joined(separator: ", ")
                Text(.resolved(localized("\(own.count) nur hier: \(names)")))
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(file.problems) { problem in
                HStack(spacing: AnvilSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.warning)
                    Text(.resolved(localized("Zeile \(problem.line): \(problem.kind.title)")))
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textSecondary)
                    Text.raw(problem.subject)
                        .font(AnvilFont.monoSmall)
                        .foregroundStyle(AnvilColor.textTertiary)
                        .lineLimit(1)
                }
            }

            AnvilButton("Fehlende Zeilen kopieren", systemImage: "text.badge.plus") {
                context.pasteboard.copy(comparison.missingLines(for: index))
                note = localized("Die fehlenden Schlüssel liegen in der Zwischenablage — ohne Werte.")
            }
        }
        .padding(AnvilSpacing.sm)
        .anvilCard()
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(files.count)", label: "Dateien", systemImage: "doc.on.doc")
            StatusMetric("\(comparison.keys.count)", label: "Schlüssel", systemImage: "key")
            StatusMetric(
                "\(comparison.missing.count)",
                label: "fehlt irgendwo",
                systemImage: "questionmark.circle",
                tone: comparison.missing.isEmpty ? .neutral : .warning
            )
            StatusMetric(
                "\(comparison.differing.count)",
                label: "unterschiedlich",
                systemImage: "arrow.left.arrow.right",
                tone: .accent
            )
        } trailing: {
            if !comparison.problems.isEmpty {
                StatusPill(
                    .resolved(localized("\(comparison.problems.count) Zeilen ohne Zuweisung")),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            }
            StatusPill("Werte bleiben hier", systemImage: "eye.slash", tone: .success)
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Dateien",
            systemImage: "doc.on.doc",
            footnote: "Zwei oder mehr — je Datei eine Spalte. Der Ordner-Knopf nimmt alles mit, was dort .env heißt, samt .env.example und .env.local."
        ) {
            AnvilButton("Ordner durchsehen", systemImage: "folder") { chooseFiles() }
            if !files.isEmpty {
                AnvilButton("Liste leeren", systemImage: "trash") { clear() }
            }
        }

        InspectorSection(
            "Zeigen",
            systemImage: "line.3.horizontal.decrease.circle"
        ) {
            ChipPicker(
                selection: $filter,
                options: EnvComparison.Filter.allCases,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
        }

        InspectorNote(
            "Warum keine Werte",
            systemImage: "eye.slash",
            footnote: "In einer .env-Datei stehen Zugangsdaten. Anvil liest sie, vergleicht sie im Speicher und zeigt nur, ob etwas dasteht und ob es überall dasselbe ist. Nichts davon wird abgelegt, und in der Zwischenablage landet kein Wert."
        )

        if !sources.isEmpty {
            InspectorSection(
                "Woher",
                systemImage: "folder",
                footnote: "Die Dateien werden einmal gelesen. Ändert sich eine, zieh sie erneut hinein."
            ) {
                KeyValueList(sources.suffix(6).map { url in
                    KeyValueList.Item(url.lastPathComponent, url.deletingLastPathComponent().path)
                })
            }
        }
    }
}
