import AppKit
import Foundation

/// Thin wrapper over `NSPasteboard`.
@MainActor
public class Pasteboard {
    public init() {}

    public func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    public func string() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Bumped by the system on every copy, from any app.
    public var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    /// Whether the current contents are marked as sensitive.
    public func isConcealed() -> Bool {
        guard let types = NSPasteboard.general.types else { return false }
        return types.contains { $0.rawValue == "org.nspasteboard.ConcealedType" }
    }
}

/// In-memory pasteboard for tests and previews.
@MainActor
public final class RecordingPasteboard: Pasteboard {
    public private(set) var copied: [String] = []
    private var contents: String?
    private var changes = 0
    /// Set in tests to imitate a password manager.
    public var isConcealedContent = false

    public override init() { super.init() }

    public override func copy(_ string: String) {
        copied.append(string)
        contents = string
        changes += 1
    }

    public override func string() -> String? { contents }

    public override var changeCount: Int { changes }

    public override func isConcealed() -> Bool { isConcealedContent }
}
