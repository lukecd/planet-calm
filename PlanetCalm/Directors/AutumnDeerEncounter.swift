import Foundation
import simd

struct AutumnDeerTuning: Codable, Equatable, Sendable {
  var size = 1.0
  var speed = 1.0
  var settlingSeconds = 8.0
  var restingPosition = 0.65
}

struct AutumnDeerStudy: Codable, Equatable, Sendable {
  var tuning = AutumnDeerTuning()
  var encounter: AutumnDeerEncounter?
}

/// One guaranteed StoryMoment. Stage percentages schedule the entrance; the
/// articulation is measured in real seconds and samples the existing transport.
struct AutumnDeerEncounter: Codable, Equatable, Sendable {
  let startTime: Double
  let tuning: AutumnDeerTuning
  var walkDuration: Double { 18 / min(1.3, max(0.7, tuning.speed)) }
  var standingDuration: Double { 3.5 }
  var settlingDuration: Double { min(12, max(6, tuning.settlingSeconds)) }
  var duration: Double { walkDuration + standingDuration + settlingDuration }
  var restingTime: Double { startTime + duration }

  static func scheduled(duration: Double, tuning: AutumnDeerTuning = .init()) -> Self {
    let prototype = Self(startTime: 0, tuning: tuning)
    let hold = min(45, max(8, duration * 0.07))
    return Self(startTime: max(0, duration - hold - prototype.duration), tuning: tuning)
  }

  var moment: StoryMoment {
    StoryMoment(
      id: .init(rawValue: "autumn.deer.ending"), startTime: startTime,
      duration: duration, intensity: 1, randomSeed: 0, quantization: .none,
      visualCue: .init(effect: .init(rawValue: "autumn.deer.rest")), audioCue: nil)
  }

  static func smooth(_ value: Double) -> Double { AutumnOrigamiFlight.smooth(value) }

  struct Stage {
    let left: Double
    let right: Double
    var width: Double { right - left }
  }

  struct Hoof: Equatable {
    let point: SIMD3<Double>
    let planted: Bool
  }
  struct Footprint {
    let point: SIMD3<Double>
    let age: Double
  }

  struct Pose {
    enum Phase: String { case walking, listening, kneeling, resting }
    let root: Double
    let shoulder: Double
    let hip: Double
    let frontFold: Double
    let hindFold: Double
    let headAngle: Double
    let earAngle: Double
    let eyesClosed: Bool
    let hooves: [Hoof]
    let phase: Phase
    let size: Double
    let opacity: Double
    var footprints: [Footprint] = []
    let ground = -24.0
    var settled: Double { min(frontFold, hindFold) }
  }

  /// Nonlinear deceleration has zero terminal velocity. Hoof anchors evaluate
  /// this same root curve at touchdown, never integrate an independent speed.
  func root(at time: Double, stage: Stage) -> Double {
    let size = min(1.2, max(0.75, tuning.size))
    let rest = stage.left + stage.width * min(0.76, max(0.56, tuning.restingPosition))
    let entry = stage.right + 150 * size
    let u = min(1, max(0, time / walkDuration))
    let end = 0.78
    let integral: Double
    if u < end {
      integral = u
    } else {
      let v = (u - end) / (1 - end)
      integral = end + (1 - end) * (v - pow(v, 3) + 0.5 * pow(v, 4))
    }
    return entry + (rest - entry) * integral / ((1 + end) * 0.5)
  }

  private func footfallTimes(leg: Int, stage: Stage) -> (times: [Double], period: Double) {
    let size = min(1.2, max(0.75, tuning.size))
    let distance = root(at: 0, stage: stage) - root(at: walkDuration, stage: stage)
    let period = min(2.15, max(0.75, 50 * size / (distance / walkDuration)))
    // Four-beat lateral sequence, separated support phases rather than a trot.
    let phases = [0.25, 0.75, 0.0, 0.5]
    let offset = phases[leg] * period
    let last = walkDuration - 0.65 + Double(leg) * 0.13
    var contacts = stride(from: offset - period, through: last - period * 0.20, by: period).map {
      $0
    }
    contacts.append(last)
    return (contacts, period)
  }

