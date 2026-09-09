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

struct AutumnBranchRecord: Codable, Equatable {
    var tuning = AutumnBranchTuning.standard
    var manualGusts: [Double] = []
}

/// Story percentages place events. Physical motion always runs in seconds.
struct AutumnBranchPlan: Equatable {
    let duration: Double
    let seed: UInt64
    let tuning: AutumnBranchTuning
    let gusts: [StoryMoment]

    init(duration: Double, seed: UInt64, tuning: AutumnBranchTuning, manualGusts: [Double] = []) {
        self.duration = duration
        self.seed = seed
        self.tuning = tuning
        let scheduled = [0.08, 0.40, 0.72].map { $0 * duration }
        gusts = (scheduled + manualGusts).enumerated().map { index, onset in
            StoryMoment(id: .init(rawValue: "autumn.breeze.\(index)"),
                startTime: onset, duration: tuning.gustDuration, intensity: tuning.windStrength,
                randomSeed: seed, quantization: .none,
                visualCue: .init(effect: .init(rawValue: "autumn.wind")),
                audioCue: .init(assetID: "autumn-gust-intent", bus: .atmosphere, gain: 0.2))
        }
    }

    func hasSameDynamics(as other: Self) -> Bool {
        duration == other.duration && seed == other.seed && gusts == other.gusts
            && tuning.flexibility == other.tuning.flexibility
            && tuning.damping == other.tuning.damping
            && tuning.releaseSensitivity == other.tuning.releaseSensitivity
    }

    /// Named sound banks are Autumn art direction, not reversed splash events.
    func poolWeights(at seconds: Double) -> PerformancePoolBlend {
        PerformancePoolBlend.sample(progress: seconds / max(1, duration))
    }

    func wind(at x: Double, seconds: Double) -> Double {
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

struct AutumnBranchLeaf: Equatable {
    enum Phase: String { case attached, falling, landed, settled }
    let id: Int
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
}

struct AutumnBranchFrame: Equatable {
    var time = 0.0
    var angle = 0.0
    var angularVelocity = 0.0
    var tipAngle = 0.0
    var tipVelocity = 0.0
    var leaves = (0..<6).map { AutumnBranchLeaf(id: $0) }
}

/// Fixed-step replay of a bounded six-leaf study. No independent wall clock.
/// Reopening replays the same plan; display cadence cannot alter integration.
final class AutumnBranchSimulation {
    static let step = 1.0 / 120
    let plan: AutumnBranchPlan
    private(set) var frame = AutumnBranchFrame()
    private var tick = 0
    private let reference: LeafGravityLabConfiguration

    init(plan: AutumnBranchPlan, reference: LeafGravityLabConfiguration) {
        self.plan = plan
        self.reference = reference
        updateAttached(dt: Self.step)
    }

    func sample(at elapsed: Double) -> AutumnBranchFrame {
        let target = Int((min(max(elapsed, 0), plan.duration) / Self.step).rounded(.down))
        if target < tick {
            tick = 0
            frame = AutumnBranchFrame()
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
        let base = twigRoot(id: id, frame: frame)
        let up = id % 2 == 0
        return (base.x + (up ? 8 : -12), base.y + (up ? 64 : -62), up ? -0.4 : 2.4)
    }

    private func updateAttached(dt: Double) {
        for id in frame.leaves.indices where frame.leaves[id].phase == .attached {
            let pose = Self.attachment(id: id, frame: frame)
            let old = frame.leaves[id]
            frame.leaves[id].x = pose.x
            frame.leaves[id].y = pose.y
            frame.leaves[id].vx = frame.time == 0 ? 0 : (pose.x - old.x) / dt
            frame.leaves[id].vy = frame.time == 0 ? 0 : (pose.y - old.y) / dt
            let flutter = plan.wind(at: pose.x, seconds: frame.time)
                * 0.13 * sin(frame.time * 3.1 + Double(id))
            let angle = pose.angle + frame.angle + flutter
            frame.leaves[id].omega = frame.time == 0 ? 0 : (angle - old.angle) / dt
            frame.leaves[id].angle = angle
            frame.leaves[id].turn = 0.30 * sin(frame.time * 1.7 + Double(id)) * plan.wind(at: pose.x, seconds: frame.time)
        }
    }

    private func integrate() {
        let dt = Self.step
        frame.time = Double(tick + 1) * dt
        let tuning = plan.tuning
        let air = plan.wind(at: 290, seconds: frame.time)
        let stiffness = 3.8 / tuning.flexibility
        frame.angularVelocity += (air * 0.14 - stiffness * frame.angle
            - 2 * sqrt(stiffness) * tuning.damping * frame.angularVelocity) * dt
        frame.angle += frame.angularVelocity * dt
        frame.tipVelocity += (air * 0.24 - stiffness * 0.75 * frame.tipAngle
            - 2 * sqrt(stiffness * 0.75) * tuning.damping * frame.tipVelocity) * dt
        frame.tipAngle += frame.tipVelocity * dt
        updateAttached(dt: dt)
        guard let drag = reference.stillAirDrag, let flutter = reference.passiveFlutter else { return }
        for id in frame.leaves.indices {
            var leaf = frame.leaves[id]
            let wind = plan.wind(at: leaf.x, seconds: frame.time)
            if leaf.phase == .attached {
                let threshold = (0.32 + Double(id) * 0.055
                    + Double(plan.seed % 17) * 0.002) / tuning.releaseSensitivity
                if [1, 3, 5].contains(id), wind > threshold {
                    leaf.phase = .falling
                    leaf.releasedAt = frame.time
                }
            } else if leaf.phase == .falling {
                let shelter = min(1, max(0, leaf.y / 90))
                let sample = LeafAerodynamics.sample(
                    airVelocity: .init(x: wind * drag.scenePointsPerMeter * shelter, y: 0),
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
                if leaf.y <= 16 {
                    leaf.y = 16
                    leaf.vy = 0
                    leaf.phase = .landed
                }
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
