import AnvilKit
import Foundation
import FoundationModels

/// Apple's on-device model.
///
/// The default everywhere in Anvil: nothing leaves the Mac, there is no API key
/// to manage, and it is free to call. Its limits are real though — a small
/// context window and no knowledge of anything outside the prompt — which is
/// why tools chunk long input and why the router can fall back to a remote
/// provider when the user has configured one.
public struct FoundationModelsProvider: AIProvider {
    public let identifier = AIProviderIdentifier.foundationModels
    public let displayName = "Apple Intelligence (on-device)"
    public let runsOnDevice = true

    /// The on-device window is small. Kept conservative on purpose: exceeding
    /// it fails the whole call, and a tool that chunks slightly too early costs
    /// nothing.
    public let approximateInputBudget = 4_000

    public init() {}

    public func availability() async -> AIAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceDisabled)
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable(.modelNotReady):
            return .unavailable(.modelNotReady)
        case let .unavailable(other):
            return .unavailable(.other("Modell nicht verfügbar (\(other))."))
        }
    }

    public func complete(_ request: AIRequest) async throws -> String {
        let session = LanguageModelSession(instructions: request.instructions)
        do {
            let response = try await session.respond(
                to: request.prompt,
                options: Self.generationOptions(for: request.options)
            )
            return response.content
        } catch {
            throw Self.mapped(error)
        }
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let session = LanguageModelSession(instructions: request.instructions)
                do {
                    let stream = session.streamResponse(
                        to: request.prompt,
                        options: Self.generationOptions(for: request.options)
                    )
                    // Snapshots are cumulative, which is exactly the contract
                    // `AIProvider.stream` promises its callers.
                    for try await snapshot in stream {
                        try Task.checkCancellation()
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapped(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func generationOptions(for options: AIOptions) -> GenerationOptions {
        GenerationOptions(
            temperature: options.temperature,
            maximumResponseTokens: options.maximumTokens
        )
    }

    /// Turns a Foundation Models error into something a user can act on.
    ///
    /// The framework's error cases are matched on their description rather than
    /// by pattern: this file should keep compiling across framework revisions,
    /// and a slightly generic message beats a build failure.
    private static func mapped(_ error: any Error) -> AnvilError {
        if error is CancellationError { return .cancelled }

        let description = String(describing: error)
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

        if description.contains("exceededContextWindowSize") {
            return .invalidInput(
                localized("Der Text ist zu lang für das On-Device-Modell. Teile ihn auf oder wähle in den Einstellungen einen externen Anbieter.")
            )
        }
        if description.contains("guardrailViolation") || description.contains("refusal") {
            return .provider(
                "Das On-Device-Modell hat die Antwort abgelehnt.",
                underlying: detail
            )
        }
        if description.contains("assetsUnavailable") || description.contains("modelNotReady") {
            return .modelUnavailable(
                localized("Das On-Device-Modell ist gerade nicht geladen. Versuch es in einem Moment noch einmal.")
            )
        }
        if description.contains("rateLimited") {
            return .provider(
                "Zu viele Anfragen hintereinander. Kurz warten und noch einmal versuchen.",
                underlying: detail
            )
        }

        return .provider("Das On-Device-Modell konnte nicht antworten.", underlying: detail)
    }
}
