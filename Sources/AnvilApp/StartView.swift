import AnvilAI
import AnvilKit
import AnvilToolbox
import AnvilUI
import SwiftUI

/// What you see before opening a tool.
struct StartView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AIRouter.self) private var router: AIRouter?
    @Environment(\.openWindow) private var openWindow

    private var registry: ToolRegistry { environment.registry }

    private let cardColumns = [
        GridItem(.adaptive(minimum: AnvilSize.toolCardMinWidth), spacing: AnvilSpacing.md)
    ]
    private let rowColumns = [
        GridItem(.adaptive(minimum: AnvilSize.toolRowMinWidth), spacing: AnvilSpacing.xs)
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
                    capabilities

                    if !registry.favouriteTools.isEmpty {
                        section("Favoriten", systemImage: "star.fill") {
                            cardGrid(registry.favouriteTools)
                        }
                    }

                    if !registry.recentTools.isEmpty {
                        section("Zuletzt benutzt", systemImage: "clock") {
                            cardGrid(registry.recentTools)
                        }
                    }

                    ForEach(registry.categories) { category in
                        let tools = registry.tools(in: category)
                        section(
                            .resolved(category.title),
                            systemImage: category.systemImage,
                            count: tools.count
                        ) {
                            rowGrid(tools)
                        }
                    }
                }
            }
            .padding(AnvilSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AnvilColor.canvas)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
            HStack(spacing: AnvilSpacing.sm) {
                Image(systemName: "hammer.fill")
                    .font(AnvilFont.display)
                    .foregroundStyle(AnvilColor.accent)
                Text("Anvil")
                    .font(AnvilFont.display)
                    .foregroundStyle(AnvilColor.textPrimary)
            }

            Text("\(registry.tools.count) Werkzeuge · ⌘K öffnet die Suche")
                .font(AnvilFont.body)
                .foregroundStyle(AnvilColor.textSecondary)
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

    // MARK: - Was die App kann

    /// Etwas, das die App kann, ohne dass es irgendwo in der Seitenleiste steht.
    private struct Capability: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let systemImage: String
        /// Die Tastenkombination, sofern es eine gibt und sie scharf ist.
        let keys: String?
    }

    private var capabilities: some View {
        AnvilCard {
            VStack(alignment: .leading, spacing: AnvilSpacing.md) {
                Text("Das kann Anvil")
                    .font(AnvilFont.sectionTitle)
                    .foregroundStyle(AnvilColor.textPrimary)

                FlowLayout(spacing: AnvilSpacing.xl, lineSpacing: AnvilSpacing.md) {
                    ForEach(capabilityList) { capability in
                        HStack(spacing: AnvilSpacing.sm) {
                            Image(systemName: capability.systemImage)
                                .font(AnvilFont.body)
                                .foregroundStyle(AnvilColor.textTertiary)
                            Text(capability.title)
                                .font(AnvilFont.body)
                                .foregroundStyle(AnvilColor.textSecondary)
                            if let keys = capability.keys {
                                KeycapLabel(keys)
                            } else {
                                Text("nicht belegt")
                                    .font(AnvilFont.caption)
                                    .foregroundStyle(AnvilColor.textTertiary)
                            }
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
                systemImage: "mic",
                keys: keys(for: QuickDictationController.actionID)
            ),
            Capability(
                id: "screenshot",
                title: "Ausschnitt aufnehmen",
                systemImage: "rectangle.dashed",
                keys: keys(for: ScreenshotToolBundle.regionActionID)
            ),
            Capability(
                id: "drop",
                title: "Dateien ins Fenster ziehen",
                systemImage: "arrow.down.doc",
                keys: nil
            ),
            Capability(
                id: "window",
                title: "Werkzeug in eigenem Fenster",
                systemImage: "macwindow.on.rectangle",
                keys: "⇧⌘N"
            ),
            Capability(
                id: "quickAccess",
                title: "Favoriten auf Zifferntasten",
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

    // MARK: - Abschnitte

    private func section<Content: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        count: Int? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
            HStack(spacing: AnvilSpacing.sm) {
                Image(systemName: systemImage)
                    .font(AnvilFont.label)
                    .foregroundStyle(AnvilColor.textTertiary)
                Text(title)
                    .font(AnvilFont.sectionTitle)
                    .foregroundStyle(AnvilColor.textPrimary)
                if let count {
                    Text("\(count) Werkzeuge")
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textTertiary)
                }
                Spacer(minLength: 0)
            }

            content()
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

    private func rowGrid(_ tools: [ToolMetadata]) -> some View {
        let shortcuts = registry.quickAccessShortcuts
        return LazyVGrid(columns: rowColumns, alignment: .leading, spacing: AnvilSpacing.xxs) {
            ForEach(tools) { tool in
                Button { environment.open(tool.id) } label: {
                    ToolListRow(
                        metadata: tool,
                        isFavourite: registry.isFavourite(tool.id),
                        shortcutHint: shortcuts[tool.id],
                        onToggleFavourite: { registry.toggleFavourite(tool.id) }
                    )
                }
                .buttonStyle(.plain)
                .contextMenu { toolMenu(tool) }
            }
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
