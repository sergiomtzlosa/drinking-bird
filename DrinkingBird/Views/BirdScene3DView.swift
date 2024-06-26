import SwiftUI
import SceneKit

/// 3D drinking bird scene (SceneKit), hosted in SwiftUI. Every visual property
/// is driven from the `PhysicsState` snapshot — nothing here is canned.
struct BirdScene3DView: View {
    let state: PhysicsState
    let xray: Bool
    @State private var resetCounter = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            SceneViewHost(state: state, resetToken: resetCounter)
            if xray {
                HUDOverlay(state: state)
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                resetCounter += 1
            } label: {
                Label("Center view", systemImage: "arrow.counterclockwise.circle")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.borderless)
            .help("Center the 3D model in the viewport")
            .padding(10)
        }
        .accessibilityLabel("Drinking bird 3D simulation")
    }
}

// MARK: - SCNView bridge

private struct SceneViewHost: NSViewRepresentable {
    let state: PhysicsState
    let resetToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        let rig = BirdScene3DBuilder.makeScene()
        context.coordinator.rig = rig
        context.coordinator.lastResetToken = resetToken
        view.scene = rig.scene
        view.pointOfView = rig.cameraNode
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = true
        context.coordinator.apply(state)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.centerCamera()
            view.pointOfView = context.coordinator.rig?.cameraNode
        }
        context.coordinator.apply(state)
    }
}

/// Applies each physics snapshot to the SceneKit node graph.
private final class Coordinator {
    var rig: BirdScene3DBuilder.Rig?
    var lastResetToken = 0

    /// Restores the default, scene-centered camera framing.
    func centerCamera() {
        guard let rig else { return }
        rig.cameraNode.transform = rig.initialCameraTransform
    }

