#if DEBUG
import Foundation
import SpriteKit
import UIKit

/// Review configuration, deliberately separate from the production Autumn Director.
enum AutumnLeafReview {
    static let startProgress = 0.10
    static let endProgress = 0.78
    static let pairGapSeconds = 0.65...1.35
    static let breathingGapSeconds = 4.0...7.0
    static let liveFreshness = 0.35
    static let checkpointInterval = 0.25
    // Diagnostic observation window, not a settling rule or an animation duration.
    static let maximumFlightSeconds = 36.0
    /// Provisional story-environment assumption; not a change to calibrated air aloft.
    static let groundShelterHeightMeters = 0.25
    static let leafWidthFraction = 0.105
    static let canopyPivotY = 0.86
    static let counts = [3, 12]
    static let storageKey = "leafLab.gate6.session.v2"

    static func windScale(heightMeters: Double) -> Double {
        let fraction = min(1, max(0, heightMeters / groundShelterHeightMeters))
        return fraction * fraction * (3 - 2 * fraction)
    }
}

struct AutumnLeafReviewModule: StoryModule {
    let story: Story = .autumnTree
    let layout: AutumnLeafLayout
    let count: Int
    let reference: LeafGravityLabConfiguration
    func makeDirector() -> any StoryDirector {
        AutumnLeafReviewDirector(layout: layout, count: count, reference: reference)
    }
}

struct AutumnLeafReviewDirector: StoryDirector {
    let layout: AutumnLeafLayout
    let count: Int
    let reference: LeafGravityLabConfiguration

    func selectedLeaves(seed: UInt64) -> [AutumnCanopyLeaf] {
        // Depth is assigned BEFORE release from canonical size and branch layering.
        // Small back-canopy instances already have the correct apparent perspective.
        var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("autumn-review-cast-v2"))
        var pools = AutumnLeafDepth.allCases.map { depth in
            var candidates = layout.canopy.filter {
                (0.40...0.69).contains($0.x) && (0.22...0.46).contains($0.y) && depth.accepts($0)
            }.sorted { $0.id < $1.id }
            if candidates.count > 1 {
                for i in stride(from: candidates.count - 1, through: 1, by: -1) {
                    candidates.swapAt(i, random.integer(in: 0...i))
                }
            }
            return candidates
        }
        var selected: [AutumnCanopyLeaf] = []
        for index in 0..<(AutumnLeafReview.counts.contains(count) ? count : 3) {
            let pool = index % pools.count
            if !pools[pool].isEmpty { selected.append(pools[pool].removeFirst()) }
        }
        return selected
    }

    func releaseTimes(duration: Double, seed: UInt64, count: Int) -> [Double] {
        var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("autumn-review-cadence-v2"))
        var offsets = [0.0]
        for i in 1..<count {
            // Only isolated pairs; never a chain of rapid releases.
            let pair = count > 3 && (i == 3 || i == 8)
            offsets.append(offsets.last! + random.value(in: pair
                ? AutumnLeafReview.pairGapSeconds : AutumnLeafReview.breathingGapSeconds))
        }
        let window = duration * (AutumnLeafReview.endProgress - AutumnLeafReview.startProgress)
        let stretch = window / max(1, offsets.last!)
        return offsets.map { duration * AutumnLeafReview.startProgress + $0 * stretch }
    }

    func makePlan(for session: StorySessionContext) -> StoryPlan {
        let start = session.duration * AutumnLeafReview.startProgress
        let leaves = selectedLeaves(seed: session.randomSeed)
        let times = releaseTimes(duration: session.duration, seed: session.randomSeed, count: leaves.count)
        var moments = leaves.enumerated().map { index, leaf in
            let seed = session.randomSeed ^ StableSeed.hash(leaf.id)
            return StoryMoment(id: StoryMomentID(rawValue: "autumn-review.detach.\(leaf.id)"),
                startTime: times[index],
                duration: AutumnLeafReview.maximumFlightSeconds, intensity: 1, randomSeed: seed, quantization: .none,
                visualCue: StoryVisualCue(effect: StoryEffectID(rawValue: leaf.id)),
                audioCue: StoryAudioCue(assetID: "autumn-leaf-detach-intent", bus: .leaves, gain: 0.2))
        }
        if let config = reference.wind,
           let gust = WindField(configuration: config, seed: session.randomSeed, mode: .gust).gust {
            moments.append(StoryMoment(id: StoryMomentID(rawValue: "autumn-review.gust"),
                startTime: start + gust.startSeconds, duration: gust.endSeconds - gust.startSeconds,
                intensity: 1, randomSeed: session.randomSeed, quantization: .none,
                visualCue: StoryVisualCue(effect: StoryEffectID(rawValue: "autumn-review.air")),
                audioCue: StoryAudioCue(assetID: "autumn-gust-intent", bus: .atmosphere, gain: 0.2)))
        }
        return StoryPlan(moments: moments)
    }

    func performance(at context: StoryContext, plan: StoryPlan) -> StoryPerformance {
        AutumnTreeDirector().performance(at: context, plan: plan)
    }
}

