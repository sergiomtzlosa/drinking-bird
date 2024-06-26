import Foundation

/// Thin presentation logic for the instrument panel: preset descriptions and
/// derived "what does the bird think it's like?" summaries.
///
/// (The "what-if experimentation panel" from the plan's v1.1 will grow here.)
struct InstrumentPanelViewModel {
    /// One-line description of each environment preset for tooltips.
    static let presetDescriptions: [String: String] = [
        "Hot desert day": "Dry heat — the felt flash-evaporates. Figure on a sprint.",
        "Cold dry winter": "Chill but thirsty air; slow, patient cycles.",
        "Bahamas humid": "Warm and soaking wet — evaporation barely wins.",
        "Calm cellar (near-stall)": "Cool, stagnant, damp. Enjoy the wobble; expect stalling.",
    ]

    var state: PhysicsState

    /// Headline sentence describing what the bird is up against right now.
    var environmentSummary: String {
        let humidityWord: String
        switch state.feltMoisture {
        case ..<0.15: humidityWord = "felt nearly bone-dry"
        case ..<0.6: humidityWord = "felt drying"
        default: humidityWord = "felt soaked"
        }
        return String(
            format: "Room %.1f °C · %.0f %% RH · %@",
            state.bulbTemperature, state.feltMoisture * 100, humidityWord)
    }
}
