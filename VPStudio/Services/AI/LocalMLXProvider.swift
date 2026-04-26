import Foundation

/// AIProvider conformance for on-device local LLM inference via CoreML.
struct LocalMLXProvider: AIProvider, Sendable {

    let providerKind: AIProviderKind = .local

    private let inferenceEngine: LocalInferenceEngine
    private let modelID: String

    init(inferenceEngine: LocalInferenceEngine, modelID: String) {
        self.inferenceEngine = inferenceEngine
        self.modelID = modelID
    }

    func complete(system: String, userMessage: String) async throws -> AIProviderResponse {
        let result = try await inferenceEngine.generate(
            modelID: modelID,
            system: system,
            userMessage: userMessage,
            maxTokens: 4096
        )

        return AIProviderResponse(
            provider: .local,
            content: result.content,
            model: modelID,
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens
        )
    }
}
