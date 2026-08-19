import AnvilKit
import AnvilUI
import SwiftUI

/// Ein einzelnes Werkzeug in einem eigenen Fenster.
struct ToolWindow: View {
    @Environment(AppEnvironment.self) private var environment

    let toolID: ToolIdentifier?

    var body: some View {
        content
            .frame(minWidth: AnvilSize.toolWindowMinWidth, minHeight: AnvilSize.toolWindowMinHeight)
            .anvilWindowFrame(autosaveName: "anvil.tool.\(toolID?.rawValue ?? "leer")")
            .navigationTitle(Text(verbatim: tool?.metadata.title ?? localized("Anvil")))
    }

    @ViewBuilder
    private var content: some View {
        if let tool {
            tool.makeView(context: environment.context)
                .id(tool.id)
        } else {
            EmptyStateView(
                title: "Werkzeug nicht verfügbar",
                message: "Es ist abgeschaltet oder gibt es nicht mehr. Im Tool-Store lässt es sich wieder einschalten.",
                systemImage: "questionmark.square.dashed"
            )
        }
    }

    private var tool: ToolRegistration? {
        toolID.flatMap { environment.registry.tool(id: $0) }
    }
}
