import AppKit
import SceneKit

/// Procedural SceneKit world for the drinking bird: geometry, materials,
/// lighting. All positions reuse the SI body-frame constants from
/// `BirdGeometry`, so physics and visuals can never drift apart.
enum BirdScene3DBuilder {

    // MARK: - Rig (node references the view layer animates per frame)

    final class Rig {
        let scene: SCNScene
        let cameraNode: SCNNode
        /// Default framing captured at scene build time — the "Center view"
        /// button restores this transform after the user orbits away.
        var initialCameraTransform = SCNMatrix4Identity
        /// Rotating bird assembly, pivot at the origin (the red crossbar).
        let birdNode: SCNNode
        /// Counter-rotating liquid nodes — their local euler.z is set to −θ
        /// each frame so the liquid surfaces stay world-horizontal.
        let bulbLiquidNode: SCNNode
        let headLiquidNode: SCNNode
        let neckLiquidNode: SCNNode
        let bubbleNodes: [SCNNode]
        /// Group node the feather boa hangs from; flutter rotates it slightly.
        let featherGroup: SCNNode
        let eyeNode: SCNNode
        let pupilNode: SCNNode
        let frostNode: SCNNode
        let feltNode: SCNNode
        let rippleNodes: [SCNNode]
        let dropletNode: SCNNode
        var lastHeadFill: Float = -1
        var lastBulbFill: Float = -1

        init(scene: SCNScene, cameraNode: SCNNode, birdNode: SCNNode,
             bulbLiquidNode: SCNNode, headLiquidNode: SCNNode, neckLiquidNode: SCNNode,
             bubbleNodes: [SCNNode], featherGroup: SCNNode,
             eyeNode: SCNNode, pupilNode: SCNNode, frostNode: SCNNode, feltNode: SCNNode,
             rippleNodes: [SCNNode], dropletNode: SCNNode) {
            self.scene = scene
            self.cameraNode = cameraNode
            self.birdNode = birdNode
            self.bulbLiquidNode = bulbLiquidNode
            self.headLiquidNode = headLiquidNode
            self.neckLiquidNode = neckLiquidNode
            self.bubbleNodes = bubbleNodes
            self.featherGroup = featherGroup
            self.eyeNode = eyeNode
            self.pupilNode = pupilNode
            self.frostNode = frostNode
            self.feltNode = feltNode
            self.rippleNodes = rippleNodes
            self.dropletNode = dropletNode
        }
    }

