import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = BirdViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                BirdScene3DView(state: viewModel.snapshot, xray: viewModel.dials.xray)
                    .frame(minWidth: 660)
                InstrumentPanel(
                    dials: $viewModel.dials,
                    state: viewModel.snapshot,
                    onRestart: { viewModel.restart() },
                    onPreset: { viewModel.applyPreset($0) })
                    .frame(minWidth: 300, idealWidth: 320)
            }
            StatusBar(state: viewModel.snapshot)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
        }
    }
}

/// Bottom readout strip: the numeric nervous system of the toy.
struct StatusBar: View {
    let state: PhysicsState

    var body: some View {
        HStack(spacing: 18) {
            readout("Tᵇᵘˡᵇ", value: String(format: "%.1f °C", state.bulbTemperature))
            readout("Tᵐᵉᵃᵈ", value: String(format: "%.1f °C", state.headTemperature))
            readout("ΔP", value: String(format: "%+.2f kPa", state.pressureDelta / 1000))
            readout("θ", value: String(format: "%+.1f°", state.angle * 180 / .pi))
            Spacer()
            Text(phaseLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.accentColor)
            Text("Drinks: \(state.cycleCount)")
                .font(.system(.caption, design: .monospaced))
            if let period = state.lastCyclePeriod {
                Text("Cycle: \(String(format: "%.1f s", period))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    var phaseLabel: String {
        switch state.phase {
        case .warmingUp: return "Warming up…"        // feel the gradient build
        case .rising: return "Liquid rising"
        case .tipping: return "Tipping!"
        case .drinking: return "Drinking… glug"
        case .recovering: return "Recovering"
        }
    }

    @ViewBuilder
    private func readout(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.caption, design: .monospaced))
        }
    }
}
