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
        .anvilWindowFrame(autosaveName: "anvil.main")
        .onChange(of: environment.handoff.lastTarget) {
            environment.followHandoff()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let tool = environment.selectedTool {
            tool.makeView(context: environment.context)
                .id(tool.id)
        } else {
            StartView()
        }
    }
}
