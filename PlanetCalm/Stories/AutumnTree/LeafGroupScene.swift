#if DEBUG
import SpriteKit
import UIKit

struct LeafGroupDiagnostics: Equatable {
    var state = "ready"
    var elapsed: Double = 0
    var released = 0
    var finished = 0
    var contacting = 0
    var settled = 0
    var failed = false
    var wind: WindSample?
}

/// Population orchestration only. Aerodynamic equations and the force-couple
/// calculation are shared with the unchanged single-leaf calibration scene.
@MainActor
final class LeafGroupScene: SKScene {
    let plan: LeafGroupPlan
    let terrain: LeafTerrainConfiguration?
    private let reference: LeafGravityLabConfiguration
    private let wind: WindField
    private var leaves: [LeafGroupBody] = []
    private let debugRoot = SKNode()
    private let windArrow = SKShapeNode()
    private let terrainOutline = SKShapeNode()
    private var elapsed = 0.0
    private var frameDelta = 0.0
    private var failed = false
    private var lastFrame: Double?
    private var lastPublication = -Double.infinity
    private(set) var isRunning = false
    private(set) var reducedMotion = false
    var diagnosticsHandler: ((LeafGroupDiagnostics) -> Void)?

    init(size: CGSize, reference: LeafGravityLabConfiguration, plan: LeafGroupPlan,
         images: [String: UIImage], terrain: LeafTerrainConfiguration? = nil) throws {
        self.plan = plan
        self.terrain = try terrain?.validated()
        self.reference = reference
        guard let windConfig = reference.wind else { throw LeafGravityLabConfigurationError.invalidWind }
        wind = plan.wind(reference: windConfig)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.96, green: 0.90, blue: 0.75, alpha: 1)
        physicsWorld.gravity = CGVector(dx: reference.gravity.x, dy: reference.gravity.y)
        physicsWorld.speed = 1
        debugRoot.zPosition = 100
        debugRoot.isHidden = true
        addChild(debugRoot)
        windArrow.strokeColor = .systemIndigo
        windArrow.lineWidth = 3
        debugRoot.addChild(windArrow)
        if let terrain {
            guard let image = images[terrain.assetID] else { throw LeafGravityLabConfigurationError.missingResource }
            let groundSize = CGSize(width: size.width, height: size.height * terrain.renderedHeightFraction)
            let ground = SKSpriteNode(texture: SKTexture(image: image), size: groundSize)
            ground.name = "terrain"
            ground.anchorPoint = .zero
            ground.zPosition = 0
            let path = CGMutablePath()
            for (index, point) in terrain.surface.enumerated() {
                let position = CGPoint(x: point.x * groundSize.width, y: point.y * groundSize.height)
                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
            }
            ground.physicsBody = SKPhysicsBody(edgeChainFrom: path)
            ground.physicsBody?.categoryBitMask = LeafGroupCollision.terrain
            ground.physicsBody?.collisionBitMask = LeafGroupCollision.leaf
            ground.physicsBody?.contactTestBitMask = LeafGroupCollision.leaf
            ground.physicsBody?.friction = terrain.friction
            ground.physicsBody?.restitution = terrain.restitution
            addChild(ground)
            terrainOutline.path = path
            terrainOutline.strokeColor = .systemBrown
            terrainOutline.lineWidth = 2
            debugRoot.addChild(terrainOutline)
        }
        let colliders = terrain == nil ? nil : try LeafCollisionCatalog.bundled.get()
        for member in plan.members {
            guard let image = images[member.assetID] else { throw LeafGravityLabConfigurationError.missingResource }
            let fittedShape = try colliders?.shape(for: member.assetID)
            if let fittedShape {
                guard image.cgImage?.width == fittedShape.sourcePixelWidth,
                      image.cgImage?.height == fittedShape.sourcePixelHeight else {
                    throw LeafGravityLabConfigurationError.invalidResource
                }
            }
            let leaf = try LeafGroupBody(member: member, reference: reference, viewport: size,
                                         image: image, terrain: terrain, fittedShape: fittedShape,
                                         contactInsetPoints: colliders?.contactInsetPoints ?? 0)
            leaves.append(leaf)
            addChild(leaf.node)
            debugRoot.addChild(leaf.overlay)
        }
        reset()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func replay() {
        reset()
        guard !reducedMotion else { return }
        isRunning = true
        publish(force: true)
    }

