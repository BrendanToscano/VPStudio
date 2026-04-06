import SwiftUI

struct DetailAIAnalysis: View {
    let viewModel: DetailViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let analysis = viewModel.aiAnalysis {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: analysis.verdict.systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(verdictColor(analysis.verdict))
                        Text(analysis.verdict.label)
                            .font(.headline)
                            .foregroundStyle(verdictColor(analysis.verdict))
                        Spacer()
                        Text(String(format: "%.0f/10", analysis.predictedRating))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                viewModel.aiAnalysis = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        #if os(visionOS)
                        .hoverEffect(.highlight)
                        #endif
                    }

                    Text(analysis.personalizedDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    if !analysis.reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(analysis.reasons, id: \.self) { reason in
                                Label(reason, systemImage: "circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .labelStyle(BulletLabelStyle())
                            }
                        }
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
                            lineWidth: 0.5
                        )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if viewModel.isLoadingAIAnalysis {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing based on your taste profile\u{2026}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .transition(.opacity)
            } else if let aiError = viewModel.aiAnalysisError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                    Text(aiError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .transition(.opacity)
            } else if viewModel.mediaItem != nil {
                Button {
                    Task { await viewModel.fetchAIAnalysis() }
                } label: {
                    Label("Would I Like This?", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .tint(.purple)
                #if os(visionOS)
                .hoverEffect(.lift)
                #endif
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.aiAnalysis != nil)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isLoadingAIAnalysis)
    }

    private func verdictColor(_ verdict: AIPersonalizedAnalysis.Verdict) -> Color {
        switch verdict {
        case .strongYes, .yes:
            return .green
        case .maybe:
            return .yellow
        case .no:
            return .orange
        case .strongNo:
            return .red
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .font(.system(size: 4))
                .foregroundStyle(.tertiary)
            configuration.title
        }
    }
}