  func hoof(at time: Double, leg: Int, stage: Stage) -> Hoof {
    let size = min(1.2, max(0.75, tuning.size))
    let localX = (leg < 2 ? -44.0 : 43.0) * size
    let z = (leg % 2 == 0 ? -12.0 : 12.0) * size
    let schedule = footfallTimes(leg: leg, stage: stage)
    let contacts = schedule.times
    let period = schedule.period
    func anchor(_ contact: Double, final: Bool) -> SIMD3<Double> {
      SIMD3(root(at: final ? walkDuration : contact + period * 0.32, stage: stage) + localX, 0, z)
    }
    for index in 0..<(contacts.count - 1) {
      let next = contacts[index + 1]
      if time < next {
        let lift = contacts[index] + (next - contacts[index]) * 0.68
        let a = anchor(contacts[index], final: false)
        guard time > lift else { return Hoof(point: a, planted: true) }
        let u = (time - lift) / (next - lift)
        let b = anchor(next, final: index + 1 == contacts.count - 1)
        var p = a + (b - a) * Self.smooth(u)
        p.y = 13 * size * pow(sin(.pi * u), 2)
        return Hoof(point: p, planted: false)
      }
    }
    return Hoof(point: anchor(contacts.last!, final: true), planted: true)
  }

  func sample(at elapsed: Double, stage: Stage, reduceMotion: Bool = false) -> Pose? {
    guard elapsed.isFinite, elapsed >= startTime else { return nil }
    let t = max(0, elapsed - startTime)
    let size = min(1.2, max(0.75, tuning.size))
    let down = (t - walkDuration - standingDuration) / settlingDuration
    // The observed knee-to-ground transition is brief and overlapping, not
    // a prolonged bow. Reserve the surrounding seconds for deciding/resting.
    let front = Self.smooth((down - 0.18) / 0.32)
    let hind = Self.smooth((down - 0.25) / 0.35)
    let rest = Self.smooth((down - 0.70) / 0.30)
    if reduceMotion {
      // No stepped locomotion at the reduced one-Hz display cadence.
      guard t >= walkDuration else { return nil }
      return restingPose(stage: stage, opacity: Self.smooth((t - walkDuration) / 2))
    }
    let moving = 1 - Self.smooth((t - walkDuration + 2.5) / 2.5)
    let gaitPhase = t * 4 * .pi / footfallTimes(leg: 0, stage: stage).period
    let bob = 0.65 * sin(gaitPhase) * moving
    let breath = 0.24 * sin(t * 1.15) * rest
    var feet = (0..<4).map { hoof(at: t, leg: $0, stage: stage) }
    let root = root(at: t, stage: stage)
    for leg in 0..<4 {
      let fold = leg < 2 ? front : hind
      let p = feet[leg].point
      let target = root + (leg < 2 ? -34.0 : 38.0) * size
      // During kneeling, distal paper folds tuck behind the carpal/hock
      // contact; this is no longer a planted walking hoof.
      feet[leg] = Hoof(
        point: SIMD3(p.x + (target - p.x) * fold, p.y, p.z),
        planted: feet[leg].planted && fold == 0)
    }
    let listen = sin(.pi * min(1, max(0, (t - walkDuration) / standingDuration)))
    var pose = Pose(
      root: root, shoulder: 96 - 70 * front + bob + breath,
      hip: 102 - 74 * hind + 0.45 * sin(gaitPhase - .pi / 2) * moving + breath,
      frontFold: front, hindFold: hind,
      headAngle: 0.035 * sin(t * 1.8) * moving + 0.16 * listen + 0.30 * rest
        + 0.72 * Self.smooth(down / 0.18) * (1 - Self.smooth((down - 0.3) / 0.35)),
      earAngle: 0.10 * listen + 0.015 * sin(t * 0.73) * (1 - rest),
      eyesClosed: rest > 0.7, hooves: feet,
      phase: t < walkDuration ? .walking : down < 0 ? .listening : down < 1 ? .kneeling : .resting,
      size: size, opacity: 1)
    for leg in 0..<4 {
      for contact in footfallTimes(leg: leg, stage: stage).times where contact >= 0 && contact <= t
      {
        pose.footprints.append(
          Footprint(
            point: hoof(at: contact + 0.000001, leg: leg, stage: stage).point,
            age: t - contact))
      }
    }
    return pose
  }