    func reset() {
        isRunning = false
        elapsed = 0
        frameDelta = 0
        failed = false
        physicsWorld.speed = 1
        lastFrame = nil
        lastPublication = -.infinity
        for leaf in leaves { leaf.prepare() }
        updateDebug()
        publish(force: true)
    }

    func setDiagnosticsVisible(_ visible: Bool) {
        debugRoot.isHidden = !visible
        updateDebug()
    }

    func setReducedMotion(_ enabled: Bool) {
        reducedMotion = enabled
        reset()
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastFrame = currentTime }
        guard isRunning else { return }
        frameDelta = lastFrame.map { min(max(currentTime - $0, 0), 0.1) } ?? 0
        elapsed += frameDelta
        for leaf in leaves {
            if !leaf.released && elapsed >= leaf.member.releaseSeconds { leaf.release() }
            guard leaf.released && !leaf.finished else { continue }
            // Every body samples this ONE field at group time, not time since its release.
            leaf.apply(wind: wind, elapsed: elapsed)
        }
    }

    override func didSimulatePhysics() {
        guard isRunning else { return }
        for leaf in leaves where leaf.released && !leaf.finished {
            if let terrain {
                leaf.updateContact(deltaTime: frameDelta, configuration: terrain)
                let belowSurface = leaf.node.frame.maxY < size.height * terrain.renderedHeightFraction
                    * terrain.surfaceHeight(at: leaf.node.position.x / size.width)
                if belowSurface { failed = true }
            }
            if leaf.node.frame.maxY < -size.height * reference.offscreenMarginFraction {
                leaf.finish()
                if terrain != nil { failed = true }
            }
        }
        let complete = leaves.allSatisfy(\.finished)
        if let terrain, !complete, elapsed >= terrain.maximumTrialSeconds { failed = true }
        if failed {
            // Preserve the failing pose for diagnosis; never fake a successful landing.
            physicsWorld.speed = 0
            isRunning = false
        }
        if complete { isRunning = false }
        updateDebug()
        publish(force: complete || failed)
    }

    private func updateDebug() {
        guard !debugRoot.isHidden, let drag = reference.stillAirDrag, let config = reference.wind else { return }
        let velocity = wind.sample(at: .zero, elapsedTime: elapsed).velocityMetersPerSecond
        windArrow.path = Self.arrow(origin: CGPoint(x: size.width * 0.07, y: size.height * 0.95),
            vector: PhysicsVector(x: velocity.x * drag.scenePointsPerMeter * config.debugVectorSeconds,
                                  y: velocity.y * drag.scenePointsPerMeter * config.debugVectorSeconds))
        for leaf in leaves { leaf.updateDebug(wind: wind, elapsed: elapsed) }
    }

    private func publish(force: Bool) {
        guard force || elapsed - lastPublication >= reference.diagnosticsUpdateInterval else { return }
        lastPublication = elapsed
        let released = leaves.filter(\.released).count
        let finished = leaves.filter(\.finished).count
        let settled = leaves.filter { $0.settling.isSettled }.count
        let contacting = leaves.filter(\.touchingGround).count
        let state = reducedMotion ? "static preview" : failed ? "needs attention"
            : settled == leaves.count ? "settled" : finished == leaves.count ? "finished"
            : isRunning ? (contacting > 0 ? "settling" : "falling") : "ready"
        diagnosticsHandler?(LeafGroupDiagnostics(state: state, elapsed: elapsed, released: released,
            finished: finished, contacting: contacting, settled: settled, failed: failed,
            wind: wind.sample(at: .zero, elapsedTime: elapsed)))
        if ProcessInfo.processInfo.arguments.contains("--leaf-lab-trace") {
            print(String(format: "group,%llu,%.3f,%@,%d,%d", plan.seed, elapsed, state, released, finished))
            if terrain != nil { print("terrain,\(plan.seed),\(elapsed),contacting=\(contacting),settled=\(settled),failed=\(failed)") }
            for leaf in leaves {
                print(String(format: "member,%d,%.3f,%.2f,%.2f,%.3f,%.3f", leaf.member.id, elapsed,
                    leaf.node.position.x, leaf.node.position.y, leaf.node.zRotation, leaf.node.physicsBody?.angularVelocity ?? 0.0))
            }
        }
    }

    static func arrow(origin: CGPoint, vector: PhysicsVector) -> CGPath {
        let path = CGMutablePath()
        let length = hypot(vector.x, vector.y)
        guard length > 0.5 else { return path }
        let tip = CGPoint(x: origin.x + vector.x, y: origin.y + vector.y)
        let dx = vector.x / length, dy = vector.y / length
        let head = min(10, length * 0.3)
        path.move(to: origin); path.addLine(to: tip)
        path.move(to: CGPoint(x: tip.x - head * dx - head * 0.5 * dy, y: tip.y - head * dy + head * 0.5 * dx))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x - head * dx + head * 0.5 * dy, y: tip.y - head * dy - head * 0.5 * dx))
        return path
    }
}

