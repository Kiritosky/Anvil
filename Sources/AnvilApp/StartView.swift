import AnvilAI
import AnvilKit
import AnvilToolbox
import AnvilUI
import SwiftUI

/// What you see before opening a tool.
struct StartView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AIRouter.self) private var router: AIRouter?

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: AnvilSpacing.md)]

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

                if !environment.registry.favouriteTools.isEmpty {
                    grid(localized("Favoriten"), tools: environment.registry.favouriteTools)
                }
                if !environment.registry.recentTools.isEmpty {
                    grid(localized("Zuletzt benutzt"), tools: environment.registry.recentTools)
                }

                ForEach(environment.registry.categories) { category in
                    grid(category.title, tools: environment.registry.tools(in: category))
                }
            }
            .padding(AnvilSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AnvilColor.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.xs) {
            HStack(spacing: AnvilSpacing.sm) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(AnvilColor.accent)
                Text("Anvil")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(AnvilColor.textPrimary)
            }

            Text("\(environment.registry.tools.count) Werkzeuge · ⌘K öffnet die Suche")
                .font(AnvilFont.body)
                .foregroundStyle(AnvilColor.textSecondary)
        }
    }

    private func grid(_ title: String, tools: [ToolMetadata]) -> some View {
        VStack(alignment: .leading, spacing: AnvilSpacing.sm) {
            Text(title)
                .font(AnvilFont.sectionTitle)
                .foregroundStyle(AnvilColor.textPrimary)

            LazyVGrid(columns: columns, spacing: AnvilSpacing.md) {
                ForEach(tools) { tool in
                    ToolCard(metadata: tool) { environment.open(tool.id) }
                }
            }
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
