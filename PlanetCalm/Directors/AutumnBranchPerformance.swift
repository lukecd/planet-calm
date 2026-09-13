import Foundation

struct AutumnBranchTuning: Codable, Equatable, Sendable {
    var windStrength = 0.65
    var gustDuration = 8.0
    var flexibility = 1.0
    var damping = 1.0
    var releaseSensitivity = 1.0
    var sunPosition = 0.25
    var sunIntensity = 1.0
    var shadowSoftness = 0.5
    var backlight = 0.55
    static let standard = Self()
}

struct AutumnBranchRecord: Codable, Equatable, Sendable {
    /// Persist knobs, never the performance or its manually triggered events.
    var settingsOnly: Self {
        var settings = self
        settings.manualGusts = []
        settings.bird?.flight = nil
        settings.deer?.encounter = nil
        return settings
    }
    var tuning = AutumnBranchTuning.standard
    var manualGusts: [Double] = []
    // Optional keeps previously persisted records compatible.
    var bird: AutumnBirdStudy?
    var deer: AutumnDeerStudy?
}

/// Seeded spatial description of one shared StoryMoment, not a second scheduler.
struct AutumnWindPassage: Equatable, Sendable {
    let origin: SIMD2<Double>
    let direction: SIMD2<Double>
    let travelSpeed: Double
    let breadth: Double
    let attack: Double
    let doublePulse: Bool
    let durationScale: Double
    let strengthScale: Double

    init(seed: UInt64, index: Int) {
        func choice(_ channel: Int) -> Double {
            AutumnCanopy.variation(Int(seed % 100_003) * 29 + index * 173 + channel * 811)
        }
        let side = choice(0) < 0.5 ? 1.0 : -1.0
        let angle = (choice(1) - 0.5) * 0.48
        direction = SIMD2(side * cos(angle), sin(angle))
        origin = SIMD2(side > 0 ? -120 : 860, 160 + choice(2) * 580)
        travelSpeed = 240 + choice(3) * 100
        breadth = 420 + choice(4) * 300
        attack = 0.23 + choice(5) * 0.20
        doublePulse = choice(8) < 0.35
        durationScale = 0.85 + choice(6) * 0.45
        strengthScale = 0.90 + choice(7) * 0.22
    }

    func velocity(at position: SIMD2<Double>, seconds: Double, moment: StoryMoment) -> SIMD2<Double> {
        guard seconds > moment.startTime else { return .zero }
        let delta = position - origin
        let along = max(0, delta.x * direction.x + delta.y * direction.y)
        let across = delta.x * direction.y - delta.y * direction.x
        let local = seconds - moment.startTime - along / travelSpeed
        guard local > 0, local < moment.duration else { return .zero }
        var pulse = GustPlan(startSeconds: 0, attackSeconds: moment.duration * attack,
            peakSeconds: moment.duration * 0.12, decaySeconds: moment.duration * (0.88 - attack),
            velocityMetersPerSecond: .zero).envelope(at: local).value
        if doublePulse { pulse *= 1 - 0.24 * pow(sin(.pi * local / moment.duration), 8) }
        let footprint = 0.55 + 0.45 * exp(-pow(across / breadth, 2))
        return direction * pulse * moment.intensity * footprint
    }
}

/// Story percentages place events. Physical motion always runs in seconds.
struct AutumnBranchPlan: Equatable, Sendable {
    let duration: Double
    let seed: UInt64
    let tuning: AutumnBranchTuning
    let gusts: [StoryMoment]
    let windPassages: [AutumnWindPassage]
    let isFullTree: Bool
    /// One stable event per leaf, indexed by leaf identity rather than release order.
    let leafReleases: [StoryMoment]
    let deerEnding: AutumnDeerEncounter
    let encounters: AutumnEncounterSchedule

