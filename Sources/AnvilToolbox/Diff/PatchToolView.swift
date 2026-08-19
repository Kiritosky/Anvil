import AnvilKit
import AnvilUI
import SwiftUI

/// Einen Patch lesen, umkehren und anwenden.
public struct PatchToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    private enum Mode: String, Hashable, CaseIterable, Identifiable {
        case overview
        case apply
        case reversed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: localized("Übersicht")
            case .apply: localized("Anwenden")
            case .reversed: localized("Umgekehrt")
            }
        }

        var systemImage: String {
            switch self {
            case .overview: "list.bullet.rectangle"
            case .apply: "arrow.down.doc"
            case .reversed: "arrow.uturn.backward"
            }
        }
    }

    @State private var patchText = ""
    @State private var sourceText = ""
    @State private var mode: Mode = .overview
    @State private var selectedFile = 0
    @State private var diff = UnifiedDiff(parsing: "")
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
            WorkbenchOrientationPicker(orientation: $orientation)
        }
        .anvilErrorBanner($dropError)
        .anvilFileDrop(.text, error: $dropError) { dropped in
            guard case let .text(text, _) = dropped else { return }
            if text.contains("@@ ") {
                patchText = text
            } else {
                sourceText = text
            }
        }
        .onAppear {
            restore()
            read()
        }
        .onDisappear(perform: remember)
        .onChange(of: patchText) { read() }
    }

    private func read() {
        diff = UnifiedDiff(parsing: patchText)
        if !diff.files.indices.contains(selectedFile) { selectedFile = 0 }
    }

    private func restore() {
        if let handed = context.handoff.take(for: metadata.id) {
            if handed.contains("@@ ") {
                patchText = handed
            } else {
                sourceText = handed
            }
            return
        }
        guard let draft = context.drafts.draft(for: metadata.id) else { return }
        patchText = draft.input
        sourceText = draft.extra("source")
    }

    private func remember() {
        context.drafts.save(
            DraftStore.Draft(input: patchText, extras: ["source": sourceText]),
            for: metadata.id,
            allowed: context.settings[.remembersInput]
        )
    }

    // MARK: - Content

    private var file: UnifiedDiff.FilePatch? {
        diff.files.indices.contains(selectedFile) ? diff.files[selectedFile] : nil
    }

    private var applied: Result<String, AnvilError>? {
        guard let file else { return nil }
        do {
            return .success(try diff.applied(file, to: sourceText))
        } catch {
            return .failure(AnvilError.wrapping(error))
        }
    }

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            inputPanes
        } secondary: {
            resultPane
        } status: {
            statusBar
        }
    }

    @ViewBuilder
    private var inputPanes: some View {
        VStack(spacing: AnvilSpacing.sm) {
            AnvilPane("Patch", systemImage: "doc.text.below.ecg") {
                AnvilTextEditor(
                    text: $patchText,
                    placeholder: "--- a/datei.txt\n+++ b/datei.txt\n@@ -1,3 +1,3 @@",
                    isMonospaced: true
                )
            } accessory: {
                Button { patchText = context.pasteboard.string() ?? patchText } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Einfügen")
            }

            if mode == .apply {
                AnvilPane("Vorlage", systemImage: "doc.plaintext") {
                    AnvilTextEditor(
                        text: $sourceText,
                        placeholder: "Der Text, auf den der Patch angewendet wird.",
                        isMonospaced: true
                    )
                } accessory: {
                    Button { sourceText = context.pasteboard.string() ?? sourceText } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(AnvilIconButtonStyle())
                    .anvilHelp("Einfügen")
                }
            }
        }
    }

    @ViewBuilder
    private var resultPane: some View {
        AnvilPane(.resolved(mode.title), systemImage: mode.systemImage, tone: .neutral) {
            if diff.isEmpty {
                EmptyStateView(
                    title: "Noch kein Patch",
                    message: "Ein Unified Diff — mit oder ohne diff --git davor, mit oder ohne a/ und b/.",
                    systemImage: "doc.text.below.ecg"
                )
            } else {
                switch mode {
                case .overview: overview
                case .reversed: AnvilTextView(diff.reversed.text, isMonospaced: true)
                case .apply: applyResult
                }
            }
        } accessory: {
            HStack(spacing: AnvilSpacing.xs) {
                HandoffMenu(context: context, from: metadata.id, text: outputText)
                CopyButton(text: outputText)
            }
        }
    }

    private var outputText: String {
        switch mode {
        case .overview:
            return diff.text
        case .reversed:
            return diff.reversed.text
        case .apply:
            guard case let .success(text)? = applied else { return "" }
            return text
        }
    }

    private var overview: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: AnvilSpacing.sm) {
                ForEach(diff.files) { file in
                    fileRow(file)
                }
            }
            .padding(AnvilSpacing.md)
        }
    }

    private func fileRow(_ file: UnifiedDiff.FilePatch) -> some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
            HStack(spacing: AnvilSpacing.sm) {
                Text(verbatim: file.displayPath)
                    .font(AnvilFont.rowTitle)
                    .foregroundStyle(AnvilColor.textPrimary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                if file.isNew {
                    StatusPill("neu", systemImage: "plus", tone: .success)
                } else if file.isDeleted {
                    StatusPill("gelöscht", systemImage: "minus", tone: .danger)
                } else if file.isRename {
                    StatusPill("umbenannt", systemImage: "arrow.right", tone: .info)
                }

                Spacer(minLength: 0)

                StatusPill(.resolved("+\(file.additions)"), tone: .success)
                StatusPill(.resolved("−\(file.deletions)"), tone: .danger)
            }

            ForEach(file.hunks) { hunk in
                HStack(spacing: AnvilSpacing.sm) {
                    Text(verbatim: hunk.header)
                        .font(AnvilFont.monoSmall)
                        .foregroundStyle(AnvilColor.accent)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, AnvilSpacing.md)
            }
        }
        .padding(AnvilSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .fill(file.id == selectedFile ? AnvilTone.accent.fill : AnvilColor.surface)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedFile = file.id }
    }

    @ViewBuilder
    private var applyResult: some View {
        if sourceText.isEmpty {
            EmptyStateView(
                title: "Noch keine Vorlage",
                message: "Der Patch braucht den Text, auf den er angewendet werden soll — links unten.",
                systemImage: "doc.plaintext"
            )
        } else {
            switch applied {
            case let .success(text)?:
                DiffTextView(from: sourceText, to: text)
            case let .failure(error)?:
                AnvilBanner(error: error)
            case nil:
                EmptyStateView(title: "Keine Datei gewählt", systemImage: "doc")
            }
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(diff.files.count)", label: "Dateien", systemImage: "doc.on.doc")
            StatusMetric("\(diff.additions)", label: "hinzu", systemImage: "plus", tone: .success)
            StatusMetric("\(diff.deletions)", label: "weg", systemImage: "minus", tone: .danger)
        } trailing: {
            if let file {
                StatusPill(.resolved(file.displayPath), tone: .neutral)
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection("Was tun", systemImage: "wrench.and.screwdriver") {
            ChipPicker(
                selection: $mode,
                options: Mode.allCases,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
        }

        if diff.files.count > 1 {
            InspectorSection(
                "Datei",
                systemImage: "doc.on.doc",
                footnote: "Angewendet wird immer eine Datei — die Vorlage links ist ja auch nur eine."
            ) {
                ChipPicker(
                    selection: $selectedFile,
                    options: Array(diff.files.indices),
                    title: { diff.files[$0].displayPath }
                )
            }
        }

        if let file {
            InspectorSection("Diese Datei", systemImage: "info.circle") {
                KeyValueList([
                    KeyValueList.Item(localized("Vorher"), file.oldPath),
                    KeyValueList.Item(localized("Nachher"), file.newPath),
                    KeyValueList.Item(localized("Abschnitte"), "\(file.hunks.count)"),
                    KeyValueList.Item(localized("Hinzugefügt"), "\(file.additions)", tone: .success),
                    KeyValueList.Item(localized("Entfernt"), "\(file.deletions)", tone: .danger)
                ])
            }
        }

        if mode == .apply {
            InspectorSection(
                "Wie gesucht wird",
                systemImage: "magnifyingglass",
                footnote: "Die Zeilennummer im Kopf ist ein Hinweis, keine Zusage. Anvil sucht um sie herum nach dem passenden Umfeld — und meldet einen Fehler, statt an der falschen Stelle zu schneiden."
            ) {
                KeyValueList([
                    KeyValueList.Item(localized("Suchfenster"), "± \(UnifiedDiff.searchWindow)")
                ])
            }
        }
    }
}
