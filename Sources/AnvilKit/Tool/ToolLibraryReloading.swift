import Foundation

/// Something that can rebuild the set of user-defined tools from disk.
@MainActor
public protocol ToolLibraryReloading: AnyObject {
    /// Re-reads user tool definitions and re-registers them.
    /// - Returns: how many tools were loaded.
    @discardableResult
    func reloadUserTools() -> Int

    /// The directory user tool files live in, for "Reveal in Finder".
    var userToolsDirectory: URL { get }
}