    init(duration: Double, seed: UInt64, tuning: AutumnBranchTuning, manualGusts: [Double] = [], isFullTree: Bool = false,
         deerTuning: AutumnDeerTuning = .init()) {
        self.isFullTree = isFullTree
        self.duration = duration
        self.seed = seed
        self.tuning = tuning
        deerEnding = .scheduled(duration:duration,tuning:deerTuning)
        encounters = AutumnEncounterSchedule(duration: duration, seed: seed, deer: deerEnding,
                                             gustDuration: tuning.gustDuration)
        let scheduled = isFullTree ? encounters.breezeTimes : [0.08, 0.40, 0.72].map { $0 * duration }
        leafReleases = isFullTree ? Self.makeLeafReleases(duration: duration, seed: seed, tuning: tuning) : []
        let passages = (scheduled + manualGusts).indices.map { AutumnWindPassage(seed: seed, index: $0) }
        windPassages = passages
        gusts = (scheduled + manualGusts).enumerated().map { index, onset in
            StoryMoment(id: .init(rawValue: "autumn.breeze.\(index)"),
                startTime: onset, duration: tuning.gustDuration * (isFullTree ? passages[index].durationScale : 1),
                intensity: tuning.windStrength * (isFullTree ? passages[index].strengthScale : 1)
                    * (isFullTree && onset > duration * 0.82 ? 0.78 : 1),
                randomSeed: seed, quantization: .none,
                visualCue: .init(effect: .init(rawValue: "autumn.wind")),
                audioCue: .init(assetID: "autumn-gust-intent", bus: .atmosphere, gain: 0.2))
        }
    }

    private static func makeLeafReleases(duration: Double, seed: UInt64,
                                         tuning: AutumnBranchTuning) -> [StoryMoment] {
        let count = AutumnCanopy.shoots.count
        let salt = Int(seed % 100_003)
        // Related shoots tend to loosen near one another without stripping whole
        // branches at once. Stratified ranks prevent an end-of-session avalanche.
        let order = AutumnCanopy.shoots.indices.sorted { a, b in
            func key(_ id: Int) -> Double {
                0.45 * AutumnCanopy.variation(AutumnCanopy.shoots[id].limb + salt)
                    + 0.55 * AutumnCanopy.variation(id * 19 + salt + 701)
            }
            return key(a) == key(b) ? a < b : key(a) < key(b)
        }
        var ranks = Array(repeating: 0, count: count)
        for (rank, id) in order.enumerated() { ranks[id] = rank }
        let first = duration * 0.08
        // Reserve physical seconds for flight, then ground-only breezes.
        let last = max(first, min(duration * 0.80, duration - 16))
        return (0..<count).map { id in
            let jitter = 0.2 + 0.6 * AutumnCanopy.variation(id + salt + 1900)
            let rank = (Double(ranks[id]) + jitter) / Double(count)
            let looseness = min(1.25, max(0.8, tuning.releaseSensitivity))
            let u = pow(rank, looseness)
            let spread = 0.6 * u + 0.4 * u * u * (3 - 2 * u)
            return StoryMoment(id: .init(rawValue: "autumn.leaf.release.\(id)"),
                startTime: first + (last - first) * spread, duration: 0,
                intensity: 1, randomSeed: seed, quantization: .none,
                visualCue: .init(effect: .init(rawValue: "autumn.leaf.release")), audioCue: nil)
        }
    }

    func hasSameDynamics(as other: Self) -> Bool {
        duration == other.duration && seed == other.seed && gusts == other.gusts && leafReleases == other.leafReleases && isFullTree == other.isFullTree
            && tuning.flexibility == other.tuning.flexibility
            && tuning.damping == other.tuning.damping
            && tuning.releaseSensitivity == other.tuning.releaseSensitivity
    }

    /// Named sound banks are Autumn art direction, not reversed splash events.
    func poolWeights(at seconds: Double) -> PerformancePoolBlend {
        PerformancePoolBlend.sample(progress: seconds / max(1, duration))
    }

    func air(at position: SIMD2<Double>, seconds: Double, indices: [Int]? = nil) -> SIMD2<Double> {
        guard isFullTree else { return SIMD2(wind(at: position.x, seconds: seconds), 0) }
        var velocity = SIMD2<Double>.zero
        for index in indices ?? Array(gusts.indices) {
            velocity += windPassages[index].velocity(at: position, seconds: seconds, moment: gusts[index])
        }
        let speed = hypot(velocity.x, velocity.y)
        if speed > 1.8 { velocity *= 1.8 / speed }
        // No perpetual rightward conveyor between gusts.
        velocity.x += 0.025 * tuning.windStrength * sin(seconds * 0.19 + position.x * 0.003)
        return velocity
    }