    // MARK: - Palette

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func material(_ c: NSColor, roughness: Double, metalness: Double = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = c
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    private static func glassMaterial(alpha: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color(0.96, 0.98, 1.0, alpha)
        m.roughness.contents = 0.04
        m.metalness.contents = 0.0
        m.blendMode = .alpha
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        return m
    }

    private static func liquidMaterial() -> SCNMaterial {
        let m = material(color(0.94, 0.10, 0.16, 0.92), roughness: 0.12)
        m.blendMode = .alpha
        m.isDoubleSided = true
        return m
    }

    /// Small flattened white "catch light" blob — sells the blown-glass look.
    private static func addGlassHighlight(to parent: SCNNode,
                                          at p: SCNVector3,
                                          facing: SCNVector3,
                                          size: Double, alpha: Double) {
        let hl = SCNNode(geometry: SCNSphere(radius: size))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color(1, 1, 1, alpha)
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        hl.geometry?.firstMaterial = m
        hl.scale = SCNVector3(1, 1.35, 0.22)
        hl.position = p
        parent.addChildNode(hl)
        hl.look(at: SCNVector3(p.x + facing.x, p.y + facing.y, p.z + facing.z),
                up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
    }

    /// Vertical gradient used as the lighting environment — dark studio with a
    /// brighter top, so chrome and glass pick up the Sketchfab-style sheen.
    private static func environmentImage() -> NSImage {
        let size = NSSize(width: 256, height: 128)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [
            color(0.55, 0.56, 0.60),
            color(0.20, 0.20, 0.22),
            color(0.03, 0.03, 0.04),
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        image.unlockFocus()
        return image
    }

    private static let feltColor = color(0.90, 0.08, 0.12)   // glossy cherry-red plastic
    private static let feltDarkColor = color(0.74, 0.05, 0.08) // beak / shaded red

    private static func chromeMaterial() -> SCNMaterial {
        material(color(0.90, 0.90, 0.92), roughness: 0.22, metalness: 0.9)
    }

    // MARK: - Scene assembly

    static func makeScene() -> Rig {
        let scene = SCNScene()
        // Dark studio backdrop, like the reference render.
        scene.background.contents = color(0.10, 0.10, 0.115)
        scene.lightingEnvironment.contents = environmentImage()
        scene.lightingEnvironment.intensity = 1.2
        let root = scene.rootNode

        addLighting(to: root)
        let cameraNode = addCamera(to: root)
        addFloor(to: root)
        addGlass(to: root)
        addBootsAndLegs(to: root)

        // --- Rotating bird assembly (body frame, pivot at origin) ---
        let bird = SCNNode()
        root.addChildNode(bird)

        // Chrome clamp collar gripping the neck tube at the pivot (bird child:
        // it rotates with the tube, like the real toy's swivel clamp).
        let clamp = SCNNode(geometry: SCNTube(innerRadius: 0.0062, outerRadius: 0.0076,
                                              height: 0.0075))
        clamp.geometry?.firstMaterial = chromeMaterial()
        clamp.position = SCNVector3(0, 0, 0)
        bird.addChildNode(clamp)

        let featherGroup = SCNNode()
        bird.addChildNode(featherGroup)

        let bulbLiquid = addBulb(to: bird)
        let neckLiquid = addNeck(to: bird)
        let (headLiquid, frost, felt) = addHead(to: bird)
        addHat(to: bird)
        let (eye, pupil) = addEye(to: bird)
        addBeak(to: bird)
        addFeathers(group: featherGroup)
        let bubbles = addBubbles(to: bird)

        // --- World-frame water effects (beak contact point) ---
        let ripples = addRipples(to: root)
        let droplet = addDroplet(to: root)

        let rig = Rig(scene: scene, cameraNode: cameraNode, birdNode: bird,
                      bulbLiquidNode: bulbLiquid, headLiquidNode: headLiquid,
                      neckLiquidNode: neckLiquid, bubbleNodes: bubbles,
                      featherGroup: featherGroup, eyeNode: eye, pupilNode: pupil,
                      frostNode: frost, feltNode: felt,
                      rippleNodes: ripples, dropletNode: droplet)
        rig.initialCameraTransform = cameraNode.transform
        applyDefaults(rig)
        return rig
    }

    private static func applyDefaults(_ rig: Rig) {
        setLiquidGeometry(rig.headLiquidNode, radius: headLiquidRadius, fill: 0.06)
        rig.lastHeadFill = 0.06
        setLiquidGeometry(rig.bulbLiquidNode, radius: bulbLiquidRadius, fill: 0.34)
        rig.lastBulbFill = 0.34
        rig.frostNode.opacity = 0
        rig.rippleNodes.forEach { $0.opacity = 0 }
        rig.dropletNode.opacity = 0
    }

    // MARK: Lighting / camera / floor

    private static func addLighting(to root: SCNNode) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 120
        ambient.light?.color = color(0.85, 0.88, 1.0)
        root.addChildNode(ambient)

        // Hard key light — casts the tabletop shadow on the dark floor.
        root.addChildNode(aimedLight(color(1.0, 0.97, 0.92), intensity: 1300,
                                     from: (x: 0.35, y: 0.45, z: 0.55),
                                     castsShadow: true))

        // Cool fill from the left.
        root.addChildNode(aimedLight(color(0.85, 0.90, 1.0), intensity: 260,
                                     from: (x: -0.6, y: 0.2, z: 0.35)))

        // Strong cool rim light from behind — this is what glints the chrome bulb.
        root.addChildNode(aimedLight(color(0.70, 0.80, 1.0), intensity: 800,
                                     from: (x: 0.05, y: 0.3, z: -0.6)))
    }

    private static func aimedLight(_ c: NSColor, intensity: Double,
                                   from p: (x: Double, y: Double, z: Double),
                                   castsShadow: Bool = false) -> SCNNode {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = .directional
        node.light?.color = c
        node.light?.intensity = intensity
        if castsShadow {
            node.light?.castsShadow = true
            node.light?.shadowRadius = 8
            node.light?.shadowColor = color(0, 0, 0, 0.38)
            node.light?.shadowSampleCount = 24
        }
        node.position = SCNVector3(p.x, p.y, p.z)
        node.look(at: SCNVector3(0, -0.04, 0))
        return node
    }

    private static func addCamera(to root: SCNNode) -> SCNNode {
        let cameraNode = SCNNode()
        let cam = SCNCamera()
        cam.fieldOfView = 42
        // Scene work in real meters — pull the clip planes in close or the
        // default zNear = 1.0 clips the entire toy-sized world away.
        cam.zNear = 0.01
        cam.zFar = 20
        cameraNode.camera = cam
        // Centered composition: scene center (x −0.136…+0.056, y −0.138…+0.127)
        // with a gentle ~5° downward tilt, matching the reference render's
        // framing. The "Center view" button restores this exact transform.
        // From the face-front diagonal (~45° off the beak axis), aimed at the
        // bird itself so the 3D model sits in the middle of the viewport.
        // Both googly eyes straddle the beak visibly and the beak points
        // screen-left, with the glass still in frame foreground-left.
        let center = SCNVector3(0.000, -0.006, 0)
        cameraNode.position = SCNVector3(-0.284, 0.149, 0.322)
        cameraNode.look(at: center)
        root.addChildNode(cameraNode)
        return cameraNode
    }

    private static func addFloor(to root: SCNNode) {
        let floor = SCNFloor()
        floor.reflectivity = 0.04
        floor.firstMaterial = material(color(0.16, 0.16, 0.18), roughness: 0.7)
        let node = SCNNode(geometry: floor)
        // The floor plane is exactly the underside of the bird's boots; the
        // glass is drawn from this same plane up, so everything stands
        // on the ground.
        node.position = SCNVector3(0, BirdGeometry.bootFrame.bottomY, 0)
        root.addChildNode(node)
    }

    // MARK: Static scenery

    private static func addGlass(to root: SCNNode) {
        let f = BirdGeometry.glassFrame
        // The tumbler stands on the ground (same plane as the bird's boots)
        // while its water surface stays at the physics contact height, so it
        // is proportioned like a tall real water glass.
        let groundY = BirdGeometry.bootFrame.bottomY
        // Glass sits well clear of the bird: its near edge leaves ~26 mm of
        // air to the bulb, while the beak tip still lands inside at contact.
        let radius = 0.038
        let cx = -0.098
        let height = f.rimY - groundY

        // Wall of a tumbler with noticeable glass thickness.
        let wall = SCNNode(geometry: SCNTube(innerRadius: radius - 0.0035,
                                             outerRadius: radius,
                                             height: height))
        wall.geometry?.firstMaterial = glassMaterial(alpha: 0.14)
        wall.position = SCNVector3(cx, groundY + height / 2, 0)
        root.addChildNode(wall)

        // Rounded rim lip.
        let rim = SCNNode(geometry: SCNTorus(ringRadius: radius - 0.0012, pipeRadius: 0.0009))
        rim.geometry?.firstMaterial = glassMaterial(alpha: 0.35)
        rim.position = SCNVector3(cx, f.rimY, 0)
        root.addChildNode(rim)

        // Heavy glass base resting exactly on the floor plane.
        let base = SCNNode(geometry: SCNCylinder(radius: radius, height: 0.006))
        base.geometry?.firstMaterial = glassMaterial(alpha: 0.30)
        base.position = SCNVector3(cx, groundY + 0.003, 0)
        root.addChildNode(base)

        // Water body: near-clear, only faintly blue.
        let waterBottom = groundY + 0.004
        let waterHeight = f.waterY - waterBottom
        let water = SCNNode(geometry: SCNCylinder(radius: radius - 0.0040, height: waterHeight))
        water.geometry?.firstMaterial = material(color(0.62, 0.78, 0.95, 0.25), roughness: 0.015)
        water.geometry?.firstMaterial?.blendMode = .alpha
        water.position = SCNVector3(cx, waterBottom + waterHeight / 2, 0)
        root.addChildNode(water)

        // Water surface: thin bright disc for a crisp specular plane.
        let surface = SCNNode(geometry: SCNCylinder(radius: radius - 0.0040, height: 0.0006))
        surface.geometry?.firstMaterial = material(color(0.88, 0.94, 1.0, 0.55), roughness: 0.01)
        surface.geometry?.firstMaterial?.blendMode = .alpha
        surface.position = SCNVector3(cx, f.waterY, 0)
        root.addChildNode(surface)

        // Meniscus ring where water meets the wall.
        let meniscus = SCNNode(geometry: SCNTorus(ringRadius: radius - 0.0042,
                                                  pipeRadius: 0.0005))
        meniscus.geometry?.firstMaterial = material(color(0.90, 0.96, 1.0, 0.6), roughness: 0.03)
        meniscus.geometry?.firstMaterial?.blendMode = .alpha
        meniscus.position = SCNVector3(cx, f.waterY, 0)
        root.addChildNode(meniscus)

        // Catch-light streak on the wall, like the reference render's glass.
        addGlassHighlight(to: root,
                          at: SCNVector3(cx - radius * 0.70, groundY + 0.055, radius * 0.62),
                          facing: SCNVector3(-0.70, 0.15, 0.62),
                          size: 0.0038, alpha: 0.45)
    }

    private static func addBootsAndLegs(to root: SCNNode) {
        let red = material(color(0.86, 0.10, 0.13), roughness: 0.28)
        let bottom = BirdGeometry.bootFrame.bottomY

        // Chunky red pedestal (the reference model's blocky base), laid
        // PERPENDICULAR to the bird's drinking axis (−x): its long side runs
        // along z, left-right across the tipping direction, like the real
        // toy's base rail under the pivot.
        let pedestal = SCNNode(geometry: SCNBox(width: 0.048, height: 0.040,
                                                length: 0.104, chamferRadius: 0.010))
        pedestal.geometry?.firstMaterial = red
        pedestal.position = SCNVector3(0.000, bottom + 0.020, 0)
        root.addChildNode(pedestal)
        // Two foot tabs at the ends of the long base rail.
        for sz in [-1.0, 1.0] {
            let tab = SCNNode(geometry: SCNBox(width: 0.030, height: 0.008,
                                               length: 0.014, chamferRadius: 0.003))
            tab.geometry?.firstMaterial = red
            tab.position = SCNVector3(0.000, bottom - 0.002, sz * 0.044)
            root.addChildNode(tab)
        }

        // Smooth white body-panel loops: thick capsule chains sprouting from
        // the top of the red base rail. The arcs bow out to the SIDES (±z),
        // along the base's long axis, perpendicular to the bird's drinking
        // axis (−x) — they cradle the pivot like the real toy's wire legs
        // and never swing into the water glass.
        let legMat = material(color(0.92, 0.92, 0.90), roughness: 0.30)
        for sz in [-1.0, 1.0] {
            for xOffset in [-0.005, 0.005] {
                addLegLoop(root: root, bow: sz, xOffset: xOffset, material: legMat)
            }
        }

        // Chrome pivot crossbar running front-to-back through the clamp.
        let bar = SCNNode(geometry: SCNCylinder(radius: 0.0016, height: 0.052))
        bar.geometry?.firstMaterial = chromeMaterial()
        bar.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        root.addChildNode(bar)
        let bolt = SCNNode(geometry: SCNSphere(radius: 0.0030))
        bolt.geometry?.firstMaterial = chromeMaterial()
        bolt.position = SCNVector3(0, 0, 0.030)
        root.addChildNode(bolt)
        let bolt2 = bolt.clone()
        bolt2.position = SCNVector3(0, 0, -0.030)
        root.addChildNode(bolt2)
    }

    /// One bowed leg loop rendered as a chain of capsule segments following a
    /// quadratic Bézier from a boot top up to the pivot. The loop lies in the
    /// plane perpendicular to the drinking axis: it bows outward in ±z, so
    /// the two arcs straddle the pivot beside the bulb (like the big cream
    /// loops in the reference photo) and stay clear of the water glass.
    private static func addLegLoop(root: SCNNode, bow sz: Double,
                                   xOffset: Double, material: SCNMaterial) {
        // Bézier solved in (bow, y) space; the bow coordinate maps straight
        // onto world z (it is already signed by `sz`), and `xOffset` only
        // offsets the loop pair's thickness along x. Loops are planted well
        // apart on the long red rail (springing from z ≈ ±30 mm, inside the
        // end feet at ±44 mm) and bow out to a ±50 mm peak — matching the
        // 104 mm base the arcs stand on.
        let start = Vec2(x: sz * 0.030, y: BirdGeometry.bootFrame.bottomY + 0.038)
        let control = Vec2(x: sz * 0.085, y: -0.038)
        let end = Vec2(x: 0.0, y: 0.0)
        let segments = 9
        var previous = start
        for i in 1...segments {
            let t = Double(i) / Double(segments)
            let point = quadratic(start, control, end, t)
            let mid = (previous + point) * 0.5
            let tangent = point - previous
            let segment = SCNNode(geometry: SCNCapsule(capRadius: 0.0034, height: tangent.magnitude))
            segment.geometry?.firstMaterial = material
            segment.position = SCNVector3(xOffset, mid.y, mid.x)
            // The arc bends in the y–z plane: pitch about +x so the capsule's
            // local +y follows the tangent (0, tangent.y, tangent.x).
            let φ = atan2(tangent.x, tangent.y)
            segment.eulerAngles = SCNVector3(φ, 0, 0)
            root.addChildNode(segment)
            previous = point
        }
    }

    private static func quadratic(_ a: Vec2, _ b: Vec2, _ c: Vec2, _ t: Double) -> Vec2 {
        let u = 1 - t
        return a * (u * u) + b * (2 * u * t) + c * (t * t)
    }

    static let bulbLiquidRadius: Double = BirdGeometry.bulbRadius - 0.0035
    static let headLiquidRadius: Double = BirdGeometry.headRadius - 0.0028

    /// Visual-only anchor, not a physics constant: the drawn neck pipe dips
    /// down into the bulb so the red column always connects to the bulb
    /// water. The physics keeps its own `neckBottom` (bulb rim) untouched.
    static let neckPipeBottom: Double = -0.088

    private static func addBulb(to bird: SCNNode) -> SCNNode {
        let glass = SCNNode(geometry: SCNSphere(radius: BirdGeometry.bulbRadius))
        glass.geometry?.firstMaterial = glassMaterial(alpha: 0.13)
        glass.position = SCNVector3(BirdGeometry.bulbCenter.x, BirdGeometry.bulbCenter.y, 0)
        bird.addChildNode(glass)

        // Big chrome-style catch light on the bulb, like the reference render.
        addGlassHighlight(to: bird,
                          at: SCNVector3(BirdGeometry.bulbCenter.x - 0.015,
                                         BirdGeometry.bulbCenter.y + 0.025,
                                         0.016),
                          facing: SCNVector3(-0.45, 0.75, 0.48),
                          size: 0.0030, alpha: 0.6)

        let liquid = SCNNode()
        setLiquidGeometry(liquid, radius: bulbLiquidRadius, fill: 0.34)
        liquid.position = glass.position
        bird.addChildNode(liquid)
        return liquid
    }

    private static func addNeck(to bird: SCNNode) -> SCNNode {
        // Drawn pipe: dips into the bulb water (bottom −0.088) so the red
        // column stays connected to the reservoir, and tops out under the
        // red collar cone. Visual anchors only — physics keeps neckBottom.
        let bottom = Vec2(x: 0.000, y: BirdScene3DBuilder.neckPipeBottom)
        let top = Vec2(x: 0.000, y: 0.042)
        let length = top.y - bottom.y
        let tube = SCNNode(geometry: SCNTube(innerRadius: BirdGeometry.neckInnerRadius,
                                             outerRadius: BirdGeometry.neckOuterRadius,
                                             height: length))
        // Clear glass neck like the real toy — red paint caps each end.
        tube.geometry?.firstMaterial = glassMaterial(alpha: 0.18)
        tube.position = SCNVector3(0, (bottom.y + top.y) / 2, 0)
        bird.addChildNode(tube)

        // Glossy red paint cap where the tube passes the bulb rim.
        let cap = SCNNode(geometry: SCNCylinder(radius: 0.0070, height: 0.012))
        cap.geometry?.firstMaterial = material(feltColor, roughness: 0.18)
        cap.position = SCNVector3(BirdGeometry.neckBottom.x, -0.022, 0)
        bird.addChildNode(cap)

        // Liquid column: unit-height cylinder, scaled from below with its
        // center re-positioned each frame (no pivot trick — unambiguous).
        let column = SCNNode(geometry: SCNCylinder(radius: BirdGeometry.neckInnerRadius - 0.0004,
                                                   height: 1))
        column.geometry?.firstMaterial = liquidMaterial()
        column.position = SCNVector3(bottom.x, bottom.y, 0)
        column.scale = SCNVector3(1, 0.01, 1)
        bird.addChildNode(column)
        return column
    }

    private static func addHead(to bird: SCNNode) -> (SCNNode, SCNNode, SCNNode) {
        let c = BirdGeometry.headCenter

        // Glass head sphere, fully covered by the glossy red shell (like the
        // real toy — no window). Slightly egg-shaped for a real head profile.
        let glass = SCNNode(geometry: SCNSphere(radius: BirdGeometry.headRadius))
        glass.geometry?.firstMaterial = glassMaterial(alpha: 0.13)
        glass.position = SCNVector3(c.x, c.y, 0)
        glass.scale = SCNVector3(0.97, 1.05, 0.97)
        bird.addChildNode(glass)

        // Red liquid cap, counter-rotated to stay level (inside the shell).
        let liquid = SCNNode()
        setLiquidGeometry(liquid, radius: headLiquidRadius, fill: 0.06)
        liquid.opacity = 0  // hidden under the painted shell
        liquid.position = glass.position
        bird.addChildNode(liquid)

        // Glossy cherry-red plastic shell covering ~93% of the head; only a
        // bottom sliver of glass peeks out where the neck joins.
        let felt = SCNNode(geometry: partialSphereGeometry(
            radius: BirdGeometry.headRadius + 0.0010,
            phiStart: 0, phiEnd: 0.86 * .pi))
        felt.geometry?.firstMaterial = material(feltColor, roughness: 0.16)
        felt.position = SCNVector3(c.x, c.y, 0)
        felt.scale = SCNVector3(0.97, 1.05, 0.97)
        bird.addChildNode(felt)

        // Subtle glossy dark crown (two-tone, like worn paint on the toy).
        let feltShade = SCNNode(geometry: partialSphereGeometry(
            radius: BirdGeometry.headRadius + 0.0014,
            phiStart: 0, phiEnd: 0.30 * .pi))
        feltShade.geometry?.firstMaterial = material(feltDarkColor, roughness: 0.25)
        feltShade.position = SCNVector3(c.x, c.y, 0)
        feltShade.scale = SCNVector3(0.97, 1.05, 0.97)
        bird.addChildNode(feltShade)

        // Glossy red taper bridging the head onto the neck tube.
        let collar = SCNNode(geometry: SCNCone(topRadius: 0.0040, bottomRadius: 0.0075,
                                               height: 0.020))
        collar.geometry?.firstMaterial = material(feltColor, roughness: 0.18)
        collar.position = SCNVector3(0, 0.050, 0)
        bird.addChildNode(collar)

        // Main catch light on the crown of the head.
        addGlassHighlight(to: bird,
                          at: SCNVector3(c.x - 0.011, c.y + 0.020, 0.0135),
                          facing: SCNVector3(-0.42, 0.62, 0.56),
                          size: 0.0026, alpha: 0.75)

        // Condensation haze — opacity driven by the temperature differential.
        let frost = SCNNode(geometry: SCNSphere(radius: BirdGeometry.headRadius + 0.002))
        let frostMat = SCNMaterial()
        frostMat.lightingModel = .constant
        frostMat.diffuse.contents = color(0.85, 0.92, 1.0, 0.5)
        frostMat.blendMode = .add
        frostMat.writesToDepthBuffer = false
        frost.geometry?.firstMaterial = frostMat
        frost.position = glass.position
        bird.addChildNode(frost)

        return (liquid, frost, felt)
    }

    private static func addHat(to bird: SCNNode) {
        let a = BirdGeometry.hatAnchor
        let hatMat = material(color(0.15, 0.40, 0.95), roughness: 0.15)

        // Anchor the hat to the actual top of the (studied, egg-shaped) head
        // so the brim visibly wraps and covers the crown.
        let headTopY = BirdGeometry.headCenter.y + 1.05 * (BirdGeometry.headRadius + 0.0010)
        let brimY = headTopY - 0.0045

        let brim = SCNNode(geometry: SCNTube(innerRadius: 0.011, outerRadius: 0.024, height: 0.0035))
        brim.geometry?.firstMaterial = hatMat
        brim.position = SCNVector3(a.x, brimY, 0)
        bird.addChildNode(brim)

        let crown = SCNNode(geometry: SCNCylinder(radius: 0.0135, height: 0.027))
        crown.geometry?.firstMaterial = hatMat
        crown.position = SCNVector3(a.x, brimY + 0.015, 0)
        bird.addChildNode(crown)

        let top = SCNNode(geometry: SCNCylinder(radius: 0.0135, height: 0.0022))
        top.geometry?.firstMaterial = hatMat
        top.position = SCNVector3(a.x, brimY + 0.029, 0)
        bird.addChildNode(top)
    }

    private static func addEye(to bird: SCNNode) -> (SCNNode, SCNNode) {
        let c = BirdGeometry.headCenter
        // Pair of big googly eyes exactly like the reference toy photo:
        // flat white discs with black pupils, side by side on the upper face,
        // angled so both read from the default camera. They ride ON the red
        // shell surface (shell is at headRadius + 0.001) so they can't vanish
        // inside the head.
        let white = material(color(0.98, 0.98, 0.98), roughness: 0.2)
        let black = material(color(0.02, 0.02, 0.02), roughness: 0.08)
        let shell = BirdGeometry.headRadius + 0.0015

        // Mirrored pair straddling the beak axis (θ −0.5π): one eye each side
        // of the nose, just above the beak root (polar 0.40π ≈ nose height).
        // The 45° face-front camera shows the near eye full-circle and the
        // far eye as a foreshortened oval — like the product photo.
        let eyeSpecs: [(theta: Double, polar: Double, animated: Bool)] = [(-0.38 * .pi, 0.40 * .pi, true),
                                                                          (-0.62 * .pi, 0.40 * .pi, false)]
        var frontEye: SCNNode?
        var frontGlint: SCNNode?
        for spec in eyeSpecs {
            let sp = sin(spec.polar), cp = cos(spec.polar)
            let st = sin(spec.theta), ct = cos(spec.theta)
            let dir = SCNVector3(sp * st, cp, sp * ct)
            // Egg-scale (0.97, 1.05, 0.97) applied to the surface placement;
            // +1.5 mm along the normal so the googly stands clearly proud.
            let eyeR = shell + 0.0015
            let position = SCNVector3(c.x + 0.97 * eyeR * dir.x,
                                      c.y + 1.05 * eyeR * dir.y,
                                      0.97 * eyeR * dir.z)
            let eye = SCNNode(geometry: SCNSphere(radius: 0.0082))
            eye.geometry?.firstMaterial = white
            eye.scale = SCNVector3(1, 1.05, 0.55)  // proud googly ball
            eye.position = position
            bird.addChildNode(eye)
            eye.look(at: SCNVector3(position.x + dir.x, position.y + dir.y, position.z + dir.z),
                     up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))

            let pupil = SCNNode(geometry: SCNSphere(radius: 0.0042))
            pupil.geometry?.firstMaterial = black
            pupil.scale = SCNVector3(1, 1, 0.45)
            // Centered in the white, flush with its front — child positions
            // inherit the parent's z-flatten (0.55), hence the large value.
            pupil.position = SCNVector3(0, 0, 0.0064)
            eye.addChildNode(pupil)

            if spec.animated {
                let glint = SCNNode(geometry: SCNSphere(radius: 0.0012))
                glint.geometry?.firstMaterial = material(color(1, 1, 1, 0.9), roughness: 0.2)
                glint.geometry?.firstMaterial?.blendMode = .alpha
                glint.scale = SCNVector3(1, 1, 0.35)
                glint.position = SCNVector3(0.0010, 0.0010, 0.0030)
                pupil.addChildNode(glint)
                frontEye = eye
                frontGlint = glint
            }
        }
        return (frontEye ?? SCNNode(), frontGlint ?? SCNNode())
    }

    private static func addBeak(to bird: SCNNode) {
        // Long, pointy, glossy red cone — apex lands on BirdGeometry.beakTip.
        let beak = SCNNode(geometry: SCNCone(topRadius: 0.0008, bottomRadius: 0.0066, height: 0.042))
        beak.geometry?.firstMaterial = material(feltDarkColor, roughness: 0.20)
        // Cone axis is +y with the apex up; rotate +90° about z so the apex
        // points toward −x (the glass).
        beak.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        beak.position = SCNVector3(-0.027, 0.0665, 0)
        bird.addChildNode(beak)
    }

    /// Jagged blue tail fin fanning up behind the bulb — the reference render's
    /// fractal-blue flame motif, approximated with overlapping glossy petals.
    private static func addFeathers(group: SCNNode) {
        let blue = material(color(0.10, 0.32, 0.90), roughness: 0.22)
        let center = SCNVector3(0.024, -0.002, 0)

        // Petals fan upward/backward from behind the bulb; angles in the xy
        // plane measured from +x. Lengths alternate to break the silhouette.
        let lengths: [Double] = [0.030, 0.042, 0.052, 0.047, 0.038, 0.030]
        let angles: [Double] = [0.22, 0.42, 0.62, 0.85, 1.05, 1.24]  // radians
        for i in 0..<angles.count {
            let dirAngle = angles[i]
            let dir = SCNVector3(cos(dirAngle), sin(dirAngle), 0)
            let length = lengths[i]
            let reach = 0.018 + 0.010 * Double(i % 2)
            let petal = SCNNode(geometry: SCNSphere(radius: 1))
            petal.geometry?.firstMaterial = blue
            petal.scale = SCNVector3(length, 0.011, 0.0042)
            petal.position = SCNVector3(center.x + reach * dir.x,
                                        center.y + reach * dir.y,
                                        0.004 - Double(i % 3) * 0.0032)
            group.addChildNode(petal)
            // Long (local x) axis along the fan direction.
            petal.look(at: SCNVector3(petal.position.x + dir.x,
                                      petal.position.y + dir.y,
                                      petal.position.z),
                       up: SCNVector3(0, 0, 1), localFront: SCNVector3(1, 0, 0))
        }
    }

    /// Two tiny bubbles that rise inside the neck while the pump is running.
    private static func addBubbles(to bird: SCNNode) -> [SCNNode] {
        let mat = material(color(1, 1, 1, 0.75), roughness: 0.1)
        mat.blendMode = .alpha
        return (0..<2).map { i in
            let bubble = SCNNode(geometry: SCNSphere(radius: 0.0008))
            bubble.geometry?.firstMaterial = mat
            bubble.position = SCNVector3(0, 0, 0.002 + Double(i) * 0.0009)
            bubble.opacity = 0
            bird.addChildNode(bubble)
            return bubble
        }
    }

    // MARK: Water-contact effects (world frame, at the beak dip point)

    private static let contactPoint = Vec2(x: -0.086, y: BirdGeometry.glassFrame.waterY + 0.0004)

    private static func addRipples(to root: SCNNode) -> [SCNNode] {
        let mat = material(color(0.98, 1, 1, 0.9), roughness: 0.05)
        mat.blendMode = .alpha
        mat.writesToDepthBuffer = false
        return (0..<3).map { _ in
            // Unit ring; the ripple phase scales it outward and fades it.
            let ripple = SCNNode(geometry: SCNTorus(ringRadius: 1, pipeRadius: 0.012))
            ripple.geometry?.firstMaterial = mat
            ripple.position = SCNVector3(contactPoint.x, contactPoint.y, 0)
            ripple.opacity = 0
            root.addChildNode(ripple)
            return ripple
        }
    }

    private static func addDroplet(to root: SCNNode) -> SCNNode {
        let droplet = SCNNode(geometry: SCNSphere(radius: 0.0022))
        droplet.geometry?.firstMaterial = material(color(0.45, 0.70, 0.92, 0.8), roughness: 0.05)
        droplet.geometry?.firstMaterial?.blendMode = .alpha
        droplet.position = SCNVector3(contactPoint.x, contactPoint.y + 0.008, 0.002)
        droplet.opacity = 0
        root.addChildNode(droplet)
        return droplet
    }

    // MARK: - Custom meshes

    /// Lat/long band of a sphere between polar angles `phiStart…phiEnd`
    /// (0 = north pole, π = south pole), optionally closed with a flat disc
    /// at the start ring (the level surface of a liquid cap).
    static func partialSphereGeometry(radius: Double, phiStart: Double, phiEnd: Double,
                                      thetaStart: Double = 0, thetaEnd: Double = 2 * .pi,
                                      latSegments: Int = 12, lonSegments: Int = 28,
                                      closeStartDisc: Bool = false) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        for j in 0...lonSegments {
            let theta = thetaStart + (thetaEnd - thetaStart) * Double(j) / Double(lonSegments)
            for i in 0...latSegments {
                let phi = phiStart + (phiEnd - phiStart) * Double(i) / Double(latSegments)
                let sp = sin(phi), cp = cos(phi)
                let st = sin(theta), ct = cos(theta)
                vertices.append(SCNVector3(radius * sp * st, radius * cp, radius * sp * ct))
                normals.append(SCNVector3(sp * st, cp, sp * ct))
            }
        }
        var indices: [Int32] = []
        let row = latSegments + 1
        for j in 0..<lonSegments {
            for i in 0..<latSegments {
                let r0 = Int32(j * row + i), r1 = Int32((j + 1) * row + i)
                indices.append(contentsOf: [r0, r0 + 1, r1 + 1, r0, r1 + 1, r1])
            }
        }

        if closeStartDisc {
            // Flat disc sealing the cut plane (the liquid surface).
            let ringBase = Int32(vertices.count)
            let planeY = radius * cos(phiStart)
            let ringR = radius * sin(phiStart)
            let centerIndex = Int32(vertices.count + lonSegments + 1)
            for j in 0...lonSegments {
                let theta = Double(j) / Double(lonSegments) * 2 * .pi
                vertices.append(SCNVector3(ringR * sin(theta), planeY, ringR * cos(theta)))
                normals.append(SCNVector3(0, 1, 0))
            }
            vertices.append(SCNVector3(0, planeY, 0))
            normals.append(SCNVector3(0, 1, 0))
            for j in 0..<lonSegments {
                indices.append(contentsOf: [centerIndex, ringBase + Int32(j), ringBase + Int32(j + 1)])
            }
        }

        let vertexSource = vectorSource(vertices, semantic: .vertex)
        let normalSource = vectorSource(normals, semantic: .normal)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
    }

