import AnvilKit
import Foundation

/// Identifies a language-model backend.
public struct AIProviderIdentifier: Hashable, Sendable, Codable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    /// Apple's on-device model via the Foundation Models framework.
    public static let foundationModels = AIProviderIdentifier("foundation")
    /// Anything speaking the OpenAI chat-completions protocol — OpenAI itself,
    /// Ollama, LM Studio, OpenRouter, a self-hosted gateway.
    public static let openAICompatible = AIProviderIdentifier("openai")
    /// Anthropic's Messages API.
    public static let anthropic = AIProviderIdentifier("anthropic")
}

/// Why a provider cannot be used right now.
public enum AIUnavailableReason: Sendable, Equatable {
    case appleIntelligenceDisabled
    case deviceNotEligible
    case modelNotReady
    case missingCredentials
    case notConfigured
    case other(String)

    public var message: String {
        switch self {
        case .appleIntelligenceDisabled:
            localized("Apple Intelligence ist auf diesem Mac nicht eingeschaltet.")
        case .deviceNotEligible:
            localized("Dieser Mac unterstützt das On-Device-Modell nicht.")
        case .modelNotReady:
            localized("Das Modell wird noch geladen. Versuch es gleich noch einmal.")
        case .missingCredentials:
            localized("Für diesen Anbieter fehlt der API-Schlüssel.")
        case .notConfigured:
            localized("Dieser Anbieter ist noch nicht eingerichtet.")
        case let .other(text):
            text
        }
    }

    /// Whether the user can fix this themselves in Settings.
    public var isUserFixable: Bool {
        switch self {
        case .deviceNotEligible: false
        default: true
        }
    }
}

public enum AIAvailability: Sendable, Equatable {
    case available
    case unavailable(AIUnavailableReason)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var reason: AIUnavailableReason? {
        if case let .unavailable(reason) = self { return reason }
        return nil
    }
}

/// Knobs the caller may set per request.
public struct AIOptions: Sendable, Equatable {
    /// 0 = deterministic, 1 = creative. `nil` uses the provider default.
    public var temperature: Double?
    public var maximumTokens: Int?

    public init(temperature: Double? = nil, maximumTokens: Int? = nil) {
        self.temperature = temperature
        self.maximumTokens = maximumTokens
    }

    /// For rewriting and cleanup, where invention is the enemy.
    public static let precise = AIOptions(temperature: 0.1)
    /// For drafting and brainstorming.
    public static let creative = AIOptions(temperature: 0.8)
    public static let `default` = AIOptions()
}

/// One turn of work for a model.
///
/// Deliberately single-shot: every tool in the app is "take this text, produce
/// that text". Chat history, when a tool needs it, is that tool's business.
public struct AIRequest: Sendable {
    /// The standing role description. Stays constant across calls in a tool.
    public var instructions: String
    /// The actual input for this call.
    public var prompt: String
    public var options: AIOptions

    public init(instructions: String, prompt: String, options: AIOptions = .default) {
        self.instructions = instructions
        self.prompt = prompt
        self.options = options
    }
}

/// A language-model backend.
///
/// Providers are value-like and cheap to create; configuration lives in
/// ``AIRouter``. Anything conforming to this can be dropped into the router,
/// which is how a future local llama.cpp or a company gateway gets added
/// without touching a single tool.
public protocol AIProvider: Sendable {
    var identifier: AIProviderIdentifier { get }
    var displayName: String { get }
    /// Whether inference happens on this Mac. Drives the privacy badge in the UI.
    var runsOnDevice: Bool { get }
    /// Roughly how much input the model accepts, in characters. Used to decide
    /// when a tool has to split its input into chunks.
    var approximateInputBudget: Int { get }

    func availability() async -> AIAvailability

    /// Produces the whole answer at once.
    func complete(_ request: AIRequest) async throws -> String

    /// Produces the answer incrementally.
    ///
    /// Each element is the *cumulative* text so far, not a delta, so a view can
    /// bind straight to the latest value without accumulating anything itself.
    func stream(_ request: AIRequest) -> AsyncThrowingStream<String, any Error>
}

extension AIProvider {
    public var approximateInputBudget: Int { 12_000 }

    /// Providers that cannot stream get a one-shot stream for free.
    public func stream(_ request: AIRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let text = try await complete(request)
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AnvilError.wrapping(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
