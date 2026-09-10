import Foundation
import simd

struct AutumnBirdTuning: Codable, Equatable {
    var speed = 1.0
    var wingbeat = 1.55
    var depth = 1.0
    var windResponse = 1.0
    var perchSeconds = 6.0
}

struct AutumnBirdStudy: Codable, Equatable {
    var tuning = AutumnBirdTuning()
    var flight: AutumnOrigamiFlight?
}

/// The tree lives at z = 0. Positive z recedes; the camera is at z = -focalLength.
/// Project every vertex, not a sprite scale. The same camera handles route and mesh.
struct AutumnBirdCamera {
    let center: SIMD2<Double>
    static let focalLength = 1100.0

    func magnification(at z: Double) -> Double {
        Self.focalLength / max(100, Self.focalLength + z)
    }

    func project(_ p: SIMD3<Double>) -> SIMD2<Double> {
        center + (SIMD2(p.x, p.y) - center) * magnification(at: p.z)
    }

    func unproject(_ p: SIMD2<Double>, z: Double) -> SIMD3<Double> {
        let xy = center + (p - center) / magnification(at: z)
        return SIMD3(xy.x, xy.y, z)
    }
}

struct AutumnBirdStage {
    let camera: AutumnBirdCamera
    let left: Double
    let right: Double
    let sun: SIMD2<Double>
}

struct AutumnBirdPose: Equatable {
    enum Phase: String { case approaching, perched, departing }
    let position: SIMD3<Double>
    let yaw: Double
    let pitch: Double
    let bank: Double
    let wingAngle: Double
    let tipFold: Double
    let phase: Phase
    var legFold: Double = 0

    func transform(_ vertex: SIMD3<Double>) -> SIMD3<Double> {
        let roll = simd_quatd(angle: bank, axis: SIMD3(1, 0, 0))
        let lift = simd_quatd(angle: pitch, axis: SIMD3(0, 0, 1))
        let turn = simd_quatd(angle: yaw, axis: SIMD3(0, 1, 0))
        return position + turn.act(lift.act(roll.act(vertex)))
    }
}

/// A finite automatic or development event on the existing transport. Each visit
/// captures its tuning so live controls cannot teleport an airborne bird.
struct AutumnOrigamiFlight: Codable, Equatable {
    let startTime: Double
    let seed: UInt64
    let tuning: AutumnBirdTuning
    static let perchLimb = 7
    static let perchFraction = 0.64

    private var speed: Double { min(1.5, max(0.5, tuning.speed)) }
    var approachDuration: Double { 8 / speed }
    var perchDuration: Double { min(12, max(3, tuning.perchSeconds)) }
    var departureDuration: Double { 13 / speed }
    var duration: Double { approachDuration + perchDuration + departureDuration }

    var moment: StoryMoment {
        StoryMoment(id: .init(rawValue: "autumn.origami.\(seed).\(startTime)"), startTime: startTime,
            duration: duration, intensity: 1, randomSeed: seed, quantization: .none,
            visualCue: .init(effect: .init(rawValue: "autumn.origami.flight")), audioCue: nil)
    }

    static func perch(in frame: AutumnBranchFrame) -> SIMD3<Double> {
        let curves = frame.canopyCurves.isEmpty ? AutumnCanopy.frame().canopyCurves : frame.canopyCurves
        let curve = curves[perchLimb]
        let p = curve.point(perchFraction)
        let tangent = simd_normalize(curve.tangent(perchFraction))
        let limb = AutumnCanopy.limbs[perchLimb]
        let halfWidth = (limb.tipWidth + (limb.width - limb.tipWidth)
            * pow(1 - perchFraction, 1.15)) * 0.5
        let top = p + SIMD2(-tangent.y, tangent.x) * halfWidth
        return SIMD3(top.x, top.y, 0)
    }

