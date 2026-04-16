import Foundation

/// Google Gemini API provider (Gemini 2.5 Flash, Gemini 2.5 Pro, etc.)
struct GeminiProvider: AIProvider, Sendable {
    let providerKind: AIProviderKind = .gemini
    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let sleep: AIHTTPSleep

    init(
        apiKey: String,
        model: String = "gemini-2.5-flash",
        session: URLSession = AIHTTPTransport.defaultSession,
        sleep: @escaping AIHTTPSleep = AIHTTPTransport.defaultSleep
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
        self.sleep = sleep
    }

    func complete(system: String, userMessage: String) async throws -> AIProviderResponse {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else { throw AIError.invalidResponse }

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": system]]
            ],
            "contents": [
                ["parts": [["text": userMessage]]]
            ],
            "generationConfig": [
                "maxOutputTokens": 4096
            ]
        ]

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw AIError.invalidResponse }

        var components = URLComponents(string: "https://generativelanguage.googleapis.com")
        components?.path = "/v1beta/models/\(trimmedModel):generateContent"
        guard let url = components?.url else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await AIHTTPTransport.perform(request, using: session, sleep: sleep)
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(http.statusCode, msg)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let parts = (candidates?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
        guard let content = parts?.first?["text"] as? String, !content.isEmpty else {
            throw AIError.invalidResponse
        }
        let usage = json?["usageMetadata"] as? [String: Any]
        let inputTokens = usage?["promptTokenCount"] as? Int ?? 0
        let outputTokens = usage?["candidatesTokenCount"] as? Int ?? 0

        return AIProviderResponse(
            provider: .gemini,
            content: content,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}
