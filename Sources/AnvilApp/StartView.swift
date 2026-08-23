import AnvilAI
import AnvilKit
import AnvilToolbox
import AnvilUI
import SwiftUI

/// What you see before opening a tool: the whole toolbox on one page, plus
/// what the app does without a tool being open at all.
struct StartView: View {
    private enum Page: Hashable {
        case tools
        case shortcuts
    }

    @Environment(AppEnvironment.self) private var environment
    @Environment(AIRouter.self) private var router: AIRouter?
    @Environment(\.openWindow) private var openWindow

    @State private var page: Page = .tools

    private var registry: ToolRegistry { environment.registry }

    private let cardColumns = [
        GridItem(.adaptive(minimum: AnvilSize.toolCardMinWidth), spacing: AnvilSpacing.md)
    ]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: AnvilSpacing.xl) {
                header

                if let router, !router.availability.isAvailable {
                    AnvilBanner(
                        title: "Kein Sprachmodell verfügbar",
                        message: .resolved(router.statusSummary),
                        tone: .warning,
                        actionTitle: "Einstellungen",
                        action: openSettings
                    )
                }

                if registry.tools.isEmpty {
                    emptyState
                } else {
                    switch page {
                    case .tools: toolsPage
                    case .shortcuts: shortcutsPage
                    }
                }
            }
            .padding(AnvilSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AnvilColor.canvas)
        .animation(AnvilMotion.standard, value: page)
    }

    // MARK: - Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.lg) {
            HStack(spacing: AnvilSpacing.md) {
                AnvilIconBadge("hammer.fill", size: 44)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Anvil")
                        .font(AnvilFont.display)
                        .foregroundStyle(AnvilColor.textPrimary)

                    Text("\(registry.tools.count) Werkzeuge · ⌘K öffnet die Suche")
                        .font(AnvilFont.body)
                        .foregroundStyle(AnvilColor.textSecondary)
                }

                Spacer(minLength: AnvilSpacing.lg)

                AnvilButton("Tool-Store", systemImage: "square.grid.2x2") {
                    environment.open(SystemToolBundle.storeToolID)
                }
            }

            AnvilSegmentedControl(
                selection: $page,
                segments: [
                    .init(.tools, title: "Werkzeuge", systemImage: "wrench.and.screwdriver"),
                    .init(.shortcuts, title: "Kürzel", systemImage: "command")
                ]
            )
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            title: "Kein Werkzeug eingeschaltet",
            message: "Im Tool-Store lässt sich jedes einzeln wieder anschalten.",
            systemImage: "wrench.and.screwdriver"
        ) {
            AnvilButton("Tool-Store öffnen", systemImage: "square.grid.2x2", role: .primary) {
                environment.open(SystemToolBundle.storeToolID)
            }
        }
    }

    // MARK: - Werkzeuge

    @ViewBuilder
    private var toolsPage: some View {
        if !registry.favouriteTools.isEmpty {
            group("Favoriten") {
                cardGrid(registry.favouriteTools)
            }
        }

        if !registry.recentTools.isEmpty {
            group("Zuletzt benutzt") {
                cardGrid(registry.recentTools)
            }
        }

        ForEach(registry.categories) { category in
            let tools = registry.tools(in: category)
            group(.resolved(category.title), count: tools.count) {
                rowGroup(tools)
            }
        }
    }

    private func cardGrid(_ tools: [ToolMetadata]) -> some View {
        let shortcuts = registry.quickAccessShortcuts
        return LazyVGrid(columns: cardColumns, alignment: .leading, spacing: AnvilSpacing.md) {
            ForEach(tools) { tool in
                ToolCard(
                    metadata: tool,
                    isFavourite: registry.isFavourite(tool.id),
                    shortcutHint: shortcuts[tool.id],
                    onToggleFavourite: { registry.toggleFavourite(tool.id) }
                ) {
                    environment.open(tool.id)
                }
                .contextMenu { toolMenu(tool) }
            }
        }
    }

    private func rowGroup(_ tools: [ToolMetadata]) -> some View {
        let shortcuts = registry.quickAccessShortcuts
        return AnvilRowGroup {
            ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                if index > 0 {
                    Divider().padding(.leading, AnvilSize.iconBadge + AnvilSpacing.xl)
                }

                Button { environment.open(tool.id) } label: {
                    AnvilRow(
                        .resolved(tool.title),
                        subtitle: .resolvedIfPresent(tool.subtitle.isEmpty ? nil : tool.subtitle),
                        systemImage: tool.systemImage,
                        tone: tool.usesAI ? .ai : .accent,
                        pills: pills(for: tool)
                    ) {
                        HStack(spacing: AnvilSpacing.sm) {
                            if let keys = shortcuts[tool.id] {
                                KeycapLabel(keys)
                            }
                            Image(systemName: "chevron.right")
                                .font(AnvilFont.caption)
                                .foregroundStyle(AnvilColor.textTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu { toolMenu(tool) }
            }
        }
    }

    private func pills(for tool: ToolMetadata) -> [AnvilRowPill] {
        var pills: [AnvilRowPill] = []
        if tool.usesAI {
            pills.append(AnvilRowPill("KI", tone: .ai, systemImage: "sparkles"))
        }
        if let badge = tool.badge {
            pills.append(AnvilRowPill(.resolved(badge), tone: .accent))
        }
        if registry.isFavourite(tool.id) {
            pills.append(AnvilRowPill("Favorit", tone: .warning, systemImage: "star.fill"))
        }
        return pills
    }

    // MARK: - Kürzel

    /// Etwas, das die App kann, ohne dass es irgendwo in der Seitenleiste steht.
    private struct Capability: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let systemImage: String
        /// Die Tastenkombination, sofern es eine gibt und sie scharf ist.
        let keys: String?
    }

    private var shortcutsPage: some View {
        group("Das kann Anvil, ohne dass ein Werkzeug offen ist") {
            AnvilRowGroup {
                ForEach(Array(capabilityList.enumerated()), id: \.element.id) { index, capability in
                    if index > 0 {
                        Divider().padding(.leading, AnvilSize.iconBadge + AnvilSpacing.xl)
                    }

                    AnvilRow(
                        capability.title,
                        subtitle: capability.subtitle,
                        systemImage: capability.systemImage,
                        tone: capability.keys == nil ? .neutral : .accent
                    ) {
                        if let keys = capability.keys {
                            KeycapLabel(keys)
                        } else {
                            AnvilPill("nicht belegt")
                        }
                    }
                }
            }
        }
    }

    private var capabilityList: [Capability] {
        [
            Capability(
                id: "dictation",
                title: "Diktieren, überall",
                subtitle: "Sprechen statt tippen, in jedem Programm.",
                systemImage: "mic",
                keys: keys(for: QuickDictationController.actionID)
            ),
            Capability(
                id: "screenshot",
                title: "Ausschnitt aufnehmen",
                subtitle: "Bereich wählen, annotieren, weitergeben.",
                systemImage: "rectangle.dashed",
                keys: keys(for: ScreenshotToolBundle.regionActionID)
            ),
            Capability(
                id: "drop",
                title: "Dateien ins Fenster ziehen",
                subtitle: "Jedes Werkzeug nimmt auch dreißig auf einmal.",
                systemImage: "arrow.down.doc",
                keys: nil
            ),
            Capability(
                id: "window",
                title: "Werkzeug in eigenem Fenster",
                subtitle: "Zwei Werkzeuge nebeneinander statt hintereinander.",
                systemImage: "macwindow.on.rectangle",
                keys: "⇧⌘N"
            ),
            Capability(
                id: "quickAccess",
                title: "Favoriten auf Zifferntasten",
                subtitle: "Die ersten neun Favoriten liegen auf ⌘1 bis ⌘9.",
                systemImage: "number",
                keys: registry.quickAccessTools.isEmpty ? nil : "⌘1…9"
            )
        ]
    }

    /// Zeigt nur, worauf auch wirklich gehört wird: ein abgeschaltetes Kürzel
    /// anzuschreiben wäre ein Versprechen, das die App nicht hält.
    private func keys(for id: ShortcutActionID) -> String? {
        let setting = environment.shortcuts.setting(for: id)
        guard setting.scope != .off, let shortcut = setting.shortcut else { return nil }
        return shortcut.displayString
    }

    // MARK: - Bausteine

    private func group<Content: View>(
        _ title: LocalizedStringKey,
        count: Int? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.md) {
            AnvilSectionHeader(title) {
                if let count {
                    Text("\(count)")
                        .font(AnvilFont.label)
                        .foregroundStyle(AnvilColor.textTertiary)
                }
            }

            content()
        }
    }

    @ViewBuilder
    private func toolMenu(_ tool: ToolMetadata) -> some View {
        Button("In neuem Fenster öffnen") {
            openWindow(id: AnvilApp.toolWindowID, value: tool.id)
        }

        Button(registry.isFavourite(tool.id) ? "Aus Favoriten entfernen" : "Zu Favoriten") {
            registry.toggleFavourite(tool.id)
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