/// All image and collision placement uses this same composition-to-scene transform.
struct AutumnLeafGeometry {
    let composition: AutumnDeviceComposition
    let viewport: CGSize
    let scale: Double
    let offset: CGPoint

    init(resources: AutumnTreeSceneResources, viewport: CGSize) {
        composition = resources.composition(for: viewport)
        self.viewport = viewport
        // The debug controls consume height. Fit the complete reviewed composition
        // inside that remaining area instead of cropping away its landing surface.
        scale = min(viewport.width / composition.width, viewport.height / composition.height)
        offset = CGPoint(x: (viewport.width - composition.width * scale) / 2,
                         y: (viewport.height - composition.height * scale) / 2)
    }

    func point(x: Double, y: Double) -> CGPoint {
        CGPoint(x: offset.x + x * scale, y: viewport.height - offset.y - y * scale)
    }

    func leafPose(_ leaf: AutumnCanopyLeaf, imageSize: CGSize) -> (position: CGPoint, size: CGSize, rotation: Double) {
        let square = composition.tree.width * AutumnLeafReview.leafWidthFraction * leaf.scale * scale
        let fit = square / max(imageSize.width, imageSize.height)
        let rotation = -leaf.rotation * .pi / 180
        let pivot = point(x: composition.tree.x + leaf.x * composition.tree.width,
                          y: composition.tree.y + leaf.y * composition.tree.height)
        let centerOffset = square * (AutumnLeafReview.canopyPivotY - 0.5)
        return (CGPoint(x: pivot.x - sin(rotation) * centerOffset,
                        y: pivot.y + cos(rotation) * centerOffset),
                CGSize(width: imageSize.width * fit, height: imageSize.height * fit), rotation)
    }
}

struct AutumnLeafCheckpoint: Codable, Equatable {
    let x: Double
    let y: Double
    let rotation: Double
    let velocityX: Double
    let velocityY: Double
    let angularVelocity: Double
    let resting: Bool
    let reconstructed: Bool
    var depth: AutumnLeafDepth = .foreground
    var sheet: LeafSheetContact = LeafSheetContact()
}

struct AutumnLeafReviewRecord: Codable, Equatable {
    let session: FocusSession
    let count: Int
    var savedAt: Date
    var bodies: [String: AutumnLeafCheckpoint] = [:]
    var viewport: NormalizedPhysicsPoint? = nil
}

enum AutumnLeafRestoration: Equatable {
    case attached, recent, resting, reconstruct
    static func resolve(moment: StoryMoment, elapsed: Double, checkpoint: AutumnLeafCheckpoint?,
                        checkpointAge: Double, reduceMotion: Bool) -> Self {
        if elapsed < moment.startTime { return .attached }
        if checkpoint?.resting == true { return .resting }
        if !reduceMotion, checkpoint != nil, checkpointAge >= 0,
           checkpointAge <= AutumnLeafReview.liveFreshness, moment.isActive(at: elapsed) { return .recent }
        return .reconstruct
    }
}

@MainActor
final class AutumnLeafIntegrationScene: SKScene {
    let record: AutumnLeafReviewRecord
    let player: StoryPlayer
    let geometry: AutumnLeafGeometry
    let terrain: LeafTerrainConfiguration
    let groundRect: CGRect
    let moments: [StoryMoment]
    private(set) var bodies: [String: LeafGroupBody] = [:]
    private(set) var depths: [String: AutumnLeafDepth] = [:]
    private(set) var surfaces: [AutumnLeafDepth: AutumnReviewSurface] = [:]
    private var canopyBottom = Double.infinity
    private(set) var reconstructedIDs: Set<String> = []
    private let reference: LeafGravityLabConfiguration
    private let wind: WindField
    private let shapes: LeafCollisionCatalog
    private let debugRoot = SKNode()
    private let artRoot = SKCropNode()
    private let dispatcher = StoryAudioDispatcher(engine: SilentStoryAudioEngine())
    private var lastDate: Date?
    private var lastSave: Date = .distantPast
    private var lastPublish: Date = .distantPast
    private var images: [String: UIImage] = [:]
    private var textures: [String: SKTexture] = [:]
    private var delta = 0.0
    private(set) var reduceMotion: Bool
    private(set) var failed = false
    var now: () -> Date = Date.init
    var checkpointHandler: ((AutumnLeafReviewRecord) -> Void)?
    var statusHandler: ((String) -> Void)?

