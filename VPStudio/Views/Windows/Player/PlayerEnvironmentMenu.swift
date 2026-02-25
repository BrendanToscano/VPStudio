#if os(visionOS)
import SwiftUI

/// Isolated subview for the environment picker in the player transport controls.
///
/// By separating this into its own View struct, SwiftUI gives it an independent
/// observation scope. It only re-evaluates when `AppState.isImmersiveSpaceOpen`
/// or `assets` change — not on every engine time-tick that rebuilds the parent.
struct PlayerEnvironmentMenu: View {
    let assets: [EnvironmentAsset]
    let onSelect: (EnvironmentAsset) -> Void
    let onDismiss: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        if !assets.isEmpty || appState.isImmersiveSpaceOpen {
            Menu {
                ForEach(assets, id: \.id) { asset in
                    Button {
                        onSelect(asset)
                    } label: {
                        if asset.isActive {
                            Label(asset.name, systemImage: "checkmark")
                        } else {
                            Label(asset.name, systemImage: asset.sourceType == .bundled ? "circle.fill" : "pano")
                        }
                    }
                }
                if appState.isImmersiveSpaceOpen {
                    Divider()
                    Button("Exit Environment", systemImage: "xmark.circle") {
                        onDismiss()
                    }
                }
            } label: {
                Image(systemName: appState.isImmersiveSpaceOpen ? "mountain.2.fill" : "mountain.2")
                    .font(.title3)
                    .foregroundStyle(appState.isImmersiveSpaceOpen ? .blue : .primary)
            }
        }
    }
}

/// Compact environment toggle button for the player top info bar.
///
/// Uses an independent observation scope so it only re-evaluates when
/// `AppState.isImmersiveSpaceOpen` or `assets` changes — not on every
/// engine time-tick that rebuilds the parent view.
struct PlayerEnvironmentButton: View {
    let assets: [EnvironmentAsset]
    let onSelect: (EnvironmentAsset) -> Void
    let onDismiss: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            if assets.isEmpty {
                Text("No environments available")
            } else {
                ForEach(assets, id: \.id) { asset in
                    Button {
                        onSelect(asset)
                    } label: {
                        HStack {
                            Label(asset.name, systemImage: assetIcon(asset))
                            if asset.id == appState.selectedEnvironmentAsset?.id,
                               appState.isImmersiveSpaceOpen {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            if appState.isImmersiveSpaceOpen {
                Divider()
                Button(role: .destructive) {
                    onDismiss()
                } label: {
                    Label("Exit Environment", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: appState.isImmersiveSpaceOpen ? "mountain.2.fill" : "mountain.2")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    appState.isImmersiveSpaceOpen
                        ? AnyShapeStyle(.blue.opacity(0.25))
                        : AnyShapeStyle(.ultraThinMaterial),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: appState.isImmersiveSpaceOpen
                                    ? [.blue.opacity(0.6), .blue.opacity(0.2)]
                                    : [.white.opacity(0.28), .white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                }
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private func assetIcon(_ asset: EnvironmentAsset) -> String {
        let ext = URL(fileURLWithPath: asset.assetPath).pathExtension.lowercased()
        return ["hdr", "exr"].contains(ext) ? "pano" : "cube.transparent"
    }
}
#endif
