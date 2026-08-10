import Foundation
import Observation

/// Ein Ergebnis an das nächste Werkzeug weiterreichen.
///
/// Der Unterschied zwischen einer Sammlung von sechzig Bildschirmen und einer
/// Werkzeugkiste: Was hinten herauskommt, geht vorne wieder hinein. Ein
/// Zeitstempel aus einer Logzeile in den Zeitrechner, die Antwort einer API in
/// den Tabellenrechner, der Text aus einem PDF in die Lesbarkeitsprüfung —
/// ohne den Umweg über die Zwischenablage, bei dem man sich verklickt.
///
/// Der Speicher hält bewusst **nur im Arbeitsspeicher**: Weitergereichtes ist
/// unterwegs, nicht abgelegt. Es überlebt keinen Neustart, und es landet nie
/// auf der Platte — auch dann nicht, wenn es harmlos aussieht.
@MainActor
@Observable
public final class HandoffStore {
    private var pending: [ToolIdentifier: String] = [:]

    /// Wohin zuletzt etwas geschickt wurde. Die Shell öffnet daraufhin das
    /// Werkzeug; der Wert wird beim Lesen zurückgesetzt.
    public private(set) var lastTarget: ToolIdentifier?

    public init() {}

    /// Legt `text` für `tool` bereit.
    ///
    /// Ein zweites Weiterreichen an dasselbe Werkzeug überschreibt das erste:
    /// bereitgelegt ist immer das Letzte, was man geschickt hat, nicht eine
    /// Schlange, die man abarbeiten müsste.
    public func send(_ text: String, to tool: ToolIdentifier) {
        pending[tool] = text
        lastTarget = tool
    }

    /// Nimmt das Bereitgelegte für `tool` und räumt es weg.
    ///
    /// Einmalig mit Absicht: Wer ein Werkzeug ein zweites Mal öffnet, will
    /// seinen eigenen Stand sehen und nicht wieder das, was vor einer Stunde
    /// hereingereicht wurde.
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
