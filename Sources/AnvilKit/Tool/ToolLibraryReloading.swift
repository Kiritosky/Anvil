import Foundation

/// Something that can rebuild the set of user-defined tools from disk.
///
/// Declared in `AnvilKit` so the Tool Store can offer a reload button without
/// knowing how user tools are stored — the toolbox layer registers whatever
/// implements this into the ``ToolContext``.
@MainActor
public protocol ToolLibraryReloading: AnyObject {
    /// Re-reads user tool definitions and re-registers them.
    /// - Returns: how many tools were loaded.
    @discardableResult
    func reloadUserTools() -> Int

    /// The directory user tool files live in, for "Reveal in Finder".
    var userToolsDirectory: URL { get }
}
