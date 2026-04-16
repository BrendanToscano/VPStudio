import CoreML
import Foundation
import Hub
import Tokenizers

// MARK: - Adapter Protocol

protocol LocalInferenceAdapting: Sendable {
    func loadModel(from directory: URL) async throws -> LoadedLocalModel
    func generate(
        model: LoadedLocalModel,
        system: String,
        userMessage: String,
        maxTokens: Int
    ) async throws -> LocalGenerationResult
}

// MARK: - Result Types

final class LoadedLocalModel: @unchecked Sendable {
    let coreMLModel: MLModel
    let tokenizer: any Tokenizers.Tokenizer
    let modelID: String

    init(coreMLModel: MLModel, tokenizer: any Tokenizers.Tokenizer, modelID: String) {
        self.coreMLModel = coreMLModel
        self.tokenizer = tokenizer
        self.modelID = modelID
    }
}

struct LocalGenerationResult: Sendable {
    let content: String
    let inputTokens: Int
    let outputTokens: Int
}

// MARK: - CoreML Implementation

struct CoreMLInferenceAdapter: LocalInferenceAdapting {

    func loadModel(from directory: URL) async throws -> LoadedLocalModel {
        // Find .mlmodelc or .mlpackage in directory
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let modelURL = contents.first(where: {
            $0.pathExtension == "mlmodelc" || $0.pathExtension == "mlpackage"
        }) else {
            throw LocalInferenceError.inferenceError("No CoreML model found in \(directory.lastPathComponent)")
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try await MLModel.load(contentsOf: modelURL, configuration: config)

        // Load tokenizer from same directory
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory, hubApi: HubApi.shared)

        return LoadedLocalModel(
            coreMLModel: model,
            tokenizer: tokenizer,
            modelID: directory.lastPathComponent
        )
    }

    func generate(
        model: LoadedLocalModel,
        system: String,
        userMessage: String,
        maxTokens: Int
    ) async throws -> LocalGenerationResult {
        let prompt = "<|system|>\n\(system)<|end|>\n<|user|>\n\(userMessage)<|end|>\n<|assistant|>\n"
        let inputTokens = model.tokenizer.encode(text: prompt)
        var tokens = inputTokens
        var generatedCount = 0

        for _ in 0..<maxTokens {
            try Task.checkCancellation()

            let inputArray = try MLMultiArray(shape: [1, NSNumber(value: tokens.count)], dataType: .int32)
            for (i, token) in tokens.enumerated() {
                inputArray[i] = NSNumber(value: token)
            }

            let input = try MLDictionaryFeatureProvider(dictionary: ["input_ids": inputArray])
            let output = try await model.coreMLModel.prediction(from: input)

            guard let logits = output.featureValue(for: "logits")?.multiArrayValue else {
                break
            }

            // Greedy decode: take argmax of last position
            let vocabSize = logits.shape.last!.intValue
            let lastPos = tokens.count - 1
            var maxIdx = 0
            var maxVal = Float(-1e9)
            for v in 0..<vocabSize {
                let idx = lastPos * vocabSize + v
                let val = logits[idx].floatValue
                if val > maxVal {
                    maxVal = val
                    maxIdx = v
                }
            }

            // Check for EOS
            if let eosToken = model.tokenizer.eosToken,
               let eosId = model.tokenizer.convertTokenToId(eosToken),
               maxIdx == eosId {
                break
            }

            tokens.append(maxIdx)
            generatedCount += 1
        }

        let outputTokens = Array(tokens.suffix(generatedCount))
        let text = model.tokenizer.decode(tokens: outputTokens)

        return LocalGenerationResult(
            content: text,
            inputTokens: inputTokens.count,
            outputTokens: generatedCount
        )
    }
}

// MARK: - Model Downloader

enum LocalModelDownloader {
    /// Downloads a HuggingFace model repo snapshot to local storage.
    static func download(
        repoID: String,
        to directory: URL,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let repo = Hub.Repo(id: repoID)
        return try await HubApi.shared.snapshot(
            from: repo,
            matching: ["*.mlmodelc/*", "*.mlpackage/*", "*.json", "*.jinja", "tokenizer*"],
            progressHandler: progressHandler
        )
    }
}
