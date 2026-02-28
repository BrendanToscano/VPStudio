import Foundation

/// Google Gemini API provider
struct GeminiProvider: AIProvider, Sendable {
    let providerKind: AIProviderKind = .gemini
    private let apiKey: String
    private let model: String
    private let baseURL: String

    init(apiKey: String, model: String = "gemini-2.0-flash", baseURL: String = "https://generativelanguage.googleapis.com/v1beta") {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    func complete(system: String, userMessage: String) async throws -> AIProviderResponse {
        let urlString = "\(baseURL)/models/\(model):generateContent?key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw AIError.invalidResponse
        }

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": userMessage]
                    ]
                ]
            ],
            "systemInstruction": [
                "parts": [
                    ["text": system]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 4096,
                "temperature": 0.7
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }

        // Handle rate limiting
        if http.statusCode == 429 {
            throw AIError.rateLimited
        }

        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(http.statusCode, msg)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Parse Gemini response format
        let candidates = json?["candidates"] as? [[String: Any]]
        guard let content = candidates?.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String, !text.isEmpty else {
            throw AIError.invalidResponse
        }

        let usage = json?["usageMetadata"] as? [String: Any]
        let inputTokens = usage?["promptTokenCount"] as? Int ?? 0
        let outputTokens = usage?["candidatesTokenCount"] as? Int ?? 0

        return AIProviderResponse(
            provider: .gemini,
            content: text,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }
}
