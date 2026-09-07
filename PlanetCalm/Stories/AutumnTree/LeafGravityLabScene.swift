import SpriteKit
import UIKit

enum LeafGravityLabState: String, Equatable, Sendable {
    case ready
    case falling
    case finished
}

struct LeafGravityDiagnostics: Equatable, Sendable {
    let state: LeafGravityLabState
    let elapsedTime: TimeInterval
    let verticalPosition: Double
    let velocity: PhysicsVector
    let dragForceNewtons: PhysicsVector
    var rotationRadians: Double = 0
    var angularVelocity: Double = 0
    var aerodynamics: LeafAerodynamicSample? = nil
    var horizontalPosition: Double = 0
    var wind: WindSample? = nil

    static let ready = LeafGravityDiagnostics(
        state: .ready,
        elapsedTime: 0,
        verticalPosition: 0,
        velocity: .zero,
        dragForceNewtons: .zero
    )
}

enum LeafGravityLabDebugConstants {
    /// Reproducible proof seed; interactive trials persist their own seed.
    static let fixedSeed: UInt64 = 42
    static let markerRadius: CGFloat = 5
    static let markerLabelOffset = CGPoint(x: 9, y: 7)
    static let proofAutodropDelay: TimeInterval = 3
    /// Allow recording to start before release; set dedicated device orientation first.
    static let windProofAutodropDelay: TimeInterval = 8
    static let windMarkerOrigin = NormalizedPhysicsPoint(x: 0.08, y: 0.92)
}

@MainActor
final class LeafGravityLabScene: SKScene {
    var diagnosticsHandler: ((LeafGravityDiagnostics) -> Void)?

    private let configuration: LeafGravityLabConfiguration
    private let leafImage: UIImage
    private var leafNode: SKSpriteNode?
    private var state: LeafGravityLabState = .ready
    private var lastFrameTime: TimeInterval?
    private var simulationElapsed: TimeInterval = 0
    private var lastDiagnosticsTime: TimeInterval = -.infinity
    private var slowMotionEnabled = false
    private let velocityVectorNode = SKShapeNode()
    private let dragVectorNode = SKShapeNode()
    private var dragForceNewtons = PhysicsVector.zero
    private var aerodynamicSample: LeafAerodynamicSample?
    private let airflowVectorNode = SKShapeNode()
    private let liftVectorNode = SKShapeNode()
    private let massMarker = SKShapeNode(circleOfRadius: LeafGravityLabDebugConstants.markerRadius)
    private let pressureMarker = SKShapeNode(circleOfRadius: LeafGravityLabDebugConstants.markerRadius)
    private let pressureArmNode = SKShapeNode()
    private var windField: WindField?
    private let windVectorNode = SKShapeNode()
    private let windLabel = SKLabelNode(text: "WORLD AIR · m/s")

    init(
        size: CGSize,
        configuration: LeafGravityLabConfiguration,
        leafImage: UIImage,
        windSeed: UInt64 = LeafGravityLabDebugConstants.fixedSeed,
        windMode: WindTrialMode = .steady
    ) {
        self.configuration = configuration
        self.leafImage = leafImage
        self.windField = configuration.wind.map { WindField(configuration: $0, seed: windSeed, mode: windMode) }
        super.init(size: size)

        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.96, green: 0.90, blue: 0.75, alpha: 1)
        physicsWorld.gravity = CGVector(
            dx: configuration.gravity.x,
            dy: configuration.gravity.y
        )
        physicsWorld.speed = 1
        addCalibrationGuides()
        configureDebugVectorNodes()
        updateWindVector()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func dropLeaf() {
        resetLeaf(publishReadyState: false)

        let width = min(size.width, size.height) * configuration.leafWidthFraction
        let imageAspectRatio = leafImage.size.height / max(leafImage.size.width, 1)
        let leafSize = CGSize(width: width, height: width * imageAspectRatio)
        let node = SKSpriteNode(
            texture: SKTexture(image: leafImage),
            color: .clear,
            size: leafSize
        )
        node.name = configuration.passiveFlutter != nil ? "passive-flutter-leaf" : configuration.stillAirDrag == nil
            ? "passive-gravity-leaf"
            : "passive-still-air-drag-leaf"
        node.position = CGPoint(
            x: size.width * configuration.releasePoint.x,
            y: size.height * configuration.releasePoint.y
        )
        node.zPosition = 10
        node.zRotation = 0

        let body = SKPhysicsBody(polygonFrom: collisionPath(for: leafSize))
        body.mass = configuration.mass
        body.affectedByGravity = true
        body.allowsRotation = true
        body.linearDamping = 0
        body.angularDamping = 0
        body.velocity = .zero
        body.angularVelocity = 0
        body.collisionBitMask = 0
        body.contactTestBitMask = 0
        body.fieldBitMask = 0
        node.physicsBody = body

        addChild(node)
        leafNode = node
        state = .falling
        simulationElapsed = 0
        lastDiagnosticsTime = -.infinity
        dragForceNewtons = .zero
        updateDebugVectors(for: node)
        publishDiagnostics(force: true)
    }

