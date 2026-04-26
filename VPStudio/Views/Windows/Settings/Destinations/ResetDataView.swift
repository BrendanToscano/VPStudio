import SwiftUI

enum ResetDataPolicy {
    struct DeletionItem: Equatable, Sendable {
        let icon: String
        let title: String
    }

    static let requiredConfirmationPhrase = "RESET"
    static let resetButtonTitle = "Reset Everything"
    static let progressAccessibilityLabel = "Reset in progress"

    static let deletionItems: [DeletionItem] = [
        DeletionItem(icon: "key.fill", title: "API Keys & Credentials"),
        DeletionItem(icon: "clock.fill", title: "Watch History & Library"),
        DeletionItem(icon: "arrow.down.circle.fill", title: "Downloads"),
        DeletionItem(icon: "mountain.2.fill", title: "Environment Assets"),
        DeletionItem(icon: "gearshape.fill", title: "All Settings"),
    ]

    static func normalizedConfirmationText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canExecuteReset(confirmationText: String, isResetting: Bool = false) -> Bool {
        guard !isResetting else { return false }
        return normalizedConfirmationText(confirmationText)
            .caseInsensitiveCompare(requiredConfirmationPhrase) == .orderedSame
    }
}

enum ResetDataStep: Int, CaseIterable {
    case warning = 0
    case secondConfirmation = 1
    case finalConfirmation = 2
}

struct ResetDataView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step: ResetDataStep
    @State private var confirmationText: String
    @State private var isResetting = false
    @State private var resetError: String?
    @State private var didRunQAAutoReset = false

    init(initialStep: ResetDataStep = .warning, initialConfirmationText: String = "") {
        _step = State(initialValue: initialStep)
        _confirmationText = State(initialValue: initialConfirmationText)
    }

    private var canExecuteReset: Bool {
        ResetDataPolicy.canExecuteReset(
            confirmationText: confirmationText,
            isResetting: isResetting
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.3), value: step)

            if let resetError {
                errorBanner(resetError)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 380, idealHeight: 440)
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear {
            guard QARuntimeOptions.autoExecuteReset else { return }
            guard !didRunQAAutoReset else { return }
            didRunQAAutoReset = true

            Task {
                try? await Task.sleep(for: .milliseconds(250))
                await MainActor.run {
                    step = .secondConfirmation
                }
                try? await Task.sleep(for: .milliseconds(250))
                await MainActor.run {
                    step = .finalConfirmation
                    confirmationText = "RESET"
                }
                try? await Task.sleep(for: .milliseconds(250))
                await MainActor.run {
                    executeReset()
                }
            }
        }
    }

    // MARK: - Step Router

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .warning:
            warningStep
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case .secondConfirmation:
            secondConfirmationStep
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case .finalConfirmation:
            finalConfirmationStep
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        }
    }

    // MARK: - Step 1: Warning

    private var warningStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
                .shadow(color: .red.opacity(0.3), radius: 12, y: 4)

            VStack(spacing: 10) {
                Text("Reset All Data")
                    .font(.title2.weight(.bold))

                Text("This will permanently delete all your data including API keys, watch history, library, downloads, environments, and settings. This action cannot be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif

                Button {
                    withAnimation { step = .secondConfirmation }
                } label: {
                    Text("Continue")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.red.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.red)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 2: Second Confirmation

    private var secondConfirmationStep: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 10) {
                Text("Are You Sure?")
                    .font(.title2.weight(.bold))

                Text("All configured services, saved credentials, watch progress, and downloaded content will be permanently erased.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(ResetDataPolicy.deletionItems, id: \.title) { item in
                    deletionBullet(icon: item.icon, text: item.title)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .padding(.horizontal, 32)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    withAnimation { step = .warning }
                } label: {
                    Text("Go Back")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif

                Button {
                    withAnimation { step = .finalConfirmation }
                } label: {
                    Text("I Understand, Continue")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.red.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.red)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 3: Final Confirmation

    private var finalConfirmationStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "trash.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red)
                .shadow(color: .red.opacity(0.3), radius: 12, y: 4)

            VStack(spacing: 10) {
                Text("Final Confirmation")
                    .font(.title2.weight(.bold))

                Text("Type **\(ResetDataPolicy.requiredConfirmationPhrase)** to confirm")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField("Type \(ResetDataPolicy.requiredConfirmationPhrase)", text: $confirmationText)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium).monospaced())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            LinearGradient(
                                colors: canExecuteReset
                                    ? [.red.opacity(0.6), .red.opacity(0.3)]
                                    : [.white.opacity(0.28), .white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .padding(.horizontal, 64)
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif

            Spacer()

            HStack(spacing: 16) {
                Button {
                    withAnimation {
                        confirmationText = ""
                        step = .secondConfirmation
                    }
                } label: {
                    Text("Go Back")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif

                Button {
                    executeReset()
                } label: {
                    Group {
                        if isResetting {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel(ResetDataPolicy.progressAccessibilityLabel)
                        } else {
                            Text(ResetDataPolicy.resetButtonTitle)
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        canExecuteReset ? AnyShapeStyle(.red) : AnyShapeStyle(.red.opacity(0.22)),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(canExecuteReset ? .white : .red.opacity(0.5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canExecuteReset || isResetting)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Components

    private func deletionBullet(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.red.opacity(0.8))
                .frame(width: 20, alignment: .center)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private func executeReset() {
        isResetting = true
        resetError = nil
        Task {
            do {
                try await appState.resetAllData()
                dismiss()
            } catch {
                resetError = error.localizedDescription
                isResetting = false
            }
        }
    }
}
