import Foundation

/// Minimal 2D vector used by both the physics engine and the drawing layer,
/// in real SI units (meters). Origin conventions are defined in `BirdGeometry`.
public struct Vec2: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(x: 0, y: 0)

    public static func + (lhs: Vec2, rhs: Vec2) -> Vec2 { Vec2(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    public static func - (lhs: Vec2, rhs: Vec2) -> Vec2 { Vec2(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    public static func * (lhs: Vec2, scalar: Double) -> Vec2 { Vec2(x: lhs.x * scalar, y: lhs.y * scalar) }
    public static func * (scalar: Double, lhs: Vec2) -> Vec2 { lhs * scalar }

    public var magnitude: Double { (x * x + y * y).squareRoot() }
}

/// Canonical geometry of the drinking bird, in meters (toy-sized bird ~18 cm tall).
///
/// All coordinates live in the **body frame**: the origin is the leg pivot (the red
/// crossbar in the reference photo), +y points up, and the beak points toward −x
/// (the glass sits on the −x side, as in the product photo `619LgYGxolL.jpg`).
///
/// These constants are used *both* by the physics integrator and the drawing code
/// so visuals and physics can never drift apart.
public enum BirdGeometry {
    // MARK: Liquid reservoirs

    /// Total dyed-liquid charge in the toy, m³ (~55 mL).
    public static let liquidChargeVolume: Double = 5.5e-5
    /// Full spherical capacity of the lower bulb, m³.
    public static let bulbCapacity: Double = 1.6e-4
    /// Full capacity of the glass head, m³ (sphere of `headRadius`).
    public static let headCapacity: Double = (4.0 / 3.0) * .pi * pow(headRadius, 3)

    // MARK: Body-frame anchors

    /// Center of the lower bulb (hangs below the pivot — the pendulum side).
    public static let bulbCenter = Vec2(x: 0.000, y: -0.060)
    /// Bottom end of the glass neck tube (dips into the bulb).
    public static let neckBottom = Vec2(x: 0.000, y: -0.016)
    /// Top end of the glass neck tube (enters the head).
    public static let neckTop = Vec2(x: 0.000, y: 0.050)
    /// Center of the head (sits above the pivot — the destabilizing side).
    public static let headCenter = Vec2(x: -0.002, y: 0.068)
    /// Where the felt cap + top hat sit (a touch toward the beak side — this
    /// gives the bird its slight forward bias, like the real toy).
    public static let hatAnchor = Vec2(x: -0.002, y: 0.086)
    /// Center of mass of the beak cone itself.
    public static let beakCenter = Vec2(x: -0.030, y: 0.062)
    /// Very tip of the beak — this is the point that reaches the drinking water.
    public static let beakTip = Vec2(x: -0.048, y: 0.068)
    /// Root of the green tail feathers (behind the bulb, +x side).
    public static let tailAnchor = Vec2(x: 0.014, y: -0.006)

    // MARK: Static scenery (world frame relative to the pivot)

    /// The water tumbler. Water surface is placed so the beak tip touches it
    /// exactly at `contactAngle` — verified by the unit tests.
    public static let glassFrame = (
        minX: -0.130, maxX: -0.052,
        rimY: -0.012, bottomY: -0.088,
        waterY: -0.021
    )

    /// Boots/base footprint (stays fixed — only the glass body rotates).
    public static let bootFrame = (
        minX: -0.054, maxX: 0.064,
        bottomY: -0.138, topY: -0.072
    )

    // MARK: Radii

    public static let bulbRadius: Double = 0.034
    public static let headRadius: Double = 0.026
    public static let neckOuterRadius: Double = 0.0055
    public static let neckInnerRadius: Double = 0.0035
    /// Tube cross-section, m² (π r² of the inner bore).
    public static let neckCrossSection: Double = .pi * neckInnerRadius * neckInnerRadius
    /// Occupy-able length of the neck tube, m (slightly less than the drawn tube).
    public static let neckFillLength: Double = 0.050
    /// Vertical rise from the bulb liquid surface to the head cavity, m.
    public static let liftHeight: Double = 0.060

    // MARK: Beak immersion

    /// Angle at which the beak tip dips into the water surface of the glass.
    /// Computed so `bodyWorld(beakTip, angle) ≈ (−0.086, waterY)`.
    public static let contactAngle: Double = 1.20  // rad, ≈ 69°
    /// Hysteresis before the beak is declared out of the water again.
    public static let contactHysteresis: Double = 0.08
    /// How far the bird may lean backward before the tail rests on the boots.
    public static let maxBackwardLean: Double = -0.22

    /// Rotates a body-frame point by the bird's tilt angle θ.
    /// θ>0 tilts the bird toward the glass (mathematically CCW with +y up).
    public static func bodyWorld(_ p: Vec2, angle θ: Double) -> Vec2 {
        let c = cos(θ), s = sin(θ)
        return Vec2(x: p.x * c - p.y * s, y: p.x * s + p.y * c)
    }
}
