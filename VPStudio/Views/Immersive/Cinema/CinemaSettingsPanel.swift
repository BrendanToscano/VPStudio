#if os(visionOS)
import SwiftUI
import simd

// MARK: - CinemaSettingsPanel

/// A visionOS settings panel for configuring the cinema environment.
/// Can be used inside or outside an immersive space.
public struct CinemaSettingsPanel: View {
    @Bindable public var settings: CinemaSettings

    public init(settings: CinemaSettings) {
        self.settings = settings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                presetSection
                Divider()
                screenGeometrySection
                Divider()
                seatOffsetSection
                Divider()
                environmentSection
                Divider()
                actionsSection
            }
            .padding(28)
        }
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 520)
        .glassBackgroundEffect()
    }

    // MARK: - 1. Preset Picker

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preset")
                .font(.title3)
                .fontWeight(.semibold)

            Picker("Preset", selection: $settings.activePreset) {
                ForEach(CinemaPreset.allCases) { preset in
                    Text(preset.title)
                        .tag(preset)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - 2. Screen Geometry

    private var screenGeometrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screen Geometry")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Screen Size") {
                    Text(
                        "\(settings.screenSize.width, specifier: "%.2f") × \(settings.screenSize.height, specifier: "%.2f") m"
                    )
                    .monospacedDigit()
                }

                if !settings.isComfortable {
                    Label(
                        "Current settings may cause discomfort",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Slider(value: $settings.screenWidth, in: 1...10) {
                Text("Width")
            } minimumValueLabel: {
                Text("1 m")
            } maximumValueLabel: {
                Text("10 m")
            }

            Slider(value: $settings.screenDistance, in: 1.5...15) {
                Text("Distance")
            } minimumValueLabel: {
                Text("1.5 m")
            } maximumValueLabel: {
                Text("15 m")
            }

            Slider(value: $settings.screenHeight, in: -2...4) {
                Text("Height")
            } minimumValueLabel: {
                Text("-2 m")
            } maximumValueLabel: {
                Text("4 m")
            }

            Slider(value: $settings.screenTilt, in: -15...15) {
                Text("Tilt")
            } minimumValueLabel: {
                Text("-15°")
            } maximumValueLabel: {
                Text("15°")
            }
        }
    }

    // MARK: - 3. Seat Offset

    private var seatOffsetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seat Offset")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                offsetStepper(axis: "X", value: seatXBinding)
                offsetStepper(axis: "Y", value: seatYBinding)
                offsetStepper(axis: "Z", value: seatZBinding)
            }
        }
    }

    // MARK: - 4. Environment

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Environment")
                .font(.title3)
                .fontWeight(.semibold)

            Slider(value: $settings.environmentDarkness, in: 0...1) {
                Text("Darkness")
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("1")
            }

            Slider(value: $settings.ambientLighting, in: 0...1) {
                Text("Ambient Light")
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("1")
            }

            Picker("Immersion Style", selection: $settings.immersionStyleRaw) {
                ForEach(CinemaImmersionStyle.allCases, id: \.self) { style in
                    Text(style.rawValue.capitalized)
                        .tag(style.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Use Surroundings Effect", isOn: $settings.useSurroundingsEffect)
        }
    }

    // MARK: - 5. Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    settings.load()
                } label: {
                    Label("Load Defaults", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    settings.save()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    settings.apply(
                        preset: settings.activePreset,
                        baseAspectRatio: settings.videoAspectRatio
                    )
                } label: {
                    Label("Reset to Preset", systemImage: "slider.horizontal.below.rectangle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - SIMD Bindings

    private func offsetStepper(axis: String, value: Binding<Double>) -> some View {
        Stepper(
            "\(axis): \(value.wrappedValue, specifier: "%.1f") m",
            value: value,
            in: -2...2,
            step: 0.1
        )
    }

    private var seatXBinding: Binding<Double> {
        Binding(
            get: { settings.seatOffset.x },
            set: { settings.seatOffset.x = $0 }
        )
    }

    private var seatYBinding: Binding<Double> {
        Binding(
            get: { settings.seatOffset.y },
            set: { settings.seatOffset.y = $0 }
        )
    }

    private var seatZBinding: Binding<Double> {
        Binding(
            get: { settings.seatOffset.z },
            set: { settings.seatOffset.z = $0 }
        )
    }
}
#endif