    /// SCNVector3-based geometry source built explicitly over a `Float` buffer
    /// (the convenience initializers are ambiguous with mixed numeric types).
    private static func vectorSource(_ vectors: [SCNVector3],
                                     semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
        var floats: [Float] = []
        floats.reserveCapacity(vectors.count * 3)
        for v in vectors {
            floats.append(contentsOf: [Float(v.x), Float(v.y), Float(v.z)])
        }
        return floats.withUnsafeBufferPointer { buffer in
            SCNGeometrySource(
                data: Data(buffer: buffer),
                semantic: semantic,
            vectorCount: vectors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<Float>.size * 3)
        }
    }

    /// Bottom spherical cap of a sphere of `radius`, filled to `fill`
    /// (fraction of the diameter) — the liquid inside bulb/head, whose cut
    /// plane stays world-horizontal via counter-rotation.
    static func liquidCapGeometry(radius: Double, fill: Double) -> SCNGeometry {
        let clamped = min(max(fill, 0.04), 1.0)
        let planeY = -radius + 2 * radius * clamped
        let beta = acos(min(max(planeY / radius, -1), 1))
        return partialSphereGeometry(radius: radius, phiStart: beta, phiEnd: .pi,
                                     latSegments: 16, lonSegments: 30, closeStartDisc: true)
    }

    /// Replaces a node's liquid mesh and (re)installs the shared material.
    static func setLiquidGeometry(_ node: SCNNode, radius: Double, fill: Double) {
        node.geometry = liquidCapGeometry(radius: radius, fill: fill)
        node.geometry?.firstMaterial = liquidMaterial()
    }
}
