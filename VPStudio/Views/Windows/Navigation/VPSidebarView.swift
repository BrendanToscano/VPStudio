import SwiftUI

// MARK: - Sidebar Layout Policy

enum SidebarLayoutPolicy {
    /// Width of the icon-only sidebar pill.
    static let collapsedWidth: CGFloat = 52
    /// Expanded width (reserved for future use / macOS with labels).
    static let expandedWidth: CGFloat = 160
    /// Corner radius for the sidebar pill shape.
    static let cornerRadius: CGFloat = 26
    /// Icon frame size for each sidebar button.
    static let iconFrame: CGFloat = 44

    /// The tabs shown in the main sidebar group (excludes environments, which is separate).
    static var sidebarMainTabs: [SidebarTab] {
        [.discover, .search, .library, .downloads]
    }
}

// MARK: - Sidebar View

struct VPSidebarView: View {
    @Binding var selectedTab: SidebarTab
    let opensEnvironmentPicker: Bool
    let onOpenEnvironmentPicker: () -> Void
    let onTabSelection: (SidebarTab) -> Void

    var activeDownloadCount: Int = 0
    var settingsWarningCount: Int = 0

    var body: some View {
        VStack(spacing: 10) {
            mainSidebarPill

            #if os(visionOS)
            environmentButton
            #endif
        }
    }

    // MARK: - Main Sidebar Pill

    private var mainSidebarPill: some View {
        VStack(spacing: 4) {
            ForEach(SidebarLayoutPolicy.sidebarMainTabs, id: \.self) { tab in
                sidebarIconButton(tab: tab, isSelected: selectedTab == tab) {
                    switch BottomTabRoutingPolicy.action(
                        for: tab,
                        opensEnvironmentPicker: opensEnvironmentPicker
                    ) {
                    case .openEnvironmentPicker:
                        onOpenEnvironmentPicker()
                    case .select(let selected):
                        onTabSelection(selected)
                    }
                }
            }

            // Thin separator
            Capsule()
                .fill(.white.opacity(0.15))
                .frame(width: 24, height: 1)
                .padding(.vertical, 2)

            sidebarIconButton(tab: .settings, isSelected: selectedTab == .settings) {
                onTabSelection(.settings)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SidebarLayoutPolicy.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SidebarLayoutPolicy.cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: .black.opacity(0.07), radius: 24, y: 0)
        .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
    }

    // MARK: - Icon Button

    private func sidebarIconButton(tab: SidebarTab, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                    .frame(width: SidebarLayoutPolicy.iconFrame, height: SidebarLayoutPolicy.iconFrame)
                    .background {
                        if isSelected {
                            Circle()
                                .fill(LinearGradient.vpAccent.opacity(0.85))
                                .shadow(color: .vpRed.opacity(0.4), radius: 8, y: 2)
                        }
                    }

                // Badge dot
                if TabBadgePolicy.shouldShowBadge(
                    for: tab,
                    activeDownloadCount: activeDownloadCount,
                    settingsWarningCount: settingsWarningCount
                ) {
                    Circle()
                        .fill(TabBadgePolicy.badgeColor(for: tab))
                        .frame(width: 7, height: 7)
                        .offset(x: -4, y: 4)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TabBarAccessibilityPolicy.accessibilityLabel(for: tab, isSelected: isSelected))
        .accessibilityHint(TabBarAccessibilityPolicy.accessibilityHint(for: tab))
        #if os(visionOS)
        .hoverEffect(.highlight)
        #endif
    }

    // MARK: - Environments Button (separate circle, visionOS only)

    #if os(visionOS)
    private var environmentButton: some View {
        Button {
            switch BottomTabRoutingPolicy.action(
                for: .environments,
                opensEnvironmentPicker: opensEnvironmentPicker
            ) {
            case .openEnvironmentPicker:
                onOpenEnvironmentPicker()
            case .select(let tab):
                onTabSelection(tab)
            }
        } label: {
            Image(systemName: SidebarTab.environments.icon)
                .font(.system(size: 18, weight: selectedTab == .environments ? .semibold : .medium))
                .foregroundStyle(selectedTab == .environments ? .white : .white.opacity(0.55))
                .frame(width: SidebarLayoutPolicy.iconFrame, height: SidebarLayoutPolicy.iconFrame)
                .background {
                    if selectedTab == .environments {
                        Circle()
                            .fill(LinearGradient.vpAccent.opacity(0.85))
                            .shadow(color: .vpRed.opacity(0.4), radius: 8, y: 2)
                    }
                }
                .background(.regularMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.07), radius: 24, y: 0)
        .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
        .hoverEffect(.lift)
        .accessibilityLabel("Environments")
    }
    #endif
}
