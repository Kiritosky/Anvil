import AnvilKit
import Foundation

/// A remote endpoint that speaks the OpenAI chat-completions protocol.
public struct OpenAICompatibleProvider: AIProvider {
    public let identifier = AIProviderIdentifier.openAICompatible
    public var displayName: String { configuration.presetName }
    public let runsOnDevice: Bool
    public var approximateInputBudget: Int { configuration.inputBudget }

    private let configuration: RemoteConfiguration
    private let apiKey: String?
    private let session: URLSession

    public init(
        configuration: RemoteConfiguration,
        apiKey: String?,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.apiKey = apiKey
        self.session = session
        self.runsOnDevice = configuration.isLocalEndpoint
    }

    public func availability() async -> AIAvailability {
        if configuration.model.isEmpty { return .unavailable(.notConfigured) }
        if configuration.requiresAPIKey, apiKey?.isEmpty != false {
            return .unavailable(.missingCredentials)
        }
        return .available
    }

    public func complete(_ request: AIRequest) async throws -> String {
        let (data, response) = try await session.data(for: try makeRequest(request, stream: false))
        try Self.validate(response: response, data: data)

        struct Payload: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let content = payload.choices.first?.message.content
        else {
            throw AnvilError.provider(
                localized("Die Antwort von \(configuration.presetName) war nicht lesbar."),
                underlying: String(decoding: data.prefix(400), as: UTF8.self)
            )
        }
        return content
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeRequest(request, stream: true)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    try Self.validate(response: response, data: nil)

                    var accumulated = ""
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }

                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let delta = Self.decodeDelta(payload) else { continue }

                        accumulated += delta
                        continuation.yield(accumulated)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AnvilError.wrapping(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Wire format

    private func makeRequest(_ request: AIRequest, stream: Bool) throws -> URLRequest {
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": [
                ["role": "system", "content": request.instructions],
                ["role": "user", "content": request.prompt]
            ],
            "stream": stream
        ]
        if let temperature = request.options.temperature { body["temperature"] = temperature }
        if let maximum = request.options.maximumTokens { body["max_tokens"] = maximum }

        var urlRequest = URLRequest(url: configuration.chatCompletionsURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        urlRequest.timeoutInterval = configuration.timeout
        return urlRequest
    }

    private static func decodeDelta(_ payload: String) -> String? {
        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let delta: Delta?
            }
            let choices: [Choice]
        }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data)
        else { return nil }
        return chunk.choices.first?.delta?.content
    }

    private static func validate(response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let detail = data.map { String(decoding: $0.prefix(400), as: UTF8.self) }
            throw AnvilError.provider(
                localized("Der Anbieter hat mit HTTP \(http.statusCode) geantwortet."),
                underlying: detail
            )
        }
    }
}
