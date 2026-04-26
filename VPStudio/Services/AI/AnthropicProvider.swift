import Foundation

/// Anthropic Claude API provider
struct AnthropicProvider: AIProvider, Sendable {
    let providerKind: AIProviderKind = .anthropic
    private let apiKey: String
    private let model: String
    private let baseURL: String
    private let session: URLSession
    private let sleep: AIHTTPSleep

    init(
        apiKey: String,
        model: String = "claude-sonnet-4-6",
        baseURL: String = "https://api.anthropic.com/v1/messages",
        session: URLSession = AIHTTPTransport.defaultSession,
        sleep: @escaping AIHTTPSleep = AIHTTPTransport.defaultSleep
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = session
        self.sleep = sleep
    }

    func complete(system: String, userMessage: String) async throws -> AIProviderResponse {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty, !trimmedModel.isEmpty else {
            throw AIError.invalidResponse
        }

        let body: [String: Any] = [
            "model": trimmedModel,
            "max_tokens": 4096,
            "system": system,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        guard let url = URL(string: baseURL) else {
            throw AIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await AIHTTPTransport.perform(request, using: session, sleep: sleep)

        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(http.statusCode, msg)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = (json?["content"] as? [[String: Any]])?.first?["text"] as? String, !content.isEmpty else {
            throw AIError.invalidResponse
        }
        let usage = json?["usage"] as? [String: Any]
        let inputTokens = usage?["input_tokens"] as? Int ?? 0
        let outputTokens = usage?["output_tokens"] as? Int ?? 0

        return AIProviderResponse(
            provider: .anthropic,
            content: content,
            model: trimmedModel,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}
