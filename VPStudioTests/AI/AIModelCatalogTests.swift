import Foundation
import Testing
@testable import VPStudio

// MARK: - Model Catalog Tests

@Suite("AIModelCatalog")
struct AIModelCatalogTests {

    // MARK: - Cost Calculation Accuracy

    @Test func costCalculationForClaudeSonnet4() {
        // 1000 input tokens at $3/1M = $0.003
        // 500 output tokens at $15/1M = $0.0075
        let cost = AIModelCatalog.estimateCost(
            modelID: "claude-sonnet-4-20250514",
            inputTokens: 1000,
            outputTokens: 500
        )
        #expect(abs(cost - 0.0105) < 0.000001)
    }

    @Test func costCalculationForClaudeOpus4() {
        // 1000 input at $15/1M = $0.015
        // 1000 output at $75/1M = $0.075
        let cost = AIModelCatalog.estimateCost(
            modelID: "claude-opus-4-20250514",
            inputTokens: 1000,
            outputTokens: 1000
        )
        #expect(abs(cost - 0.09) < 0.000001)
    }

    @Test func costCalculationForClaudeHaiku35() {
        // 10000 input at $0.80/1M = $0.008
        // 5000 output at $4/1M = $0.02
        let cost = AIModelCatalog.estimateCost(
            modelID: "claude-3-5-haiku-20241022",
            inputTokens: 10_000,
            outputTokens: 5_000
        )
        #expect(abs(cost - 0.028) < 0.000001)
    }

    @Test func costCalculationForGPT4o() {
        // 2000 input at $2.50/1M = $0.005
        // 1000 output at $10/1M = $0.01
        let cost = AIModelCatalog.estimateCost(
            modelID: "gpt-4o",
            inputTokens: 2_000,
            outputTokens: 1_000
        )
        #expect(abs(cost - 0.015) < 0.000001)
    }

    @Test func costCalculationForGPT4oMini() {
        // 10000 input at $0.15/1M = $0.0015
        // 5000 output at $0.60/1M = $0.003
        let cost = AIModelCatalog.estimateCost(
            modelID: "gpt-4o-mini",
            inputTokens: 10_000,
            outputTokens: 5_000
        )
        #expect(abs(cost - 0.0045) < 0.000001)
    }

    @Test func costCalculationForO1() {
        // 1000 input at $15/1M = $0.015
        // 1000 output at $60/1M = $0.06
        let cost = AIModelCatalog.estimateCost(
            modelID: "o1",
            inputTokens: 1_000,
            outputTokens: 1_000
        )
        #expect(abs(cost - 0.075) < 0.000001)
    }

    @Test func costCalculationForClaudeOpus46() {
        // 1000 input at $15/1M = $0.015
        // 1000 output at $75/1M = $0.075
        let cost = AIModelCatalog.estimateCost(
            modelID: "claude-opus-4-6",
            inputTokens: 1000,
            outputTokens: 1000
        )
        #expect(abs(cost - 0.09) < 0.000001)
    }

    @Test func costCalculationForClaudeSonnet46() {
        // 1000 input at $3/1M = $0.003
        // 500 output at $15/1M = $0.0075
        let cost = AIModelCatalog.estimateCost(
            modelID: "claude-sonnet-4-6",
            inputTokens: 1000,
            outputTokens: 500
        )
        #expect(abs(cost - 0.0105) < 0.000001)
    }

    @Test func costCalculationForGPT5() {
        // 2000 input at $5/1M = $0.01
        // 1000 output at $15/1M = $0.015
        let cost = AIModelCatalog.estimateCost(
            modelID: "gpt-5",
            inputTokens: 2_000,
            outputTokens: 1_000
        )
        #expect(abs(cost - 0.025) < 0.000001)
    }

    @Test func costCalculationForGPT52() {
        // 5000 input at $2/1M = $0.01
        // 2000 output at $8/1M = $0.016
        let cost = AIModelCatalog.estimateCost(
            modelID: "gpt-5.2",
            inputTokens: 5_000,
            outputTokens: 2_000
        )
        #expect(abs(cost - 0.026) < 0.000001)
    }

    @Test func costCalculationForOllamaIsZero() {
        let cost = AIModelCatalog.estimateCost(
            modelID: "llama3.1",
            inputTokens: 100_000,
            outputTokens: 50_000
        )
        #expect(cost == 0)
    }

    @Test func costCalculationForAllOllamaModelsIsZero() {
        for model in AIModelCatalog.models(for: .ollama) {
            let cost = AIModelCatalog.estimateCost(
                model: model,
                inputTokens: 1_000_000,
                outputTokens: 1_000_000
            )
            #expect(cost == 0, "Expected zero cost for Ollama model \(model.id)")
        }
    }

