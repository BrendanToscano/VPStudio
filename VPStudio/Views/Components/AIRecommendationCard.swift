import SwiftUI

struct AIRecommendationCard: View {
    let recommendation: AIMovieRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(recommendation.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Spacer()
                if let score = recommendation.score {
                    GlassTag(
                        text: String(format: "%.0f%%", score * 100),
                        tintColor: .purple,
                        weight: .bold
                    )
                }
            }

            HStack(spacing: 6) {
                if let year = recommendation.year {
                    Text(String(year))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                GlassTag(
                    text: recommendation.type == .movie ? "Movie" : "TV",
                    weight: .regular
                )
            }

            if !recommendation.reason.isEmpty {
                Text(recommendation.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .frame(width: 210, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .glassStroke(cornerRadius: 14)
        .glassShadow()
    }
}
