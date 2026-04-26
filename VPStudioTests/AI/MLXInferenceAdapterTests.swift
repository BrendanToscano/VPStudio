import Foundation
import Testing
@testable import VPStudio

@Suite("CoreML Inference Adapter")
struct MLXInferenceAdapterTests {
    @Test
    func modelArtifactURLFindsCompiledModelBundle() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let modelBundle = tempDir.appendingPathComponent("Model.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: modelBundle, withIntermediateDirectories: true)

        let selected = try CoreMLInferenceAdapter.modelArtifactURL(in: tempDir)
        #expect(selected?.lastPathComponent == modelBundle.lastPathComponent)
        #expect(selected?.pathExtension == "mlmodelc")
    }

    @Test
    func modelArtifactURLFindsModelPackageBundle() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let modelPackage = tempDir.appendingPathComponent("Model.mlpackage", isDirectory: true)
        try FileManager.default.createDirectory(at: modelPackage, withIntermediateDirectories: true)

        let selected = try CoreMLInferenceAdapter.modelArtifactURL(in: tempDir)
        #expect(selected?.lastPathComponent == modelPackage.lastPathComponent)
        #expect(selected?.pathExtension == "mlpackage")
    }

    @Test
    func modelArtifactURLIgnoresTokenizerAndMetadataFiles() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "metadata".write(
            to: tempDir.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )
        try "tokenizer".write(
            to: tempDir.appendingPathComponent("tokenizer.json"),
            atomically: true,
            encoding: .utf8
        )

        #expect(try CoreMLInferenceAdapter.modelArtifactURL(in: tempDir) == nil)
    }

    @Test
    func promptUsesExpectedChatTemplateSeparators() {
        let prompt = CoreMLInferenceAdapter.prompt(
            system: "Be concise.",
            userMessage: "Recommend something."
        )

        #expect(prompt == "<|system|>\nBe concise.<|end|>\n<|user|>\nRecommend something.<|end|>\n<|assistant|>\n")
    }

    @Test
    func downloaderPatternsIncludeModelTokenizerAndTemplateAssets() {
        #expect(LocalModelDownloader.snapshotMatchingPatterns.contains("*.mlmodelc/*"))
        #expect(LocalModelDownloader.snapshotMatchingPatterns.contains("*.mlpackage/*"))
        #expect(LocalModelDownloader.snapshotMatchingPatterns.contains("*.json"))
        #expect(LocalModelDownloader.snapshotMatchingPatterns.contains("*.jinja"))
        #expect(LocalModelDownloader.snapshotMatchingPatterns.contains("tokenizer*"))
    }

    @Test
    func loadModelFromDirectoryWithoutCoreMLBundleThrowsInferenceError() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let adapter = CoreMLInferenceAdapter()

        do {
            _ = try await adapter.loadModel(from: tempDir)
            Issue.record("Expected missing CoreML bundle to throw")
        } catch LocalInferenceError.inferenceError(let message) {
            #expect(message.contains("No CoreML model found"))
            #expect(message.contains(tempDir.lastPathComponent))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func loadModelWithInvalidCoreMLBundlePropagatesLoadFailure() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let invalidBundle = tempDir.appendingPathComponent("Broken.mlmodelc", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidBundle, withIntermediateDirectories: true)

        let adapter = CoreMLInferenceAdapter()

        do {
            _ = try await adapter.loadModel(from: tempDir)
            Issue.record("Expected invalid CoreML bundle to throw")
        } catch LocalInferenceError.inferenceError {
            Issue.record("Expected CoreML load failure, not missing-bundle wrapper")
        } catch {
            #expect(String(describing: error).isEmpty == false)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
}