    @Test func costCalculationForZeroTokens() {
        let cost = AIModelCatalog.estimateCost(
            modelID: "claude-sonnet-4-20250514",
            inputTokens: 0,
            outputTokens: 0
        )
        #expect(cost == 0)
    }

    @Test func costCalculationForUnknownModelReturnsZero() {
        let cost = AIModelCatalog.estimateCost(
            modelID: "nonexistent-model-v99",
            inputTokens: 10_000,
            outputTokens: 5_000
        )
        #expect(cost == 0)
    }

    @Test func costCalculationViaModelDefinition() {
        let model = AIModelCatalog.claudeSonnet4
        let cost = AIModelCatalog.estimateCost(
            model: model,
            inputTokens: 1_000_000,
            outputTokens: 1_000_000
        )
        // $3 input + $15 output = $18
        #expect(abs(cost - 18.0) < 0.000001)
    }

    // MARK: - Model Lookup by Provider

    @Test func anthropicModelsReturnCorrectCount() {
        let models = AIModelCatalog.models(for: .anthropic)
        #expect(models.count == 5)
    }

    @Test func openAIModelsReturnCorrectCount() {
        let models = AIModelCatalog.models(for: .openAI)
        #expect(models.count == 5)
    }

    @Test func ollamaModelsReturnCorrectCount() {
        let models = AIModelCatalog.models(for: .ollama)
        #expect(models.count == 3)
    }

    @Test func allModelsHaveCorrectProvider() {
        for model in AIModelCatalog.allModels {
            let providerModels = AIModelCatalog.models(for: model.provider)
            #expect(providerModels.contains(where: { $0.id == model.id }))
        }
    }

    @Test func allModelsHaveNonEmptyDisplayNames() {
        for model in AIModelCatalog.allModels {
            #expect(!model.displayName.isEmpty, "Model \(model.id) has empty displayName")
        }
    }

    @Test func allModelsHavePositiveContextWindow() {
        for model in AIModelCatalog.allModels {
            #expect(model.maxContextTokens > 0, "Model \(model.id) has non-positive context window")
        }
    }

    @Test func allModelIDsAreUnique() {
        let ids = AIModelCatalog.allModels.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count)
    }

    // MARK: - Default Model Selection

    @Test func defaultAnthropicModelIsSonnet46() {
        let def = AIModelCatalog.defaultModel(for: .anthropic)
        #expect(def?.id == "claude-sonnet-4-6")
    }

    @Test func defaultOpenAIModelIsGPT52() {
        let def = AIModelCatalog.defaultModel(for: .openAI)
        #expect(def?.id == "gpt-5.2")
    }

    @Test func defaultOllamaModelIsLlama31() {
        let def = AIModelCatalog.defaultModel(for: .ollama)
        #expect(def?.id == "llama3.1")
    }

    @Test func eachProviderHasExactlyOneDefault() {
        for provider in AIProviderKind.allCases {
            let providerModels = AIModelCatalog.models(for: provider)
            let defaults = providerModels.filter(\.isDefault)
            #expect(defaults.count == 1, "Provider \(provider.rawValue) should have exactly 1 default, found \(defaults.count)")
        }
    }

    // MARK: - Model Lookup by ID

    @Test func lookupKnownModelByID() {
        let model = AIModelCatalog.model(byID: "gpt-4o")
        #expect(model != nil)
        #expect(model?.provider == .openAI)
        #expect(model?.displayName == "GPT-4o")
    }

    @Test func lookupUnknownModelByIDReturnsNil() {
        let model = AIModelCatalog.model(byID: "nonexistent-model")
        #expect(model == nil)
    }

    // MARK: - Pricing Sanity Checks

    @Test func paidModelsCostMoreThanZero() {
        for model in AIModelCatalog.allModels where model.provider != .ollama {
            #expect(model.inputCostPer1MTokens > 0, "\(model.id) should have positive input cost")
            #expect(model.outputCostPer1MTokens > 0, "\(model.id) should have positive output cost")
        }
    }

    @Test func outputCostsAreHigherThanInputCosts() {
        for model in AIModelCatalog.allModels where model.provider != .ollama {
            #expect(
                model.outputCostPer1MTokens > model.inputCostPer1MTokens,
                "\(model.id): output cost should exceed input cost"
            )
        }
    }

    // MARK: - AIModelDefinition Equatable & Identifiable

    @Test func modelDefinitionEquatable() {
        let a = AIModelCatalog.claudeSonnet4
        let b = AIModelCatalog.claudeSonnet4
        #expect(a == b)
    }

    @Test func modelDefinitionIdentifiable() {
        let model = AIModelCatalog.gpt4o
        #expect(model.id == "gpt-4o")
    }
}