    func reset() {
        resetLeaf(publishReadyState: true)
    }

    func setWindTrial(seed: UInt64, mode: WindTrialMode) {
        windField = configuration.wind.map { WindField(configuration: $0, seed: seed, mode: mode) }
        reset()
    }

    func setSlowMotion(_ enabled: Bool) {
        slowMotionEnabled = enabled
        physicsWorld.speed = enabled ? 0.25 : 1
    }

    override func update(_ currentTime: TimeInterval) {
        defer { lastFrameTime = currentTime }
        guard state == .falling, let node = leafNode else { return }

        if let lastFrameTime {
            let frameDuration = min(max(currentTime - lastFrameTime, 0), 0.1)
            simulationElapsed += frameDuration * physicsWorld.speed
        }
        updateWindVector()

        if let body = node.physicsBody,
           let dragConfiguration = configuration.stillAirDrag {
            if configuration.passiveFlutter != nil {
                let sample = flutterSample(for: node)
                aerodynamicSample = sample
                dragForceNewtons = sample?.dragForceNewtons ?? .zero
                if let sample {
                    let scale = dragConfiguration.scenePointsPerMeter
                    // Same translational scale as approved Gate 2. The application
                    // point is in scene coordinates; the engine derives r cross F.
                    body.applyForce(CGVector(dx: sample.forceNewtons.x * scale,
                                             dy: sample.forceNewtons.y * scale),
                                    at: CGPoint(x: sample.centerOfPressure.x, y: sample.centerOfPressure.y))
                    // Express the resisting torque as a force couple through the
                    // SAME force/scene-point adapter. Do not apply an independently
                    // scaled torque: SpriteKit's torque units differ from point forces.
                    for application in LeafAerodynamics.resistanceCouple(
                        torqueNewtonMeters: sample.resistanceTorqueNewtonMeters,
                        center: sample.centerOfMass, radiusScenePoints: node.size.width / 2,
                        rotation: node.zRotation, scenePointsPerMeter: scale
                    ) {
                        body.applyForce(CGVector(dx: application.forceNewtons.x * scale,
                                                 dy: application.forceNewtons.y * scale),
                                        at: CGPoint(x: application.scenePoint.x, y: application.scenePoint.y))
                    }
                }
            } else {
                dragForceNewtons = LeafAerodynamics.stillAirDrag(
                    leafVelocity: PhysicsVector(
                        x: body.velocity.dx,
                        y: body.velocity.dy
                    ),
                    configuration: dragConfiguration
                )
                // The pure model returns Newtons; SpriteKit integrates force through
                // scene-distance units, so convert physical meters to scene points.
                body.applyForce(
                    CGVector(
                        dx: dragForceNewtons.x * dragConfiguration.scenePointsPerMeter,
                        dy: dragForceNewtons.y * dragConfiguration.scenePointsPerMeter
                    )
                )
            }
        } else {
            dragForceNewtons = .zero
        }

        // Gate 3 overlays and termination use the integrated frame, not stale state.
        if configuration.passiveFlutter != nil { return }
        let margin = size.height * configuration.offscreenMarginFraction
        if node.position.y + node.size.height / 2 < -margin {
            state = .finished
            node.physicsBody?.affectedByGravity = false
            node.physicsBody?.velocity = .zero
        }
        updateDebugVectors(for: node)
        publishDiagnostics(force: state == .finished)
    }

