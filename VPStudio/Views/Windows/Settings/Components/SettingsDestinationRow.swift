import SwiftUI

struct SettingsDestinationRow: View {
    let destination: SettingsDestination
    let status: SettingsDestinationStatus?
    let isRecent: Bool

    private var indicatorStatus: SettingsRowIndicatorPolicy.StatusKind {
        guard let status else { return .disabled }
        return SettingsRowIndicatorPolicy.statusKind(from: status.kind)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient.vpAccent.opacity(0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(LinearGradient.vpAccent.opacity(0.35), lineWidth: 0.8)
                    }

                Image(systemName: destination.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LinearGradient.vpAccent)

                // Indicator dot overlay
                if SettingsRowIndicatorPolicy.shouldShowIndicator(for: indicatorStatus) {
                    Circle()
                        .fill(SettingsRowIndicatorPolicy.indicatorColor(for: indicatorStatus))
                        .frame(width: 8, height: 8)
                        .shadow(color: SettingsRowIndicatorPolicy.indicatorColor(for: indicatorStatus).opacity(0.5), radius: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .offset(x: 2, y: -2)
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(destination.title)
                        .font(.headline)
                    if isRecent {
                        GlassTag(text: "Recent", weight: .semibold)
                    }
                }

                Text(destination.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let status {
                statusBadge(status)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: SettingsDestinationStatus) -> some View {
        Text(status.message)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(statusForeground(status.kind))
            .background(statusBackground(status.kind), in: Capsule())
    }

    private func statusForeground(_ kind: SettingsStatusKind) -> Color {
        switch kind {
        case .positive: return .green
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }

    private func statusBackground(_ kind: SettingsStatusKind) -> Color {
        switch kind {
        case .positive: return .green.opacity(0.14)
        case .warning: return .orange.opacity(0.14)
        case .neutral: return .white.opacity(0.08)
        }
    }
}