    func wind(at x: Double, seconds: Double) -> Double {
        if isFullTree { return air(at: SIMD2(x, 350), seconds: seconds).x }
        let delay = max(0, x) / 230
        let strength = gusts.reduce(0.0) { value, event in
            let local = seconds - event.startTime - delay
            let pulse = GustPlan(startSeconds: 0, attackSeconds: event.duration * 0.30,
                peakSeconds: event.duration * 0.12, decaySeconds: event.duration * 0.58,
                velocityMetersPerSecond: .zero).envelope(at: local).value
            return value + pulse * event.intensity
        }
        return min(1.8, strength) + 0.07 * tuning.windStrength
            * (1 + 0.3 * sin(seconds * 0.6 + x * 0.006))
    }
}

/// Branch hierarchy in a fixed, y-up drawing space. Children attach to parent
/// centerlines; taper and asymmetric forks are authored, not independent sprites.
enum AutumnCanopy {
    struct Limb {
        let parent: Int?
        let at: Double
        let length: Double
        let angle: Double
        let width: Double
        let tipWidth: Double
        let bend: Double
        let depth: Int
    }
    struct Shoot {
        let limb: Int
        let at: Double
        let side: Double
        let reach: Double
        let angle: Double
        let size: Double
        let artwork: Int
    }
    struct Curve: Equatable {
        var start: SIMD2<Double>
        var control: SIMD2<Double>
        var end: SIMD2<Double>
        var rotation: Double
        func point(_ t: Double) -> SIMD2<Double> {
            start * ((1-t)*(1-t)) + control * (2*t*(1-t)) + end * (t*t)
        }
        func tangent(_ t: Double) -> SIMD2<Double> {
            (control-start) * (2*(1-t)) + (end-control) * (2*t)
        }
    }

    static func variation(_ index: Int) -> Double {
        let x = sin(Double(index * 137 + 41) * 12.9898) * 43758.5453
        return x - floor(x)
    }

    static let limbs: [Limb] = {
        var result: [Limb] = []
        func add(_ parent: Int?, _ at: Double, _ length: Double, _ angle: Double,
                 _ width: Double, _ tip: Double, _ bend: Double, _ depth: Int) {
            result.append(Limb(parent: parent, at: at, length: length, angle: angle,
                width: width, tipWidth: tip, bend: bend, depth: depth))
        }
        add(nil, 0, 214, 1.48, 60, 32, -0.06, 0)
        add(0, 1, 204, 1.75, 32, 19, 0.09, 0)
        add(1, 1, 193, 1.29, 19, 9, -0.08, 1)
        add(2, 1, 136, 1.75, 9, 1.2, 0.05, 2)
        add(0, 0.82, 237, 2.45, 25, 11, 0.13, 1)
        add(4, 1, 151, 2.28, 11, 1.4, -0.07, 2)
        add(1, 0.30, 239, 0.60, 23, 9, -0.13, 1)
        add(6, 1, 162, 0.63, 9, 1.2, 0.07, 2)
        add(1, 0.76, 216, 2.35, 17, 6, 0.11, 1)
        add(8, 1, 110, 2.50, 6, 1.0, -0.06, 2)
        add(2, 0.48, 173, 0.58, 12, 4, -0.07, 2)
        add(10, 1, 121, 0.65, 4, 0.8, 0.06, 3)
        add(2, 0.60, 153, 2.20, 9, 1.1, 0.09, 2)
        add(6, 0.48, 164, 1.35, 10, 1.5, 0.05, 2)
        add(4, 0.48, 165, 1.60, 10, 1.4, -0.07, 2)
        add(8, 0.45, 145, 1.40, 8, 1.0, 0.07, 2)
        // Smaller lateral shoots, with unequal intervals and no mirror symmetry.
        for parent in 3..<16 {
            let base = result[parent]
            for side in 0..<2 {
                let index = parent * 2 + side
                let at = 0.42 + Double(side) * 0.36 + variation(index) * 0.08
                let direction = side == 0 ? -1.0 : 1.0
                add(parent, at, 65 + 44 * variation(index+30),
                    base.angle + direction * (0.48 + 0.32 * variation(index+60)),
                    max(2, base.width * (1-at) * 0.5), 0.65,
                    direction * 0.10, 3)
            }
        }
        return result
    }()