    override func didSimulatePhysics() {
        guard configuration.passiveFlutter != nil, state == .falling, let node = leafNode else { return }
        let margin = size.height * configuration.offscreenMarginFraction
        if node.calculateAccumulatedFrame().maxY < -margin {
            state = .finished
            node.physicsBody?.isDynamic = false
            node.physicsBody?.velocity = .zero
            node.physicsBody?.angularVelocity = 0
            aerodynamicSample = nil
            dragForceNewtons = .zero
        } else {
            aerodynamicSample = flutterSample(for: node)
            dragForceNewtons = aerodynamicSample?.dragForceNewtons ?? .zero
        }
        updateDebugVectors(for: node)
        publishDiagnostics(force: state == .finished)
    }

    private func flutterSample(for node: SKSpriteNode) -> LeafAerodynamicSample? {
        guard let body = node.physicsBody,
              let drag = configuration.stillAirDrag,
              let flutter = configuration.passiveFlutter else { return nil }
        let air = windField?.sample(
            at: PhysicsVector(x: node.position.x / drag.scenePointsPerMeter,
                              y: node.position.y / drag.scenePointsPerMeter),
            elapsedTime: simulationElapsed).velocityMetersPerSecond ?? .zero
        return LeafAerodynamics.sample(
            airVelocity: PhysicsVector(x: air.x * drag.scenePointsPerMeter, y: air.y * drag.scenePointsPerMeter),
            leafVelocity: PhysicsVector(x: body.velocity.dx, y: body.velocity.dy),
            angularVelocity: body.angularVelocity, rotation: node.zRotation,
            position: PhysicsVector(x: node.position.x, y: node.position.y),
            leafSize: PhysicsVector(x: node.size.width, y: node.size.height),
            centerOfMass: LeafAerodynamics.centerOfMass(hull: configuration.collisionHull),
            drag: drag, flutter: flutter
        )
    }

    private func resetLeaf(publishReadyState: Bool) {
        leafNode?.removeFromParent()
        leafNode = nil
        state = .ready
        simulationElapsed = 0
        updateWindVector()
        lastDiagnosticsTime = -.infinity
        dragForceNewtons = .zero
        aerodynamicSample = nil
        for overlay in [airflowVectorNode, liftVectorNode, massMarker, pressureMarker, pressureArmNode] {
            overlay.isHidden = true
        }
        velocityVectorNode.isHidden = true
        dragVectorNode.isHidden = true
        if publishReadyState {
            var ready = LeafGravityDiagnostics.ready
            ready.wind = windField?.sample(at: .zero, elapsedTime: 0)
            diagnosticsHandler?(ready)
        }
    }

    private func publishDiagnostics(force: Bool) {
        guard force || simulationElapsed - lastDiagnosticsTime >= configuration.diagnosticsUpdateInterval else {
            return
        }
        lastDiagnosticsTime = simulationElapsed
        diagnosticsHandler?(
            LeafGravityDiagnostics(
                state: state,
                elapsedTime: simulationElapsed,
                verticalPosition: Double(leafNode?.position.y ?? 0),
                velocity: PhysicsVector(
                    x: Double(leafNode?.physicsBody?.velocity.dx ?? 0),
                    y: Double(leafNode?.physicsBody?.velocity.dy ?? 0)
                ),
                dragForceNewtons: dragForceNewtons,
                rotationRadians: Double(leafNode?.zRotation ?? 0),
                angularVelocity: Double(leafNode?.physicsBody?.angularVelocity ?? 0),
                aerodynamics: aerodynamicSample,
                horizontalPosition: Double(leafNode?.position.x ?? 0),
                wind: windField?.sample(at: .zero, elapsedTime: simulationElapsed)
            )
        )
    }