    static func smooth(_ raw: Double) -> Double {
        let t = min(1, max(0, raw))
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    func sample(at elapsed: Double, frame: AutumnBranchFrame, stage: AutumnBirdStage,
                wind: SIMD2<Double>, reduceMotion: Bool = false) -> AutumnBirdPose? {
        let t = elapsed - startTime
        guard t.isFinite, t >= 0, t < duration else { return nil }
        let anchor = Self.perch(in: frame)
        let arrival = approachDuration
        let departure = arrival + perchDuration
        let phase: AutumnBirdPose.Phase = t < arrival ? .approaching : t < departure ? .perched : .departing
        // No continuous flight, flutter, or branch following under Reduce Motion.
        if reduceMotion {
            guard phase == .perched else { return nil }
            return AutumnBirdPose(position: Self.perch(in: AutumnCanopy.frame()), yaw: 0.32,
                pitch: 0, bank: 0, wingAngle: 0.78, tipFold: 0.12, phase: .perched)
        }
        let depth = min(1.5, max(0, tuning.depth))
        let variation = Double(seed % 101) / 100
        func route(_ time: Double) -> SIMD3<Double> {
            if time < arrival {
                let u = min(1, max(0, time / arrival))
                // Glide behind the canopy, bank into the near plane, then flare
                // toward the receiver. Shared tangents preserve velocity at joins;
                // only the landing endpoint has zero velocity. No global ease-in.
                let times = [0.0, 0.45, 0.76, 1.0]
                let points = [
                    stage.camera.unproject(SIMD2(stage.left - 150, anchor.y + 270), z: 650 * depth),
                    stage.camera.unproject(SIMD2(anchor.x - 215, anchor.y + 180 + 25 * variation), z: 280 * depth),
                    stage.camera.unproject(SIMD2(anchor.x - 72, anchor.y + 78), z: -105 * depth),
                    anchor]
                let segment = u < times[1] ? 0 : u < times[2] ? 1 : 2
                let span = times[segment + 1] - times[segment]
                let s = (u - times[segment]) / span
                func tangent(_ index: Int) -> SIMD3<Double> {
                    if index == 3 { return .zero }
                    if index == 0 { return (points[1] - points[0]) / times[1] }
                    return (points[index + 1] - points[index - 1]) / (times[index + 1] - times[index - 1])
                }
                let p0 = points[segment], p1 = points[segment + 1]
                let m0 = tangent(segment) * span, m1 = tangent(segment + 1) * span
                return p0 * (2*s*s*s - 3*s*s + 1) + m0 * (s*s*s - 2*s*s + s)
                    + p1 * (-2*s*s*s + 3*s*s) + m1 * (s*s*s - s*s)
            }
            if time < departure { return anchor }
            let u = min(1, max(0, (time - departure) / departureDuration))
            // A broad arc around the sun's screen position, behind the canopy.
            // The sun is at atmospheric distance: the bird never flies behind it.
            let points = [anchor,
                stage.camera.unproject(stage.sun + SIMD2(-110, 235), z: 230 * depth),
                stage.camera.unproject(stage.sun + SIMD2(115, 210), z: 510 * depth),
                stage.camera.unproject(SIMD2(stage.right + 200, stage.sun.y + 120), z: 820 * depth)]
            let segment = min(2, Int(u * 3))
            let s = u * 3 - Double(segment)
            let p0 = points[segment], p1 = points[segment + 1]
            let m0 = segment == 0 ? SIMD3<Double>.zero : (p1 - points[segment - 1]) * 0.5
            let m1 = segment == 2 ? p1 - p0 : (points[segment + 2] - p0) * 0.5
            return p0 * (2*s*s*s - 3*s*s + 1) + m0 * (s*s*s - 2*s*s + s)
                + p1 * (-2*s*s*s + 3*s*s) + m1 * (s*s*s - s*s)
        }
        let flightBlend = phase == .approaching ? 1 - Self.smooth((t / arrival - 0.68) / 0.32)
            : phase == .departing ? Self.smooth((t - departure) / 1.6) : 0
        let velocity = route(t + 0.025) - route(t - 0.025)
        let yaw = simd_length(velocity) > 0.001 ? atan2(-velocity.z, velocity.x) : 0.32
        let pitch = atan2(velocity.y, max(0.001, hypot(velocity.x, velocity.z)))
        let hz = min(2.5, max(0.8, tuning.wingbeat))
        let cycle = t * hz * 2 * Double.pi
        // Unequal up/down stroke and a delayed outer fold, separated by glides.
        let glide = Self.smooth((sin(t * 1.15 + variation * 2) - 0.10) / 0.65)
        let flap = sin(cycle) + 0.18 * sin(2 * cycle + 0.6)
        let flyingWing = 0.27 + 0.63 * flap * (1 - 0.78 * glide)
        let response = min(2, max(0, tuning.windResponse))
        let drift = SIMD3(wind.x * 15, wind.y * 12, wind.x * 6) * response * flightBlend
        let bob = SIMD3(0, sin(cycle - 0.8) * 1.5, 0) * flightBlend
        if phase == .approaching {
            let u = t / arrival
            let braking = Self.smooth((u - 0.67) / 0.26)
            let alignment = Self.smooth((u - 0.80) / 0.20)
            // Curvature-driven bank: lateral acceleration / scene gravity.
            // Sample over a short window to soften the authored route's joins.
            let h = 0.14 / speed
            let v = (route(t + h) - route(t - h)) / (2 * h)
            let a = (route(t + h) - 2 * route(t) + route(t - h)) / (h * h)
            let lateral = (v.x * a.z - v.z * a.x) / max(1, hypot(v.x, v.z))
            let turnBank = min(0.42, max(-0.42, atan(lateral / 300)))
            let flare = pow(sin(.pi * Self.smooth((u - 0.62) / 0.38)), 2)
            return AutumnBirdPose(position: route(t) + drift + bob,
                yaw: yaw * (1 - alignment) + 0.32 * alignment,
                pitch: min(0.25, max(-0.30, pitch)) * (1 - alignment) + 0.32 * flare,
                bank: (turnBank + wind.x * response * 0.10) * flightBlend,
                wingAngle: flyingWing * (1 - braking) + 0.10 * braking,
                tipFold: 0.12 + 0.18 * sin(cycle - 0.6) * (1 - braking),
                phase: phase, legFold: -1.15 * (1 - Self.smooth((u - 0.70) / 0.24)))
        }
        if phase == .perched && t < arrival + 1.1 {
            let settle = (t - arrival) / 1.1
            // Rotate around the planted feet, not a positional bounce off the branch.
            return AutumnBirdPose(position: anchor, yaw: 0.32,
                pitch: -0.045 * pow(sin(.pi * settle), 2), bank: 0,
                wingAngle: 0.10 + 0.68 * Self.smooth(settle), tipFold: 0.12, phase: phase)
        }
        // Approved departure is deliberately unchanged by the entrance choreography.
        return AutumnBirdPose(position: route(t) + drift + bob,
            yaw: 0.32 + (yaw - 0.32) * flightBlend,
            pitch: min(0.40, max(-0.35, pitch)) * flightBlend,
            bank: (0.09 * sin(t * 0.8) + wind.x * response * 0.16) * flightBlend,
            wingAngle: 0.78 + (flyingWing - 0.78) * flightBlend,
            tipFold: 0.12 + 0.18 * sin(cycle - 0.6) * flightBlend, phase: phase)
    }
}

/// Faceted paper, not a sprite sheet. Panels remain rigid; wing hinges and the
/// outer crease articulate. Each triangle keeps its own paper-local texture basis.
enum AutumnOrigamiMesh {
    // Split panels at the tree plane; centroid-only sorting would pop an entire
    // wing in front of a branch when just its tip crosses the plane.
    static func clipped(_ triangle: [SIMD3<Double>], behindTree: Bool) -> [SIMD3<Double>] {
        guard var previous = triangle.last else { return [] }
        func inside(_ p: SIMD3<Double>) -> Bool { behindTree ? p.z > 0 : p.z <= 0 }
        var result: [SIMD3<Double>] = []
        for current in triangle {
            if inside(previous) != inside(current) {
                let t = previous.z / (previous.z - current.z)
                result.append(previous + (current - previous) * t)
            }
            if inside(current) { result.append(current) }
            previous = current
        }
        return result
    }

