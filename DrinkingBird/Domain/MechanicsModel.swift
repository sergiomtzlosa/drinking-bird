import Foundation

/// Mass distribution and rigid-body pendulum dynamics of the bird about the
/// leg pivot. The glass assembly (bulb + neck + head) rotates; the legs and
/// boots stay planted.
public enum MechanicsModel {
    /// A point mass fixed in the bird's body frame.
    public struct MassPoint: Sendable {
        public let mass: Double
        public let position: Vec2
    }

    // MARK: Structural masses (kg)

    static let bulbGlassMass: Double = 0.030
    static let neckGlassMass: Double = 0.005
    static let headGlassMass: Double = 0.008
    /// Felt cap, top hat and googly eye — the felt is meaty when soaked.
    static let feltAndHatMass: Double = 0.012
    /// Beak cone — its forward pull is what makes the bird dip toward the glass.
    static let beakMass: Double = 0.004
    /// Green feathers — keep the resting lean gentle, not tail-planted.
    static let tailMass: Double = 0.005
    static let tailPosition = Vec2(x: 0.020, y: -0.002)

    /// Extra rotational inertia from the distributed glass shells, kg·m².
    static let distributedInertia: Double = 4.0e-5

    /// Rotational drag while free, kg·m²/s (per rad/s).
    static let freeDamping: Double = 0.020
    /// Rotational "stickiness" of the beak resting on the glass rim.
    static let contactDamping: Double = 0.9

    /// Torque threshold (pulling upright) above which the beak leaves the water.
    /// Tuned so the bird drains to a comfortable margin below its tip-fill level
    /// before lifting off — verified by the no-re-tip test.
    static let releaseTorque: Double = -0.008

    /// Builds the instantaneous mass distribution for the current liquid volumes.
    ///
    /// As the bird leans over, liquid in the head slides toward the beak
    /// (gravity pulls it into the head's lower-front) — exactly the positive
    /// feedback that makes the real toy slam over once it starts tipping.
    public static func massPoints(
        bulbLiquidVolume: Double,
        neckLiquidVolume: Double,
        headLiquidVolume: Double,
        fluid: FluidParams,
        angle: Double = 0
    ) -> [MassPoint] {
        var points: [MassPoint] = [
            MassPoint(mass: bulbGlassMass, position: BirdGeometry.bulbCenter),
            MassPoint(mass: neckGlassMass, position: Vec2(
                x: 0, y: (BirdGeometry.neckBottom.y + BirdGeometry.neckTop.y) / 2)),
            MassPoint(mass: headGlassMass, position: BirdGeometry.headCenter),
            MassPoint(mass: feltAndHatMass, position: BirdGeometry.hatAnchor),
            MassPoint(mass: beakMass, position: BirdGeometry.beakCenter),
            MassPoint(mass: tailMass, position: tailPosition),
        ]

        let ρ = fluid.density
        points.append(MassPoint(mass: ρ * bulbLiquidVolume, position: BirdGeometry.bulbCenter))

        if neckLiquidVolume > 0 {
            let tubeHeight = min(neckLiquidVolume / BirdGeometry.neckCrossSection, BirdGeometry.neckFillLength)
            let position = Vec2(
                x: 0,
                y: BirdGeometry.neckBottom.y + tubeHeight / 2)
            points.append(MassPoint(mass: ρ * neckLiquidVolume, position: position))
        }

        if headLiquidVolume > 0 {
            let fill = min(headLiquidVolume / BirdGeometry.headCapacity, 1)
            let surge = fill * (0.012 + 0.040 * max(sin(angle), 0))
            let pooled = Vec2(
                x: BirdGeometry.headCenter.x - surge,
                y: BirdGeometry.headCenter.y - 0.008 * fill)
            points.append(MassPoint(mass: ρ * headLiquidVolume, position: pooled))
        }

        return points
    }

    /// Center of gravity in the body frame, relative to the pivot.
    public static func centerOfGravity(_ masses: [MassPoint]) -> Vec2 {
        var weighted = Vec2.zero
        var total = 0.0
        for m in masses {
            weighted = weighted + m.position * m.mass
            total += m.mass
        }
        guard total > 0 else { return .zero }
        return weighted * (1.0 / total)
    }

    /// Net gravitational torque about the pivot, N·m, at tilt angle θ.
    /// Positive torque pushes the bird toward the glass (θ grows).
    /// Convention: `worldX(p, θ) = p.x·cosθ − p.y·sinθ`, `τ = −m·g·worldX`.
    public static func torque(masses: [MassPoint], angle θ: Double) -> Double {
        let g = 9.80665
        let c = cos(θ), s = sin(θ)
        var τ = 0.0
        for m in masses where m.mass > 0 {
            let worldX = m.position.x * c - m.position.y * s
            τ -= m.mass * g * worldX
        }
        return τ
    }

    /// Rotational inertia about the pivot, kg·m².
    public static func momentOfInertia(_ masses: [MassPoint]) -> Double {
        var inertia = distributedInertia
        for m in masses {
            let p = m.position
            inertia += m.mass * (p.x * p.x + p.y * p.y)
        }
        return inertia
    }

    /// Integrates the tilt angle one tick (semi-implicit Euler), with contact
    /// constraints, tail-stop clamp, and damping.
    ///
    /// Returns updated `(angle, angularVelocity, beakInWater)`.
    public static func advanceAngle(
        angle: Double,
        angularVelocity ω: Double,
        masses: [MassPoint],
        beakInWater: Bool,
        momentOfInertia inertia: Double,
        dt: Double
    ) -> (angle: Double, angularVelocity: Double, beakInWater: Bool) {
        var θ = angle
        var ω = ω
        var inWater = beakInWater

        let τ = torque(masses: masses, angle: θ)
        let damping = inWater ? max(contactDamping, freeDamping) : freeDamping

        if inWater {
            // The beak rests against the glass rim; the bird sits pinned while
            // liquid drains. Release when restoring torque is strong enough.
            if τ < releaseTorque {
                inWater = false
                ω = 0
            } else {
                θ = BirdGeometry.contactAngle
                ω = 0
                return (θ, ω, inWater)
            }
        }

        // Free pendulum integration.
        ω += dt * (τ / max(inertia, 1e-9) - damping * ω / max(inertia, 1e-9))
        θ += ω * dt

        // Beak contact: entering the water pins the bird.
        if θ >= BirdGeometry.contactAngle {
            θ = BirdGeometry.contactAngle
            if ω > 0 { inWater = true }
            ω = min(ω, 0)
        }

        // Tail feathers hit the boots on the back side.
        if θ < BirdGeometry.maxBackwardLean {
            θ = BirdGeometry.maxBackwardLean
            ω = max(-ω, 0)
        }

        return (θ, ω, inWater)
    }
}
