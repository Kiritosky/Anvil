import AnvilKit
import AnvilUI
import SwiftUI

/// Sidebar on the left, the open tool on the right.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var environment = environment

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: 210,
                    ideal: AnvilSize.sidebarWidth,
                    max: 320
                )
        } detail: {
            detail
        }
        .sheet(isPresented: $environment.isCommandPaletteOpen) {
            CommandPalette()
        }
        .sheet(isPresented: $environment.isOnboardingOpen) {
            OnboardingView()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let tool = environment.selectedTool {
            tool.makeView(context: environment.context)
                // Rebuilds the tool when the selection changes, so two tools
                // never share the state SwiftUI would otherwise reuse.
                .id(tool.id)
        } else {
            StartView()
        }
    }
}