    func apply(_ state: PhysicsState) {
        guard let rig else { return }
        let θ = Float(state.angle)

        // Bird tilt: +θ about z maps exactly like BirdGeometry.bodyWorld.
        rig.birdNode.rotation = SCNVector4(0, 0, 1, θ)

        // Liquids stay level with the world horizon, so counter-rotate the
        // pool caps inside the bird. The neck column is NOT counter-rotated:
        // it must follow the tube walls as the bird tips (a world-vertical
        // column pierces the tipped tube), so it rides along like the pipe.
        rig.bulbLiquidNode.eulerAngles = SCNVector3(0, 0, -θ)
        rig.headLiquidNode.eulerAngles = SCNVector3(0, 0, -θ)

        // Liquid meshes: rebuilt only when fill changed appreciably.
        let headFill = fillFraction(state.headLiquidVolume, BirdGeometry.headCapacity)
        let bulbFill = fillFraction(state.bulbLiquidVolume, BirdGeometry.bulbCapacity)
        if abs(headFill - Double(rig.lastHeadFill)) > 0.02 {
            rig.lastHeadFill = Float(headFill)
            BirdScene3DBuilder.setLiquidGeometry(rig.headLiquidNode,
                                                 radius: BirdScene3DBuilder.headLiquidRadius,
                                                 fill: headFill)
        }
        if abs(bulbFill - Double(rig.lastBulbFill)) > 0.02 {
            rig.lastBulbFill = Float(bulbFill)
            BirdScene3DBuilder.setLiquidGeometry(rig.bulbLiquidNode,
                                                 radius: BirdScene3DBuilder.bulbLiquidRadius,
                                                 fill: bulbFill)
        }
        rig.headLiquidNode.opacity = 0  // hidden under the painted head shell

        // Neck column: unit-height (1 m) cylinder; each frame place its
        // CENTER so the column spans exactly from the submerged pipe bottom
        // in the bulb up to the physics top (neckBottom + frac·neckFillLength).
        // No pivot tricks — position + scale are unambiguous.
        let submerged = BirdGeometry.neckBottom.y - BirdScene3DBuilder.neckPipeBottom
        let columnMeters = max(0.002, submerged
            + state.neckColumnFraction * BirdGeometry.neckFillLength)
        rig.neckLiquidNode.position = SCNVector3(0, Float(BirdScene3DBuilder.neckPipeBottom
            + columnMeters / 2), 0)
        rig.neckLiquidNode.scale = SCNVector3(1, Float(columnMeters), 1)

        // Pump bubbles rising in the neck.
        let pumping = state.pressureDelta > 350
            && state.neckColumnFraction < 0.99
            && !state.beakInWater
        for (i, bubble) in rig.bubbleNodes.enumerated() {
            if pumping {
                let phase: Double = fmod(state.time * 0.55 + Double(i) * 0.5, 1)
                let rise: Double = state.neckColumnFraction * BirdGeometry.neckFillLength * phase
                let bubbleY: Float = Float(BirdScene3DBuilder.neckPipeBottom + rise)
                let bubbleZ: Float = Float(0.002 + Double(i) * 0.001)
                bubble.position = SCNVector3(0, bubbleY, bubbleZ)
                bubble.opacity = pumping ? 0.8 : 0
            } else {
                bubble.opacity = 0
            }
        }

        // Feather boa sway + eye jiggle driven by angular velocity.
        let wobble = Double(abs(state.angularVelocity))
        let flutter: Double = sin(state.time * 2.6) * 0.015 * (1 + wobble * 3)
        rig.featherGroup.eulerAngles = SCNVector3(0, 0, Float(flutter))
        rig.pupilNode.position = SCNVector3(
            0.0008 - Float(state.angularVelocity) * 0.0002,
            0.0008 + Float(state.angularVelocity) * 0.0002,
            0.0035)

        // Condensation haze grows as the head cools below the bulb.
        let cooling = state.bulbTemperature - state.headTemperature
        rig.frostNode.opacity = CGFloat(max(0, min(0.35, (cooling - 5) / 28)))

        // Felt darkens slightly as it dries.
        rig.feltNode.geometry?.firstMaterial?.diffuse.intensity = CGFloat(0.72 + 0.28 * state.feltMoisture)

        // Ripples + falling droplet while drinking.
        let drinking = state.beakInWater
        for (i, ripple) in rig.rippleNodes.enumerated() {
            if drinking {
                let p = fmod(state.time * 0.9 + Double(i) * 0.33, 1)
                let s = 0.004 + 0.022 * p
                ripple.scale = SCNVector3(Float(s), Float(s), Float(s))
                ripple.opacity = CGFloat((1 - p) * 0.85)
            } else {
                ripple.opacity = 0
            }
        }
        if drinking {
            let p = fmod(state.time * 1.35, 1)
            rig.dropletNode.position = SCNVector3(
                -0.086, Float(-0.013 - 0.010 * p), 0.002)
            rig.dropletNode.opacity = CGFloat((1 - p) * 0.9)
        } else {
            rig.dropletNode.opacity = 0
        }
    }

    private func fillFraction(_ volume: Double, _ capacity: Double) -> Double {
        guard capacity > 0 else { return 0 }
        return min(max(volume / capacity, 0), 0.97)
    }
}

// MARK: - X-ray HUD (text overlay in real units)

private struct HUDOverlay: View {
    let state: PhysicsState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            hudRow("ΔP", SceneText.pascalToKiloPascal(state.pressureDelta))
            hudRow("θ", SceneText.degrees(state.angle))
            hudRow("τ", SceneText.torque(state.torque))
            hudRow("CG", SceneText.millimeters(
                BirdGeometry.bodyWorld(state.centerOfGravity, angle: state.angle).x))
            hudRow("Felt", String(format: "%.0f %% wet", state.feltMoisture * 100))
            hudRow("Tᵇᵘˡᵇ", String(format: "%.1f °C", state.bulbTemperature))
            hudRow("Tᵐᵉᵃᵈ", String(format: "%.1f °C", state.headTemperature))
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func hudRow(_ key: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(key).frame(width: 52, alignment: .leading)
                .foregroundStyle(.tertiary)
            Text(value)
        }
    }
}
