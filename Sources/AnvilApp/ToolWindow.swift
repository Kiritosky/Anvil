import AnvilKit
import AnvilUI
import SwiftUI

/// Ein einzelnes Werkzeug in einem eigenen Fenster.
///
/// Das Hauptfenster zeigt immer genau ein Werkzeug — bequem, solange man eines
/// braucht. Sobald zwei nebeneinander gehören, steht es im Weg: einen
/// Textvergleich neben dem Regex-Tester, das Diktat neben dem Werkzeug, in das
/// man das Ergebnis tippt.
///
/// Bewusst ohne Seitenleiste. Ein Fenster, das ein Werkzeug zeigt, soll dieses
/// Werkzeug zeigen und nicht anbieten, ein anderes zu werden — dafür gibt es
/// das Hauptfenster.
struct ToolWindow: View {
    @Environment(AppEnvironment.self) private var environment

    let toolID: ToolIdentifier?

    var body: some View {
        content
            .frame(minWidth: 620, minHeight: 460)
            // Jedes Werkzeug merkt sich seine eigene Fenstergröße; die des
            // Bildschirmfotos hat mit der des Farbwerkzeugs nichts zu tun.
            .anvilWindowFrame(autosaveName: "anvil.tool.\(toolID?.rawValue ?? "leer")")
            .navigationTitle(Text(verbatim: tool?.metadata.title ?? localized("Anvil")))
    }

    @ViewBuilder
    private var content: some View {
        if let tool {
            tool.makeView(context: environment.context)
                .id(tool.id)
        } else {
            // Kann passieren: ein Fenster, das beim Beenden offen war, kommt
            // beim nächsten Start zurück — auch wenn das Werkzeug inzwischen
            // im Tool-Store abgeschaltet wurde.
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
