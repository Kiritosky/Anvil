import Foundation
import Observation

/// Ein Ergebnis an das nächste Werkzeug weiterreichen.
@MainActor
@Observable
public final class HandoffStore {
    private var pending: [ToolIdentifier: String] = [:]

    /// Wohin zuletzt etwas geschickt wurde. Die Shell öffnet daraufhin das
    /// Werkzeug; der Wert wird beim Lesen zurückgesetzt.
    public private(set) var lastTarget: ToolIdentifier?

    public init() {}

    /// Legt `text` für `tool` bereit.
    public func send(_ text: String, to tool: ToolIdentifier) {
        pending[tool] = text
        lastTarget = tool
    }

    /// Nimmt das Bereitgelegte für `tool` und räumt es weg.
    public func take(for tool: ToolIdentifier) -> String? {
        pending.removeValue(forKey: tool)
    }

    /// Ob für `tool` etwas bereitliegt, ohne es wegzunehmen.
    public func hasPending(for tool: ToolIdentifier) -> Bool {
        pending[tool] != nil
    }

    /// Wird von der Shell aufgerufen, nachdem sie das Ziel geöffnet hat.
    public func clearTarget() {
        lastTarget = nil
    }

    /// Wirft alles weg. Beim Abschalten eines Werkzeugs im Tool-Store.
    public func forget(_ tool: ToolIdentifier) {
        pending.removeValue(forKey: tool)
        if lastTarget == tool { lastTarget = nil }
    }
}

extension ToolContext {
    /// Was gerade von einem Werkzeug zum nächsten unterwegs ist.
    public var handoff: HandoffStore { require(HandoffStore.self) }
}