    struct Face {
        let a: SIMD3<Double>
        let b: SIMD3<Double>
        let c: SIMD3<Double>
        let ink: Double
    }

    static func faces(wing: Double, tipFold: Double, legFold: Double = 0) -> [Face] {
        var result: [Face] = []
        func face(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, _ ink: Double = 1) {
            result.append(Face(a: a, b: b, c: c, ink: ink))
        }
        let nose = SIMD3(19.0, 29, 0), tail = SIMD3(-28.0, 23, 0)
        let ridge = SIMD3(-3.0, 40, 0), keel = SIMD3(-2.0, 13, 0)
        for side in [-1.0, 1.0] {
            let flank = SIMD3(-4.0, 25, 8 * side)
            face(nose, ridge, flank, 1.0)
            face(ridge, tail, flank, 0.97)
            face(tail, keel, flank, 0.88)
            face(keel, nose, flank, 0.93)
            // Reverse-folded neck and the tiny downturned beak.
            let neckBase = SIMD3(10.0, 25, 3.5 * side)
            let neckFront = SIMD3(22.0, 29, 2.5 * side)
            let crown = SIMD3(33.0, 67, 1.0 * side)
            let throat = SIMD3(26.0, 58, 2.0 * side)
            face(neckBase, crown, throat, 0.97)
            face(neckBase, neckFront, crown, 1.02)
            face(crown, SIMD3(50.0, 53, 0), throat, 0.93)
            // The other narrowed point of the bird base becomes the tail.
            face(tail, SIMD3(-53.0, 62, 0), SIMD3(-12.0, 29, 4 * side), 0.96)
            // Rigid folded supports tuck at the hip in flight and reach for the
            // receiver during braking. At zero fold the feet end exactly at y = 0.
            func leg(_ p: SIMD3<Double>) -> SIMD3<Double> {
                let hip = SIMD3(-1.0, 15.5, side * 2)
                return hip + simd_quatd(angle: legFold, axis: SIMD3(0, 0, 1)).act(p - hip)
            }
            face(leg(SIMD3(-5.0, 16, side*2)), leg(SIMD3(0.0, 0, side*2)),
                 leg(SIMD3(3.0, 15, side*2)), 0.83)
            face(leg(SIMD3(0.0, 0, side*2)), leg(SIMD3(10.0, 0, side*2)),
                 leg(SIMD3(2.0, 3, side*2)), 0.86)
            let hinge = SIMD3(-2.0, 29, side * 5)
            func folded(_ p: SIMD3<Double>, outer: Bool = false) -> SIMD3<Double> {
                let root = simd_quatd(angle: -side * wing, axis: SIMD3(1, 0, 0))
                var local = p
                if outer {
                    let crease = SIMD3(-12.0, 2, side * 34)
                    local = crease + simd_quatd(angle: -side * tipFold, axis: SIMD3(1, 0, 0)).act(p - crease)
                }
                return hinge + root.act(local)
            }
            let front = folded(SIMD3(18.0, 0, 0))
            let rear = folded(SIMD3(-24.0, 0, 0))
            let creaseFront = folded(SIMD3(8.0, 2, side*34))
            let creaseRear = folded(SIMD3(-20.0, 2, side*34))
            let tip = folded(SIMD3(-31.0, 0, side*87), outer: true)
            face(front, creaseFront, rear, 1.02)
            face(creaseFront, creaseRear, rear, 0.94)
            face(creaseFront, tip, creaseRear, 1.0)
        }
        return result
    }
}
