import Foundation

/// OpenAI API provider (GPT-5, GPT-4o, etc.)
struct OpenAIProvider: AIProvider, Sendable {
    let providerKind: AIProviderKind = .openAI
    private let apiKey: String
    private let model: String
    private let baseURL: String

    init(apiKey: String, model: String = "gpt-5.2", baseURL: String = "https://api.openai.com/v1/chat/completions") {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    func complete(system: String, userMessage: String) async throws -> AIProviderResponse {
        let body: [String: Any] = [
            "model": model,
            "max_completion_tokens": 4096,
            "messages": [
                ["role": "system", "content": system],
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }

        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(http.statusCode, msg)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        guard let content = (choices?.first?["message"] as? [String: Any])?["content"] as? String, !content.isEmpty else {
            throw AIError.invalidResponse
        }
        let usage = json?["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0

        return AIProviderResponse(
            provider: .openAI,
            content: content,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}
