import SwiftUI

// MARK: - Setup Wizard View

struct SetupWizardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var currentStep = 0
    @State private var debridApiKey = ""
    @State private var selectedService: DebridServiceType = .realDebrid
    @State private var tmdbApiKey = ""
    @State private var selectedAIProvider: AIProviderOption = .none
    @State private var aiApiKey = ""
    @State private var selectedQuality: VideoQuality = .hd1080p
    @State private var selectedSubtitleLanguage: SubtitleLanguageOption = .none
    @State private var saveError: String?
    @State private var appeared = false
    @State private var didRunQAAutoAdvance = false

    private let totalSteps = 5
    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    var body: some View {
        ZStack {
            // ── Cinematic background gradient ────────────────────────────────
            WizardBackgroundView(currentStep: currentStep)

            VStack(spacing: 0) {
                // ── Step indicator dots ──────────────────────────────────────
                WizardStepIndicator(currentStep: currentStep, totalSteps: totalSteps)
                    .padding(.top, 28)
                    .padding(.bottom, 24)

                // ── Step content ─────────────────────────────────────────────
                ZStack {
                    if currentStep == 0 {
                        welcomeStep
                            .transition(stepTransition)
                    }
                    if currentStep == 1 {
                        debridStep
                            .transition(stepTransition)
                    }
                    if currentStep == 2 {
                        metadataAIStep
                            .transition(stepTransition)
                    }
                    if currentStep == 3 {
                        preferencesStep
                            .transition(stepTransition)
                    }
                    if currentStep == 4 {
                        completeStep
                            .transition(stepTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86), value: currentStep)

                // ── Navigation buttons ───────────────────────────────────────
                wizardNavigation
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
            }
        }
        .frame(minWidth: 640, minHeight: 560)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.6)) {
                    appeared = true
                }
            }

            guard QARuntimeOptions.setupAutoAdvance else { return }
            guard !didRunQAAutoAdvance else { return }
            didRunQAAutoAdvance = true

            if let tmdbKey = QARuntimeOptions.setupTMDBApiKey {
                tmdbApiKey = tmdbKey
            }
            if let preferredQuality = QARuntimeOptions.setupPreferredQuality {
                selectedQuality = preferredQuality
            }
            if let subtitleLanguage = QARuntimeOptions.setupSubtitleLanguage {
                selectedSubtitleLanguage = subtitleLanguage
            }

            Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    advanceStep()
                }

                while !Task.isCancelled {
                    let stepBeforeAdvance = await MainActor.run {
                        currentStep
                    }
                    guard stepBeforeAdvance > 0 && stepBeforeAdvance < totalSteps - 1 else { break }
                    try? await Task.sleep(for: .milliseconds(250))
                    await handleNextStep()
                    let stepAfterAdvance = await MainActor.run {
                        currentStep
                    }
                    guard stepAfterAdvance > stepBeforeAdvance else { break }
                }

                let isCompleteStep = await MainActor.run { currentStep == totalSteps - 1 }
                guard !Task.isCancelled, isCompleteStep else { return }
                try? await Task.sleep(for: .milliseconds(250))
                await MainActor.run {
                    appState.isShowingSetup = false
                }
            }
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 28) {
            Spacer()

            // App icon + title
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.vpRed.opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 70
                            )
                        )
                        .frame(width: 120, height: 120)

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(LinearGradient.vpAccent)
                        .shadow(color: .vpRed.opacity(0.4), radius: 16, y: 4)
                }

                Text("Welcome to VPStudio")
                    .font(.system(size: 32, weight: .bold))

                Text("Your personal cinema, anywhere")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Feature highlight cards
            featureHighlightGrid
                .padding(.horizontal, 32)

            Spacer()

            // Get started button
            WizardAccentButton(title: "Get Started", icon: "arrow.right") {
                advanceStep()
            }
        }
        .padding(.horizontal, 24)
    }

    private var featureHighlightGrid: some View {
        let features = WizardFeatureHighlight.allFeatures
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
            spacing: 14
        ) {
            ForEach(features) { feature in
                FeatureHighlightCard(feature: feature)
            }
        }
    }

    // MARK: - Step 1: Debrid Service

    private var debridStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header
            VStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient.vpAccent)

                Text("Connect a Debrid Service")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("A debrid service unlocks high-quality cached streams. Recommended, but optional.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            // Service picker + API key
            VStack(spacing: 16) {
                // Service picker with glass styling
                HStack {
                    Text("Service")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $selectedService) {
                        ForEach(DebridServiceType.allCases) { service in
                            Text(service.displayName).tag(service)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .accessibilityLabel("Debrid service")
                    .accessibilityHint("Choose the debrid provider to connect.")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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

                // API key field
                HStack(spacing: 8) {
                    SecureField("API Key", text: $debridApiKey)
                        .textFieldStyle(.plain)
                    PasteFieldButton { debridApiKey = $0 }
                        .accessibilityLabel("Paste debrid API key from clipboard")
                        .accessibilityHint("Pastes the debrid API key into the setup field.")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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

                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: 420)

            // Expandable explanation
            DisclosureGroup {
                Text("Debrid services act as premium download managers that cache popular files on fast servers. When you search for content, the debrid service checks if it already has a cached copy to enable fast streaming. You can skip this step and add a service later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                    Text("What's a debrid service?")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420)
            .tint(.secondary)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Step 2: Metadata & AI

    private var metadataAIStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // ── TMDB API Key Section ─────────────────────────────────────
            VStack(spacing: 10) {
                Image(systemName: "film")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient.vpAccent)

                Text("TMDB API Key")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Required for movie and TV show metadata, artwork, and recommendations. Get a free key at themoviedb.org")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    SecureField("TMDB API Key", text: $tmdbApiKey)
                        .textFieldStyle(.plain)
                    PasteFieldButton { tmdbApiKey = $0 }
                        .accessibilityLabel("Paste TMDB API key from clipboard")
                        .accessibilityHint("Pastes the TMDB API key into the setup field.")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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

                Button {
                    if let url = URL(string: "https://www.themoviedb.org/settings/api") {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                        Text("Get Free Key")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(LinearGradient.vpAccent)
                }
                .buttonStyle(.plain)
                #if os(visionOS)
                .hoverEffect(.highlight)
                #endif
            }
            .frame(maxWidth: 420)

            // ── AI Assistant Section ─────────────────────────────────────
            VStack(spacing: 10) {
                Divider()
                    .padding(.vertical, 4)

                Image(systemName: "brain")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                Text("AI Assistant")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("Add an AI provider key for smart recommendations and content analysis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            VStack(spacing: 12) {
                // Provider picker
                HStack {
                    Text("Provider")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $selectedAIProvider) {
                        ForEach(AIProviderOption.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("AI provider")
                    .accessibilityHint("Choose an optional AI provider for recommendations and analysis.")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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

                // Conditional API key field
                if selectedAIProvider != .none {
                    HStack(spacing: 8) {
                        SecureField("\(selectedAIProvider.displayName) API Key", text: $aiApiKey)
                            .textFieldStyle(.plain)
                        PasteFieldButton { aiApiKey = $0 }
                            .accessibilityLabel("Paste \(selectedAIProvider.displayName) API key from clipboard")
                            .accessibilityHint("Pastes the AI API key into the setup field.")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: selectedAIProvider)
                }

                Text("Optional — you can configure this later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 420)

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 420)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: selectedAIProvider)
    }

    // MARK: - Step 3: Preferences

    private var preferencesStep: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header
            VStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient.vpAccent)

                Text("Set Your Preferences")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Quick defaults to get you started. You can customize more in Settings later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            // Preference rows
            VStack(spacing: 14) {
                // Quality picker
                WizardPreferenceRow(
                    icon: "4k.tv",
                    title: "Preferred Quality"
                ) {
                    Picker("", selection: $selectedQuality) {
                        Text("720p").tag(VideoQuality.hd720p)
                        Text("1080p").tag(VideoQuality.hd1080p)
                        Text("4K").tag(VideoQuality.uhd4k)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Preferred quality")
                    .accessibilityHint("Choose the default streaming quality.")
                }

                // Subtitle language picker
                WizardPreferenceRow(
                    icon: "captions.bubble",
                    title: "Subtitle Language"
                ) {
                    Picker("", selection: $selectedSubtitleLanguage) {
                        ForEach(SubtitleLanguageOption.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    .accessibilityLabel("Subtitle language")
                    .accessibilityHint("Choose the default subtitle language.")
                }
            }
            .frame(maxWidth: 420)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Step 4: Completion

    private var completeStep: some View {
        WizardCompletionContent(
            selectedService: selectedService,
            debridApiKey: debridApiKey,
            tmdbApiKey: tmdbApiKey,
            selectedAIProvider: selectedAIProvider,
            selectedQuality: selectedQuality,
            selectedSubtitleLanguage: selectedSubtitleLanguage
        )
    }

    // MARK: - Navigation

    private var wizardNavigation: some View {
        HStack {
            if currentStep > 0 && currentStep < totalSteps - 1 {
                Button {
                    moveToStep(currentStep - 1)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                        Text("Back")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Returns to the previous setup step.")
            }

            Spacer()

            if currentStep > 0 && currentStep < totalSteps - 1 {
                WizardAccentButton(
                    title: continueButtonTitle,
                    icon: continueButtonIcon
                ) {
                    Task { await handleNextStep() }
                }
                .accessibilityHint("Saves this step and continues.")
            } else if currentStep == totalSteps - 1 {
                WizardAccentButton(title: "Start Exploring", icon: "sparkles") {
                    appState.isShowingSetup = false
                }
                .accessibilityHint("Closes setup and opens the app.")
            }
        }
    }

    // MARK: - Actions

    private func advanceStep() {
        moveToStep(currentStep + 1)
    }

    private func moveToStep(_ nextStep: Int) {
        let clampedStep = min(max(nextStep, 0), totalSteps - 1)
        guard clampedStep != currentStep else { return }
        guard !reduceMotion else {
            currentStep = clampedStep
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            currentStep = clampedStep
        }
    }

    private func handleNextStep() async {
        saveError = nil
        let normalizedApiKey = debridApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if currentStep == 1, !normalizedApiKey.isEmpty {
            let configId = UUID().uuidString
            let secretKey = SecretKey.debridToken(service: selectedService, configId: configId)
            let tokenRef = SecretReference.encode(key: secretKey)

            do {
                try await appState.secretStore.setSecret(normalizedApiKey, for: secretKey)
                let config = DebridConfig(
                    id: configId,
                    serviceType: selectedService,
                    apiTokenRef: tokenRef,
                    isActive: true,
                    priority: 0,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                try await appState.database.saveDebridConfig(config)
                try await appState.debridManager.initialize()
            } catch {
                saveError = error.localizedDescription
                return
            }
        }

        if currentStep == 2 {
            let normalizedTmdbKey = tmdbApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedAiKey = aiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

            guard SetupWizardValidationPolicy.canContinueFromMetadataStep(tmdbApiKey: normalizedTmdbKey) else {
                saveError = SetupWizardValidationPolicy.requiredTMDBMessage
                return
            }

            do {
                try await appState.settingsManager.setValue(
                    normalizedTmdbKey,
                    forKey: SettingsKeys.tmdbApiKey
                )
                NotificationCenter.default.post(name: .tmdbApiKeyDidChange, object: nil)

                // Save AI provider selection
                try await appState.settingsManager.setValue(
                    selectedAIProvider == .none ? nil : selectedAIProvider.rawValue,
                    forKey: SettingsKeys.defaultAIProvider
                )

                // Save AI key if a provider is selected and key is provided
                if selectedAIProvider != .none, !normalizedAiKey.isEmpty {
                    let aiSettingsKey: String = switch selectedAIProvider {
                    case .openAI: SettingsKeys.openAIApiKey
                    case .anthropic: SettingsKeys.anthropicApiKey
                    case .gemini: SettingsKeys.geminiApiKey
                    case .openRouter: SettingsKeys.openRouterApiKey
                    case .none: ""
                    }
                    if !aiSettingsKey.isEmpty {
                        try await appState.settingsManager.setValue(
                            normalizedAiKey,
                            forKey: aiSettingsKey
                        )
                    }
                }
                NotificationCenter.default.post(name: .settingsDidChange, object: nil)
                NotificationCenter.default.post(name: .discoverAISettingsDidChange, object: nil)
            } catch {
                saveError = error.localizedDescription
                return
            }
        }

        if currentStep == 3 {
            do {
                try await appState.settingsManager.setValue(
                    selectedQuality.rawValue,
                    forKey: SettingsKeys.preferredQuality
                )
                if selectedSubtitleLanguage != .none {
                    try await appState.settingsManager.setValue(
                        selectedSubtitleLanguage.rawValue,
                        forKey: SettingsKeys.subtitleLanguage
                    )
                }
            } catch {
                saveError = error.localizedDescription
                return
            }
        }

        advanceStep()
    }

    private var continueButtonTitle: String {
        if currentStep == 1, debridApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Skip for Now"
        }
        return "Continue"
    }

    private var continueButtonIcon: String {
        if currentStep == 1, debridApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "forward"
        }
        return "arrow.right"
    }
}

// MARK: - Wizard Background

private struct WizardBackgroundView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let currentStep: Int
    @State private var gradientPhase: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Animated ambient gradient
            Canvas { context, size in
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.35)
                let radius = max(size.width, size.height) * 0.7

                let phase = gradientPhase
                let offsetX = cos(phase * .pi * 2) * size.width * 0.08
                let offsetY = sin(phase * .pi * 2) * size.height * 0.06

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - radius * 0.5 + offsetX,
                        y: center.y - radius * 0.4 + offsetY,
                        width: radius,
                        height: radius * 0.8
                    )),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color.vpRed.opacity(0.08),
                            Color.vpRed.opacity(0.03),
                            Color.clear,
                        ]),
                        center: CGPoint(
                            x: center.x + offsetX,
                            y: center.y + offsetY
                        ),
                        startRadius: 0,
                        endRadius: radius * 0.5
                    )
                )

                // Secondary subtle blue-ish ambient
                let center2 = CGPoint(
                    x: size.width * 0.7 - offsetX * 0.5,
                    y: size.height * 0.6 - offsetY * 0.5
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center2.x - radius * 0.35,
                        y: center2.y - radius * 0.3,
                        width: radius * 0.7,
                        height: radius * 0.6
                    )),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 0.2, green: 0.1, blue: 0.3).opacity(0.06),
                            Color.clear,
                        ]),
                        center: center2,
                        startRadius: 0,
                        endRadius: radius * 0.35
                    )
                )
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: currentStep)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: true)) {
                gradientPhase = 1.0
            }
        }
    }
}

