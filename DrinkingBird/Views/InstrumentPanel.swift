import SwiftUI

/// Right-rail control panel: environment dials, simulation dials, presets,
/// and live numeric readouts.
struct InstrumentPanel: View {
    @Binding var dials: Dials
    let state: PhysicsState
    let onRestart: () -> Void
    let onPreset: (Dials) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                environmentSection
                simulationSection
                presetsSection
                readoutsSection
            }
            .padding(14)
        }
        .frame(maxWidth: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var environmentSection: some View {
        section("Environment") {
            ClimateSlider(
                title: "Room temperature",
                value: Binding(
                    get: { dials.roomTemperature },
                    set: { dials.roomTemperature = $0; dials.waterTemperature = min(dials.waterTemperature, $0) }),
                range: 15 ... 30,
                format: { String(format: "%.1f °C", $0) })
            ClimateSlider(
                title: "Water temperature",
                value: Binding(
                    get: { dials.waterTemperature },
                    set: { dials.waterTemperature = $0; dials.roomTemperature = max(dials.roomTemperature, $0) }),
                range: 5 ... 30,
                format: { String(format: "%.1f °C", $0) })
            ClimateSlider(
                title: "Humidity",
                value: Binding(
                    get: { dials.humidity },
                    set: { dials.humidity = $0 }),
                range: 0 ... 0.95,
                format: { String(format: "%.0f %%", $0 * 100) })
            ClimateSlider(
                title: "Airflow",
                value: Binding(
                    get: { dials.airflow },
                    set: { dials.airflow = $0 }),
                range: 0 ... 2,
                format: { String(format: "%.2f m/s", $0) })
        }
    }

    private var simulationSection: some View {
        section("Simulation") {
            Picker("Working fluid", selection: Binding(
                get: { dials.fluid },
                set: { dials.fluid = $0 })) {
                ForEach(FluidKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ClimateSlider(
                title: "Time scale",
                value: Binding(
                    get: { dials.timeScale },
                    set: { dials.timeScale = $0 }),
                range: 0.1 ... 2,
                format: { String(format: "%.2f ×", $0) })

            Toggle(isOn: Binding(
                get: { dials.xray },
                set: { dials.xray = $0 })) {
                Text("X-ray overlay")
            }
            .toggleStyle(.switch)

            Button(action: onRestart) {
                Label("Restart bird", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var presetsSection: some View {
        section("Presets") {
            Menu {
                ForEach(Dials.presets, id: \.name) { preset in
                    Button(preset.name) { onPreset(preset.dials) }
                }
            } label: {
                Label("Pick an environment", systemImage: "cloud.sun")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var readoutsSection: some View {
        section("Live state") {
            KeyValue(key: "T bulb", value: String(format: "%.2f °C", state.bulbTemperature))
            KeyValue(key: "T head", value: String(format: "%.2f °C", state.headTemperature))
            KeyValue(key: "ΔP", value: SceneText.pascalToKiloPascal(state.pressureDelta))
            KeyValue(key: "CG offset", value: SceneText.millimeters(state.centerOfGravity.x))
            KeyValue(key: "Torque", value: SceneText.torque(state.torque))
            KeyValue(key: "Felt", value: String(format: "%.0f %% wet", state.feltMoisture * 100))
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
                .kerning(0.6)
            content()
        }
    }
}

// MARK: Reusable pieces

private struct ClimateSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(format(value))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .accessibilityLabel(title)
        }
    }
}

private struct KeyValue: View {
    let key: String
    let value: String

    var body: some View {
        HStack {
            Text(key).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.caption, design: .monospaced))
        }
    }
}
