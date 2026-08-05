import Foundation

/// A stable, human-readable identifier for a tool.
///
/// Identifiers are reverse-DNS-ish (`speech.studio`, `text.json`, `ai.commit`)
/// and are persisted in favourites, recents, window state and user-defined tool
/// files. Renaming a tool's title is free; changing its identifier is not.
public struct ToolIdentifier: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }
}

extension ToolIdentifier: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}
