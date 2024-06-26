import Foundation

/// Deterministic, pure-ish integrator: `state × dials × Δt → state`.
/// No UI types, no clock reads — advance it externally in fixed substeps.
public struct SimulationEngine {
    /// Publicly readable; internal-settable so `@testable` hosts can craft
    /// hand-authored starting states (see `DrinkingBirdTests`).
    public internal(set) var state: PhysicsState
    public let dials: Dials

    /// Largest substep the engine is asked to integrate, s.
    public static let substep: Double = 0.002

    // Tunables that don't belong to any single submodel.
    /// Small deterministic "gust" so ambient evaporation breathes, not paces.
    static let gustAmplitude: Double = 0.12
    /// Pause-worthiness: how dry the felt must be before evaporation matters.
    static let evaporationMoistureFloor: Double = 0.02

    public init(dials: Dials = .standard) {
        self.dials = dials
        var initial = PhysicsState.initial(roomTemperature: dials.roomTemperature)
        initial.bulbTemperature = dials.roomTemperature + 0.02
        self.state = initial
    }

    /// Fresh/reset state with current dials.
    public mutating func reset() {
        var fresh = PhysicsState.initial(roomTemperature: dials.roomTemperature)
        fresh.bulbTemperature = dials.roomTemperature + 0.02
        state = fresh
    }

    /// Advances by up to `simSeconds` in internal substeps of at most `substep`.
    public mutating func advance(simSeconds: Double) {
        var remaining = max(simSeconds, 0)
        let stepSize = Self.substep
        while remaining > 0 {
            let dt = min(stepSize, remaining)
            step(dt: dt)
            remaining -= dt
        }
    }