    static let shoots: [Shoot] = {
        var result: [Shoot] = []
        for limb in 3..<limbs.count {
            let count = limb < 16 ? 4 : 5
            for slot in 0..<count {
                let index = result.count
                let side = slot % 2 == 0 ? -1.0 : 1.0
                let at = 0.24 + Double(slot) / Double(count) * 0.72 + variation(index+300)*0.08
                let size = 0.53 + variation(index+500) * 0.25
                // Regions lean amber, gold, or russet rather than alternating colors.
                let region = limb % 5
                let artwork = variation(index+800) < 0.73 ? (region < 2 ? 1 : region < 4 ? 0 : 2) : index % 3
                result.append(Shoot(limb: limb, at: min(0.98, at), side: side,
                    reach: 13 + variation(index+600)*15,
                    angle: 0.25 + side * (0.55 + variation(index+700)*0.85),
                    size: size, artwork: artwork))
            }
        }
        return result
    }()

    static func curves(angles: [Double]) -> [Curve] {
        var result: [Curve] = []
        for (index, limb) in limbs.enumerated() {
            let parent = limb.parent.map { result[$0] }
            let start = parent?.point(limb.at) ?? SIMD2(350, 0)
            let rotation = (parent?.rotation ?? 0) + (angles.indices.contains(index) ? angles[index] : 0)
            let angle = limb.angle + rotation
            let delta = SIMD2(cos(angle), sin(angle)) * limb.length
            let normal = SIMD2(-sin(angle), cos(angle))
            result.append(Curve(start: start, control: start + delta * 0.48 + normal * limb.length * limb.bend,
                end: start + delta, rotation: rotation))
        }
        return result
    }

    static func joint(id: Int, curves: [Curve]) -> (root: SIMD2<Double>, tip: SIMD2<Double>, angle: Double) {
        let shoot = shoots[id]
        let curve = curves[shoot.limb]
        let root = curve.point(shoot.at)
        let tangent = curve.tangent(shoot.at)
        let theta = atan2(tangent.y, tangent.x)
        let direction = theta + shoot.side * 0.85
        let tip = root + SIMD2(cos(direction), sin(direction)) * shoot.reach
        return (root, tip, shoot.angle + curve.rotation)
    }

    static func frame() -> AutumnBranchFrame {
        var frame = AutumnBranchFrame()
        frame.isFullTree = true
        frame.limbAngles = Array(repeating: 0, count: limbs.count)
        frame.limbVelocities = frame.limbAngles
        frame.canopyCurves = curves(angles: frame.limbAngles)
        frame.leaves = shoots.enumerated().map { id, shoot in
            var leaf = AutumnBranchLeaf(id: id)
            leaf.artwork = shoot.artwork
            leaf.size = shoot.size
            leaf.groundLevel = -4 - variation(id + 900) * 39
            return leaf
        }
        return frame
    }
}

/// Authored stem tips in the three 1254-square alpha assets, in y-up scene points.
enum AutumnBranchLeafGeometry {
    static let width = 88.0
    static let height = 105.0

    static func stemOffset(id: Int, angle: Double, turn: Double) -> (x: Double, y: Double) {
        let tips = [(842.0, 1140.0), (878.0, 1127.0), (766.0, 1119.0)]
        let tip = tips[id % tips.count]
        let x = (tip.0 / 1254 - 0.5) * width * cos(turn)
        let y = (0.5 - tip.1 / 1254) * height
        return (x * cos(angle) - y * sin(angle), x * sin(angle) + y * cos(angle))
    }
}

struct AutumnBranchLeaf: Equatable {
    enum Phase: String { case attached, falling, landed, settled }
    let id: Int
    var artwork: Int
    var size = 1.0
    var groundLevel = 0.0
    init(id: Int) { self.id = id; artwork = id % 3 }
    var x: Double = 0
    var y: Double = 0
    var vx: Double = 0
    var vy: Double = 0
    var angle: Double = 0
    var omega: Double = 0
    var turn: Double = 0
    var groundTilt: Double = 0
    var phase = Phase.attached
    var releasedAt: Double?
    var contactTime = 0.0