// MARK: - Step Indicator

private struct WizardStepIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep
                        ? AnyShapeStyle(LinearGradient.vpAccent)
                        : AnyShapeStyle(Color.white.opacity(0.2)))
                    .frame(width: index == currentStep ? 28 : 8, height: 8)
                    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Step \(currentStep + 1) of \(totalSteps)")
        .accessibilityHint("The highlighted capsule shows your current setup step.")
    }
}

// MARK: - Feature Highlight Card

private struct WizardFeatureHighlight: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let visionOSOnly: Bool

    static var allFeatures: [WizardFeatureHighlight] {
        var features = [
            WizardFeatureHighlight(
                icon: "play.circle.fill",
                title: "Stream Anywhere",
                subtitle: "Access your media library from any debrid service",
                visionOSOnly: false
            ),
            WizardFeatureHighlight(
                icon: "sparkles",
                title: "Smart Discovery",
                subtitle: "Find new content with intelligent recommendations",
                visionOSOnly: false
            ),
            WizardFeatureHighlight(
                icon: "clock.arrow.circlepath",
                title: "Track Progress",
                subtitle: "Automatically save and sync your watch history",
                visionOSOnly: false
            ),
        ]

        #if os(visionOS)
        features.insert(
            WizardFeatureHighlight(
                icon: "mountain.2",
                title: "Immersive Cinema",
                subtitle: "Watch in stunning immersive environments",
                visionOSOnly: true
            ),
            at: 1
        )
        #endif

        return features
    }
}

