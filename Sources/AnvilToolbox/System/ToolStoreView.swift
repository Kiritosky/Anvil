import AnvilKit
import AnvilUI
import AppKit
import SwiftUI

/// Which slice of the library the store is showing.
enum ToolStoreFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case active
    case inactive
    case ai
    case userDefined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: localized("Alle")
        case .active: localized("Aktiv")
        case .inactive: localized("Aus")
        case .ai: localized("Mit KI")
        case .userDefined: localized("Eigene")
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .active: "checkmark.circle"
        case .inactive: "slash.circle"
        case .ai: "sparkles"
        case .userDefined: "person.crop.square"
        }
    }
}

/// Browse every installed tool and switch it on or off.
public struct ToolStoreView: View {
    private let context: ToolContext
    private let metadata: ToolMetadata

    @State private var query = ""
    @State private var filter: ToolStoreFilter = .all
    @State private var pendingDeletion: ToolRegistration?
    @State private var notice: String?

    public init(context: ToolContext, metadata: ToolMetadata) {
        self.context = context
        self.metadata = metadata
    }

    private var registry: ToolRegistry { context.registry }
    private var activation: ToolActivationStore { context.activation }
    private var library: (any ToolLibraryReloading)? { context.resolve() }

    public var body: some View {
        ToolScaffold(metadata: metadata, tone: .accent) {
            content
        } inspector: {
            inspector
        } actions: {
            if library != nil {
                Button {
                    let count = library?.reloadUserTools() ?? 0
                    notice = "\(count) eigene Tools neu geladen."
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Eigene Tools neu laden")
            }
        }
        .confirmationDialog(
            "Tool löschen?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { tool in
            Button("Löschen", role: .destructive) { delete(tool) }
            Button("Abbrechen", role: .cancel) { pendingDeletion = nil }
        } message: { tool in
            Text("„\(tool.metadata.title)\" wird von der Festplatte entfernt. Das lässt sich nicht rückgängig machen.")
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: AnvilSpacing.md) {
            if let notice {
                AnvilBanner(
                    title: .resolved(notice),
                    tone: .success,
                    onDismiss: { self.notice = nil }
                )
            }

            searchBar

            if groups.isEmpty {
                EmptyStateView(
                    title: "Keine Tools gefunden",
                    message: "Für „\(query)\" gibt es in dieser Ansicht nichts. Setze den Filter zurück oder such nach etwas anderem.",
                    systemImage: "magnifyingglass"
                )
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: AnvilSpacing.xl) {
                        ForEach(groups) { group in
                            originSection(group)
                        }
                    }
                    .padding(.bottom, AnvilSpacing.lg)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            statusBar
        }
    }

    private var searchBar: some View {
        HStack(spacing: AnvilSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AnvilColor.textTertiary)
            TextField("Tools durchsuchen", text: $query)
                .textFieldStyle(.plain)
                .font(AnvilFont.body)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AnvilColor.textTertiary)
            }
        }
        .padding(.horizontal, AnvilSpacing.md)
        .frame(height: AnvilSize.filterBarHeight)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .fill(AnvilColor.field)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .strokeBorder(AnvilColor.border, lineWidth: AnvilSize.hairline)
        }
    }

    private func originSection(_ group: ToolGroup) -> some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
            HStack(spacing: AnvilSpacing.sm) {
                Text(group.origin.displayName)
                    .font(AnvilFont.sectionTitle)
                    .foregroundStyle(AnvilColor.textPrimary)

                StatusPill("\(group.tools.count)", tone: .neutral)

                if group.origin.isEssential {
                    StatusPill("Immer aktiv", systemImage: "lock.fill", tone: .neutral)
                }

                Spacer(minLength: AnvilSpacing.sm)

                if !group.origin.isEssential {
                    Toggle(
                        "Sammlung aktiv",
                        isOn: Binding(
                            get: { activation.isBundleEnabled(group.origin) },
                            set: { activation.setBundleEnabled($0, for: group.origin) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .anvilHelp("Ganze Sammlung ein- oder ausschalten")
                }
            }

            VStack(spacing: AnvilSpacing.sm) {
                ForEach(group.tools) { tool in
                    row(for: tool, bundleEnabled: activation.isBundleEnabled(group.origin))
                }
            }
            .opacity(activation.isBundleEnabled(group.origin) ? 1 : 0.55)
        }
    }

    private func row(for tool: ToolRegistration, bundleEnabled: Bool) -> some View {
        let isEnabled = activation.isEnabled(tool.id, isEssential: tool.origin.isEssential)

        return HStack(spacing: AnvilSpacing.md) {
            ToolIconBadge(
                systemImage: tool.metadata.systemImage,
                tone: tool.metadata.usesAI ? .ai : .accent,
                size: 28
            )

            VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
                HStack(spacing: AnvilSpacing.xs) {
                    Text(tool.metadata.title)
                        .font(AnvilFont.body.weight(.medium))
                        .foregroundStyle(AnvilColor.textPrimary)
                    if tool.hasSettings {
                        Image(systemName: "gearshape")
                            .font(AnvilFont.micro)
                            .foregroundStyle(AnvilColor.textTertiary)
                            .anvilHelp("Hat eigene Einstellungen")
                    }
                }

                Text(tool.metadata.subtitle)
                    .font(AnvilFont.caption)
                    .foregroundStyle(AnvilColor.textSecondary)
                    .lineLimit(1)

                if !tool.metadata.requirements.isEmpty {
                    HStack(spacing: AnvilSpacing.xs) {
                        ForEach(Array(tool.metadata.requirements).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { requirement in
                            StatusPill(
                                .resolved(requirement.localizedDescription),
                                tone: requirement == .onDeviceLanguageModel ? .ai : .neutral
                            )
                        }
                    }
                    .padding(.top, AnvilSize.hairline)
                }
            }

            Spacer(minLength: AnvilSpacing.sm)

            if tool.origin.isUserDefined {
                Button { reveal(tool) } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Im Finder zeigen")

                ClearButton(help: "Tool löschen") { pendingDeletion = tool }
            }

            Button {
                registry.toggleFavourite(tool.id)
            } label: {
                Image(systemName: registry.isFavourite(tool.id) ? "star.fill" : "star")
            }
            .buttonStyle(AnvilIconButtonStyle(tone: registry.isFavourite(tool.id) ? .warning : .neutral))
            .anvilHelp("Favorit")

            if tool.origin.isEssential {
                StatusPill("Fest", systemImage: "lock.fill", tone: .neutral)
            } else {
                Toggle(
                    "Aktiv",
                    isOn: Binding(
                        get: { isEnabled },
                        set: { activation.setEnabled($0, for: tool.id) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(!bundleEnabled)
            }
        }
        .padding(AnvilSpacing.md)
        .anvilCard()
        .overlay {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .strokeBorder(AnvilColor.border, lineWidth: AnvilSize.hairline)
        }
        .opacity(isEnabled ? 1 : 0.6)
        .animation(AnvilMotion.quick, value: isEnabled)
    }

    private var statusBar: some View {
        ToolStatusBar {
            StatusMetric("\(registry.allTools.count)", label: "installiert", systemImage: "square.grid.2x2")
            StatusMetric(
                "\(registry.tools.count)",
                label: "aktiv",
                systemImage: "checkmark.circle",
                tone: .success
            )
            let off = registry.allTools.count - registry.tools.count
            if off > 0 {
                StatusMetric("\(off)", label: "aus", systemImage: "slash.circle", tone: .warning)
            }
        } trailing: {
            if activation.hasDisabledAnything {
                AnvilButton("Alles aktivieren", systemImage: "arrow.counterclockwise", role: .ghost) {
                    activation.reset()
                }
            }
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        Group {
            InspectorSection("Filter", systemImage: "line.3.horizontal.decrease") {
                ChipPicker(
                    selection: $filter,
                    options: ToolStoreFilter.allCases,
                    title: \.title,
                    systemImage: { $0.systemImage }
                )
            }

            InspectorSection(
                "Eigene Tools",
                systemImage: "plus.square.on.square",
                footnote: "Reine Prompt-Tools bestehen aus einer JSON-Datei. Neu geladen wird beim Start und über den Knopf oben rechts."
            ) {
                if let library {
                    AnvilButton("Ordner öffnen", systemImage: "folder", role: .secondary) {
                        NSWorkspace.shared.open(library.userToolsDirectory)
                    }
                    AnvilButton("Neu laden", systemImage: "arrow.clockwise", role: .secondary) {
                        let count = library.reloadUserTools()
                        notice = "\(count) eigene Tools neu geladen."
                    }
                } else {
                    Text("Nicht verfügbar.")
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textTertiary)
                }
            }

            InspectorSection("Sammlungen", systemImage: "shippingbox") {
                ForEach(registry.toolsByOrigin) { group in
                    HStack(spacing: AnvilSpacing.xs) {
                        Circle()
                            .fill(activation.isBundleEnabled(group.origin) ? AnvilColor.success : AnvilColor.textTertiary)
                            .frame(width: AnvilSize.dot, height: AnvilSize.dot)
                        Text(group.origin.displayName)
                            .font(AnvilFont.caption)
                            .foregroundStyle(AnvilColor.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(group.tools.count)")
                            .font(AnvilFont.caption.monospacedDigit())
                            .foregroundStyle(AnvilColor.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Data

    private var groups: [ToolGroup] {
        registry.toolsByOrigin.compactMap { group in
            let matching = group.tools.filter(matches)
            return matching.isEmpty ? nil : ToolGroup(origin: group.origin, tools: matching)
        }
    }

    private func matches(_ tool: ToolRegistration) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !FuzzyMatch.matches(query: trimmed, in: tool.metadata.searchCorpus) {
            return false
        }

        switch filter {
        case .all: return true
        case .active: return activation.isActive(tool)
        case .inactive: return !activation.isActive(tool)
        case .ai: return tool.metadata.usesAI
        case .userDefined: return tool.origin.isUserDefined
        }
    }

    // MARK: - Actions

    private func reveal(_ tool: ToolRegistration) {
        guard let url = tool.origin.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func delete(_ tool: ToolRegistration) {
        defer { pendingDeletion = nil }
        guard let url = tool.origin.fileURL else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            registry.removeTool(id: tool.id)
            notice = "„\(tool.metadata.title)\" wurde in den Papierkorb gelegt."
        } catch {
            notice = "Konnte nicht gelöscht werden: \(error.localizedDescription)"
        }
    }
}
