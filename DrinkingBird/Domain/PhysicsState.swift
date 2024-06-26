import Foundation

/// Complete, deterministic snapshot of everything the simulation knows.
/// The engine is a pure function `PhysicsState × Dials × Δt → PhysicsState`,
/// so this struct is what flows to tests, the view layer, and any recorder.
public struct PhysicsState: Equatable, Codable, Sendable {
    /// High-level lifecycle of the bird — always *derived* from the numeric
    /// state below, never authoritative.
    public enum Phase: String, Codable, Sendable {
        case warmingUp   // temperature gradient building, liquid idle
        case rising      // column climbing the neck / head filling
        case tipping     // top-heavy, rotating toward the glass
        case drinking    // beak in water: wetting, vapor bypass, draining
        case recovering  // returning upright under restoring torque
    }

    public var time: Double

    // Thermodynamics
    public var headTemperature: Double      // °C, the wet felt head
    public var bulbTemperature: Double      // °C, the warm lower bulb
    public var vaporPressureHead: Double    // Pa
    public var vaporPressureBulb: Double    // Pa
    public var pressureDelta: Double        // Pa, P_bulb − P_head

    // Fluid distribution
    public var neckColumnFraction: Double   // 0…1, how full the neck tube is
    public var headLiquidVolume: Double     // m³ migrated into the head
    public var neckLiquidVolume: Double     // m³ inside the tube
    public var bulbLiquidVolume: Double     // m³ remaining in the bulb
    public var feltMoisture: Double         // 0…1 dryness of the felt

    // Mechanics
    public var angle: Double                // rad; 0 upright, + toward the glass
    public var angularVelocity: Double      // rad/s
    public var beakInWater: Bool
    public var centerOfGravity: Vec2        // body frame, relative to pivot
    public var torque: Double               // N·m about the pivot
    public var momentOfInertia: Double      // kg·m²

    // Bookkeeping
    public var phase: Phase
    public var cycleCount: Int
    public var lastCyclePeriod: Double?     // seconds, of the last completed drink
    public var tipStartedAt: Double?
    /// Hysteresis flag: vapor path stays open from first big tilt until the bird
    /// has swung most of the way back upright.
    public var vaporPathOpen: Bool = false

    public init(
        time: Double = 0,
        headTemperature: Double,
        bulbTemperature: Double,
        vaporPressureHead: Double = 0,
        vaporPressureBulb: Double = 0,
        pressureDelta: Double = 0,
        neckColumnFraction: Double = 0,
        headLiquidVolume: Double = 0,
        neckLiquidVolume: Double = 0,
        bulbLiquidVolume: Double = BirdGeometry.liquidChargeVolume,
        feltMoisture: Double = 1,
        angle: Double = 0,
        angularVelocity: Double = 0,
        beakInWater: Bool = false,
        centerOfGravity: Vec2 = .zero,
        torque: Double = 0,
        momentOfInertia: Double = 0,
        phase: Phase = .warmingUp,
        cycleCount: Int = 0,
        lastCyclePeriod: Double? = nil,
        tipStartedAt: Double? = nil,
        vaporPathOpen: Bool = false
    ) {
        self.time = time
        self.headTemperature = headTemperature
        self.bulbTemperature = bulbTemperature
        self.vaporPressureHead = vaporPressureHead
        self.vaporPressureBulb = vaporPressureBulb
        self.pressureDelta = pressureDelta
        self.neckColumnFraction = neckColumnFraction
        self.headLiquidVolume = headLiquidVolume
        self.neckLiquidVolume = neckLiquidVolume
        self.bulbLiquidVolume = bulbLiquidVolume
        self.feltMoisture = feltMoisture
        self.angle = angle
        self.angularVelocity = angularVelocity
        self.beakInWater = beakInWater
        self.centerOfGravity = centerOfGravity
        self.torque = torque
        self.momentOfInertia = momentOfInertia
        self.phase = phase
        self.cycleCount = cycleCount
        self.lastCyclePeriod = lastCyclePeriod
        self.tipStartedAt = tipStartedAt
        self.vaporPathOpen = vaporPathOpen
    }
}

extension PhysicsState {
    /// State used when the app starts: bird upright, felt wet, everything at room temp.
    public static func initial(roomTemperature: Double = 22, bulbTemperature: Double? = nil) -> PhysicsState {
        let bulb = bulbTemperature ?? roomTemperature
        return PhysicsState(
            headTemperature: roomTemperature,
            bulbTemperature: bulb,
            bulbLiquidVolume: BirdGeometry.liquidChargeVolume)
    }
}