    /// Paper and shadow share the leaf's receiving plane at groundLevel.
    func groundShadow(sunX: Double, sunHeight: Double) -> (x: Double, verticalScale: Double) {
        let height = max(0, y - groundLevel)
        let settling = min(1, max(0, contactTime / 2))
        let contact = settling * settling * (3 - 2 * settling)
        return (x + (x - sunX) * height / max(80, sunHeight),
                0.25 + (cos(groundTilt) - 0.25) * contact)
    }
}

/// Reduced-order paper-on-ground contact. Drag is quadratic in relative air speed;
/// static friction keeps sheltered sheets still and kinetic friction stops sliding.
/// Coefficients are art-directed scene units, not measured material properties.
enum AutumnGroundContact {
    static let flatTilt = 1.28
    static func integrate(_ leaf: inout AutumnBranchLeaf, wind: Double, dt: Double, neighbours: Double = 0) {
        leaf.contactTime += dt
        let grain = AutumnCanopy.variation(leaf.id + 1200)
        let curl = AutumnCanopy.variation(leaf.id + 1400)
        // The lee of the trunk and individual paper curl change exposure smoothly.
        let lee = 350 + (wind >= 0 ? 40.0 : -40.0)
        let trunkShelter = 1 - 0.48 * exp(-pow((leaf.x - lee) / 90, 2))
        // Overlap shelter saturates: a deeper carpet still has exposed top sheets.
        let cover = 2 * (1 - exp(-max(0, neighbours) / 2))
        let exposure = (0.55 + 0.45 * curl) * trunkShelter / (1 + 0.30 * cover)
        let airSpeed = wind * 155 * exposure
        let relative = airSpeed - leaf.vx
        let mass = 0.7 + leaf.size * 0.6
        let acceleration = 0.009 * relative * abs(relative) / mass
        let staticFriction = (26 + 65 * grain) * (1 + 0.18 * cover)
        let kineticFriction = staticFriction * 0.62
        let wasStill = abs(leaf.vx) < 0.08
        if wasStill && abs(acceleration) <= staticFriction {
            leaf.vx = 0
        } else {
            let direction = leaf.vx == 0 ? (acceleration >= 0 ? 1.0 : -1.0) : (leaf.vx > 0 ? 1.0 : -1.0)
            // Surface drag dissipates a shuffle rather than letting a caught sheet
            // accelerate into a long, smooth slide across the whole ground.
            let next = leaf.vx + (acceleration - direction * kineticFriction - 10 * leaf.vx) * dt
            leaf.vx = next * direction < 0 && abs(acceleration) < staticFriction ? 0 : next
        }
        leaf.x += leaf.vx * dt
        // Off-centre pressure pivots a moving sheet; no rotation in still air.
        let torque = leaf.vx * (curl - 0.5) * 0.10
        leaf.omega += (torque - 5 * leaf.omega) * dt
        leaf.angle += leaf.omega * dt
        leaf.turn += (0 - leaf.turn) * (1 - exp(-3 * dt))
        leaf.groundTilt += (flatTilt - leaf.groundTilt) * (1 - exp(-3 * dt))
        leaf.y = leaf.groundLevel
        leaf.vy = 0
        if leaf.contactTime >= 2 && abs(leaf.vx) < 0.08 && abs(leaf.omega) < 0.01 {
            leaf.phase = .settled
            leaf.vx = 0
            leaf.omega = 0
        } else {
            leaf.phase = .landed
        }
    }
}

struct AutumnBranchFrame: Equatable {
    var time = 0.0
    var angle = 0.0
    var angularVelocity = 0.0
    var tipAngle = 0.0
    var tipVelocity = 0.0
    var leaves = (0..<6).map { AutumnBranchLeaf(id: $0) }
    var isFullTree = false
    var limbAngles: [Double] = []
    var limbVelocities: [Double] = []
    var canopyCurves: [AutumnCanopy.Curve] = []
}

