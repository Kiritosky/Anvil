import Foundation

/// Where a tool came from.
public struct ToolOrigin: Hashable, Sendable, Identifiable {
    public let bundleIdentifier: String
    public let displayName: String
    /// Loaded from a file in `~/Library/Application Support/Anvil/Tools`.
    public let isUserDefined: Bool
    /// A tool the app cannot function without — never switchable.
    public let isEssential: Bool
    /// The file a user-defined tool was loaded from, for editing and deleting.
    public let fileURL: URL?

    public var id: String { bundleIdentifier }

    public init(
        bundleIdentifier: String,
        displayName: String,
        isUserDefined: Bool = false,
        isEssential: Bool = false,
        fileURL: URL? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = localized(runtime: displayName)
        self.isUserDefined = isUserDefined
        self.isEssential = isEssential
        self.fileURL = fileURL
    }

    /// Assigned to tools registered without a bundle.
    public static let unspecified = ToolOrigin(
        bundleIdentifier: "dev.anvil.unspecified",
        displayName: "Ohne Zuordnung"
    )

    /// The shell's own tools — settings, the store itself.
    public static let system = ToolOrigin(
        bundleIdentifier: "dev.anvil.system",
        displayName: "System",
        isEssential: true
    )

    public static func userDefined(fileURL: URL) -> ToolOrigin {
        ToolOrigin(
            bundleIdentifier: "dev.anvil.user",
            displayName: "Eigene Tools",
            isUserDefined: true,
            fileURL: fileURL
        )
    }
}