    private func configureDebugVectorNodes() {
        windVectorNode.strokeColor = .systemIndigo
        windVectorNode.lineWidth = 4
        windVectorNode.zPosition = 25
        addChild(windVectorNode)
        windLabel.fontName = "Menlo-Bold"
        windLabel.fontSize = 12
        windLabel.fontColor = .systemIndigo
        windLabel.horizontalAlignmentMode = .left
        windLabel.zPosition = 25
        addChild(windLabel)
        velocityVectorNode.strokeColor = UIColor(red: 0.02, green: 0.42, blue: 0.72, alpha: 0.95)
        velocityVectorNode.lineWidth = 3
        velocityVectorNode.zPosition = 20
        velocityVectorNode.name = "velocity-vector"
        velocityVectorNode.isHidden = true
        addChild(velocityVectorNode)

        dragVectorNode.strokeColor = UIColor(red: 0.72, green: 0.13, blue: 0.42, alpha: 0.95)
        dragVectorNode.lineWidth = 3
        dragVectorNode.zPosition = 21
        dragVectorNode.name = "drag-force-vector"
        dragVectorNode.isHidden = true
        addChild(dragVectorNode)

        airflowVectorNode.strokeColor = .systemTeal
        airflowVectorNode.lineWidth = 7
        airflowVectorNode.zPosition = 19
        liftVectorNode.strokeColor = UIColor(red: 0.12, green: 0.42, blue: 0.16, alpha: 1)
        liftVectorNode.lineWidth = 3
        liftVectorNode.zPosition = 22
        pressureArmNode.strokeColor = .darkGray
        pressureArmNode.lineWidth = 1
        pressureArmNode.zPosition = 23
        massMarker.fillColor = .black
        massMarker.strokeColor = .white
        pressureMarker.fillColor = .systemOrange
        pressureMarker.strokeColor = .black
        for (marker, label) in [(massMarker, "M"), (pressureMarker, "P")] {
            marker.zPosition = 24
            let text = SKLabelNode(text: label)
            text.fontName = "Menlo-Bold"
            text.fontSize = 11
            text.fontColor = .black
            text.position = LeafGravityLabDebugConstants.markerLabelOffset
            marker.addChild(text)
        }
        for overlay in [airflowVectorNode, liftVectorNode, massMarker, pressureMarker, pressureArmNode] {
            overlay.isHidden = true
            addChild(overlay)
        }
    }

    private func updateDebugVectors(for node: SKSpriteNode) {
        guard let dragConfiguration = configuration.stillAirDrag,
              let velocity = node.physicsBody?.velocity else {
            velocityVectorNode.isHidden = true
            dragVectorNode.isHidden = true
            return
        }

        if configuration.passiveFlutter != nil {
            velocityVectorNode.isHidden = true
            guard let sample = aerodynamicSample ?? flutterSample(for: node), state == .falling else {
                for overlay in [airflowVectorNode, dragVectorNode, liftVectorNode, massMarker, pressureMarker, pressureArmNode] {
                    overlay.isHidden = true
                }
                return
            }
            let pressure = CGPoint(x: sample.centerOfPressure.x, y: sample.centerOfPressure.y)
            massMarker.position = CGPoint(x: sample.centerOfMass.x, y: sample.centerOfMass.y)
            pressureMarker.position = pressure
            massMarker.isHidden = false
            pressureMarker.isHidden = false
            let arm = CGMutablePath()
            arm.move(to: massMarker.position)
            arm.addLine(to: pressure)
            pressureArmNode.path = arm
            pressureArmNode.isHidden = false
            setArrow(airflowVectorNode, origin: pressure,
                     vector: CGVector(dx: sample.relativeAirVelocity.x * dragConfiguration.debugVelocityVectorSeconds,
                                      dy: sample.relativeAirVelocity.y * dragConfiguration.debugVelocityVectorSeconds))
            for (arrow, force) in [(dragVectorNode, sample.dragForceNewtons), (liftVectorNode, sample.liftForceNewtons)] {
                setArrow(arrow, origin: pressure,
                         vector: CGVector(dx: force.x * dragConfiguration.debugForceVectorPointsPerNewton,
                                          dy: force.y * dragConfiguration.debugForceVectorPointsPerNewton))
            }
            return
        }

        setArrow(
            velocityVectorNode,
            origin: node.position,
            vector: CGVector(
                dx: velocity.dx * dragConfiguration.debugVelocityVectorSeconds,
                dy: velocity.dy * dragConfiguration.debugVelocityVectorSeconds
            )
        )
        setArrow(
            dragVectorNode,
            origin: node.position,
            vector: CGVector(
                dx: dragForceNewtons.x * dragConfiguration.debugForceVectorPointsPerNewton,
                dy: dragForceNewtons.y * dragConfiguration.debugForceVectorPointsPerNewton
            )
        )
    }

