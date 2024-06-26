import Foundation

/// Fluid thermodynamic constants used by `ThermodynamicsModel`.
public struct FluidParams: Equatable, Sendable {
    public let kind: FluidKind
    /// kg/mol
    public let molarMass: Double
    /// J/mol
    public let vaporizationHeat: Double
    /// Normal boiling point, K (reference point for Clausius–Clapeyron).
    public let boilingPoint: Double
    /// Saturation pressure at the boiling point: 101 325 Pa by definition.
    public let pReference: Double
    /// Dynamic viscosity of the liquid, Pa·s (affects nothing drain-critical,
    /// but kept as a knob).
    public let dynamicViscosity: Double
    /// Liquid density, kg/m³.
    public let density: Double

    public static let dichloromethane = FluidParams(
        kind: .dichloromethane,
        molarMass: 0.08493,
        vaporizationHeat: 28.5e3,
        boilingPoint: 312.75,        // 39.6 °C
        pReference: 101_325,
        dynamicViscosity: 4.3e-4,
        density: 1330
    )

    public static let isopropanol = FluidParams(
        kind: .isopropanol,
        molarMass: 0.0601,
        vaporizationHeat: 43.9e3,
        boilingPoint: 355.6,         // 82.5 °C
        pReference: 101_325,
        dynamicViscosity: 2.4e-3,
        density: 786
    )

    public init(for kind: FluidKind) {
        switch kind {
        case .dichloromethane: self = .dichloromethane
        case .isopropanol: self = .isopropanol
        }
    }

    init(
        kind: FluidKind,
        molarMass: Double,
        vaporizationHeat: Double,
        boilingPoint: Double,
        pReference: Double,
        dynamicViscosity: Double,
        density: Double
    ) {
        self.kind = kind
        self.molarMass = molarMass
        self.vaporizationHeat = vaporizationHeat
        self.boilingPoint = boilingPoint
        self.pReference = pReference
        self.dynamicViscosity = dynamicViscosity
        self.density = density
    }

    static subscript(kind: FluidKind) -> FluidParams {
        FluidParams(for: kind)
    }
}

public enum ThermodynamicsModel {
    // MARK: Tunable transport constants (SI)

    /// Mass-transfer coefficient of the wet felt surface, m/s. Felt is thin,
    /// porous and breatheable — transport is brisk.
    static let massTransferCoefficient: Double = 0.012
    /// Effective wetted area of the felt cap, m².
    static let feltArea: Double = 0.007
    /// Convective film coefficient (still air), W/(m²·K). Low on purpose: the
    /// green tail feathers insulate the head, exactly as in the real toy.
    static let convectionStill: Double = 4.5
    /// Conductance of the glass neck between bulb and head, W/K.
    static let neckConductance: Double = 0.03
    /// Heat capacity of head assembly (glass + felt + hat), J/K.
    static let headHeatCapacity: Double = 9.0
    /// Heat capacity of the bulb assembly, J/K.
    static let bulbHeatCapacity: Double = 55.0
    /// Time constant with which the large warm bulb tracks room temperature, s.
    static let bulbTimeConstant: Double = 9.0

    public static let gasConstant: Double = 8.3144626

    // MARK: Saturation vapor pressure (Clausius–Clapeyron)

    /// Saturation vapor pressure of the working fluid, Pa, from Clausius–Clapeyron
    /// anchored at the normal boiling point. Smooth, monotone, and physically honest
    /// to within a few percent for the sub-100 °C range both toy fluids live in.
    public static func saturationPressure(_ fluid: FluidParams, celsius t: Double) -> Double {
        let temperatureKelvin = max(t + 273.15, 200)
        let exponent = -fluid.vaporizationHeat / gasConstant
            * (1 / temperatureKelvin - 1 / fluid.boilingPoint)
        return fluid.pReference * exp(exponent)
    }

    // MARK: Evaporative cooling

    /// Sum over the atmosphere of the vapor-difference factor: evaporation of the
    /// wet felt competes with the ambient vapor already in the air.
    public static func evaporationPower(
        fluid: FluidParams,
        headTemperature tHead: Double,
        roomTemperature tRoom: Double,
        humidity relativeHumidity: Double,
        airflow: Double,
        moisture: Double
    ) -> Double {
        guard moisture > 0 else { return 0 }
        let pHead = saturationPressure(fluid, celsius: tHead)
        let pRoom = saturationPressure(fluid, celsius: tRoom)
        // Vapor pressure gradient across the boundary layer above the felt.
        let densityGradient = max(0, (pHead - relativeHumidity * pRoom)) / (gasConstant * kelvin(tHead))
        // Airflow thins the boundary layer (sub-linear, as in convective transport).
        let airflowFactor = 1.0 + 0.9 * pow(max(airflow, 0), 0.7)
        let molarFlux = massTransferCoefficient * feltArea * densityGradient * airflowFactor
        // Felt never transmits more than its saturation capacity; a half-dry
        // wick still evaporates most of its peak (it stays damp to the touch).
        let moistureFactor = 0.35 + 0.65 * min(max(moisture, 0), 1)
        // Heat drawn out of the head: W (molar flux × latent heat).
        return molarFlux * fluid.vaporizationHeat * moistureFactor
    }

    /// Convective heat flowing INTO the head from the ambient air, W.
    public static func convectionPower(
        roomTemperature tRoom: Double,
        headTemperature tHead: Double,
        airflow: Double
    ) -> Double {
        let filmConvection = convectionStill * (1.0 + 0.8 * max(airflow, 0))
        return filmConvection * feltArea * (tRoom - tHead)
    }

    /// Heat conducted along the glass neck from the warm bulb, W.
    public static func neckConductionPower(
        bulbTemperature tBulb: Double,
        headTemperature tHead: Double
    ) -> Double {
        neckConductance * (tBulb - tHead)
    }

    /// Advances head temperature one tick. Returns the new temperature.
    public static func advanceHeadTemperature(
        _ tHead: Double,
        powerIn: Double,
        clampedBetween lower: Double,
        upper: Double,
        heatCapacity c: Double = 18.0,
        dt: Double
    ) -> Double {
        let next = tHead + dt * powerIn / c
        return domainClamp(next, lower, upper)
    }

    /// Advances bulb temperature one tick toward the ambient temperature.
    public static func advanceBulbTemperature(
        _ tBulb: Double,
        roomTemperature tRoom: Double,
        dt: Double,
        timeConstant τ: Double = 9.0
    ) -> Double {
        let blend = min(max(dt / τ, 0), 1)
        return tBulb + (tRoom - tBulb) * blend
    }

    static func kelvin(_ celsius: Double) -> Double { max(celsius, -60) + 273.15 }
}

/// Tiny internal clamp used across the domain layer.
@inline(__always)
func domainClamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    return min(max(value, lower), upper)
}