    /// One integration tick of exactly `dt` seconds (simulated).
    public mutating func step(dt: Double) {
        let d = dials
        let fluid = FluidParams(for: d.fluid)
        let t = state.time
        state.time += dt

        // Deterministic ambient breathing (never random): two incommensurate waves.
        let gust = 1.0 + Self.gustAmplitude * sin(0.9 * t) + 0.06 * sin(1.37 * t + 0.7)

        // 1 ─ Thermodynamics: saturation pressures in both reservoirs.
        state.vaporPressureHead = ThermodynamicsModel.saturationPressure(fluid, celsius: state.headTemperature)
        state.vaporPressureBulb = ThermodynamicsModel.saturationPressure(fluid, celsius: state.bulbTemperature)
        state.pressureDelta = state.vaporPressureBulb - state.vaporPressureHead

        // 2 ─ Head-side energy balance: convection in, evaporation out, neck conduction.
        let qAir = ThermodynamicsModel.convectionPower(
            roomTemperature: d.roomTemperature,
            headTemperature: state.headTemperature,
            airflow: d.airflow) * gust
        let qEvap = ThermodynamicsModel.evaporationPower(
            fluid: fluid,
            headTemperature: state.headTemperature,
            roomTemperature: d.roomTemperature,
            humidity: d.humidity,
            airflow: d.airflow,
            moisture: state.feltMoisture) * gust
        let qNeck = ThermodynamicsModel.neckConductionPower(
            bulbTemperature: state.bulbTemperature,
            headTemperature: state.headTemperature)

        // Vapor shortcut hysteresis: opens essentially only once the bird is at/
        // past full tilt (pinned on the glass) and stays open through recovery
        // until it has swung most of the way back upright. Vapor bypass does NOT
        // occur mid-fall (the tube mouth is still submerged in the bulb).
        if state.angle >= 1.15 {
            state.vaporPathOpen = true
        } else if state.angle < 0.35 && state.angularVelocity < 0 {
            state.vaporPathOpen = false
        }
        let vaporPathOpen = state.beakInWater || state.vaporPathOpen
        let mixingRate = FluidModel.vaporMixingRate(tipped: vaporPathOpen)
        let mixingPull = mixingRate * dt * (state.bulbTemperature - state.headTemperature)

        let dqNet = qAir - qEvap + qNeck
        state.headTemperature += dt * dqNet / ThermodynamicsModel.headHeatCapacity + mixingPull
        // Evaporative cooling of a water-fed wick can only sink so far below the
        // drinking water (wick resistance); never above boiling-ish sanity.
        let coldFloor = max(d.waterTemperature - 12.0, 2.0)
        state.headTemperature = domainClamp(state.headTemperature, coldFloor, 45.0)

        state.bulbTemperature = ThermodynamicsModel.advanceBulbTemperature(
            state.bulbTemperature, roomTemperature: d.roomTemperature + 0.02, dt: dt)
        state.bulbTemperature -= 0.05 * dt * (state.bulbTemperature - state.headTemperature)

        // 3 ─ Solution transport.
        if vaporPathOpen {
            let drained = FluidModel.advanceTipped(
                headLiquid: state.headLiquidVolume,
                neckLiquid: state.neckLiquidVolume,
                dt: dt)
            state.headLiquidVolume = drained.head
            state.neckLiquidVolume = drained.neck
            state.neckColumnFraction = drained.neck /
                (BirdGeometry.neckCrossSection * BirdGeometry.neckFillLength)
        } else {
            let pumped = FluidModel.advanceUpright(
                dP: state.pressureDelta,
                headLiquid: state.headLiquidVolume,
                neckLiquid: state.neckLiquidVolume,
                fluid: fluid,
                dt: dt)
            state.headLiquidVolume = pumped.head
            state.neckLiquidVolume = pumped.neck
            state.neckColumnFraction = domainClamp(
                pumped.neck / (BirdGeometry.neckCrossSection * BirdGeometry.neckFillLength),
                0, 1)
        }

        // Liquid mass is conserved: the bulb simply holds the remainder.
        state.bulbLiquidVolume = domainClamp(
            BirdGeometry.liquidChargeVolume - state.headLiquidVolume - state.neckLiquidVolume,
            0, BirdGeometry.liquidChargeVolume)

        // 4 ─ Mechanics: masses, CG, torque, pendulum integration.
        let masses = MechanicsModel.massPoints(
            bulbLiquidVolume: state.bulbLiquidVolume,
            neckLiquidVolume: state.neckLiquidVolume,
            headLiquidVolume: state.headLiquidVolume,
            fluid: fluid,
            angle: state.angle)
        state.momentOfInertia = MechanicsModel.momentOfInertia(masses)
        state.centerOfGravity = MechanicsModel.centerOfGravity(masses)
        let wasInWater = state.beakInWater
        let (θ, ω, inWater) = MechanicsModel.advanceAngle(
            angle: state.angle,
            angularVelocity: state.angularVelocity,
            masses: masses,
            beakInWater: state.beakInWater,
            momentOfInertia: state.momentOfInertia,
            dt: dt)
        state.angle = θ
        state.angularVelocity = ω
        state.beakInWater = inWater
        state.torque = MechanicsModel.torque(masses: masses, angle: θ)

        // 5 ─ Drinking event: wet the felt (the toy's actual reset step).
        if inWater && !wasInWater {
            state.feltMoisture = 1.0
            // The soaked felt is at water temperature — a small dip.
            state.headTemperature = min(state.headTemperature, d.waterTemperature + 1.5)
            if let started = state.tipStartedAt {
                state.lastCyclePeriod = state.time - started
            }
            state.tipStartedAt = nil
            state.cycleCount += 1
        } else if inWater {
            // Continuous small cooling from the beak sitting in the tumbler.
            state.headTemperature += dt * 0.05 * (d.waterTemperature - state.headTemperature)
        } else if wasInWater {
            state.tipStartedAt = state.time
        }

        // 6 ─ Felt dries only when evaporation is meaningfully active.
        state.feltMoisture = FluidModel.advanceMoisture(
            state.feltMoisture,
            humidity: d.humidity,
            airflow: d.airflow,
            evaporationActive: qEvap > Self.evaporationMoistureFloor,
            dt: dt)

        // 7 ─ Derived lifecycle label (read-only; the numerics remain authoritative).
        state.phase = Self.derivedPhase(state)
    }

    // MARK: Derived phase

    static func derivedPhase(_ s: PhysicsState) -> PhysicsState.Phase {
        if s.beakInWater { return .drinking }
        let columnFull = s.neckColumnFraction >= 0.98
        let headPartlyFilled = s.neckLiquidVolume > 1e-8
            || s.headLiquidVolume > 1e-9
        let leaning = s.angle > 0.20

        if leaning && s.angularVelocity > -0.05 {
            return .tipping
        }
        if s.angularVelocity < -0.03 && s.angle > 0.005 {
            return .recovering
        }
        if s.pressureDelta > 120 && (columnFull || headPartlyFilled) {
            return .rising
        }
        return .warmingUp
    }
}
