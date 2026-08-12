import AnvilKit
import AnvilUI
import AppKit
import CryptoKit
import SwiftUI

/// Zwei Ordner vergleichen.
public struct FolderCompareToolView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var left: URL?
    @State private var right: URL?
    @State private var comparison = FolderComparison.empty
    @State private var filter: FolderComparison.Difference?
    @State private var isWorking = false
    @State private var error: AnvilError?
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

            if left != nil, right != nil {
                AnvilButton(
                    "Neu vergleichen",
                    systemImage: "arrow.clockwise",
                    role: .primary,
                    isBusy: isWorking
                ) {
                    compare()
                }
                .disabled(isWorking)
            }
        }
        .anvilErrorBanner($error)
        .anvilFilesDrop(.any, error: $error) { dropped in
            accept(dropped.compactMap(\.url))
        }
    }

    // MARK: - Ordner wählen

    /// Zwei Ordner auf einmal fallen zu lassen ist der kürzeste Weg — dann
    /// ist der erste links und der zweite rechts.
    private func accept(_ urls: [URL]) {
        let folders = urls.filter(FileWalk.isDirectory)
        guard !folders.isEmpty else { return }

        if folders.count >= 2 {
            left = folders[0]
            right = folders[1]
        } else if left == nil {
            left = folders[0]
        } else {
            right = folders[0]
        }
        compare()
    }

    private func choose(left isLeft: Bool) {
        guard let folder = SavePanel.directory(prompt: localized("Ordner wählen")) else { return }
        if isLeft { left = folder } else { right = folder }
        compare()
    }

    private func compare() {
        guard let left, let right, !isWorking else { return }

        Task {
            isWorking = true
            defer { isWorking = false }

            comparison = await Task.detached {
                let leftFiles = FileWalk.files(in: left).map {
                    (path: FileWalk.relativePath(of: $0.url, under: left), size: $0.size)
                }
                let rightFiles = FileWalk.files(in: right).map {
                    (path: FileWalk.relativePath(of: $0.url, under: right), size: $0.size)
                }

                return FolderComparison(left: leftFiles, right: rightFiles) { path in
                    let a = left.appending(path: path)
                    let b = right.appending(path: path)
                    guard let first = try? FileDigest.hex(SHA256.self, of: a),
                          let second = try? FileDigest.hex(SHA256.self, of: b)
                    else { return false }
                    return first == second
                }
            }.value
        }
    }

    private var shown: [FolderComparison.Entry] {
        guard let filter else { return comparison.entries }
        return comparison.entries(filter)
    }

    // MARK: - Content

    private var content: some View {
        ToolWorkbench(orientation: $orientation, storageKey: metadata.id.rawValue) {
            folderPane
        } secondary: {
            tablePane
        } status: {
            statusBar
        }
    }

    @ViewBuilder
    private var folderPane: some View {
        AnvilPane("Die beiden Ordner", systemImage: "folder.badge.questionmark") {
            VStack(alignment: .leading, spacing: AnvilSpacing.md) {
                folderRow("Links", folder: left) { choose(left: true) }
                folderRow("Rechts", folder: right) { choose(left: false) }

                if left == nil || right == nil {
                    Text("Zieh zwei Ordner ins Fenster — der erste ist links, der zweite rechts.")
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if comparison.isIdentical {
                    AnvilBanner(
                        title: "Beide Ordner sind gleich",
                        message: "Jede Datei liegt auf beiden Seiten, und der Inhalt stimmt überein.",
                        tone: .success
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(AnvilSpacing.md)
        }
    }

    private func folderRow(
        _ title: LocalizedStringKey,
        folder: URL?,
        choose: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
            Text(title)
                .font(AnvilFont.label)
                .foregroundStyle(AnvilColor.textTertiary)

            HStack(spacing: AnvilSpacing.sm) {
                Text.raw(folder?.path ?? localized("noch keiner"))
                    .font(AnvilFont.body)
                    .foregroundStyle(folder == nil ? AnvilColor.textTertiary : AnvilColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer(minLength: 0)

                AnvilButton("Wählen", systemImage: "folder", role: .secondary) { choose() }
            }
        }
    }

    @ViewBuilder
    private var tablePane: some View {
        AnvilPane("Unterschiede", systemImage: "arrow.left.arrow.right", tone: .neutral) {
            if left == nil || right == nil {
                EmptyStateView(
                    title: "Noch nichts zu vergleichen",
                    message: "Zwei Ordner, und Anvil sagt, was nur in einem davon liegt und was sich unterscheidet.",
                    systemImage: "arrow.left.arrow.right"
                )
            } else if isWorking {
                EmptyStateView(
                    title: "Wird verglichen",
                    message: "Gelesen wird nur, wo eine Datei auf beiden Seiten gleich groß ist.",
                    systemImage: "hourglass"
                )
            } else if shown.isEmpty {
                EmptyStateView(
                    title: "Nichts dabei",
                    message: "Zu dieser Auswahl gibt es keine Datei.",
                    systemImage: "magnifyingglass"
                )
            } else {
                DataGrid(header: FolderComparison.reportColumns, rows: comparison.rows(shown))
            }
        } accessory: {
            if !comparison.isEmpty {
                HStack(spacing: AnvilSpacing.xs) {
                    HandoffMenu(context: context, from: metadata.id, text: comparison.report)
                    CopyButton(text: comparison.report)
                }
            }
        }
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(comparison.entries.count)", label: "Dateien", systemImage: "doc.on.doc")
            if !comparison.entries(.onlyLeft).isEmpty {
                StatusMetric(
                    "\(comparison.entries(.onlyLeft).count)",
                    label: "nur links",
                    systemImage: "arrow.left",
                    tone: .accent
                )
            }
            if !comparison.entries(.onlyRight).isEmpty {
                StatusMetric(
                    "\(comparison.entries(.onlyRight).count)",
                    label: "nur rechts",
                    systemImage: "arrow.right",
                    tone: .accent
                )
            }
            if !comparison.entries(.different).isEmpty {
                StatusMetric(
                    "\(comparison.entries(.different).count)",
                    label: "verschieden",
                    systemImage: "not.equal",
                    tone: .warning
                )
            }
        } trailing: {
            if comparison.isIdentical {
                StatusPill("gleich", systemImage: "checkmark", tone: .success)
            }
        }
    }

    // MARK: - Inspector

    /// „Alles" steht als leere Wahl vorne.
    private static let filterChoices: [FolderComparison.Difference?] =
        [nil] + FolderComparison.Difference.allCases.map(Optional.init)

    @ViewBuilder
    private var inspector: some View {
        InspectorSection(
            "Zeigen",
            systemImage: "line.3.horizontal.decrease.circle",
            footnote: "Verglichen wird der Pfad unterhalb der beiden Ordner. Wie die Ordner selbst heißen, spielt keine Rolle."
        ) {
            ChipPicker(
                selection: $filter,
                options: Self.filterChoices,
                title: { $0?.title ?? localized("Alles") }
            )
        }

        InspectorSection(
            "Wie verglichen wird",
            systemImage: "info.circle",
            footnote: "Erst die Größe, dann der Inhalt: Zwei Dateien verschiedener Größe können nie gleich sein, also wird dort nichts gelesen. Versteckte Ordner bleiben außen vor."
        ) {
            if !comparison.isEmpty {
                KeyValueList([
                    KeyValueList.Item(localized("Gleich"), "\(comparison.entries(.same).count)"),
                    KeyValueList.Item(localized("Auffällig"), "\(comparison.noteworthy.count)")
                ])
            }
        }
    }
}