  private func restingPose(stage: Stage, opacity: Double) -> Pose {
    let size = min(1.2, max(0.75, tuning.size))
    let x = root(at: walkDuration, stage: stage)
    return Pose(
      root: x, shoulder: 26, hip: 28, frontFold: 1, hindFold: 1,
      headAngle: 0.30, earAngle: 0, eyesClosed: true,
      hooves: (0..<4).map {
        Hoof(
          point: SIMD3(
            x + ($0 < 2 ? -34 : 38) * size,
            0, ($0 % 2 == 0 ? -12 : 12) * size), planted: false)
      },
      phase: .resting, size: size, opacity: opacity)
  }
}

/// The original paper construction uses broad torso planes, tapered folded limbs,
/// a pleated neck and lanceolate ears. It is not a copied origami crease pattern.
enum AutumnDeerMesh {
  typealias V = SIMD3<Double>
  struct Face {
    let vertices: [V]
    let pigment: V
    let grain: Bool
  }
  static let copper = V(0.80, 0.49, 0.38)
  static let cream = V(0.95, 0.78, 0.56)
  static let dark = V(0.24, 0.20, 0.24)

  static func knee(root: V, foot: V, upper: Double, lower: Double, bend: Double) -> V {
    let delta = SIMD2(foot.x - root.x, foot.y - root.y)
    let distance = min(upper + lower - 0.001, max(0.001, simd_length(delta)))
    let direction = simd_normalize(delta)
    let along = (upper * upper - lower * lower + distance * distance) / (2 * distance)
    let away = sqrt(max(0, upper * upper - along * along))
    let p =
      SIMD2(root.x, root.y) + direction * along + SIMD2(-direction.y, direction.x) * away * bend
    return V(p.x, p.y, foot.z)
  }

