import SwiftUI

/// Full-screen splash shown while `AppState.bootstrap()` runs.
/// Fades out once `isBootstrapping` becomes false.
struct LaunchScreen: View {
    @State private var logoScale: CGFloat = 0.82
    @State private var logoOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var dotsPhase: Double = 0

    var body: some View {
        ZStack {
            // ── Background ──────────────────────────────────────────────────
            Color.black.ignoresSafeArea()

            // Subtle radial glow behind the logo
            RadialGradient(
                colors: [
                    Color.vpRed.opacity(0.22 * glowOpacity),
                    Color.clear,
                ],
                center: .center,
                startRadius: 60,
                endRadius: 380
            )
            .ignoresSafeArea()
            .animation(.easeOut(duration: 1.4), value: glowOpacity)

            VStack(spacing: 0) {
                Spacer()

                // ── Logo mark ───────────────────────────────────────────────
                ZStack {
                    // Outer glow ring
                    Circle()
                        .fill(.clear)
                        .frame(width: 130, height: 130)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient.vpAccent.opacity(0.35 * glowOpacity),
                                    lineWidth: 1.5
                                )
                                .blur(radius: 3)
                        }

                    // Icon background circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.14, green: 0.06, blue: 0.09),
                                    Color(red: 0.06, green: 0.02, blue: 0.03),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 108, height: 108)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.18), .white.opacity(0.04)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.75
                                )
                        }
                        .shadow(color: .vpRed.opacity(0.4 * glowOpacity), radius: 28, y: 6)

                    // Play triangle
                    Image(systemName: "play.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(LinearGradient.vpAccent)
                        .offset(x: 3)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

                // ── App name ────────────────────────────────────────────────
                VStack(spacing: 6) {
                    Text("VP STUDIO")
                        .font(.system(size: 28, weight: .thin, design: .default))
                        .tracking(10)
                        .foregroundStyle(.white)

                    Text("CINEMA")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(5)
                        .foregroundStyle(LinearGradient.vpAccent)
                }
                .opacity(logoOpacity)
                .padding(.top, 28)

                Spacer()

                // ── Loading indicator ────────────────────────────────────────
                HStack(spacing: 7) {
                    ForEach(0..<3) { i in
                        let phase = dotsPhase - Double(i) * 0.4
                        let bright = (sin(phase * .pi * 2) + 1) / 2
                        Circle()
                            .fill(.white.opacity(0.25 + bright * 0.55))
                            .frame(width: 5, height: 5)
                    }
                }
                .opacity(taglineOpacity)
                .padding(.bottom, 56)
            }
        }
        .onAppear {
            // Stagger animations for a cinematic feel
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.1)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                glowOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.55)) {
                taglineOpacity = 1.0
            }

            // Pulse the loading dots
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                dotsPhase = 1.0
            }
        }
    }
}
