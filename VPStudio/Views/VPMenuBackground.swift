import SwiftUI

/// Shared cinematic background used across top-level menus.
struct VPMenuBackground: View {
    @AppStorage(VPMenuBackgroundIntensityPolicy.appStorageKey)
    private var menuBackgroundIntensity = VPMenuBackgroundIntensityPolicy.defaultValue

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let intensity = VPMenuBackgroundIntensityPolicy.clamped(menuBackgroundIntensity)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.04, blue: 0.09),
                        Color(red: 0.06, green: 0.09, blue: 0.17),
                        Color(red: 0.02, green: 0.03, blue: 0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color(red: 0.08, green: 0.42, blue: 0.94).opacity(0.34 * intensity))
                    .frame(width: size.width * 0.52, height: size.height * 0.62)
                    .blur(radius: 86)
                    .offset(x: -size.width * 0.24, y: -size.height * 0.14)

                Circle()
                    .fill(Color(red: 0.72, green: 0.24, blue: 0.96).opacity(0.30 * intensity))
                    .frame(width: size.width * 0.42, height: size.height * 0.50)
                    .blur(radius: 78)
                    .offset(x: size.width * 0.20, y: -size.height * 0.10)

                Circle()
                    .fill(Color(red: 0.14, green: 0.90, blue: 0.56).opacity(0.24 * intensity))
                    .frame(width: size.width * 0.45, height: size.height * 0.52)
                    .blur(radius: 74)
                    .offset(x: size.width * 0.30, y: size.height * 0.18)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.03),
                                Color.black.opacity(0.18),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }
}
