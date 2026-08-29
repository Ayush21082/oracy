import SceneKit
import UIKit

/// Builds and runs a physics-based 3D dice roll in SceneKit.
/// Kept for deprecated `DiceRollOverlay` / future reuse — not shown on Home.
@MainActor
final class DiceSceneController: NSObject {
    let scene = SCNScene()
    private(set) var dieNode: SCNNode!
    private var floorNode: SCNNode!
    private var settleTimer: Timer?
    private var onFinished: ((Int) -> Void)?
    private var hasFinished = false
    private var settleQuietFrames = 0

    override init() {
        super.init()
        buildScene()
    }

    func prepareView(_ scnView: SCNView) {
        scnView.scene = scene
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.antialiasingMode = .multisampling4X
        scnView.isPlaying = true
        scnView.autoenablesDefaultLighting = false
    }

    /// Starts a roll. Calls `onFinished` with the face value (1–6) when settled.
    func roll(reducedMotion: Bool, onFinished: @escaping (Int) -> Void) {
        self.onFinished = onFinished
        hasFinished = false
        settleQuietFrames = 0
        settleTimer?.invalidate()

        resetDiePose()

        if reducedMotion {
            let face = Int.random(in: 1...6)
            orientDie(toFace: face)
            finish(with: face)
            return
        }

        // Random tumble
        let impulse = SCNVector3(
            Float.random(in: -1.2...1.2),
            Float.random(in: 2.8...4.2),
            Float.random(in: -1.2...1.2)
        )
        let torque = SCNVector4(
            Float.random(in: -1...1),
            Float.random(in: -1...1),
            Float.random(in: -1...1),
            Float.random(in: 8...14)
        )

        dieNode.physicsBody?.velocity = SCNVector3Zero
        dieNode.physicsBody?.angularVelocity = SCNVector4Zero
        dieNode.physicsBody?.applyForce(impulse, asImpulse: true)
        dieNode.physicsBody?.applyTorque(torque, asImpulse: true)

        // Watch for settle
        settleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSettled()
            }
        }

        // Safety timeout
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            guard !hasFinished else { return }
            finish(with: resolveTopFace())
        }
    }

    // MARK: - Scene

    private func buildScene() {
        scene.physicsWorld.gravity = SCNVector3(0, -9.8, 0)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 40
        camera.position = SCNVector3(0, 3.2, 5.2)
        camera.look(at: SCNVector3(0, 0.4, 0))
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 450
        ambient.light?.color = UIColor(white: 0.95, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 700
        key.light?.castsShadow = true
        key.light?.shadowMode = .deferred
        key.light?.shadowColor = UIColor.black.withAlphaComponent(0.25)
        key.eulerAngles = SCNVector3(-0.9, 0.4, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 280
        fill.eulerAngles = SCNVector3(-0.3, -0.8, 0)
        scene.rootNode.addChildNode(fill)

        // Floor
        let floor = SCNFloor()
        floor.reflectivity = 0
        let floorMat = SCNMaterial()
        floorMat.diffuse.contents = UIColor.clear
        floorMat.lightingModel = .constant
        floor.materials = [floorMat]
        floorNode = SCNNode(geometry: floor)
        floorNode.physicsBody = SCNPhysicsBody.static()
        floorNode.physicsBody?.friction = 0.85
        floorNode.physicsBody?.restitution = 0.25
        scene.rootNode.addChildNode(floorNode)

        // Soft shadow plate
        let plate = SCNPlane(width: 2.4, height: 2.4)
        let plateMat = SCNMaterial()
        plateMat.diffuse.contents = UIColor.black.withAlphaComponent(0.06)
        plateMat.lightingModel = .constant
        plateMat.isDoubleSided = true
        plate.materials = [plateMat]
        let plateNode = SCNNode(geometry: plate)
        plateNode.eulerAngles.x = -.pi / 2
        plateNode.position = SCNVector3(0, 0.01, 0)
        scene.rootNode.addChildNode(plateNode)

        dieNode = makeDieNode()
        scene.rootNode.addChildNode(dieNode)
        resetDiePose()
    }

    private func makeDieNode() -> SCNNode {
        let size: CGFloat = 0.9
        let box = SCNBox(width: size, height: size, length: size, chamferRadius: 0.12)
        // SCNBox material order: front, right, back, left, top, bottom
        // Map: front=1, right=2, back=6, left=5, top=3, bottom=4
        box.materials = [
            pipMaterial(pips: 1), // +Z front
            pipMaterial(pips: 2), // +X right
            pipMaterial(pips: 6), // -Z back
            pipMaterial(pips: 5), // -X left
            pipMaterial(pips: 3), // +Y top
            pipMaterial(pips: 4), // -Y bottom
        ]

        let node = SCNNode(geometry: box)
        let body = SCNPhysicsBody(type: .dynamic, shape: SCNPhysicsShape(geometry: box, options: [
            SCNPhysicsShape.Option.type: SCNPhysicsShape.ShapeType.convexHull,
        ]))
        body.mass = 0.8
        body.friction = 0.7
        body.restitution = 0.35
        body.angularDamping = 0.35
        body.damping = 0.15
        body.continuousCollisionDetectionThreshold = 0.05
        node.physicsBody = body
        return node
    }

    private func resetDiePose() {
        dieNode.physicsBody?.velocity = SCNVector3Zero
        dieNode.physicsBody?.angularVelocity = SCNVector4Zero
        dieNode.position = SCNVector3(0, 1.6, 0)
        dieNode.eulerAngles = SCNVector3(
            Float.random(in: 0...Float.pi),
            Float.random(in: 0...Float.pi),
            Float.random(in: 0...Float.pi)
        )
    }

    // MARK: - Settle / face

    private func checkSettled() {
        guard !hasFinished, let body = dieNode.physicsBody else { return }

        let v = body.velocity
        let speed = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        let av = body.angularVelocity
        let spin = sqrt(av.x * av.x + av.y * av.y + av.z * av.z)
        let nearFloor = dieNode.presentation.position.y < 0.7

        if nearFloor && speed < 0.12 && spin < 0.35 {
            settleQuietFrames += 1
        } else {
            settleQuietFrames = 0
        }

        if settleQuietFrames >= 8 {
            finish(with: resolveTopFace())
        }
    }

    private func finish(with face: Int) {
        guard !hasFinished else { return }
        hasFinished = true
        settleTimer?.invalidate()
        settleTimer = nil
        dieNode.physicsBody?.velocity = SCNVector3Zero
        dieNode.physicsBody?.angularVelocity = SCNVector4Zero
        onFinished?(face)
        onFinished = nil
    }

    /// Which face normal is closest to world +Y.
    private func resolveTopFace() -> Int {
        let presentation = dieNode.presentation
        // Local face normals → world, pick max Y
        let faces: [(Int, SCNVector3)] = [
            (1, SCNVector3(0, 0, 1)),   // front
            (2, SCNVector3(1, 0, 0)),   // right
            (6, SCNVector3(0, 0, -1)),  // back
            (5, SCNVector3(-1, 0, 0)),  // left
            (3, SCNVector3(0, 1, 0)),   // top
            (4, SCNVector3(0, -1, 0)),  // bottom
        ]

        var bestFace = 1
        var bestY: Float = -Float.greatestFiniteMagnitude
        for (face, local) in faces {
            let world = presentation.convertVector(local, to: nil)
            if world.y > bestY {
                bestY = world.y
                bestFace = face
            }
        }
        return bestFace
    }

    private func orientDie(toFace face: Int) {
        // Orient so `face` points up (+Y)
        let rotation: SCNVector3
        switch face {
        case 1: rotation = SCNVector3(-Float.pi / 2, 0, 0) // front → up
        case 2: rotation = SCNVector3(0, 0, Float.pi / 2)  // right → up
        case 3: rotation = SCNVector3(0, 0, 0)             // top already up
        case 4: rotation = SCNVector3(Float.pi, 0, 0)      // bottom → up
        case 5: rotation = SCNVector3(0, 0, -Float.pi / 2) // left → up
        case 6: rotation = SCNVector3(Float.pi / 2, 0, 0)  // back → up
        default: rotation = SCNVector3Zero
        }
        dieNode.eulerAngles = rotation
        dieNode.position = SCNVector3(0, 0.55, 0)
    }

    // MARK: - Pip textures

    private func pipMaterial(pips: Int) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = Self.pipImage(pips: pips)
        mat.roughness.contents = 0.55
        mat.metalness.contents = 0.05
        mat.lightingModel = .physicallyBased
        return mat
    }

    private static func pipImage(pips: Int) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cream = UIColor(red: 0.98, green: 0.96, blue: 0.93, alpha: 1)
            cream.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Subtle inset border
            let border = UIColor(red: 0.90, green: 0.86, blue: 0.80, alpha: 1)
            border.setStroke()
            let inset = CGRect(x: 10, y: 10, width: 236, height: 236)
            let path = UIBezierPath(roundedRect: inset, cornerRadius: 36)
            path.lineWidth = 4
            path.stroke()

            let pipColor = UIColor(red: 0.15, green: 0.12, blue: 0.10, alpha: 1)
            pipColor.setFill()

            let positions = pipPositions(for: pips)
            let r: CGFloat = 22
            for p in positions {
                let center = CGPoint(x: size.width * p.x, y: size.height * p.y)
                UIBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)).fill()
            }
        }
    }

    /// Normalized pip centers (classic die layouts).
    private static func pipPositions(for pips: Int) -> [CGPoint] {
        let tl = CGPoint(x: 0.28, y: 0.28)
        let tr = CGPoint(x: 0.72, y: 0.28)
        let ml = CGPoint(x: 0.28, y: 0.50)
        let c  = CGPoint(x: 0.50, y: 0.50)
        let mr = CGPoint(x: 0.72, y: 0.50)
        let bl = CGPoint(x: 0.28, y: 0.72)
        let br = CGPoint(x: 0.72, y: 0.72)

        switch pips {
        case 1: return [c]
        case 2: return [tl, br]
        case 3: return [tl, c, br]
        case 4: return [tl, tr, bl, br]
        case 5: return [tl, tr, c, bl, br]
        case 6: return [tl, tr, ml, mr, bl, br]
        default: return [c]
        }
    }
}
