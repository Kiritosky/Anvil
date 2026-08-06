import AnvilKit
import AnvilUI
import Foundation
import SwiftUI

/// Everything that has been on the clipboard this session.
///
/// The list is the tool — there is no input pane, because the input is
/// everything you have copied since launch. One click puts an entry back on the
/// clipboard, which is the only action that matters.
public struct ClipboardToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var query = ""
    @State private var selection: ClipboardEntry?

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    private var history: ClipboardHistory { context.clipboard }
    private var settings: SettingsStore { context.settings }

    public var body: some View {
        ToolScaffold(metadata: metadata) {
            content
        } inspector: {
            inspector
        } actions: {
            AnvilButton("Nicht angeheftete löschen", systemImage: "trash", role: .destructive) {
                history.clear()
                selection = nil
            }
            .disabled(history.entries.allSatisfy(\.isPinned))
        }
        .task {
            // Catch whatever was copied while another tool was open, instead of
            // showing a stale list for the first second.
            history.poll()
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: AnvilSpacing.md) {
            AnvilTextField(text: $query, placeholder: "Im Verlauf suchen …")

            AnvilPane("Verlauf", systemImage: "list.clipboard", contentInset: true) {
                if results.isEmpty {
                    emptyState
                } else {
                    list
                }
            } accessory: {
                if !history.isWatching {
                    StatusPill("Pausiert", systemImage: "pause.circle", tone: .warning)
                }
            }

            statusBar
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if history.entries.isEmpty {
            EmptyStateView(
                title: "Noch nichts kopiert",
                message: "Alles, was du ab jetzt kopierst, sammelt sich hier — bis du Anvil beendest.",
                systemImage: "doc.on.clipboard"
            )
        } else {
            EmptyStateView(
                title: "Kein Treffer",
                message: "Kein Eintrag enthält diesen Text.",
                systemImage: "magnifyingglass"
            )
        }
    }

    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: AnvilSpacing.xs) {
                ForEach(results) { entry in
                    row(entry)
                }
            }
            .padding(.vertical, AnvilSpacing.xxs)
        }
    }

    private func row(_ entry: ClipboardEntry) -> some View {
        Button {
            history.copy(entry)
            selection = entry
        } label: {
            HStack(alignment: .top, spacing: AnvilSpacing.sm) {
                VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                    Text(verbatim: entry.preview)
                        .font(AnvilFont.body)
                        .foregroundStyle(AnvilColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: AnvilSpacing.sm) {
                        Text(verbatim: entry.copiedAt.formatted(date: .omitted, time: .shortened))
                        if let source = entry.source {
                            Text(verbatim: source)
                        }
                        if entry.lineCount > 1 {
                            Text("\(entry.lineCount) Zeilen")
                        }
                        Text("\(entry.text.count) Zeichen")
                    }
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textTertiary)
                }

                Spacer(minLength: 0)

                Button { history.togglePin(entry) } label: {
                    Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(AnvilIconButtonStyle(isActive: entry.isPinned, tone: .accent))
                .help(entry.isPinned ? "Lösen" : "Anheften")

                Button { history.remove(entry) } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(AnvilIconButtonStyle(tone: .danger))
                .help("Entfernen")
            }
            .padding(AnvilSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                    .fill(selection?.id == entry.id ? AnvilColor.accent.opacity(0.12) : AnvilColor.surface)
            }
        }
        .buttonStyle(.plain)
        .help("Zurück in die Zwischenablage")
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(history.entries.count)", label: "Einträge", systemImage: "doc.on.clipboard")
            StatusMetric("\(pinnedCount)", label: "Angeheftet", systemImage: "pin")
        } trailing: {
            if let selection {
                let excerpt = String(selection.preview.prefix(24))
                StatusPill(
                    .resolved(localized("Kopiert: \(excerpt)")),
                    systemImage: "checkmark",
                    tone: .success
                )
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Mitschneiden",
            systemImage: "record.circle",
            footnote: "Der Verlauf liegt nur im Arbeitsspeicher und ist beim nächsten Start wieder leer."
        ) {
            Toggle("Zwischenablage beobachten", isOn: watchingBinding)
                .font(AnvilFont.body)
        }

        InspectorSection(
            "Umfang",
            systemImage: "number",
            footnote: "Angeheftete Einträge zählen nicht mit und fallen nie heraus."
        ) {
            Picker("", selection: limitBinding) {
                ForEach([25, 50, 100, 250], id: \.self) { limit in
                    Text(verbatim: "\(limit)").tag(limit)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        InspectorSection("Sicherheit", systemImage: "lock.shield") {
            Text("Inhalte, die eine App als vertraulich kennzeichnet — etwa aus einem Passwortmanager — werden nie mitgeschnitten.")
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Derived

    private var results: [ClipboardEntry] {
        history.search(query)
    }

    private var pinnedCount: Int {
        history.entries.filter(\.isPinned).count
    }

    private var watchingBinding: Binding<Bool> {
        Binding(
            get: { settings[.clipboardHistoryEnabled] },
            set: { newValue in
                settings[.clipboardHistoryEnabled] = newValue
                history.syncWatching()
            }
        )
    }

    private var limitBinding: Binding<Int> {
        Binding(
            get: { settings[.clipboardHistoryLimit] },
            set: { settings[.clipboardHistoryLimit] = $0 }
        )
    }
}
