import SwiftUI

struct LoadingOverlay: View {
    let title: String
    var message: String?

    @State private var appeared = false
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .strokeBorder(.white.opacity(0.2), lineWidth: 2.5)
                .frame(width: 40, height: 40)
                .overlay {
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                }
            Text(title)
                .font(.headline)
            if let message, !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.07), radius: 24, y: 0)
        .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
        .scaleEffect(appeared ? 1 : 0.88)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }
}

struct InlineLoadingStatusView: View {
    let title: String

    @State private var appeared = false
    @State private var rotation: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(.white.opacity(0.2), lineWidth: 2)
                .frame(width: 20, height: 20)
                .overlay {
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
                appeared = true
            }
        }
    }
}

struct AppErrorInlineView: View {
    let error: AppError

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(error.errorDescription ?? "Something went wrong.")
                .font(.caption)
                .foregroundStyle(.red)
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = 12

    @State private var phase: CGFloat = -0.8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.secondary.opacity(0.2))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.12),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .scaleEffect(x: 1.4, y: 1.0)
                    .offset(x: phase * 360)
            }
            .frame(width: width, height: height)
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 0.8
                }
            }
    }
}

/// Skeleton placeholder mirroring `DiscoverView` — hero carousel + 3 MediaRow sections.
struct DiscoverSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            SkeletonBlock(height: 320, cornerRadius: 24)

            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 14) {
                    SkeletonBlock(width: 180, height: 20, cornerRadius: 8)
                    HStack(spacing: 14) {
                        ForEach(0..<5, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 8) {
                                SkeletonBlock(width: 140, height: 210, cornerRadius: 16)
                                SkeletonBlock(width: 110, height: 14, cornerRadius: 6)
                                SkeletonBlock(width: 80, height: 12, cornerRadius: 6)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

/// Skeleton placeholder mirroring `DetailView` — hero backdrop + metadata + torrent list.
struct DetailSkeletonView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SkeletonBlock(height: 360, cornerRadius: 0)
                VStack(alignment: .leading, spacing: 14) {
                    SkeletonBlock(width: 260, height: 34, cornerRadius: 8)
                    SkeletonBlock(height: 16, cornerRadius: 6)
                    SkeletonBlock(height: 16, cornerRadius: 6)
                    SkeletonBlock(width: 200, height: 16, cornerRadius: 6)
                }
                .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 10) {
                    SkeletonBlock(width: 200, height: 22, cornerRadius: 8)
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonBlock(height: 68, cornerRadius: 12)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
    }
}

/// Skeleton placeholder mirroring `LibraryView` — tab picker + 8-card grid of shimmer rectangles.
struct LibrarySkeletonView: View {
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Tab picker skeleton
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonBlock(width: 80, height: 32, cornerRadius: 8)
                }
                Spacer()
            }
            .padding(.horizontal)

            // 8-card poster grid
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(0..<8, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(height: 210, cornerRadius: 16)
                        SkeletonBlock(width: 110, height: 14, cornerRadius: 6)
                        SkeletonBlock(width: 80, height: 12, cornerRadius: 6)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.top)
    }
}

/// Skeleton placeholder mirroring `SettingsView` — health card + 4 section row skeletons.
struct SettingsSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Health card skeleton
            SkeletonBlock(height: 100, cornerRadius: 16)
                .padding(.horizontal)

            // 4 section rows
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonBlock(width: 140, height: 18, cornerRadius: 8)
                    SkeletonBlock(height: 52, cornerRadius: 12)
                    SkeletonBlock(height: 52, cornerRadius: 12)
                }
                .padding(.horizontal)
            }
        }
        .padding(.top)
    }
}

/// Skeleton placeholder for the Explore/Search results grid — 8 poster card shimmers.
struct ExploreSkeletonView: View {
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<8, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(height: 240, cornerRadius: 16)
                        SkeletonBlock(width: 120, height: 14, cornerRadius: 6)
                        SkeletonBlock(width: 80, height: 12, cornerRadius: 6)
                    }
                }
            }
            .padding(24)
        }
    }
}

/// Inline error banner with icon, message, and retry button.
struct ExploreErrorView: View {
    let error: AppError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)

            Text(error.errorDescription ?? "Something went wrong.")
                .font(.headline)
                .multilineTextAlignment(.center)

            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            SpatialButton(title: "Retry", icon: "arrow.clockwise", action: onRetry)
        }
        .padding(32)
    }
}

/// Friendly empty-state view for search results with icon and suggestions.
struct ExploreEmptyView: View {
    let query: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No results for \"\(query)\"")
                .font(.headline)

            Text("Try adjusting your search, using different keywords, or broadening your filters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(32)
    }
}

/// Compact loading indicator for the bottom of a paginated list.
struct PaginationLoadingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading more\u{2026}")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

private struct AppErrorAlertModifier: ViewModifier {
    @Binding var error: AppError?
    let title: String
    let onRetry: (() -> Void)?

    func body(content: Content) -> some View {
        content.alert(title, isPresented: isPresentedBinding, actions: {
            if let onRetry, error?.recoverySuggestion != nil {
                Button("Retry") {
                    let retryAction = onRetry
                    error = nil
                    retryAction()
                }
            }
            Button("OK", role: .cancel) {
                error = nil
            }
        }, message: {
            Text(messageText)
        })
    }

    private var isPresentedBinding: Binding<Bool> {
        Binding(
            get: { error != nil },
            set: { isPresented in
                if !isPresented {
                    error = nil
                }
            }
        )
    }

    private var messageText: String {
        guard let error else { return "Unknown error." }
        if let suggestion = error.recoverySuggestion, !suggestion.isEmpty {
            return "\(error.errorDescription ?? "Something went wrong.")\n\n\(suggestion)"
        }
        return error.errorDescription ?? "Something went wrong."
    }
}

extension View {
    func appErrorAlert(_ title: String = "Error", error: Binding<AppError?>, onRetry: (() -> Void)? = nil) -> some View {
        modifier(AppErrorAlertModifier(error: error, title: title, onRetry: onRetry))
    }
}