/// Fixed-step tree and leaf dynamics. The six-leaf fixture shares the same solver.
/// Reopening replays the same plan; display cadence cannot alter integration.
final class AutumnBranchSimulation {
    static let step = 1.0 / 120
    let plan: AutumnBranchPlan
    private(set) var frame = AutumnBranchFrame()
    private var tick = 0
    private let reference: LeafGravityLabConfiguration
    private var groundNeighbours: [Double] = []
    private var groundPositions: [SIMD2<Double>] = []
    private var windIndices: [Int] = []
    // A conservative bound for every attached point under any branch rotation.
    private static let canopyReach = AutumnCanopy.limbs.reduce(0.0) { $0 + $1.length + abs($1.bend) }
        + AutumnCanopy.shoots.reduce(0.0) { max($0, $1.reach + 200 * $1.size) }

    init(plan: AutumnBranchPlan, reference: LeafGravityLabConfiguration) {
        self.plan = plan
        self.reference = reference
        if plan.isFullTree { frame = AutumnCanopy.frame() }
        updateAttached(dt: Self.step)
    }

    func sample(at elapsed: Double) -> AutumnBranchFrame {
        let target = Int((min(max(elapsed, 0), plan.duration) / Self.step).rounded(.down))
        if target < tick {
            tick = 0
            frame = plan.isFullTree ? AutumnCanopy.frame() : AutumnBranchFrame()
            groundNeighbours = []
            groundPositions = []
            windIndices = []
            updateAttached(dt: Self.step)
        }
        while tick < target {
            integrate()
            tick += 1
        }
        return frame
    }

    static func joints(_ frame: AutumnBranchFrame) -> [(x: Double, y: Double)] {
        let root = (x: -35.0, y: 390.0)
        let baseAngle = 0.23 + frame.angle
        let elbow = (x: root.x + 355 * cos(baseAngle), y: root.y + 355 * sin(baseAngle))
        let tip = (x: elbow.x + 290 * cos(baseAngle + frame.tipAngle + 0.12),
                   y: elbow.y + 290 * sin(baseAngle + frame.tipAngle + 0.12))
        return [root, elbow, tip]
    }

    /// The same quadratic centerline supplies rendering, twig roots and leaf poses.
    static func twigRoot(id: Int, frame: AutumnBranchFrame) -> (x: Double, y: Double) {
        if frame.isFullTree {
            let root = AutumnCanopy.joint(id: id, curves: frame.canopyCurves).root
            return (root.x, root.y)
        }
        let points = joints(frame)
        let t = Double(id % 3 + 1) / 3.4
        let segment = id < 3 ? 0 : 1
        let a = points[segment], b = points[segment + 1]
        let c = (x: a.x + (segment == 0 ? 155 : 150),
                 y: a.y + (segment == 0 ? -45 : 12))
        return (pow(1 - t, 2) * a.x + 2 * (1 - t) * t * c.x + t * t * b.x,
                pow(1 - t, 2) * a.y + 2 * (1 - t) * t * c.y + t * t * b.y)
    }

    static func attachment(id: Int, frame: AutumnBranchFrame) -> (x: Double, y: Double, angle: Double) {
        if frame.isFullTree {
            let joint = AutumnCanopy.joint(id: id, curves: frame.canopyCurves)
            let shoot = AutumnCanopy.shoots[id]
            let offset = AutumnBranchLeafGeometry.stemOffset(id: shoot.artwork, angle: joint.angle, turn: 0)
            return (joint.tip.x - offset.x * shoot.size, joint.tip.y - offset.y * shoot.size, joint.angle)
        }
        let base = twigRoot(id: id, frame: frame)
        let up = id % 2 == 0
        return (base.x + (up ? 8 : -12), base.y + (up ? 64 : -62), up ? -0.4 : 2.4)
    }

    /// A branch-space joint, independent of leaf flutter. Rendering and simulation
    /// both use it; the leaf center moves around its stem, not the image center.
    static func twigTip(id: Int, frame: AutumnBranchFrame) -> (x: Double, y: Double) {
        if frame.isFullTree {
            let tip = AutumnCanopy.joint(id: id, curves: frame.canopyCurves).tip
            return (tip.x, tip.y)
        }
        let pose = attachment(id: id, frame: frame)
        let stem = AutumnBranchLeafGeometry.stemOffset(id: id,
            angle: pose.angle + frame.angle, turn: 0)
        return (pose.x + stem.x, pose.y + stem.y)
    }

