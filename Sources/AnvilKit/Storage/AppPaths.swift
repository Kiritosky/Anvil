import Foundation

/// Where Anvil keeps things on disk.
///
/// One place for every path so that a tool never hand-rolls
/// `FileManager.default.urls(for:in:)` and quietly lands somewhere else.
public enum AppPaths {
    public static let bundleIdentifier = "dev.anvil.Anvil"

    /// `~/Library/Application Support/Anvil`
    public static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appending(path: "Anvil", directoryHint: .isDirectory)
    }

    /// User-defined prompt tools, one JSON file each.
    public static var customTools: URL {
        support.appending(path: "Tools", directoryHint: .isDirectory)
    }

    /// Saved recordings from the speech tools.
    public static var recordings: URL {
        support.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    /// Per-tool history files.
    public static var history: URL {
        support.appending(path: "History", directoryHint: .isDirectory)
    }

    /// Exported transcripts and tool output.
    public static var exports: URL {
        support.appending(path: "Exports", directoryHint: .isDirectory)
    }

    /// Screenshots, when they are kept.
    public static var screenshots: URL {
        support.appending(path: "Screenshots", directoryHint: .isDirectory)
    }

    /// Creates every directory the app expects. Safe to call repeatedly.
    @discardableResult
    public static func bootstrap() -> Bool {
        let directories = [support, customTools, recordings, history, exports, screenshots]
        do {
            for directory in directories {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }
            return true
        } catch {
            return false
        }
    }
}
