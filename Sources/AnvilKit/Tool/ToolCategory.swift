import Foundation

/// A sidebar section.
public struct ToolCategory: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let sortOrder: Int

    public init(id: String, title: String, systemImage: String, sortOrder: Int) {
        self.id = id
        self.title = localized(runtime: title)
        self.systemImage = systemImage
        self.sortOrder = sortOrder
    }

    public static func == (lhs: ToolCategory, rhs: ToolCategory) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension ToolCategory {
    public static let speech = ToolCategory(
        id: "speech",
        title: "Sprache & Audio",
        systemImage: "waveform",
        sortOrder: 10
    )

    public static let coding = ToolCategory(
        id: "coding",
        title: "Coding",
        systemImage: "chevron.left.forwardslash.chevron.right",
        sortOrder: 20
    )

    public static let text = ToolCategory(
        id: "text",
        title: "Text & Daten",
        systemImage: "text.alignleft",
        sortOrder: 30
    )

    public static let everyday = ToolCategory(
        id: "everyday",
        title: "Alltag",
        systemImage: "sparkles",
        sortOrder: 40
    )

    public static let custom = ToolCategory(
        id: "custom",
        title: "Eigene Tools",
        systemImage: "wrench.and.screwdriver",
        sortOrder: 90
    )

    public static let system = ToolCategory(
        id: "system",
        title: "System",
        systemImage: "gearshape",
        sortOrder: 100
    )

    /// The categories the app ships with. A bundle may return categories that
    /// are not in this list; the registry discovers them from its tools.
    public static let builtIn: [ToolCategory] = [
        .speech, .coding, .text, .everyday, .custom, .system
    ]
}
