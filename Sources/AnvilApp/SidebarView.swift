import AnvilAI
import AnvilKit
import AnvilUI
import SwiftUI

/// The tool list.
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
                                localized("Favoriten"),
                                systemImage: "star.fill",
                                tools: registry.favouriteTools
                            )
                        }
                        if !registry.recentTools.isEmpty {
                            section(
                                localized("Zuletzt"),
                                systemImage: "clock",
                                tools: registry.recentTools
                            )
                        }
                        ForEach(registry.categories) { category in
                            section(
                                category.title,
                                systemImage: category.systemImage,
                                tools: registry.tools(in: category)
                            )
                        }
                    } else {
                        section(
                            localized("Treffer"),
                            systemImage: "magnifyingglass",
                            tools: registry.search(query)
                        )
                    }
                }
                .padding(.horizontal, AnvilSpacing.sm)
                .padding(.bottom, AnvilSpacing.lg)
            }

            Divider()
            footer
        }
        .background(AnvilColor.canvas)
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: AnvilSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(AnvilFont.caption)
                .foregroundStyle(AnvilColor.textTertiary)

            TextField("Suchen", text: $query)
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
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: AnvilRadius.sm, style: .continuous)
                .fill(AnvilColor.field)
        }
        .padding(.horizontal, AnvilSpacing.sm)
        .padding(.vertical, AnvilSpacing.sm)
    }

    private func section(_ title: String, systemImage: String, tools: [ToolMetadata]) -> some View {
        let shortcuts = registry.quickAccessShortcuts
        return VStack(alignment: .leading, spacing: AnvilSpacing.xxs) {
            HStack(spacing: AnvilSpacing.xs) {
                Image(systemName: systemImage)
                    .font(AnvilFont.micro)
                Text(title.uppercased())
                    .font(AnvilFont.label)
                    .tracking(0.6)
            }
            .foregroundStyle(AnvilColor.textTertiary)
            .padding(.horizontal, AnvilSpacing.sm)
            .padding(.bottom, 2)

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
        HStack(spacing: AnvilSpacing.sm) {
            if let router {
                Circle()
                    .fill(router.availability.isAvailable ? AnvilColor.success : AnvilColor.warning)
                    .frame(width: AnvilSize.dot, height: AnvilSize.dot)

                Text(router.statusSummary)
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
        .padding(.horizontal, AnvilSpacing.sm)
        .frame(height: 34)
        .background(AnvilColor.surface)
    }
}
