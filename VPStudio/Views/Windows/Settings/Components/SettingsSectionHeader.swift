import SwiftUI

/// A glass-styled section header for settings groups.
///
/// Displays a category icon and a "X/Y configured" summary using
/// `SettingsSectionHeaderPolicy` for the text and icon logic.
struct SettingsSectionHeader: View {
    let category: SettingsCategory
    let configuredCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: SettingsSectionHeaderPolicy.icon(for: category))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient.vpAccent)
                .frame(width: 28, height: 28)
                .background(LinearGradient.vpAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(LinearGradient.vpAccent.opacity(0.35), lineWidth: 0.8)
                }

            Text(category.title)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Text(SettingsSectionHeaderPolicy.summaryText(
                category: category,
                configuredCount: configuredCount,
                totalCount: totalCount
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
