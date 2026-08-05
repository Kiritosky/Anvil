import Foundation

/// Something a tool needs from the machine it runs on.
///
/// The shell uses these to explain *why* a tool is unavailable instead of
/// letting the tool fail at the moment the user presses a button.
public enum ToolRequirement: String, Hashable, Sendable, Codable, CaseIterable {
    /// Needs a language model — on-device or remote.
    case languageModel
    /// Needs the on-device model specifically (privacy-sensitive tools).
    case onDeviceLanguageModel
    /// Needs microphone access.
    case microphone
    /// Needs speech transcription assets.
    case speechRecognition
    /// Needs network access.
    case network
    /// Needs a `git` binary on `PATH`.
    case git

    public var localizedDescription: String {
        switch self {
        case .languageModel: "Sprachmodell"
        case .onDeviceLanguageModel: "On-Device-Modell"
        case .microphone: "Mikrofon"
        case .speechRecognition: "Spracherkennung"
        case .network: "Netzwerk"
        case .git: "git"
        }
    }
}

/// Everything the shell needs to know about a tool without instantiating it.
///
/// Metadata is `Sendable` and cheap: the registry holds hundreds of these,
/// searches them, and only builds a view when the user opens a tool.
public struct ToolMetadata: Hashable, Sendable, Identifiable {
    public let id: ToolIdentifier
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let category: ToolCategory
    /// Extra search terms — synonyms, English names, abbreviations.
    public let keywords: [String]
    public let requirements: Set<ToolRequirement>
    /// Shown in the sidebar next to the title, e.g. "Neu" or "Beta".
    public let badge: String?

    public init(
        id: ToolIdentifier,
        title: String,
        subtitle: String,
        systemImage: String,
        category: ToolCategory,
        keywords: [String] = [],
        requirements: Set<ToolRequirement> = [],
        badge: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.category = category
        self.keywords = keywords
        self.requirements = requirements
        self.badge = badge
    }

    /// The haystack used by the command palette and sidebar filter.
    public var searchCorpus: String {
        ([title, subtitle, category.title, id.rawValue] + keywords)
            .joined(separator: " ")
    }

    public var usesAI: Bool {
        requirements.contains(.languageModel) || requirements.contains(.onDeviceLanguageModel)
    }
}
