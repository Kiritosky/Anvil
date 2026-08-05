import Foundation

/// Everything needed to reach a remote (or locally hosted) model endpoint.
///
/// Presets exist so the settings screen can be "pick Ollama, type a model name"
/// instead of asking a user to remember a URL path.
public struct RemoteConfiguration: Sendable, Codable, Equatable {
    public var presetID: String
    public var presetName: String
    public var baseURL: String
    public var model: String
    public var requiresAPIKey: Bool
    public var inputBudget: Int
    public var timeout: TimeInterval

    public init(
        presetID: String,
        presetName: String,
        baseURL: String,
        model: String,
        requiresAPIKey: Bool,
        inputBudget: Int = 40_000,
        timeout: TimeInterval = 120
    ) {
        self.presetID = presetID
        self.presetName = presetName
        self.baseURL = baseURL
        self.model = model
        self.requiresAPIKey = requiresAPIKey
        self.inputBudget = inputBudget
        self.timeout = timeout
    }

    /// `POST {baseURL}/chat/completions`
    public var chatCompletionsURL: URL {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return URL(string: trimmed + "/chat/completions") ?? URL(filePath: "/dev/null")
    }

    /// `POST {baseURL}/messages` — Anthropic's shape.
    public var messagesURL: URL {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        return URL(string: trimmed + "/messages") ?? URL(filePath: "/dev/null")
    }

    /// Whether this endpoint is served from this machine.
    public var isLocalEndpoint: Bool {
        guard let host = URL(string: baseURL)?.host() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
    }

    /// The keychain account the API key is stored under.
    public var keychainAccount: String { "provider." + presetID }

    // MARK: - Presets

    public static let ollama = RemoteConfiguration(
        presetID: "ollama",
        presetName: "Ollama (lokal)",
        baseURL: "http://localhost:11434/v1",
        model: "llama3.2",
        requiresAPIKey: false,
        inputBudget: 24_000
    )

    public static let lmStudio = RemoteConfiguration(
        presetID: "lmstudio",
        presetName: "LM Studio (lokal)",
        baseURL: "http://localhost:1234/v1",
        model: "",
        requiresAPIKey: false,
        inputBudget: 24_000
    )

    public static let openAI = RemoteConfiguration(
        presetID: "openai",
        presetName: "OpenAI",
        baseURL: "https://api.openai.com/v1",
        model: "gpt-4o-mini",
        requiresAPIKey: true,
        inputBudget: 100_000
    )

    public static let openRouter = RemoteConfiguration(
        presetID: "openrouter",
        presetName: "OpenRouter",
        baseURL: "https://openrouter.ai/api/v1",
        model: "",
        requiresAPIKey: true,
        inputBudget: 100_000
    )

    public static let anthropic = RemoteConfiguration(
        presetID: "anthropic",
        presetName: "Anthropic",
        baseURL: "https://api.anthropic.com/v1",
        model: "claude-sonnet-4-5",
        requiresAPIKey: true,
        inputBudget: 150_000
    )

    /// A blank slate for a gateway that matches none of the presets.
    public static let custom = RemoteConfiguration(
        presetID: "custom",
        presetName: "Eigener Endpunkt",
        baseURL: "",
        model: "",
        requiresAPIKey: true
    )

    public static let presets: [RemoteConfiguration] = [
        .ollama, .lmStudio, .openAI, .openRouter, .anthropic, .custom
    ]

    /// Anthropic speaks its own protocol; everything else is OpenAI-shaped.
    public var usesAnthropicProtocol: Bool { presetID == "anthropic" }
}
