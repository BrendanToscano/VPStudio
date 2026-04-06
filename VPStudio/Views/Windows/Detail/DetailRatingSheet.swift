import SwiftUI

struct DetailRatingSheet: View {
    let viewModel: DetailViewModel
    @Binding var isShowing: Bool
    @Binding var draftFeedbackValue: Double

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.feedbackScaleMode == .likeDislike {
                    likeDislikeFeedback
                } else if viewModel.feedbackScaleMode == .oneToTen {
                    numberedCircleRating
                } else {
                    hundredPointRating
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .navigationTitle("Rate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowing = false
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 240)
    }

    @ViewBuilder
    private var likeDislikeFeedback: some View {
        VStack(spacing: 20) {
            Text("How do you feel about this?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                likeDislikeButton(
                    icon: "hand.thumbsdown.fill",
                    label: "Dislike",
                    isSelected: viewModel.currentFeedbackValue == 0,
                    tint: .red
                ) {
                    Task {
                        if viewModel.currentFeedbackValue == 0 {
                            await viewModel.clearFeedback()
                        } else {
                            await viewModel.submitFeedback(value: 0)
                        }
                        isShowing = false
                    }
                }

                likeDislikeButton(
                    icon: "hand.thumbsup.fill",
                    label: "Like",
                    isSelected: viewModel.currentFeedbackValue == 1,
                    tint: .green
                ) {
                    Task {
                        if viewModel.currentFeedbackValue == 1 {
                            await viewModel.clearFeedback()
                        } else {
                            await viewModel.submitFeedback(value: 1)
                        }
                        isShowing = false
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func likeDislikeButton(
        icon: String,
        label: String,
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(isSelected ? tint : .secondary)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? tint : .secondary)
            }
            .frame(width: 90, height: 90)
            .background(
                isSelected ? AnyShapeStyle(tint.opacity(0.18)) : AnyShapeStyle(.ultraThinMaterial),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(tint.opacity(0.5))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            ),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.07), radius: 20, y: 0)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }

    @ViewBuilder
    private var numberedCircleRating: some View {
        let selectedValue = viewModel.currentFeedbackValue.map { Int($0) }

        VStack(spacing: 20) {
            VStack(spacing: 4) {
                if let selected = selectedValue {
                    Text("\(selected)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(ratingGradientColor(for: selected))
                        .contentTransition(.numericText(value: Double(selected)))
                    Text("out of 10")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap to rate")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 68)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selectedValue)

            HStack(spacing: 6) {
                ForEach(1...10, id: \.self) { value in
                    ratingCircle(
                        value: value,
                        isSelected: selectedValue != nil && value <= selectedValue!,
                        isExactSelection: selectedValue == value
                    ) {
                        if selectedValue == value {
                            Task { await viewModel.clearFeedback() }
                        } else {
                            Task { await viewModel.submitFeedback(value: Double(value)) }
                        }
                    }
                }
            }

            if selectedValue != nil {
                Button {
                    Task { await viewModel.clearFeedback() }
                } label: {
                    Label("Clear Rating", systemImage: "xmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                #if os(visionOS)
                .hoverEffect(.highlight)
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: selectedValue)
    }

    @ViewBuilder
    private func ratingCircle(
        value: Int,
        isSelected: Bool,
        isExactSelection: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        isSelected
                            ? AnyShapeStyle(ratingGradientColor(for: value).opacity(0.85))
                            : AnyShapeStyle(.ultraThinMaterial)
                    )

                Circle()
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(ratingGradientColor(for: value))
                            : AnyShapeStyle(
                                LinearGradient(
                                    colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            ),
                        lineWidth: isExactSelection ? 2 : 0.5
                    )

                Text("\(value)")
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
            .frame(width: 34, height: 34)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
            .scaleEffect(isExactSelection ? 1.15 : 1.0)
        }
        .buttonStyle(.plain)
        .shadow(
            color: isSelected ? ratingGradientColor(for: value).opacity(0.3) : .clear,
            radius: isSelected ? 6 : 0,
            y: 2
        )
        .shadow(color: .black.opacity(isSelected ? 0.12 : 0.06), radius: 4, y: 2)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }

    private func ratingGradientColor(for value: Int) -> Color {
        let t = Double(value - 1) / 9.0
        if t < 0.25 {
            let localT = t / 0.25
            return Color(
                red: 1.0,
                green: 0.2 + 0.45 * localT,
                blue: 0.15 * (1.0 - localT)
            )
        } else if t < 0.5 {
            let localT = (t - 0.25) / 0.25
            return Color(
                red: 1.0 - 0.05 * localT,
                green: 0.65 + 0.2 * localT,
                blue: 0.0 + 0.05 * localT
            )
        } else if t < 0.75 {
            let localT = (t - 0.5) / 0.25
            return Color(
                red: 0.95 - 0.45 * localT,
                green: 0.85 - 0.05 * localT,
                blue: 0.05 + 0.1 * localT
            )
        } else {
            let localT = (t - 0.75) / 0.25
            return Color(
                red: 0.5 - 0.25 * localT,
                green: 0.8 - 0.05 * localT,
                blue: 0.15 + 0.2 * localT
            )
        }
    }

    @ViewBuilder
    private var hundredPointRating: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("\(Int(draftFeedbackValue))")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(value: draftFeedbackValue))
                Text("out of 100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: Int(draftFeedbackValue))

            VStack(spacing: 12) {
                Slider(
                    value: $draftFeedbackValue,
                    in: 1...100,
                    step: 1
                ) {
                    Text("Rating")
                } onEditingChanged: { isEditing in
                    if !isEditing {
                        Task {
                            await viewModel.submitFeedback(value: draftFeedbackValue)
                        }
                    }
                }
                .tint(hundredPointColor(for: draftFeedbackValue))

                HStack {
                    Text("1")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("50")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("100")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)

            if viewModel.currentFeedbackValue != nil {
                Button {
                    Task {
                        await viewModel.clearFeedback()
                        isShowing = false
                    }
                } label: {
                    Label("Clear Rating", systemImage: "xmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.highlight)
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hundredPointColor(for value: Double) -> Color {
        let t = (value - 1.0) / 99.0
        if t < 0.33 {
            return .red
        } else if t < 0.66 {
            return .yellow
        } else {
            return .green
        }
    }
}