    init(size: CGSize, record: AutumnLeafReviewRecord, resources: AutumnTreeSceneResources,
         reference: LeafGravityLabConfiguration, reduceMotion: Bool) throws {
        self.record = record
        self.reference = reference
        self.reduceMotion = reduceMotion
        geometry = AutumnLeafGeometry(resources: resources, viewport: size)
        terrain = try LeafTerrainConfiguration.bundled.get()
        shapes = try LeafCollisionCatalog.bundled.get()
        guard let windConfig = reference.wind, let drag = reference.stillAirDrag else {
            throw LeafGravityLabConfigurationError.invalidWind
        }
        wind = WindField(configuration: windConfig, seed: record.session.randomSeed, mode: .gust)
        player = StoryPlayer(session: record.session, module: AutumnLeafReviewModule(
            layout: resources.leafLayout, count: record.count, reference: reference))
        moments = player.scheduledMoments
        let ground = geometry.composition.terrain.ground
        let overlap = resources.terrainAdjustments.groundVerticalOverlap[geometry.composition.id] ?? 0
        let bottomLeft = geometry.point(x: 0, y: ground.y + ground.height)
        groundRect = CGRect(x: bottomLeft.x, y: bottomLeft.y, width: geometry.composition.width * geometry.scale,
                            height: (ground.height + overlap) * geometry.scale)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.97, green: 0.92, blue: 0.81, alpha: 1)
        physicsWorld.gravity = CGVector(dx: reference.gravity.x, dy: reference.gravity.y)
        let mask = SKSpriteNode(color: .white, size: CGSize(width: geometry.composition.width * geometry.scale,
                                                           height: geometry.composition.height * geometry.scale))
        mask.position = CGPoint(x: size.width / 2, y: size.height / 2)
        artRoot.maskNode = mask
        addChild(artRoot)
        let selected = moments.compactMap { moment in
            resources.leafLayout.canopy.first { $0.id == moment.visualCue?.effect.rawValue }
        }
        try buildScenery(resources: resources, selectedIDs: Set(selected.map(\.id)))
        debugRoot.zPosition = 100
        debugRoot.isHidden = true
        addChild(debugRoot)
        try buildSurfaces()
        for (index, leaf) in selected.enumerated() {
            let image = try loadImage(leaf.assetId)
            let pose = geometry.leafPose(leaf, imageSize: image.size)
            let moment = moments.first { $0.visualCue?.effect.rawValue == leaf.id }!
            var random = SeededRandomNumberGenerator(seed: moment.randomSeed ^ StableSeed.hash("properties"))
            let linearScale = pose.size.width / (min(size.width, size.height) * reference.leafWidthFraction)
            let density = random.value(in: 0.88...1.12)
            let member = LeafGroupMember(id: index + 1, assetID: leaf.assetId, linearScale: linearScale,
                arealDensityScale: density, massKilograms: reference.mass * linearScale * linearScale * density,
                areaSquareMeters: drag.referenceAreaSquareMeters * linearScale * linearScale,
                centerOfPressure: NormalizedPhysicsPoint(x: random.value(in: 0.05...0.11), y: random.value(in: 0.13...0.19)),
                releasePoint: NormalizedPhysicsPoint(x: pose.position.x / size.width, y: pose.position.y / size.height),
                releaseSeconds: moment.startTime, initialTiltRadians: pose.rotation,
                initialVelocityMetersPerSecond: .zero)
            let shape = try shapes.shape(for: leaf.assetId)
            let body = try LeafGroupBody(member: member, reference: reference, viewport: size, image: image,
                terrain: terrain, fittedShape: shape, contactInsetPoints: shapes.contactInsetPoints, renderedSize: pose.size)
            body.prepare()
            body.node.name = leaf.id
            let depth = AutumnLeafDepth.depth(of: leaf)
            depths[leaf.id] = depth
            body.enableSheetContact()
            body.node.physicsBody?.collisionBitMask = depth.collisionMask
            body.node.physicsBody?.contactTestBitMask = depth.collisionMask
            body.node.zPosition = leaf.depth == "behind" ? 40 : 60
            canopyBottom = min(canopyBottom, body.node.frame.minY)
            bodies[leaf.id] = body
            artRoot.addChild(body.node)
            debugRoot.addChild(body.overlay)
        }
        dispatcher.prepare(for: .autumnTree)
        reconcile(record, at: Date())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func loadImage(_ id: String) throws -> UIImage {
        if let image = images[id] { return image }
        guard let url = AutumnTreeSceneResources.assetURL(named: id), let image = UIImage(contentsOfFile: url.path) else {
            throw LeafGravityLabConfigurationError.missingResource
        }
        images[id] = image
        return image
    }

