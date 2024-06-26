import Foundation

/// The volatile working fluid of the bird's heat engine.
public enum FluidKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case dichloromethane
    case isopropanol

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dichloromethane: return "Dichloromethane"
        case .isopropanol: return "Isopropyl alcohol"
        }
    }

    /// Short label for UI pickers.
    public var shortName: String {
        switch self {
        case .dichloromethane: return "DCM"
        case .isopropanol: return "IPA"
        }
    }
}

/// Everything the user can turn while the simulation is running.
/// All temperatures in °C, pressures in Pa, times in seconds, SI meters throughout.
public struct Dials: Equatable, Codable, Sendable {
    public var roomTemperature: Double
    public var waterTemperature: Double
    /// Fraction 0…1.
    public var humidity: Double
    /// m/s of ambient airflow over the felt head.
    public var airflow: Double
    public var fluid: FluidKind
    /// Simulation speed vs. real time. 1.0 = true seconds.
    public var timeScale: Double
    /// Whether the x-ray overlay (CG, ΔP, torque) is drawn.
    public var xray: Bool

    public init(
        roomTemperature: Double = 22,
        waterTemperature: Double = 20,
        humidity: Double = 0.45,
        airflow: Double = 0.3,
        fluid: FluidKind = .isopropanol,
        timeScale: Double = 1.0,
        xray: Bool = false
    ) {
        self.roomTemperature = roomTemperature
        self.waterTemperature = waterTemperature
        self.humidity = humidity
        self.airflow = airflow
        self.fluid = fluid
        self.timeScale = timeScale
        self.xray = xray
    }

    public static let standard = Dials()

    /// Named environment presets offered by the instrument panel.
    public static let presets: [(name: String, dials: Dials)] = [
        ("Hot desert day", Dials(roomTemperature: 30, waterTemperature: 24, humidity: 0.12, airflow: 0.5)),
        ("Cold dry winter", Dials(roomTemperature: 17, waterTemperature: 8, humidity: 0.20, airflow: 0.2)),
        ("Bahamas humid", Dials(roomTemperature: 27, waterTemperature: 26, humidity: 0.88, airflow: 0.4)),
        ("Calm cellar (near-stall)", Dials(roomTemperature: 18, waterTemperature: 17, humidity: 0.93, airflow: 0.1)),
    ]
}