  static func faces(_ pose: AutumnDeerEncounter.Pose) -> [Face] {
    var result: [Face] = []
    func face(_ vertices: [V], _ pigment: V = copper, grain: Bool = true) {
      result.append(Face(vertices: vertices, pigment: pigment, grain: grain))
    }
    func foldedStrip(_ a: V, _ b: V, _ wa: Double, _ wb: Double, _ pigment: V = copper) {
      let d = simd_normalize(SIMD2(b.x - a.x, b.y - a.y))
      let n = V(-d.y, d.x, 0)
      let ridgeA = a + V(0, 0, -wa * 0.45)
      let ridgeB = b + V(0, 0, -wb * 0.45)
      face([a + n * wa, b + n * wb, ridgeB, ridgeA], pigment * 1.03)
      face([ridgeA, ridgeB, b - n * wb, a - n * wa], pigment * 0.83)
    }
    let bodyAngle = atan2(pose.hip - pose.shoulder, 88)
    let bodyCenter = V(0, (pose.shoulder + pose.hip) / 2, 0)
    func body(_ p: V) -> V {
      bodyCenter + simd_quatd(angle: bodyAngle, axis: V(0, 0, 1)).act(p)
    }
    for leg in 0..<4 {
      let front = leg < 2
      let z = leg % 2 == 0 ? -12.0 : 12.0
      let root = V(front ? -44 : 43, front ? pose.shoulder : pose.hip, z)
      let p = pose.hooves[leg].point
      let hoof = V((p.x - pose.root) / pose.size, p.y / pose.size + 3, z)
      let joint = knee(
        root: root, foot: hoof, upper: front ? 47 : 53,
        lower: front ? 51 : 52, bend: front ? -1 : 1)
      let pigment = copper * (leg % 2 == 0 ? 1 : 0.78)
      foldedStrip(root, joint, front ? 7 : 13, 3.5, pigment)
      foldedStrip(joint, hoof, 3.5, 2, pigment)
      face(
        [hoof + V(-5, -3, -1), hoof + V(4, -3, -1), hoof + V(3, 4, -1), hoof + V(-3, 5, -1)], dark)
    }
    // A closed tented torso: long quiet planes, rather than a triangulated sphere.
    let A = body(V(-54, 13, 0))
    let B = body(V(40, 20, 0))
    let C = body(V(59, 4, 0))
    let D = body(V(47, -15, 0))
    let E = body(V(-32, -20, 0))
    let F = body(V(-59, -4, 0))
    for side in [-1.0, 1.0] {
      let ridge = body(V(-7, 2, side * 23))
      face([A, B, ridge], copper * 1.12)
      face([B, C, D, ridge], copper * 0.97)
      face([ridge, D, E], copper * 0.82)
      face([A, ridge, E, F], copper)
    }
    // Small folded tail, not a waving flag.
    let tail = body(V(54, 7, 0))
    foldedStrip(tail, tail + V(16, 7, 2), 6, 0.5, cream * 0.90)
    let shoulder = V(-47, pose.shoulder + 7, 0)
    let neckRotation = simd_quatd(angle: pose.headAngle, axis: V(0, 0, 1))
    let head = shoulder + neckRotation.act(V(-30, 55, 0))
    foldedStrip(shoulder, head, 18, 10)
    face(
      [
        shoulder + V(-14, 0, -2), head + V(-7, -6, -2), head + V(-3, -13, -12),
        shoulder + V(-3, -8, -18),
      ], cream * 0.93)
    func skull(_ p: V) -> V { head + neckRotation.act(p) }
    let nose = skull(V(-31, -7, 0))
    face([skull(V(8, 8, 0)), skull(V(-12, 14, 0)), nose, skull(V(-16, -17, 0)), skull(V(9, -7, 0))])
    let cheek = skull(V(-9, -3, -10))
    face([skull(V(8, 8, 0)), skull(V(-12, 14, 0)), cheek], copper * 1.14)
    face([skull(V(-12, 14, 0)), nose, cheek], cream * 0.97)
    face([cheek, nose, skull(V(-16, -17, 0)), skull(V(9, -7, 0))], copper * 0.9)
    face([nose + V(0, 2, -1), nose + V(4, 1, -3), nose + V(3, -3, -1)], dark)
    for side in [-1.0, 1.0] {
      let base = skull(V(1, 9, side * 6))
      let tip = skull(V(side < 0 ? 19 : -18, 30 + pose.earAngle * 25, side * 20))
      let middle = (base + tip) / 2 + V(0, 0, -3)
      face([base, middle + V(-7, 4, 0), tip, middle + V(7, -3, 0)], copper * 1.05)
      face([base + V(1, 2, -1), middle + V(-4, 3, -2), tip - V(1, 4, 1)], cream)
      let antler = skull(V(-8, 14, side * 5))
      let elbow = skull(V(-2, 38, side * 10))
      let tipA = skull(V(-9, 61, side * 14))
      foldedStrip(antler, elbow, 3.7, 2.5, cream)
      foldedStrip(elbow, tipA, 2.5, 0.2, cream)
      foldedStrip(elbow - V(2, 6, 0), skull(V(-24, 47, side * 14)), 2.5, 0.1, cream)
      foldedStrip(elbow + V(-1, 6, 0), skull(V(8, 54, side * 12)), 1.7, 0.1, cream)
    }
    let eye = skull(V(-12, 2, -10.6))
    if pose.eyesClosed {
      face(
        [eye + V(-3, 0, 0), eye + V(0, -1.1, 0), eye + V(3, 1, 0), eye + V(0, 0, 0)], dark,
        grain: false)
    } else {
      face(
        [eye + V(-1.4, 0, 0), eye + V(0, 1.3, 0), eye + V(1.2, -0.3, 0), eye + V(0, -1.2, 0)], dark,
        grain: false)
    }
    return result
  }
}