    private func buildScenery(resources: AutumnTreeSceneResources, selectedIDs: Set<String>) throws {
        let c = geometry.composition
        func sprite(_ id: String, rect: AutumnRect, z: Double) throws {
            let node = SKSpriteNode(texture: try texture(id),
                size: CGSize(width: rect.width * geometry.scale, height: rect.height * geometry.scale))
            node.position = geometry.point(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
            node.zPosition = z
            node.name = id
            artRoot.addChild(node)
        }
        try sprite("sky-paper", rect: AutumnRect(x: 0, y: 0, width: c.width, height: c.height), z: 0)
        for (id, placement, z) in [("hill-far-left", c.terrain.farLeft, 10.0), ("hill-far-right", c.terrain.farRight, 10),
            ("hill-mid-left", c.terrain.midLeft, 20), ("hill-mid-right", c.terrain.midRight, 20),
            ("hill-foreground-left", c.terrain.foregroundLeft, 30), ("hill-foreground-right", c.terrain.foregroundRight, 30)] {
            try sprite(id, rect: AutumnRect(x: 0, y: placement.y, width: c.width, height: placement.height), z: z)
        }
        let overlap = resources.terrainAdjustments.groundVerticalOverlap[c.id] ?? 0
        try sprite("ground-base", rect: AutumnRect(x: 0, y: c.terrain.ground.y - overlap,
            width: c.width, height: c.terrain.ground.height + overlap), z: 35)
        try sprite("tree-trunk-branches", rect: c.tree, z: 50)
        for leaf in resources.leafLayout.canopy where !selectedIDs.contains(leaf.id) {
            let image = try loadImage(leaf.assetId)
            let pose = geometry.leafPose(leaf, imageSize: image.size)
            let node = SKSpriteNode(texture: try texture(leaf.assetId), size: pose.size)
            node.name = leaf.id
            node.position = pose.position
            node.zRotation = pose.rotation
            node.zPosition = leaf.depth == "behind" ? 40 : 60
            canopyBottom = min(canopyBottom, node.frame.minY)
            artRoot.addChild(node)
        }
        // Versioned review overrides; the production layout and bitmaps stay untouched.
        for leaf in resources.leafLayout.groundLeaves {
            let image = try loadImage(leaf.assetId)
            let pose = AutumnGroundReviewPose.forLeaf(leaf)
            let depth = pose.depth
            let square = c.width * leaf.size * (c.id == "iphone" ? 1 : 0.65) * geometry.scale
                * pose.sizeMultiplier
            let factor = square / max(image.size.width, image.size.height)
            let node = SKSpriteNode(texture: try texture(leaf.assetId),
                size: CGSize(width: image.size.width * factor, height: image.size.height * factor))
            node.zRotation = -pose.rotationDegrees * .pi / 180
            node.zPosition = depth.zPosition
            node.name = leaf.id
            // Surface placement occurs after all terrain profiles exist.
            node.position = CGPoint(x: geometry.point(x: c.width * leaf.x, y: 0).x, y: 0)
            staticLeaves.append((node, image, depth))
            artRoot.addChild(node)
        }
    }

    private var staticLeaves: [(SKSpriteNode, UIImage, AutumnLeafDepth)] = []

    private func buildSurfaces() throws {
        let c = geometry.composition
        for depth in AutumnLeafDepth.allCases {
            let surface: AutumnReviewSurface
            if depth == .foreground {
                surface = AutumnReviewSurface(points: terrain.surface.map {
                    CGPoint(x: groundRect.minX + $0.x * groundRect.width, y: groundRect.minY + $0.y * groundRect.height)
                })
            } else {
                let placements = depth == .back
                    ? [("hill-far-left", c.terrain.farLeft), ("hill-far-right", c.terrain.farRight)]
                    : [("hill-mid-left", c.terrain.midLeft), ("hill-mid-right", c.terrain.midRight)]
                let profiles = try placements.map { id, placement in
                    (AutumnReviewAlpha(image: try loadImage(id)).topEdge(), placement)
                }
                let samples = profiles[0].0.count
                surface = AutumnReviewSurface(points: (0..<samples).map { i in
                    let x = Double(i) / Double(samples - 1)
                    let y = profiles.map { edge, placement in
                        geometry.point(x: x * c.width, y: placement.y + (1 - edge[i]) * placement.height).y
                    }.max()!
                    return CGPoint(x: geometry.point(x: x * c.width, y: 0).x, y: y)
                })
            }
            surfaces[depth] = surface
            let boundary = SKNode()
            boundary.name = "terrain-contact-\(depth.rawValue)"
            boundary.physicsBody = SKPhysicsBody(edgeChainFrom: surface.path)
            boundary.physicsBody?.categoryBitMask = depth.collisionMask
            boundary.physicsBody?.collisionBitMask = LeafGroupCollision.leaf
            boundary.physicsBody?.contactTestBitMask = LeafGroupCollision.leaf
            boundary.physicsBody?.friction = terrain.friction
            boundary.physicsBody?.restitution = terrain.restitution
            addChild(boundary)
            let outline = SKShapeNode(path: surface.path)
            outline.strokeColor = .systemBrown
            debugRoot.addChild(outline)
        }
        for (node, image, depth) in staticLeaves {
            let surface = surfaces[depth]!
            let angle = surface.angle(at: node.position.x)
            let sheet = LeafSheetContact.flat(surfaceAngle: angle)
            node.warpGeometry = sheet.warp(size: node.size, rotation: node.zRotation)
            node.position.y = AutumnReviewAlpha(image: image).boundary().map { point in
                let p = sheet.project(point: CGPoint(x: point.x * node.size.width, y: point.y * node.size.height), rotation: node.zRotation)
                return surface.height(at: node.position.x + p.x) - p.y
            }.max() ?? surface.height(at: node.position.x)
        }
    }

    func groundHeight(at x: Double) -> Double {
        groundRect.minY + groundRect.height * terrain.surfaceHeight(at: (x - groundRect.minX) / groundRect.width)
    }

    private func texture(_ id: String) throws -> SKTexture {
        if let texture = textures[id] { return texture }
        let texture = SKTexture(image: try loadImage(id))
        textures[id] = texture
        return texture
    }

    func windScale(at position: CGPoint, depth: AutumnLeafDepth = .foreground) -> Double {
        let pointsPerMeter = reference.stillAirDrag!.scenePointsPerMeter
        return AutumnLeafReview.windScale(heightMeters: (position.y - surfaces[depth]!.height(at: position.x)) / pointsPerMeter)
    }

    func reconcile(_ saved: AutumnLeafReviewRecord, at date: Date) {
        lastDate = date
        let elapsed = max(0, date.timeIntervalSince(record.session.startedAt))
        for moment in moments {
            guard let id = moment.visualCue?.effect.rawValue, let body = bodies[id] else { continue }
            let sameViewport = saved.viewport == NormalizedPhysicsPoint(x: size.width, y: size.height)
            // A new composition/aspect ratio cannot reuse old screen-space contact.
            let checkpoint = sameViewport && saved.bodies[id]?.depth == depths[id] ? saved.bodies[id] : nil
            switch AutumnLeafRestoration.resolve(moment: moment, elapsed: elapsed, checkpoint: checkpoint,
                checkpointAge: date.timeIntervalSince(saved.savedAt), reduceMotion: reduceMotion) {
            case .attached: body.prepare()
            case .recent, .resting:
                guard let checkpoint else { continue }
                body.restore(position: CGPoint(x: checkpoint.x * size.width, y: checkpoint.y * size.height),
                    rotation: checkpoint.rotation, velocity: CGVector(dx: checkpoint.velocityX, dy: checkpoint.velocityY),
                    angularVelocity: checkpoint.angularVelocity, resting: checkpoint.resting)
                body.restoreSheet(checkpoint.sheet)
                updateDepthLayer(body, id: id)
                if checkpoint.reconstructed { reconstructedIDs.insert(id) }
            case .reconstruct: reconstructRest(body, id: id)
            }
        }
    }

    private func reconstructRest(_ body: LeafGroupBody, id: String) {
        // An explicit static reconciliation, NOT a simulated/predicted trajectory.
        // Support the visible silhouette directly; the body is never animated here.
        let rotation = body.member.initialTiltRadians
        let surface = surfaces[depths[id]!]!
        let x = min(size.width - body.node.size.width, max(body.node.size.width,
                    body.member.releasePoint.x * size.width))
        let sheet = LeafSheetContact.flat(surfaceAngle: surface.angle(at: x))
        let hull = (try? shapes.shape(for: body.member.assetID).hull) ?? []
        let y = hull.map { p -> Double in
            let localX = p.x * body.node.size.width, localY = p.y * body.node.size.height
            let projected = sheet.project(point: CGPoint(x: localX, y: localY), rotation: rotation)
            return surface.height(at: x + projected.x) - projected.y
        }.max() ?? surface.height(at: x)
        body.restore(position: CGPoint(x: x, y: y), rotation: rotation, velocity: .zero, angularVelocity: 0, resting: true)
        body.restoreSheet(sheet)
        body.node.zPosition = depths[id]!.zPosition
        reconstructedIDs.insert(id)
    }

    private func updateDepthLayer(_ body: LeafGroupBody, id: String) {
        // Delay the terrain layer switch until the WHOLE leaf is below every
        // canopy sprite. Between these heights only the trunk overlaps, and it
        // has the same front/behind relationship on both sides of the switch.
        let depth = depths[id]!
        body.node.zPosition = body.node.frame.maxY < canopyBottom ? depth.zPosition
            : (depth == .foreground ? 60 : 40)
    }

    func checkpoint(at date: Date) -> AutumnLeafReviewRecord {
        var result = record
        result.savedAt = date
        result.viewport = NormalizedPhysicsPoint(x: size.width, y: size.height)
        result.bodies = [:]
        for (id, body) in bodies where body.released {
            result.bodies[id] = AutumnLeafCheckpoint(x: body.node.position.x / size.width,
                y: body.node.position.y / size.height, rotation: body.node.zRotation,
                velocityX: Double(body.node.physicsBody?.velocity.dx ?? 0), velocityY: Double(body.node.physicsBody?.velocity.dy ?? 0),
                angularVelocity: Double(body.node.physicsBody?.angularVelocity ?? 0), resting: body.finished,
                reconstructed: reconstructedIDs.contains(id), depth: depths[id]!, sheet: body.sheet)
        }
        return result
    }

    func setDiagnosticsVisible(_ visible: Bool) { debugRoot.isHidden = !visible }

    func suspend(at date: Date) {
        checkpointHandler?(checkpoint(at: date))
        physicsWorld.speed = 0
        lastDate = nil
        dispatcher.stop()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !failed else { return }
        let date = now()
        let elapsed = max(0, date.timeIntervalSince(record.session.startedAt))
        guard let previous = lastDate else { return }
        delta = max(0, date.timeIntervalSince(previous))
        if delta > AutumnLeafReview.liveFreshness {
            reconcile(checkpoint(at: previous), at: date)
            delta = 0
        }
        lastDate = date
        let activeIDs = Set(player.performance(at: date, reduceMotion: reduceMotion).activeMoments.map(\.id))
        let started = player.moments(startingAfter: previous, through: date).filter { activeIDs.contains($0.id) }
        dispatcher.dispatch(started, sessionStart: record.session.startedAt)
        for moment in moments {
            guard let id = moment.visualCue?.effect.rawValue, let body = bodies[id] else { continue }
            if !body.released && elapsed >= moment.startTime {
                if reduceMotion { reconstructRest(body, id: id) }
                else if activeIDs.contains(moment.id) {
                    body.release()
                    if ProcessInfo.processInfo.arguments.contains("--leaf-lab-trace") {
                        print("gate6-release,seed=\(record.session.randomSeed),elapsed=\(elapsed),id=\(id),depth=\(depths[id]!.rawValue),width=\(body.node.size.width)")
                    }
                } else { reconstructRest(body, id: id) }
            }
            if body.released && !body.finished {
                updateDepthLayer(body, id: id)
                body.apply(wind: wind, elapsed: elapsed - record.session.duration.timeInterval * AutumnLeafReview.startProgress,
                           airVelocityScale: windScale(at: body.node.position, depth: depths[id]!))
            }
        }
    }

    override func didSimulatePhysics() {
        guard !failed, lastDate != nil else { return }
        let date = now()
        let elapsed = max(0, date.timeIntervalSince(record.session.startedAt))
        for (id, body) in bodies where body.released && !body.finished {
            let surface = surfaces[depths[id]!]!
            body.updateSheet(deltaTime: delta, gravity: abs(reference.gravity.y), surfaceAngle: surface.angle(at: body.node.position.x))
            body.updateContact(deltaTime: delta, configuration: terrain)
            if body.node.frame.maxY < surface.height(at: body.node.position.x)
                || elapsed - body.member.releaseSeconds > AutumnLeafReview.maximumFlightSeconds {
                failed = true
                print("gate6-failure,id=\(id),elapsed=\(elapsed),position=\(body.node.position),flat=\(body.sheet.isFlat)")
            }
        }
        if failed { physicsWorld.speed = 0 }
        if !debugRoot.isHidden {
            for (id, body) in bodies {
                body.updateDebug(wind: wind, elapsed: elapsed - record.session.duration.timeInterval * AutumnLeafReview.startProgress,
                                 airVelocityScale: windScale(at: body.node.position, depth: depths[id]!))
            }
        }
        if date.timeIntervalSince(lastSave) >= AutumnLeafReview.checkpointInterval {
            lastSave = date
            checkpointHandler?(checkpoint(at: date))
        }
        if date.timeIntervalSince(lastPublish) >= 0.1 {
            lastPublish = date
            let resting = bodies.values.filter(\.finished).count
            let released = bodies.values.filter(\.released).count
            let state = failed ? "Needs attention" : reduceMotion ? "Reduce Motion · static states"
                : resting == bodies.count ? "At rest" : released == 0 ? "Attached" : "Falling"
            statusHandler?("\(state) · \(resting)/\(bodies.count) at rest · \(reconstructedIDs.count) restored")
            if ProcessInfo.processInfo.arguments.contains("--leaf-lab-trace") {
                print("gate6,\(record.session.randomSeed),\(elapsed),\(released),\(resting),restored=\(reconstructedIDs.count),failed=\(failed)")
            }
        }
    }
}

/// Review-only depth strata. Canonical branch depth and apparent size are retained.
enum AutumnLeafDepth: String, CaseIterable, Codable {
    case back, middle, foreground
    var zPosition: Double { switch self { case .back: 15; case .middle: 25; case .foreground: 75 } }
    var collisionMask: UInt32 { switch self { case .back: 1 << 2; case .middle: 1 << 3; case .foreground: LeafGroupCollision.terrain } }
    func accepts(_ leaf: AutumnCanopyLeaf) -> Bool {
        switch self {
        case .back: leaf.depth == "behind" && leaf.scale <= 0.55
        case .middle: leaf.depth == "behind" && (0.60...0.75).contains(leaf.scale)
        case .foreground: leaf.depth == "front" && leaf.scale >= 0.78
        }
    }
    static func depth(of leaf: AutumnCanopyLeaf) -> Self {
        allCases.first(where: { $0.accepts(leaf) }) ?? .foreground
    }
}

/// Review configuration v2; original production placements remain unchanged.
struct AutumnGroundReviewPose {
    let depth: AutumnLeafDepth
    let sizeMultiplier: Double
    let rotationDegrees: Double
    static func forLeaf(_ leaf: AutumnGroundLeaf) -> Self {
        let distant = ["ground-settled-01", "ground-small-orange-01", "ground-oak-red-02"].contains(leaf.id)
        return Self(depth: distant ? .middle : .foreground, sizeMultiplier: distant ? 0.34 : 0.62,
            // The gold bitmap's long axis is already diagonal; -34 degrees in
            // the legacy layout stood it upright before projection.
            rotationDegrees: leaf.id == "ground-oak-gold-02" ? 20 : leaf.rotation)
    }
}

struct AutumnReviewSurface {
    let points: [CGPoint]
    var path: CGPath {
        let path = CGMutablePath()
        for (i, point) in points.enumerated() {
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
    func height(at x: Double) -> Double {
        if x <= points[0].x { return points[0].y }
        for (a, b) in zip(points, points.dropFirst()) where x <= b.x {
            return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
        }
        return points.last!.y
    }
    func angle(at x: Double) -> Double { atan2(height(at: x + 2) - height(at: x - 2), 4) }
}

/// Read original alpha only; no generated or modified artwork.
struct AutumnReviewAlpha {
    let width: Int
    let height: Int
    let bytes: [UInt8]
    init(image: UIImage) {
        let image = image.cgImage!
        width = image.width; height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let w = width, h = height
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        bytes = pixels
    }
    func topEdge() -> [Double] {
        // Fixed 257 samples keep each paired hill's union registered across sizes.
        (0...256).map { index in
            let x = min(width - 1, index * (width - 1) / 256)
            for y in 0..<height where bytes[(y * width + x) * 4 + 3] >= 128 {
                return 1 - (Double(y) + 0.5) / Double(height)
            }
            return 0
        }
    }
    func boundary() -> [NormalizedPhysicsPoint] {
        var points: [NormalizedPhysicsPoint] = []
        for y in 0..<height {
            var first: Int?, last: Int?
            for x in 0..<width where bytes[(y * width + x) * 4 + 3] >= 128 {
                if first == nil { first = x }; last = x
            }
            if let first, let last {
                for x in [first, last] {
                    points.append(.init(x: (Double(x) + 0.5) / Double(width) - 0.5,
                        y: 0.5 - (Double(y) + 0.5) / Double(height)))
                }
            }
        }
        return points
    }
}

/// Contact-only out-of-plane sheet coordinate. No flight path or in-plane spin.
/// A slender sheet supported at an edge has I = m*h²/3 and gravity moment
/// m*g*h/2*sin(tilt). A small support eccentricity avoids a perfectly balanced
/// mathematical stem. The ground is a unilateral stop at pi/2, with lost energy.
struct LeafSheetContact: Codable, Equatable {
    static let flatProjection = 0.36 // camera elevation / retained paper curl
    static let supportImperfection = 0.06 // radians; fixed, never per-frame noise
    static let dampingPerSecond = 3.5
    var active = false
    var tilt = 0.0
    var speed = 0.0
    var surfaceAngle = 0.0
    var isFlat: Bool { tilt >= .pi / 2 }
    var projection: Double { Self.flatProjection + (1 - Self.flatProjection) * cos(tilt) }
    static func flat(surfaceAngle: Double) -> Self {
        Self(active: true, tilt: .pi / 2, speed: 0, surfaceAngle: surfaceAngle)
    }
    mutating func advance(supported: Bool, dt: Double, gravity: Double, heightMeters: Double, angle: Double) {
        guard supported || active else { return }
        active = true
        surfaceAngle = angle
        guard !isFlat else { return }
        // Substeps make the contact response independent of the display cadence.
        var remaining = min(max(dt, 0), 0.1)
        while remaining > 0 {
            let step = min(remaining, 1.0 / 240)
            let acceleration = 1.5 * gravity / max(0.01, heightMeters)
                * sin(tilt + Self.supportImperfection) - Self.dampingPerSecond * speed
            speed += acceleration * step
            tilt += speed * step
            if tilt >= .pi / 2 { tilt = .pi / 2; speed = 0; break }
            remaining -= step
        }
    }
    /// Texture-local point -> scene-relative point, projected along terrain normal.
    func project(point: CGPoint, rotation: Double) -> CGPoint {
        let relative = rotation - surfaceAngle
        let tangent = point.x * cos(relative) - point.y * sin(relative)
        let normal = (point.x * sin(relative) + point.y * cos(relative)) * projection
        return CGPoint(x: tangent * cos(surfaceAngle) - normal * sin(surfaceAngle),
                       y: tangent * sin(surfaceAngle) + normal * cos(surfaceAngle))
    }
    func local(point: CGPoint, rotation: Double) -> CGPoint {
        let p = project(point: point, rotation: rotation)
        return CGPoint(x: p.x * cos(rotation) + p.y * sin(rotation),
                       y: -p.x * sin(rotation) + p.y * cos(rotation))
    }
    func warp(size: CGSize, rotation: Double) -> SKWarpGeometryGrid {
        let source: [SIMD2<Float>] = [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)]
        let destination = source.map { p -> SIMD2<Float> in
            let result = local(point: CGPoint(x: (Double(p.x) - 0.5) * size.width,
                y: (Double(p.y) - 0.5) * size.height), rotation: rotation)
            return .init(Float(result.x / size.width + 0.5), Float(result.y / size.height + 0.5))
        }
        return SKWarpGeometryGrid(columns: 1, rows: 1, sourcePositions: source, destinationPositions: destination)
    }
}

#endif