    private func updateAttached(dt: Double) {
        for id in frame.leaves.indices where frame.leaves[id].phase == .attached {
            let pose = Self.attachment(id: id, frame: frame)
            let old = frame.leaves[id]
            let localAir = plan.air(at: SIMD2(pose.x, pose.y), seconds: frame.time, indices: windIndices)
            let flutter = localAir.x
                * 0.13 * sin(frame.time * 3.1 + Double(id))
            let angle = pose.angle + (frame.isFullTree ? 0 : frame.angle) + flutter
            frame.leaves[id].omega = frame.time == 0 ? 0 : (angle - old.angle) / dt
            frame.leaves[id].angle = angle
            let turn = 0.30 * sin(frame.time * 1.7 + Double(id)) * localAir.x
            frame.leaves[id].turn = turn
            let joint = Self.twigTip(id: id, frame: frame)
            let offset = AutumnBranchLeafGeometry.stemOffset(id: old.artwork, angle: angle, turn: turn)
            let x = joint.x - offset.x * old.size, y = joint.y - offset.y * old.size
            frame.leaves[id].x = x
            frame.leaves[id].y = y
            frame.leaves[id].vx = frame.time == 0 ? 0 : (x - old.x) / dt
            frame.leaves[id].vy = frame.time == 0 ? 0 : (y - old.y) / dt
        }
    }