    private func updateWindVector() {
        guard let field = windField, let wind = configuration.wind,
              let scale = configuration.stillAirDrag?.scenePointsPerMeter else {
            windVectorNode.isHidden = true
            windLabel.isHidden = true
            return
        }
        let sample = field.sample(at: .zero, elapsedTime: simulationElapsed)
        let origin = CGPoint(x: size.width * LeafGravityLabDebugConstants.windMarkerOrigin.x,
                             y: size.height * LeafGravityLabDebugConstants.windMarkerOrigin.y)
        setArrow(windVectorNode, origin: origin,
                 vector: CGVector(dx: sample.velocityMetersPerSecond.x * scale * wind.debugVectorSeconds,
                                  dy: sample.velocityMetersPerSecond.y * scale * wind.debugVectorSeconds))
        windLabel.position = CGPoint(x: origin.x, y: origin.y + 20)
        windLabel.isHidden = false
    }

    private func setArrow(
        _ shapeNode: SKShapeNode,
        origin: CGPoint,
        vector: CGVector
    ) {
        let magnitude = hypot(vector.dx, vector.dy)
        guard magnitude > 0.5 else {
            shapeNode.isHidden = true
            return
        }

        let tip = CGPoint(x: origin.x + vector.dx, y: origin.y + vector.dy)
        let unit = CGVector(dx: vector.dx / magnitude, dy: vector.dy / magnitude)
        let normal = CGVector(dx: -unit.dy, dy: unit.dx)
        let arrowheadLength = min(12, magnitude * 0.32)
        let arrowheadWidth = arrowheadLength * 0.58
        let base = CGPoint(
            x: tip.x - unit.dx * arrowheadLength,
            y: tip.y - unit.dy * arrowheadLength
        )

        let path = CGMutablePath()
        path.move(to: origin)
        path.addLine(to: tip)
        path.move(to: CGPoint(
            x: base.x + normal.dx * arrowheadWidth,
            y: base.y + normal.dy * arrowheadWidth
        ))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(
            x: base.x - normal.dx * arrowheadWidth,
            y: base.y - normal.dy * arrowheadWidth
        ))
        shapeNode.path = path
        shapeNode.isHidden = false
    }

    private func collisionPath(for leafSize: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard let first = configuration.collisionHull.first else { return path }
        path.move(to: scenePoint(from: first, leafSize: leafSize))
        for point in configuration.collisionHull.dropFirst() {
            path.addLine(to: scenePoint(from: point, leafSize: leafSize))
        }
        path.closeSubpath()
        return path
    }

    private func scenePoint(
        from normalizedPoint: NormalizedPhysicsPoint,
        leafSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: normalizedPoint.x * leafSize.width,
            y: normalizedPoint.y * leafSize.height
        )
    }

    private func addCalibrationGuides() {
        for fraction in [0.2, 0.4, 0.6, 0.8] {
            let path = CGMutablePath()
            let y = size.height * fraction
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))

            let line = SKShapeNode(path: path)
            line.strokeColor = UIColor(red: 0.43, green: 0.31, blue: 0.18, alpha: 0.16)
            line.lineWidth = 1
            line.zPosition = 0
            addChild(line)
        }
    }
}
