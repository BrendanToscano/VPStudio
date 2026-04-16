import Foundation

/// OpenAI API provider (Responses API; GPT-5.4, GPT-4o, etc.)
struct OpenAIProvider: AIProvider, Sendable {
    let providerKind: AIProviderKind = .openAI
    private let apiKey: String
    private let model: String
    private let baseURL: String
    private let session: URLSession
    private let sleep: AIHTTPSleep

    private static let defaultResponsesURL = "https://api.openai.com/v1/responses"

    init(
        apiKey: String,
        model: String = "gpt-5.4",
        baseURL: String = Self.defaultResponsesURL,
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
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, !model.isEmpty else {
            throw AIError.invalidResponse
        }

        guard let url = URL(string: baseURL) else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = try JSONSerialization.data(
            withJSONObject: requestBody(system: system, userMessage: userMessage)
        )
        request.httpBody = body

        let (data, http) = try await AIHTTPTransport.perform(request, using: session, sleep: sleep)

        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AIError.httpError(http.statusCode, msg)
        }

        let result = try parseResponse(data: data)
        return AIProviderResponse(
            provider: .openAI,
            content: result.content,
            model: model,
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens
        )
    }

    private func requestBody(system: String, userMessage: String) -> [String: Any] {
        let model = self.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpointStyle == .chatCompletions {
            return [
                "model": model,
                "max_completion_tokens": 4096,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": userMessage]
                ]
            ]
        }

        return [
            "model": model,
            "instructions": system,
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": userMessage
                        ]
                    ]
                ]
            ],
            "max_output_tokens": 4096
        ]
    }

    private func parseResponse(data: Data) throws -> (content: String, inputTokens: Int, outputTokens: Int) {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if endpointStyle == .chatCompletions {
            let choices = json?["choices"] as? [[String: Any]]
            guard let content = (choices?.first?["message"] as? [String: Any])?["content"] as? String,
                  !content.isEmpty else {
                throw AIError.invalidResponse
            }
            let usage = json?["usage"] as? [String: Any]
            return (
                content,
                usage?["prompt_tokens"] as? Int ?? 0,
                usage?["completion_tokens"] as? Int ?? 0
            )
        }

        if let outputText = json?["output_text"] as? String, !outputText.isEmpty {
            let usage = json?["usage"] as? [String: Any]
            return (
                outputText,
                usage?["input_tokens"] as? Int ?? 0,
                usage?["output_tokens"] as? Int ?? 0
            )
        }

        let output = json?["output"] as? [[String: Any]]
        let messageContent = output?
            .filter { ($0["type"] as? String) == "message" }
            .compactMap { $0["content"] as? [[String: Any]] }
            .flatMap { items in
                items.compactMap { $0["text"] as? String }
            }
            .joined()

        guard let content = messageContent, !content.isEmpty else {
            throw AIError.invalidResponse
        }

        let usage = json?["usage"] as? [String: Any]
        return (
            content,
            usage?["input_tokens"] as? Int ?? usage?["prompt_tokens"] as? Int ?? 0,
            usage?["output_tokens"] as? Int ?? usage?["completion_tokens"] as? Int ?? 0
        )
    }

    private var endpointStyle: EndpointStyle {
        guard let url = URL(string: baseURL) else { return .responses }
        return url.path.contains("chat/completions") ? .chatCompletions : .responses
    }

    private enum EndpointStyle {
        case responses
        case chatCompletions
    }
}
