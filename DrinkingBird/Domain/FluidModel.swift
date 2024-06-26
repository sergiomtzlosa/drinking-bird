import Foundation

/// Liquid transport inside the glassware: how the vapor-pressure differential
/// pumps dyed liquid up the neck tube and into the head, and how it drains back
/// while the bird is tipped over.
public enum FluidModel {
    // MARK: Tunable constants

    /// Effective volume conductance of the neck tube, m³/(s·Pa).
    /// The real transport is vapor-mediated and far from Poiseuille-simple;
    /// this constant is tuned so a healthy temperature gradient fills the head
    /// in tens of seconds of simulated time.
    static let tubeConductance: Double = 2.0e-9

    /// Vertical rise the column must overcome to reach the head — shared
    /// with `BirdGeometry` so physics and drawing stay consistent.
    static var liftHeight: Double { BirdGeometry.liftHeight }

    /// Time constant of the vapor shortcut while resting at full tilt: vapor
    /// bubbles through the exposed tube mouth over a couple of seconds, s.
    static let vaporEqualizationTime: Double = 2.5
    /// Time constant for draining the head cavity while tipped, s.
    public static let headDrainTime: Double = 3.0
    /// Time constant for gravitationally draining the tube while tipped, s.
    static let tubeDrainTime: Double = 0.6

    /// How fast the wet felt dries, proportional to (1 − RH), 1/s at RH 0.
    static let feltDryingBaseRate: Double = 0.006

    // MARK: Column & overflow dynamics (upright)

    /// Ceiling on transport rate, m³/s — vapor-driven pumping saturates; keeps
    /// hot, low-ρ fluids (DCM) from being comically fast.
    static let maxPumpRate: Double = 4.0e-6

    /// Advances fluid distribution while the bird is upright.
    ///
    /// `dP` is the vapor-pressure differential (bulb side minus head side, Pa).
    /// Returns updated `(headLiquidVolume, neckLiquidVolume)`.
    public static func advanceUpright(
        dP: Double,
        headLiquid: Double,
        neckLiquid: Double,
        fluid: FluidParams,
        dt: Double
    ) -> (head: Double, neck: Double) {
        let g = 9.80665
        let tubeHeight = neckLiquid / BirdGeometry.neckCrossSection
        // Hydrostatic load the pump must beat: what's already in the tube,
        // plus the fixed lift from bulb surface to head cavity.
        let hydrostatic = fluid.density * g * max(0, tubeHeight)
        let excess = dP - fluid.density * g * liftHeight - hydrostatic
        guard excess > 0, headLiquid <= BirdGeometry.headCapacity else {
            return (headLiquid, neckLiquid)
        }
        let pumpedVolume = min(tubeConductance * excess * dt, maxPumpRate * dt)

        var neck = neckLiquid
        var head = headLiquid
        let tubeFreeVolume = (BirdGeometry.neckFillLength - tubeHeight) * BirdGeometry.neckCrossSection

        if tubeFreeVolume > 0 {
            let intoTube = min(pumpedVolume, tubeFreeVolume)
            neck += intoTube
        }
        // Whatever overflows the tube ends up in the head cavity.
        let overflow = pumpedVolume - min(pumpedVolume, tubeFreeVolume)
        head = min(head + overflow, BirdGeometry.headCapacity)
        return (head, neck)
    }

    // MARK: Drain dynamics (tipped, vapor shortcut open)

    /// Advances fluid distribution and thermal mixing while the beak is in the
    /// water: vapor bypasses from the bulb straight into the head, ΔP collapses,
    /// and liquid pours back down under gravity.
    ///
    /// `thermalMixingRate` is the extra tempering coefficient between the two
    /// reservoirs (1/s) that the open vapor path provides.
    public static func advanceTipped(
        headLiquid: Double,
        neckLiquid: Double,
        dt: Double
    ) -> (head: Double, neck: Double) {
        let head = max(0, headLiquid - dt * headLiquid / headDrainTime)
        let neck = max(0, neckLiquid - dt * neckLiquid / tubeDrainTime)
        return (head, neck)
    }

    /// Extra temperature coupling (1/s) between bulb and head while the neck tube
    /// is open to vapor flow (bird tipped or column fully gassed past).
    public static func vaporMixingRate(tipped: Bool) -> Double {
        tipped ? 1 / vaporEqualizationTime : 0
    }

    // MARK: Felt moisture bookkeeping

    /// Advances felt dryness one tick; ambient conditions modulate the rate.
    public static func advanceMoisture(
        _ moisture: Double,
        humidity relativeHumidity: Double,
        airflow: Double,
        evaporationActive: Bool,
        dt: Double
    ) -> Double {
        guard evaporationActive else { return moisture }
        let rate = feltDryingBaseRate * (1.0 - relativeHumidity) / (1.0 + 0.6 * max(airflow, 0))
        let drier = moisture - rate * dt
        return domainClamp(drier, 0, 1)
    }
}
