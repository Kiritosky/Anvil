import AnvilKit
import SwiftUI

/// „Weitergeben an …" — schickt ein Ergebnis in ein anderes Werkzeug.
///
/// Steht neben dem Kopieren-Knopf, weil es dieselbe Frage beantwortet: Was
/// passiert jetzt mit dem, was hier steht? Der Unterschied ist nur, dass die
/// Antwort in derselben App liegt.
///
/// Aufgeführt wird, was mit Text etwas anfangen kann und **eingeschaltet** ist
/// — ein Ziel, das im Tool-Store aus ist, würde beim Antippen nichts tun.
public struct HandoffMenu: View {
    private let text: () -> String
    private let source: ToolIdentifier
    private let context: ToolContext

    public init(
        context: ToolContext,
        from source: ToolIdentifier,
        text: @autoclosure @escaping () -> String
    ) {
        self.context = context
        self.source = source
        self.text = text
    }

    public var body: some View {
        Menu {
            if targets.isEmpty {
                Text("Kein Ziel eingeschaltet")
            } else {
                ForEach(targets) { target in
                    Button {
                        send(to: target.id)
                    } label: {
                        Label(.resolved(target.title), systemImage: target.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: "arrowshape.turn.up.right")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .anvilHelp("Weitergeben an ein anderes Werkzeug")
        .disabled(targets.isEmpty)
    }

    /// Die möglichen Ziele, ohne das Werkzeug, in dem man gerade steht.
    ///
    /// Nach Bereich und Titel sortiert, damit die Liste bei jedem Öffnen
    /// gleich aussieht — ein Menü, dessen Reihenfolge sich ändert, lernt
    /// niemand.
    private var targets: [ToolMetadata] {
        context.registry.metadata
            .filter { $0.acceptsText && $0.id != source }
            .sorted {
                $0.category.title == $1.category.title
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.category.title.localizedStandardCompare($1.category.title) == .orderedAscending
            }
    }

    private func send(to target: ToolIdentifier) {
        let payload = text()
        guard !payload.isEmpty else { return }
        context.handoff.send(payload, to: target)
    }
}
