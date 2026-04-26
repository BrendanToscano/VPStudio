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

    #if os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Vision Pro compact layouts need slightly larger controls, while regular layouts keep the prior
    /// 25% growth pass from the current lane pass.
    private var chromeScale: CGFloat {
        if QARuntimeOptions.forceCompactNavScale {
            return 1.1
        }

        if horizontalSizeClass == .compact || verticalSizeClass == .compact {
            return 1.1
        }
        return 1.25
    }
    #else
    private var chromeScale: CGFloat { 1 }
    #endif

    private var collapsedWidth: CGFloat { SidebarLayoutPolicy.collapsedWidth * chromeScale }
    private var cornerRadius: CGFloat { SidebarLayoutPolicy.cornerRadius * chromeScale }
    private var iconFrame: CGFloat { SidebarLayoutPolicy.iconFrame * chromeScale }
    private var paddingVertical: CGFloat { 9 * chromeScale }
    private var paddingHorizontal: CGFloat { 5 * chromeScale }
    private var separatorWidth: CGFloat { 24 * chromeScale }
    private var separatorPadding: CGFloat { 3 * chromeScale }
    private var iconSize: CGFloat { 17 * chromeScale }
    private var containerInset: CGFloat { 4 * chromeScale }
    private var badgeSize: CGFloat { 7 * chromeScale }
    private var badgeOffsetX: CGFloat { -4 * chromeScale }
    private var badgeOffsetY: CGFloat { 4 * chromeScale }
    private var environmentIconSize: CGFloat { 18 * chromeScale }

    var body: some View {
        VStack(spacing: 10 * chromeScale) {
            mainSidebarPill

            #if os(visionOS)
            environmentButton
            #endif
        }
    }

    // MARK: - Main Sidebar Pill

    private var mainSidebarPill: some View {
        VStack(spacing: 4 * chromeScale) {
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
                .frame(width: separatorWidth, height: 1 * chromeScale)
                .padding(.vertical, separatorPadding)

            sidebarIconButton(tab: .settings, isSelected: selectedTab == .settings) {
                onTabSelection(.settings)
            }
        }
        .padding(containerInset)
        .padding(.vertical, paddingVertical)
        .padding(.horizontal, paddingHorizontal)
        .frame(width: collapsedWidth)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: .black.opacity(0.10), radius: 28, y: 6)
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
    }

    // MARK: - Icon Button

    private func sidebarIconButton(tab: SidebarTab, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: tab.icon)
                    .font(.system(size: iconSize, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                    .frame(width: iconFrame, height: iconFrame)
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
                        .frame(width: badgeSize, height: badgeSize)
                        .offset(x: badgeOffsetX, y: badgeOffsetY)
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
                .font(.system(size: environmentIconSize, weight: selectedTab == .environments ? .semibold : .medium))
                .foregroundStyle(selectedTab == .environments ? .white : .white.opacity(0.55))
                .frame(width: iconFrame, height: iconFrame)
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
