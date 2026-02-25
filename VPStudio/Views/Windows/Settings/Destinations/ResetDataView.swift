import SwiftUI

struct ResetDataView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step: ResetStep = .warning
    @State private var confirmationText = ""
    @State private var isResetting = false
    @State private var resetError: String?

    private enum ResetStep: Int, CaseIterable {
        case warning = 0
        case secondConfirmation = 1
        case finalConfirmation = 2
    }

    private var canExecuteReset: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("RESET") == .orderedSame
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
                deletionBullet(icon: "key.fill", text: "API Keys & Credentials")
                deletionBullet(icon: "clock.fill", text: "Watch History & Library")
                deletionBullet(icon: "arrow.down.circle.fill", text: "Downloads")
                deletionBullet(icon: "mountain.2.fill", text: "Environment Assets")
                deletionBullet(icon: "gearshape.fill", text: "All Settings")
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

                Text("Type **RESET** to confirm")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField("Type RESET", text: $confirmationText)
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
                        } else {
                            Text("Reset Everything")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        canExecuteReset && !isResetting ? AnyShapeStyle(.red) : AnyShapeStyle(.red.opacity(0.22)),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundStyle(canExecuteReset && !isResetting ? .white : .red.opacity(0.5))
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