@MainActor
final class LeafGroupBody {
    let member: LeafGroupMember
    let node: SKSpriteNode
    let overlay = SKNode()
    private let drag: StillAirDragConfiguration
    private let flutter: PassiveFlutterConfiguration
    private var massCenter: NormalizedPhysicsPoint
    private let releasePosition: CGPoint
    private let airArrow = SKShapeNode()
    private let forceArrow = SKShapeNode()
    private let collisionOutline = SKShapeNode()
    private let hasFittedHull: Bool
    private let originalHull: [NormalizedPhysicsPoint]
    private var sheetEnabled = false
    private(set) var sheet = LeafSheetContact()
    private var lastSheetRotation = Double.infinity
    private var lastSheetProjection = 1.0
    private let label = SKLabelNode()
    private(set) var released = false
    private(set) var finished = false
    private(set) var touchingGround = false
    private(set) var settling = LeafSettlingTracker()

    init(member: LeafGroupMember, reference: LeafGravityLabConfiguration, viewport: CGSize, image: UIImage,
         terrain: LeafTerrainConfiguration?, fittedShape: LeafCollisionShape?, contactInsetPoints: Double,
         renderedSize: CGSize? = nil) throws {
        guard let referenceDrag = reference.stillAirDrag, let referenceFlutter = reference.passiveFlutter else {
            throw LeafGravityLabConfigurationError.invalidFlutter
        }
        self.member = member
        drag = member.drag(from: referenceDrag)
        flutter = member.flutter(from: referenceFlutter)
        let width = min(viewport.width, viewport.height) * reference.leafWidthFraction * member.linearScale
        let size = renderedSize ?? CGSize(width: width, height: width * image.size.height / max(1, image.size.width))
        let hull = try fittedShape?.collisionHull(width: size.width, height: size.height, inset: contactInsetPoints)
            ?? reference.collisionHull
        originalHull = hull
        hasFittedHull = fittedShape != nil
        massCenter = LeafAerodynamics.centerOfMass(hull: hull)
        node = SKSpriteNode(texture: SKTexture(image: image), size: size)
        node.name = "group-leaf-\(member.id)"
        node.zPosition = 10
        releasePosition = CGPoint(x: viewport.width * member.releasePoint.x, y: viewport.height * member.releasePoint.y)
        let path = CGMutablePath()
        for (index, point) in hull.enumerated() {
            let position = CGPoint(x: point.x * size.width, y: point.y * size.height)
            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        path.closeSubpath()
        collisionOutline.path = path
        collisionOutline.strokeColor = .systemPink
        collisionOutline.lineWidth = 1
        collisionOutline.isHidden = !hasFittedHull
        overlay.addChild(collisionOutline)
        // Scaling the actual polygon (not just the texture) lets SpriteKit derive inertia.
        let body = SKPhysicsBody(polygonFrom: path)
        body.mass = member.massKilograms
        body.affectedByGravity = true
        body.allowsRotation = true
        body.linearDamping = 0
        body.angularDamping = 0
        body.collisionBitMask = 0
        body.contactTestBitMask = 0
        body.fieldBitMask = 0
        if let terrain {
            body.categoryBitMask = LeafGroupCollision.leaf
            body.collisionBitMask = LeafGroupCollision.terrain
            body.contactTestBitMask = LeafGroupCollision.terrain
            body.usesPreciseCollisionDetection = true
            body.friction = terrain.friction
            body.restitution = terrain.restitution
        }
        node.physicsBody = body
        airArrow.strokeColor = .systemTeal
        forceArrow.strokeColor = .systemPurple
        for arrow in [airArrow, forceArrow] { arrow.lineWidth = 2; overlay.addChild(arrow) }
        label.text = "\(member.id)"
        label.fontName = "Menlo-Bold"
        label.fontSize = 14
        label.fontColor = .darkGray
        overlay.addChild(label)
    }

    func prepare() {
        released = false
        finished = false
        touchingGround = false
        settling = LeafSettlingTracker()
        if sheetEnabled { restoreSheet(LeafSheetContact()) }
        node.physicsBody?.isDynamic = false
        node.physicsBody?.velocity = .zero
        node.physicsBody?.angularVelocity = 0
        node.position = releasePosition
        node.zRotation = member.initialTiltRadians
        node.isHidden = false
    }

    func release() {
        released = true
        node.physicsBody?.isDynamic = true
        node.physicsBody?.isResting = false
        node.physicsBody?.velocity = CGVector(dx: member.initialVelocityMetersPerSecond.x * drag.scenePointsPerMeter,
                                             dy: member.initialVelocityMetersPerSecond.y * drag.scenePointsPerMeter)
        node.physicsBody?.angularVelocity = member.initialAngularVelocity
    }

    func finish() {
        finished = true
        node.physicsBody?.isDynamic = false
        node.physicsBody?.velocity = .zero
        node.physicsBody?.angularVelocity = 0
        node.isHidden = true
    }

    /// Lifecycle restoration only; normal landings still use updateContact.
    func restore(position: CGPoint, rotation: Double, velocity: CGVector, angularVelocity: Double, resting: Bool) {
        released = true
        finished = resting
        node.position = position
        node.zRotation = rotation
        node.isHidden = false
        node.physicsBody?.isDynamic = !resting
        node.physicsBody?.isResting = resting
        node.physicsBody?.velocity = resting ? .zero : velocity
        node.physicsBody?.angularVelocity = resting ? 0 : angularVelocity
    }

    func updateContact(deltaTime: Double, configuration: LeafTerrainConfiguration) {
        guard let body = node.physicsBody else { return }
        touchingGround = body.allContactedBodies().contains { $0.categoryBitMask & body.collisionBitMask != 0 }
        let shouldSettle = settling.update(touchingGround: touchingGround && (!sheetEnabled || sheet.isFlat),
            linearSpeed: hypot(body.velocity.dx, body.velocity.dy) / drag.scenePointsPerMeter,
            angularSpeed: body.angularVelocity, deltaTime: deltaTime, configuration: configuration)
        if shouldSettle {
            // Only remove sub-threshold residual motion after a supported quiet dwell.
            // Keep SpriteKit's actual contact position and angle, with no pose snapping.
            body.velocity = .zero
            body.angularVelocity = 0
            body.isResting = true
            body.isDynamic = false
            finished = true
        }
    }

    func enableSheetContact() { sheetEnabled = true }

    func restoreSheet(_ state: LeafSheetContact) {
        sheet = state
        if sheetEnabled { updateSheetGeometry(force: true) }
    }

    func updateSheet(deltaTime: Double, gravity: Double, surfaceAngle: Double) {
        guard sheetEnabled, let body = node.physicsBody else { return }
        let supported = body.allContactedBodies().contains { $0.categoryBitMask & body.collisionBitMask != 0 }
        sheet.advance(supported: supported, dt: deltaTime, gravity: gravity,
            heightMeters: node.size.height / drag.scenePointsPerMeter, angle: surfaceAngle)
        if sheet.active { updateSheetGeometry(force: false) }
    }

    private func updateSheetGeometry(force: Bool) {
        guard let previous = node.physicsBody else { return }
        let projectionChanged = abs(sheet.projection - lastSheetProjection) > 0.001
        let rotationChanged = abs(node.zRotation - lastSheetRotation) > 0.01
        // The texture projection tracks current orientation exactly. Collision
        // rebuilding is bounded; no pose or velocity is imposed by this operation.
        node.warpGeometry = sheet.active ? sheet.warp(size: node.size, rotation: node.zRotation) : nil
        guard force || projectionChanged || rotationChanged else { return }
        let hull = originalHull.map { p in
            sheet.local(point: CGPoint(x: p.x * node.size.width, y: p.y * node.size.height), rotation: node.zRotation)
        }
        let path = CGMutablePath()
        for (index, p) in hull.enumerated() {
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        let replacement = SKPhysicsBody(polygonFrom: path)
        replacement.mass = previous.mass
        replacement.affectedByGravity = previous.affectedByGravity
        replacement.allowsRotation = previous.allowsRotation
        replacement.linearDamping = previous.linearDamping
        replacement.angularDamping = previous.angularDamping
        replacement.categoryBitMask = previous.categoryBitMask
        replacement.collisionBitMask = previous.collisionBitMask
        replacement.contactTestBitMask = previous.contactTestBitMask
        replacement.fieldBitMask = previous.fieldBitMask
        replacement.usesPreciseCollisionDetection = previous.usesPreciseCollisionDetection
        replacement.friction = previous.friction
        replacement.restitution = previous.restitution
        replacement.isDynamic = previous.isDynamic
        replacement.velocity = previous.velocity
        replacement.angularVelocity = previous.angularVelocity
        node.physicsBody = replacement
        massCenter = LeafAerodynamics.centerOfMass(hull: hull.map {
            NormalizedPhysicsPoint(x: $0.x / node.size.width, y: $0.y / node.size.height)
        })
        collisionOutline.path = path
        lastSheetProjection = sheet.projection
        lastSheetRotation = node.zRotation
    }

    private func sample(wind: WindField, elapsed: Double, airVelocityScale: Double = 1) -> LeafAerodynamicSample {
        let scale = drag.scenePointsPerMeter
        let air = wind.sample(at: PhysicsVector(x: node.position.x / scale, y: node.position.y / scale),
                              elapsedTime: elapsed).velocityMetersPerSecond
        return LeafAerodynamics.sample(airVelocity: PhysicsVector(x: air.x * scale * airVelocityScale,
                                                                 y: air.y * scale * airVelocityScale),
            leafVelocity: PhysicsVector(x: Double(node.physicsBody?.velocity.dx ?? 0), y: Double(node.physicsBody?.velocity.dy ?? 0)),
            angularVelocity: Double(node.physicsBody?.angularVelocity ?? 0), rotation: node.zRotation,
            position: PhysicsVector(x: node.position.x, y: node.position.y),
            leafSize: PhysicsVector(x: node.size.width, y: node.size.height), centerOfMass: massCenter,
            drag: drag, flutter: flutter)
    }

    func apply(wind: WindField, elapsed: Double, airVelocityScale: Double = 1) {
        let sample = sample(wind: wind, elapsed: elapsed, airVelocityScale: airVelocityScale)
        let scale = drag.scenePointsPerMeter
        let applications = [LeafForceApplication(forceNewtons: sample.forceNewtons, scenePoint: sample.centerOfPressure)]
            + LeafAerodynamics.resistanceCouple(torqueNewtonMeters: sample.resistanceTorqueNewtonMeters,
                center: sample.centerOfMass, radiusScenePoints: node.size.width / 2,
                rotation: node.zRotation, scenePointsPerMeter: scale)
        for application in applications {
            node.physicsBody?.applyForce(CGVector(dx: application.forceNewtons.x * scale, dy: application.forceNewtons.y * scale),
                at: CGPoint(x: application.scenePoint.x, y: application.scenePoint.y))
        }
    }

    func updateDebug(wind: WindField, elapsed: Double, airVelocityScale: Double = 1) {
        // Keep the exact contact outline visible after settling for fit inspection.
        overlay.isHidden = finished && !hasFittedHull
        collisionOutline.position = node.position
        collisionOutline.zRotation = node.zRotation
        airArrow.isHidden = finished
        forceArrow.isHidden = finished
        let sample = sample(wind: wind, elapsed: elapsed, airVelocityScale: airVelocityScale)
        let origin = CGPoint(x: sample.centerOfPressure.x, y: sample.centerOfPressure.y)
        airArrow.path = LeafGroupScene.arrow(origin: origin,
            vector: PhysicsVector(x: sample.relativeAirVelocity.x * drag.debugVelocityVectorSeconds,
                                  y: sample.relativeAirVelocity.y * drag.debugVelocityVectorSeconds))
        forceArrow.path = LeafGroupScene.arrow(origin: origin,
            vector: PhysicsVector(x: sample.forceNewtons.x * drag.debugForceVectorPointsPerNewton,
                                  y: sample.forceNewtons.y * drag.debugForceVectorPointsPerNewton))
        label.position = CGPoint(x: node.position.x, y: node.position.y + node.size.height / 2)
    }
}

enum LeafGroupCollision {
    static let leaf: UInt32 = 1 << 0
    static let terrain: UInt32 = 1 << 1
}
#endif
