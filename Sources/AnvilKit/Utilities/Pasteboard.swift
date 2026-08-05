import AppKit
import Foundation

/// Thin wrapper over `NSPasteboard`.
///
/// Injected through ``ToolContext`` so tests and previews can assert on what a
/// tool copied without touching the real clipboard.
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
}

/// In-memory pasteboard for tests and previews.
@MainActor
public final class RecordingPasteboard: Pasteboard {
    public private(set) var copied: [String] = []
    private var contents: String?

    public override init() { super.init() }

    public override func copy(_ string: String) {
        copied.append(string)
        contents = string
    }

    public override func string() -> String? { contents }
}