private struct FeatureHighlightCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let feature: WizardFeatureHighlight
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: feature.icon)
                .font(.system(size: 22))
                .foregroundStyle(LinearGradient.vpAccent)
                .frame(width: 40, height: 40)
                .background(Color.vpRed.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.vpRed.opacity(0.3), Color.vpRed.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(feature.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
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
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                    appeared = true
                }
            }
        }
    }
}

// MARK: - Wizard Preference Row

private struct WizardPreferenceRow<Control: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient.vpAccent)
                .frame(width: 34, height: 34)
                .background(Color.vpRed.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.vpRed.opacity(0.3), Color.vpRed.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
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
    }
}

// MARK: - Completion Content

private struct WizardCompletionContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selectedService: DebridServiceType
    let debridApiKey: String
    let tmdbApiKey: String
    let selectedAIProvider: AIProviderOption
    let selectedQuality: VideoQuality
    let selectedSubtitleLanguage: SubtitleLanguageOption

    @State private var checkmarkScale: CGFloat = 0
    @State private var glowOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var summaryOpacity: Double = 0

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Animated checkmark with glow
            ZStack {
                // Pulse glow ring
                Circle()
                    .fill(Color.vpRed.opacity(0.08 * glowOpacity))
                    .frame(width: 140, height: 140)
                    .scaleEffect(pulseScale)

                // Glow backdrop
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.green.opacity(0.2 * glowOpacity),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(checkmarkScale)
                    .shadow(color: .green.opacity(0.3), radius: 16, y: 4)
            }

            Text("You're All Set!")
                .font(.system(size: 28, weight: .bold))

            // Summary
            VStack(spacing: 8) {
                if !debridApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    WizardSummaryRow(
                        icon: "link",
                        text: "\(selectedService.displayName) connected"
                    )
                }
                if !tmdbApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    WizardSummaryRow(
                        icon: "film",
                        text: "TMDB metadata configured"
                    )
                }
                if selectedAIProvider != .none {
                    WizardSummaryRow(
                        icon: "brain",
                        text: "\(selectedAIProvider.displayName) AI enabled"
                    )
                }
                WizardSummaryRow(
                    icon: "4k.tv",
                    text: "Quality set to \(selectedQuality.rawValue)"
                )
                if selectedSubtitleLanguage != .none {
                    WizardSummaryRow(
                        icon: "captions.bubble",
                        text: "\(selectedSubtitleLanguage.displayName) subtitles"
                    )
                }
            }
            .opacity(summaryOpacity)
            .frame(maxWidth: 320)

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear {
            if reduceMotion {
                checkmarkScale = 1.0
                glowOpacity = 1.0
                summaryOpacity = 1.0
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.15)) {
                    checkmarkScale = 1.0
                }
                withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                    glowOpacity = 1.0
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                    summaryOpacity = 1.0
                }
                withAnimation(
                    .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
                    .delay(0.8)
                ) {
                    pulseScale = 1.15
                }
            }
        }
    }
}

