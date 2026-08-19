import AnvilKit
import Foundation

/// Anthropic's Messages API.
public struct AnthropicProvider: AIProvider {
    public let identifier = AIProviderIdentifier.anthropic
    public var displayName: String { configuration.presetName }
    public let runsOnDevice = false
    public var approximateInputBudget: Int { configuration.inputBudget }

    /// The API rejects requests without a limit, so there has to be a default.
    private static let defaultMaximumTokens = 4_096
    private static let apiVersion = "2023-06-01"

    private let configuration: RemoteConfiguration
    private let apiKey: String?
    private let session: URLSession

    public init(configuration: RemoteConfiguration, apiKey: String?, session: URLSession = .shared) {
        self.configuration = configuration
        self.apiKey = apiKey
        self.session = session
    }

    public func availability() async -> AIAvailability {
        if configuration.model.isEmpty { return .unavailable(.notConfigured) }
        if apiKey?.isEmpty != false { return .unavailable(.missingCredentials) }
        return .available
    }

    public func complete(_ request: AIRequest) async throws -> String {
        let (data, response) = try await session.data(for: try makeRequest(request, stream: false))
        try Self.validate(response: response, data: data)

        struct Payload: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let content: [Block]
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw AnvilError.provider(
                localized("Die Antwort von Anthropic war nicht lesbar."),
                underlying: String(decoding: data.prefix(400), as: UTF8.self)
            )
        }
        return payload.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
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
            "max_tokens": request.options.maximumTokens ?? Self.defaultMaximumTokens,
            "system": request.instructions,
            "messages": [["role": "user", "content": request.prompt]],
            "stream": stream
        ]
        if let temperature = request.options.temperature { body["temperature"] = temperature }

        var urlRequest = URLRequest(url: configuration.messagesURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if let apiKey, !apiKey.isEmpty {
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        urlRequest.timeoutInterval = configuration.timeout
        return urlRequest
    }

    private static func decodeDelta(_ payload: String) -> String? {
        struct Event: Decodable {
            struct Delta: Decodable { let text: String? }
            let type: String
            let delta: Delta?
        }
        guard let data = payload.data(using: .utf8),
              let event = try? JSONDecoder().decode(Event.self, from: data),
              event.type == "content_block_delta"
        else { return nil }
        return event.delta?.text
    }

    private static func validate(response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let detail = data.map { String(decoding: $0.prefix(400), as: UTF8.self) }
            throw AnvilError.provider(
                localized("Anthropic hat mit HTTP \(http.statusCode) geantwortet."),
                underlying: detail
            )
        }
    }
}
