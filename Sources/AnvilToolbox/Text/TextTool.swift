import AnvilKit
import Foundation

/// One thing a text tool can do — "Formatieren", "Dekodieren", "SHA-256".
public struct TextToolMode: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String?
    /// Transforms input into output, or throws ``AnvilError/invalidInput(_:)``
    /// with a message the user can act on.
    public let run: @Sendable (String) throws -> String
    /// Dasselbe für Dateien, wo das etwas anderes ist als für ihren Text.
    public let runOnFiles: (@Sendable ([URL]) throws -> String)?

    public init(
        id: String,
        title: String,
        systemImage: String? = nil,
        runOnFiles: (@Sendable ([URL]) throws -> String)? = nil,
        run: @escaping @Sendable (String) throws -> String
    ) {
        self.id = id
        self.title = localized(runtime: title)
        self.systemImage = systemImage
        self.runOnFiles = runOnFiles
        self.run = run
    }
}

/// A deterministic text tool: input in, output out, no model involved.
public struct TextTool: Sendable {
    public let id: ToolIdentifier
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let category: ToolCategory
    public let keywords: [String]
    public let modes: [TextToolMode]
    /// Monospaced editors for code-shaped input: JSON, hashes, tokens.
    public let isMonospaced: Bool
    public let placeholder: String
    /// Tools like "UUID erzeugen" produce output without any input.
    public let generatesWithoutInput: Bool
    /// Ob dieses Werkzeug seinem Wesen nach mit Geheimnissen umgeht.
    public let handlesSecrets: Bool

    public init(
        id: ToolIdentifier,
        title: String,
        subtitle: String,
        systemImage: String,
        category: ToolCategory = .text,
        keywords: [String] = [],
        isMonospaced: Bool = true,
        placeholder: String = "Text hier einfügen …",
        generatesWithoutInput: Bool = false,
        handlesSecrets: Bool = false,
        modes: [TextToolMode]
    ) {
        self.handlesSecrets = handlesSecrets
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.category = category
        self.keywords = keywords
        self.isMonospaced = isMonospaced
        self.placeholder = localized(runtime: placeholder)
        self.generatesWithoutInput = generatesWithoutInput
        self.modes = modes
    }

    public var metadata: ToolMetadata {
        ToolMetadata(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            category: category,
            keywords: keywords + modes.map(\.title),
            acceptsText: true
        )
    }

    /// Runs a mode by identifier, falling back to the first one.
    public func run(_ input: String, modeID: String?) throws -> String {
        let mode = modes.first { $0.id == modeID } ?? modes[0]
        return try mode.run(input)
    }
}