// MARK: - Summary Row

private struct WizardSummaryRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LinearGradient.vpAccent)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
    }
}

// MARK: - Accent Button

private struct WizardAccentButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .fontWeight(.semibold)
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                LinearGradient.vpAccent,
                in: Capsule()
            )
            .shadow(color: .vpRed.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        #if os(visionOS)
        .hoverEffect(.lift)
        #endif
    }
}

// MARK: - Subtitle Language Option

enum SubtitleLanguageOption: String, CaseIterable, Identifiable, Sendable {
    case none = "none"
    case english = "eng"
    case spanish = "spa"
    case french = "fre"
    case german = "ger"
    case portuguese = "por"
    case japanese = "jpn"
    case korean = "kor"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .portuguese: return "Portuguese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        }
    }
}

enum SetupWizardValidationPolicy {
    static let requiredTMDBMessage = "TMDB API key is required to continue."

    static func canContinueFromMetadataStep(tmdbApiKey: String) -> Bool {
        !tmdbApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - AI Provider Option

// MARK: - AI Provider Option

enum AIProviderOption: String, CaseIterable, Identifiable, Sendable {
    case none = "none"
    case openAI = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case openRouter = "openrouter"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Gemini"
        case .openRouter: return "OpenRouter"
        }
    }
}
