import SwiftUI

struct SettingsInlineNotice {
    enum Tone: Equatable {
        case success
        case info
        case warning

        var tint: Color {
            switch self {
            case .success:
                return .green
            case .info:
                return .blue
            case .warning:
                return .orange
            }
        }
    }

    let message: String
    let symbolName: String
    let tone: Tone

    static func success(_ message: String, symbolName: String = "checkmark.circle.fill") -> Self {
        Self(message: message, symbolName: symbolName, tone: .success)
    }

    static func info(_ message: String, symbolName: String = "info.circle.fill") -> Self {
        Self(message: message, symbolName: symbolName, tone: .info)
    }

    static func warning(_ message: String, symbolName: String = "exclamationmark.triangle.fill") -> Self {
        Self(message: message, symbolName: symbolName, tone: .warning)
    }
}

struct SettingsNoticeBanner: View {
    let notice: SettingsInlineNotice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(notice.tone.tint)
                .padding(.top, 1)

            Text(notice.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
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
}

struct SettingsErrorBanner: View {
    let error: AppError

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.top, 1)

            AppErrorInlineView(error: error)

            Spacer(minLength: 0)
        }
        .padding(12)
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
}