    private func integrate() {
        let dt = Self.step
        frame.time = Double(tick + 1) * dt
        let tuning = plan.tuning
        if frame.isFullTree {
            let radius = frame.leaves.reduce(Self.canopyReach) { max($0, hypot($1.x - 350, $1.y)) }
            windIndices = plan.gusts.indices.filter { index in
                let moment = plan.gusts[index], passage = plan.windPassages[index]
                let maximumDelay = (hypot(passage.origin.x - 350, passage.origin.y) + radius) / passage.travelSpeed
                return frame.time > moment.startTime && frame.time < moment.endTime + maximumDelay
            }
        }
        let air = plan.wind(at: 290, seconds: frame.time)
        let stiffness = 3.8 / tuning.flexibility
        frame.angularVelocity += (air * 0.14 - stiffness * frame.angle
            - 2 * sqrt(stiffness) * tuning.damping * frame.angularVelocity) * dt
        frame.angle += frame.angularVelocity * dt
        frame.tipVelocity += (air * 0.24 - stiffness * 0.75 * frame.tipAngle
            - 2 * sqrt(stiffness * 0.75) * tuning.damping * frame.tipVelocity) * dt
        frame.tipAngle += frame.tipVelocity * dt
        if frame.isFullTree {
            for index in AutumnCanopy.limbs.indices {
                let limb = AutumnCanopy.limbs[index]
                let position = frame.canopyCurves[index].end
                let localAir = plan.air(at: position, seconds: frame.time, indices: windIndices)
                let k = (6 + Double(index % 5) * 0.8) / tuning.flexibility
                let crossLoad = localAir.x * sin(limb.angle) - localAir.y * cos(limb.angle)
                let load = crossLoad * (limb.depth == 0 ? 0.045 : 0.09 + Double(limb.depth) * 0.06)
                frame.limbVelocities[index] += (-load - k * frame.limbAngles[index]
                    - 2 * sqrt(k) * tuning.damping * frame.limbVelocities[index]) * dt
                frame.limbAngles[index] += frame.limbVelocities[index] * dt
            }
            frame.canopyCurves = AutumnCanopy.curves(angles: frame.limbAngles)
        }
        updateAttached(dt: dt)
        guard let drag = reference.stillAirDrag, let flutter = reference.passiveFlutter else { return }
        let resting = frame.leaves.filter { $0.phase == .landed || $0.phase == .settled }
        let canopyOpenness = Double(frame.leaves.filter { $0.phase != .attached }.count)
            / Double(frame.leaves.count)
        // Shelter changes slowly relative to contact integration. Sample it at a
        // fixed 10 Hz, and reuse it indefinitely while the carpet is stationary.
        if frame.isFullTree && (tick % 12 == 0 || groundNeighbours.isEmpty) {
            let positions = resting.map { SIMD2($0.x, $0.groundLevel) }
            if positions != groundPositions || groundNeighbours.isEmpty {
                groundNeighbours = Array(repeating: 0, count: frame.leaves.count)
                for leaf in resting {
                    groundNeighbours[leaf.id] = resting.reduce(0.0) { weight, other in
                        guard other.id != leaf.id else { return weight }
                        let distance = hypot(other.x - leaf.x, (other.groundLevel - leaf.groundLevel) * 1.5)
                        return weight + exp(-pow(distance / 42, 2))
                    }
                }
                groundPositions = positions
            }
        }
        for id in frame.leaves.indices {
            var leaf = frame.leaves[id]
            let localAir = plan.air(at: SIMD2(leaf.x, max(0, leaf.y)), seconds: frame.time, indices: windIndices)
            let wind = localAir.x
            if leaf.phase == .attached {
                let threshold = (0.32 + Double(frame.isFullTree ? id % 4 : id) * 0.055
                    + Double(plan.seed % 17) * 0.002) / tuning.releaseSensitivity
                let shouldRelease = frame.isFullTree
                    ? frame.time >= plan.leafReleases[id].startTime
                    : [1, 3, 5].contains(id) && hypot(localAir.x, localAir.y) > threshold
                if shouldRelease {
                    leaf.phase = .falling
                    leaf.releasedAt = frame.time
                }
            } else if leaf.phase == .falling {
                let shelter = min(1, max(frame.isFullTree ? 0.20 : 0, (leaf.y - leaf.groundLevel) / 90))
                let sample = LeafAerodynamics.sample(
                    // Canopy shelter limits horizontal transport while retaining
                    // the same gust's direction and spatial arrival.
                    airVelocity: .init(x: wind * drag.scenePointsPerMeter * shelter * (frame.isFullTree ? 0.22 : 1),
                        y: localAir.y * drag.scenePointsPerMeter * shelter * 0.22),
                    leafVelocity: .init(x: leaf.vx, y: leaf.vy), angularVelocity: leaf.omega,
                    rotation: leaf.angle, position: .init(x: leaf.x, y: leaf.y),
                    leafSize: .init(x: 65, y: 76), centerOfMass: .init(x: 0, y: 0),
                    drag: drag, flutter: flutter)
                leaf.vx += sample.forceNewtons.x / reference.mass * drag.scenePointsPerMeter * dt
                leaf.vy += (reference.gravity.y * drag.scenePointsPerMeter
                    + sample.forceNewtons.y / reference.mass * drag.scenePointsPerMeter) * dt
                let armX = (sample.centerOfPressure.x - sample.centerOfMass.x) / drag.scenePointsPerMeter
                let armY = (sample.centerOfPressure.y - sample.centerOfMass.y) / drag.scenePointsPerMeter
                let inertia = reference.mass * pow(65 / drag.scenePointsPerMeter, 2) / 12
                let torque = armX * sample.forceNewtons.y - armY * sample.forceNewtons.x
                    + sample.resistanceTorqueNewtonMeters
                leaf.omega += torque / inertia * dt
                leaf.omega = min(7, max(-7, leaf.omega))
                leaf.angle += leaf.omega * dt
                leaf.x += leaf.vx * dt
                leaf.y += leaf.vy * dt
                leaf.turn += (0.85 * sin(leaf.angle) - leaf.turn) * (1 - exp(-3 * dt))
                if leaf.y <= leaf.groundLevel {
                    leaf.y = leaf.groundLevel
                    leaf.vy = 0
                    leaf.phase = .landed
                }
            } else if frame.isFullTree && (leaf.phase == .landed || leaf.phase == .settled) {
                let neighbours = groundNeighbours[id]
                AutumnGroundContact.integrate(&leaf, wind: wind * (1.7 + 0.5 * canopyOpenness),
                    dt: dt, neighbours: neighbours)
            } else if leaf.phase == .landed {
                leaf.contactTime += dt
                leaf.vx *= exp(-4.5 * dt)
                leaf.omega *= exp(-5 * dt)
                leaf.x += leaf.vx * dt
                leaf.angle += leaf.omega * dt
                leaf.turn += (0 - leaf.turn) * (1 - exp(-3 * dt))
                leaf.groundTilt += (1.28 - leaf.groundTilt) * (1 - exp(-3 * dt))
                if leaf.contactTime >= 2 {
                    leaf.phase = .settled
                    leaf.vx = 0
                    leaf.omega = 0
                }
            }
            frame.leaves[id] = leaf
        }
    }
}
