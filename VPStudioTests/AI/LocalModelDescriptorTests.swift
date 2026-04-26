import Foundation
import Testing
@testable import VPStudio

@Suite("Local Model Descriptor")
struct LocalModelDescriptorTests {
    @Test(arguments: [
        (LocalModelStatus.available, LocalModelStatus.downloading),
        (.downloading, .downloaded),
        (.downloading, .paused),
        (.downloading, .failed),
        (.paused, .downloading),
        (.failed, .downloading),
        (.downloaded, .corrupted),
        (.corrupted, .available),
    ])
    func allowsDocumentedStatusTransitions(from: LocalModelStatus, to: LocalModelStatus) {
        #expect(LocalModelDescriptor.canTransition(from: from, to: to))
    }

    @Test(arguments: [
        (LocalModelStatus.available, LocalModelStatus.downloaded),
        (.downloaded, .downloading),
        (.failed, .downloaded),
        (.paused, .downloaded),
        (.corrupted, .downloaded),
        (.downloading, .available),
    ])
    func rejectsUndocumentedStatusTransitions(from: LocalModelStatus, to: LocalModelStatus) {
        #expect(!LocalModelDescriptor.canTransition(from: from, to: to))
    }

    @Test
    func resetToAvailableClearsDownloadAndValidationState() {
        var descriptor = makeDescriptor(
            status: .failed,
            downloadProgress: 0.42,
            downloadedBytes: 42_000,
            localPath: "/models/model",
            partialDownloadPath: "/models/partial",
            validationState: .corrupt
        )
        let previousUpdatedAt = descriptor.updatedAt

        descriptor.resetToAvailable()

        #expect(descriptor.status == .available)
        #expect(descriptor.downloadProgress == 0)
        #expect(descriptor.downloadedBytes == 0)
        #expect(descriptor.localPath == nil)
        #expect(descriptor.partialDownloadPath == nil)
        #expect(descriptor.validationState == .pending)
        #expect(descriptor.updatedAt >= previousUpdatedAt)
    }

    @Test
    func effectiveCapsUseVisionProAndMacLimits() {
        #expect(LocalModelDescriptor.effectiveCaps(nativeContext: 16_384, isVisionPro: true).promptCap == 8_192)
        #expect(LocalModelDescriptor.effectiveCaps(nativeContext: 4_096, isVisionPro: true).promptCap == 4_096)
        #expect(LocalModelDescriptor.effectiveCaps(nativeContext: 65_536, isVisionPro: false).promptCap == 32_768)
        #expect(LocalModelDescriptor.effectiveCaps(nativeContext: 8_192, isVisionPro: false).promptCap == 8_192)
        #expect(LocalModelDescriptor.effectiveCaps(nativeContext: 16_384, isVisionPro: true).outputCap == 2_048)
        #expect(LocalModelDescriptor.effectiveCaps(nativeContext: 16_384, isVisionPro: false).outputCap == 4_096)
    }

    private func makeDescriptor(
        status: LocalModelStatus,
        downloadProgress: Double,
        downloadedBytes: Int64,
        localPath: String?,
        partialDownloadPath: String?,
        validationState: LocalModelValidation
    ) -> LocalModelDescriptor {
        LocalModelDescriptor(
            id: "local/test",
            displayName: "Test Model",
            huggingFaceRepo: "local/test",
            revision: "main",
            parameterCount: "1B",
            quantization: "4bit",
            diskSizeMB: 100,
            minMemoryMB: 256,
            expectedFileCount: 1,
            maxContextTokens: 2_048,
            effectivePromptCap: 1_024,
            effectiveOutputCap: 512,
            status: status,
            downloadProgress: downloadProgress,
            downloadedBytes: downloadedBytes,
            totalBytes: 100_000,
            lastProgressAt: Date(),
            checksumSHA256: "abc123",
            validationState: validationState,
            localPath: localPath,
            partialDownloadPath: partialDownloadPath,
            isDefault: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
