import AnvilKit
import Foundation
import Observation

/// How Anvil chooses between the on-device model and a remote one.
public enum AIPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Never send text off this Mac. Tools fail rather than fall back.
    case onDeviceOnly
    /// On-device first; use the configured remote provider only when the
    /// on-device model cannot run.
    case preferOnDevice
    /// Remote first — for long input or when a stronger model is wanted.
    case preferRemote

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .onDeviceOnly: localized("Nur on-device")
        case .preferOnDevice: localized("On-device bevorzugt")
        case .preferRemote: localized("Extern bevorzugt")
        }
    }

    public var explanation: String {
        switch self {
        case .onDeviceOnly:
            localized("Nichts verlässt diesen Mac. Ohne Apple Intelligence bleiben KI-Tools aus.")
        case .preferOnDevice:
            localized("Erst das Apple-Modell. Nur wenn das nicht kann, geht es an den externen Anbieter.")
        case .preferRemote:
            localized("Erst der externe Anbieter, das Apple-Modell als Rückfallebene.")
        }
    }

    public var systemImage: String {
        switch self {
        case .onDeviceOnly: "lock.laptopcomputer"
        case .preferOnDevice: "laptopcomputer"
        case .preferRemote: "cloud"
        }
    }

    public var allowsRemote: Bool { self != .onDeviceOnly }
}

/// Picks a provider and runs requests against it.
///
/// Tools never construct a provider themselves — they ask the router. That is
/// what makes the privacy policy a single setting rather than a promise spread
/// across twenty tools.
@MainActor
@Observable
public final class AIRouter {
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let keychain: KeychainStore

    /// Last known availability of the provider the policy currently selects.
    public private(set) var availability: AIAvailability = .unavailable(.modelNotReady)
    /// The provider the last resolution settled on, for display.
    public private(set) var activeProviderName: String = "—"
    public private(set) var activeRunsOnDevice: Bool = true
    public private(set) var isRefreshing = false

    public init(settings: SettingsStore, keychain: KeychainStore = KeychainStore()) {
        self.settings = settings
        self.keychain = keychain
    }

    // MARK: - Configuration

    public var policy: AIPolicy {
        get { settings[.aiPolicy] }
        set {
            settings[.aiPolicy] = newValue
            Task { await refreshAvailability() }
        }
    }

    public var remoteConfiguration: RemoteConfiguration {
        get { settings[.remoteConfiguration] }
        set {
            settings[.remoteConfiguration] = newValue
            Task { await refreshAvailability() }
        }
    }

    public func apiKey(for configuration: RemoteConfiguration? = nil) -> String? {
        keychain.secret(for: (configuration ?? remoteConfiguration).keychainAccount)
    }

    public func setAPIKey(_ key: String?, for configuration: RemoteConfiguration? = nil) throws {
        try keychain.setSecret(key, for: (configuration ?? remoteConfiguration).keychainAccount)
        Task { await refreshAvailability() }
    }

    // MARK: - Providers

    public var onDeviceProvider: any AIProvider { FoundationModelsProvider() }

    public var remoteProvider: (any AIProvider)? {
        let configuration = remoteConfiguration
        guard !configuration.baseURL.isEmpty else { return nil }
        let key = apiKey(for: configuration)

        return configuration.usesAnthropicProtocol
            ? AnthropicProvider(configuration: configuration, apiKey: key)
            : OpenAICompatibleProvider(configuration: configuration, apiKey: key)
    }

    /// Resolves the provider to use for the next call.
    ///
    /// - Parameter inputLength: characters of input. A long input can push the
    ///   router to the remote provider even under `.preferOnDevice`, because the
    ///   on-device context window would reject it outright.
    public func resolveProvider(inputLength: Int = 0) async throws -> any AIProvider {
        let onDevice = onDeviceProvider
        let remote = policy.allowsRemote ? remoteProvider : nil

        let exceedsOnDeviceBudget = inputLength > onDevice.approximateInputBudget
        let ordered: [any AIProvider]

        switch policy {
        case .onDeviceOnly:
            ordered = [onDevice]
        case .preferOnDevice:
            ordered = exceedsOnDeviceBudget
                ? [remote, onDevice].compactMap { $0 }
                : [onDevice, remote].compactMap { $0 }
        case .preferRemote:
            ordered = [remote, onDevice].compactMap { $0 }
        }

        var firstReason: AIUnavailableReason?
        for provider in ordered {
            let availability = await provider.availability()
            if availability.isAvailable {
                record(provider: provider, availability: .available)
                return provider
            }
            if firstReason == nil { firstReason = availability.reason }
        }

        let reason = firstReason ?? .notConfigured
        record(provider: ordered.first, availability: .unavailable(reason))
        throw AnvilError.modelUnavailable(reason.message)
    }

    private func record(provider: (any AIProvider)?, availability: AIAvailability) {
        self.availability = availability
        activeProviderName = provider?.displayName ?? "—"
        activeRunsOnDevice = provider?.runsOnDevice ?? true
    }

    // MARK: - Running

    public func run(_ request: AIRequest) async throws -> String {
        let provider = try await resolveProvider(inputLength: request.prompt.count)
        return try await provider.complete(request)
    }

    /// Streams a response, yielding the cumulative text so far.
    public func stream(_ request: AIRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let provider = try await resolveProvider(inputLength: request.prompt.count)
                    for try await snapshot in provider.stream(request) {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AnvilError.wrapping(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// How much input the currently selected provider can take, in characters.
    public func inputBudget() async -> Int {
        if let provider = try? await resolveProvider() {
            return provider.approximateInputBudget
        }
        return onDeviceProvider.approximateInputBudget
    }

    // MARK: - Status

    @discardableResult
    public func refreshAvailability() async -> AIAvailability {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            _ = try await resolveProvider()
        } catch {
            // `resolveProvider` has already recorded the reason.
        }
        return availability
    }

    /// A one-line summary for the status bar and the settings screen.
    public var statusSummary: String {
        switch availability {
        case .available:
            activeRunsOnDevice ? localized("\(activeProviderName) · lokal") : activeProviderName
        case let .unavailable(reason):
            reason.message
        }
    }
}

// MARK: - Settings keys

extension SettingKey {
    public static var aiPolicy: SettingKey<AIPolicy> {
        SettingKey<AIPolicy>("aiPolicy", default: .preferOnDevice)
    }

    public static var remoteConfiguration: SettingKey<RemoteConfiguration> {
        SettingKey<RemoteConfiguration>("remoteConfiguration", default: .ollama)
    }
}

// MARK: - Tool context

extension ToolContext {
    /// The router, registered by the app at launch.
    public var ai: AIRouter { require(AIRouter.self) }
}
