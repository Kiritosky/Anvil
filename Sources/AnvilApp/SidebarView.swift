import AnvilAI
import AnvilKit
import AnvilUI
import SwiftUI

/// The tool list: a search field, groups under small capitals, and a footer
/// that says whether a model is reachable.
struct SidebarView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AIRouter.self) private var router: AIRouter?
    @Environment(\.openWindow) private var openWindow

    @State private var query = ""

    private var registry: ToolRegistry { environment.registry }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: AnvilSpacing.lg) {
                    if query.isEmpty {
                        if !registry.favouriteTools.isEmpty {
                            section(
                                "Favoriten",
                                systemImage: "star.fill",
                                tools: registry.favouriteTools
                            )
                        }
                        if !registry.recentTools.isEmpty {
                            section(
                                "Zuletzt",
                                systemImage: "clock",
                                tools: registry.recentTools
                            )
                        }
                        ForEach(registry.categories) { category in
                            section(
                                .resolved(category.title),
                                systemImage: category.systemImage,
                                tools: registry.tools(in: category)
                            )
                        }
                    } else {
                        let hits = registry.search(query)
                        if hits.isEmpty {
                            noHits
                        } else {
                            section("Treffer", systemImage: "magnifyingglass", tools: hits)
                        }
                    }
                }
                .padding(.horizontal, AnvilSpacing.sm)
                .padding(.bottom, AnvilSpacing.lg)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background(AnvilColor.canvas)
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: AnvilSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AnvilFont.body)
                .foregroundStyle(AnvilColor.textTertiary)

            TextField("Werkzeug suchen", text: $query)
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
        .padding(.horizontal, AnvilSpacing.sm)
        .frame(height: AnvilSize.controlHeight + 4)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .fill(AnvilColor.elevated)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AnvilRadius.md, style: .continuous)
                .strokeBorder(AnvilColor.border, lineWidth: AnvilSize.hairline)
        }
        .padding(.horizontal, AnvilSpacing.sm)
        .padding(.vertical, AnvilSpacing.md)
    }

    private var noHits: some View {
        Text("Nichts gefunden")
            .font(AnvilFont.body)
            .foregroundStyle(AnvilColor.textTertiary)
            .padding(.horizontal, AnvilSpacing.sm)
            .padding(.top, AnvilSpacing.sm)
    }

    private func section(
        _ title: LocalizedStringKey,
        systemImage: String,
        tools: [ToolMetadata]
    ) -> some View {
        let shortcuts = registry.quickAccessShortcuts
        return VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
            AnvilSectionHeader(title, systemImage: systemImage)
                .padding(.horizontal, AnvilSpacing.sm)
                .padding(.bottom, AnvilSpacing.xxs)

            ForEach(tools) { tool in
                Button { environment.open(tool.id) } label: {
                    ToolListRow(
                        metadata: tool,
                        isSelected: environment.selectedToolID == tool.id,
                        isFavourite: registry.isFavourite(tool.id),
                        showsSubtitle: false,
                        shortcutHint: shortcuts[tool.id],
                        onToggleFavourite: { registry.toggleFavourite(tool.id) }
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("In neuem Fenster öffnen") {
                        openWindow(id: AnvilApp.toolWindowID, value: tool.id)
                    }

                    Button(registry.isFavourite(tool.id) ? "Aus Favoriten entfernen" : "Zu Favoriten") {
                        registry.toggleFavourite(tool.id)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: AnvilSpacing.sm) {
                if let router {
                    Circle()
                        .fill(router.availability.isAvailable ? AnvilColor.success : AnvilColor.warning)
                        .frame(width: AnvilSize.dot, height: AnvilSize.dot)

                    Text(.resolved(router.statusSummary))
                        .font(AnvilFont.caption)
                        .foregroundStyle(AnvilColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                Button { environment.isCommandPaletteOpen = true } label: {
                    Image(systemName: "command")
                }
                .buttonStyle(AnvilIconButtonStyle())
                .anvilHelp("Alles finden (⌘K)")
            }
            .padding(.horizontal, AnvilSpacing.md)
            .frame(height: AnvilSize.statusBarHeight + 4)
        }
        .background(AnvilColor.canvas)
    }
}
