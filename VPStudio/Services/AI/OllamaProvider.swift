import Foundation

/// Ollama local LLM provider
struct OllamaProvider: AIProvider, Sendable {
    let providerKind: AIProviderKind = .ollama
    private let baseURL: String
    private let model: String

    init(baseURL: String = "http://localhost:11434", model: String = "llama3.1") {
        self.baseURL = baseURL
        self.model = model
    }

    func complete(system: String, userMessage: String) async throws -> AIProviderResponse {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userMessage]
            ]
        ]

        guard let url = URL(string: "\(baseURL)/api/chat") else { throw AIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120 // Ollama can be slow

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }

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
            model: model,
            inputTokens: 0,
            outputTokens: 0
        )
    }
}
