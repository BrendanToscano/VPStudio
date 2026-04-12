import Foundation

/// Ollama local LLM provider
struct OllamaProvider: AIProvider, Sendable {
    let providerKind: AIProviderKind = .ollama
    private let baseURL: String
    private let model: String
    private let session: URLSession
    private let sleep: AIHTTPSleep

    init(
        baseURL: String = "http://localhost:11434",
        model: String = "llama3.1",
        session: URLSession = AIHTTPTransport.defaultSession,
        sleep: @escaping AIHTTPSleep = AIHTTPTransport.defaultSleep
    ) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
        self.sleep = sleep
    }

    func complete(system: String, userMessage: String) async throws -> AIProviderResponse {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty, !trimmedModel.isEmpty else {
            throw AIError.invalidResponse
        }

        let body: [String: Any] = [
            "model": trimmedModel,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userMessage]
            ]
        ]

        guard let url = URL(string: "\(trimmedBaseURL)/api/chat") else { throw AIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120 // Ollama can be slow

        let (data, http) = try await AIHTTPTransport.perform(request, using: session, sleep: sleep)

        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(http.statusCode, msg)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = json?["message"] as? [String: Any]
        guard let content = message?["content"] as? String, !content.isEmpty else {
            throw AIError.invalidResponse
        }

        return AIProviderResponse(
            provider: .ollama,
            content: content,
            model: trimmedModel,
            inputTokens: 0,
            outputTokens: 0
        )
    }
}
