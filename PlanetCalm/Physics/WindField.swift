import Foundation

/// Codable bounds are explicit in the review configuration, not implicit RNG rules.
struct WindParameterRange: Codable, Equatable, Sendable {
    let minimum: Double
    let maximum: Double

    var isValid: Bool { minimum.isFinite && maximum.isFinite && minimum <= maximum }

    func draw(using generator: inout SeededRandomNumberGenerator) -> Double {
        generator.value(in: minimum...maximum)
    }
}

struct GustConfiguration: Codable, Equatable, Sendable {
    let startSeconds: WindParameterRange
    let attackSeconds: WindParameterRange
    let peakSeconds: WindParameterRange
    let decaySeconds: WindParameterRange
    let speedMetersPerSecond: WindParameterRange
    let directionRadians: WindParameterRange

    func validated() throws -> Self {
        let ranges = [startSeconds, attackSeconds, peakSeconds, decaySeconds,
                      speedMetersPerSecond, directionRadians]
        guard ranges.allSatisfy(\.isValid), startSeconds.minimum >= 0,
              attackSeconds.minimum > 0, peakSeconds.minimum >= 0,
              decaySeconds.minimum > 0, speedMetersPerSecond.minimum >= 0 else {
            throw LeafGravityLabConfigurationError.invalidWind
        }
        return self
    }
}

struct WindFieldConfiguration: Codable, Equatable, Sendable {
    let steadyVelocityMetersPerSecond: PhysicsVector
    let gust: GustConfiguration
    let debugVectorSeconds: Double

    func validated() throws -> Self {
        guard steadyVelocityMetersPerSecond.x.isFinite, steadyVelocityMetersPerSecond.y.isFinite,
              debugVectorSeconds.isFinite, debugVectorSeconds > 0 else {
            throw LeafGravityLabConfigurationError.invalidWind
        }
        _ = try gust.validated()
        return self
    }
}

enum WindTrialMode: String, CaseIterable, Identifiable, Sendable {
    case steady
    case gust
    var id: Self { self }
    var label: String { self == .steady ? "Steady breeze" : "Breeze + one gust" }
}

struct WindSample: Equatable, Sendable {
    enum Phase: String, Sendable { case steady, waiting, attack, peak, decay, ended }
    let velocityMetersPerSecond: PhysicsVector
    let gustEnvelope: Double
    let phase: Phase
}

struct GustPlan: Equatable, Sendable {
    let startSeconds: Double
    let attackSeconds: Double
    let peakSeconds: Double
    let decaySeconds: Double
    let velocityMetersPerSecond: PhysicsVector

    var endSeconds: Double { startSeconds + attackSeconds + peakSeconds + decaySeconds }

    func envelope(at elapsedTime: Double) -> (value: Double, phase: WindSample.Phase) {
        let time = elapsedTime - startSeconds
        if time < 0 { return (0, .waiting) }
        if time < attackSeconds { return (Self.smoothstep(time / attackSeconds), .attack) }
        if time < attackSeconds + peakSeconds { return (1, .peak) }
        if time < attackSeconds + peakSeconds + decaySeconds {
            return (1 - Self.smoothstep((time - attackSeconds - peakSeconds) / decaySeconds), .decay)
        }
        return (0, .ended)
    }

    /// Zero slope at both ends: no impulse at attack/peak/decay boundaries.
    private static func smoothstep(_ value: Double) -> Double { value * value * (3 - 2 * value) }
}

/// A uniform external field shared by every future leaf. It owns no body state.
/// RNG is consumed once when constructing the plan, never when sampling a frame.
struct WindField: Equatable, Sendable {
    let steadyVelocityMetersPerSecond: PhysicsVector
    let gust: GustPlan?

    init(configuration: WindFieldConfiguration, seed: UInt64, mode: WindTrialMode) {
        steadyVelocityMetersPerSecond = configuration.steadyVelocityMetersPerSecond
        guard mode == .gust else { gust = nil; return }
        var generator = SeededRandomNumberGenerator(seed: seed)
        let rule = configuration.gust
        let start = rule.startSeconds.draw(using: &generator)
        let attack = rule.attackSeconds.draw(using: &generator)
        let peak = rule.peakSeconds.draw(using: &generator)
        let decay = rule.decaySeconds.draw(using: &generator)
        let speed = rule.speedMetersPerSecond.draw(using: &generator)
        let direction = rule.directionRadians.draw(using: &generator)
        gust = GustPlan(startSeconds: start, attackSeconds: attack, peakSeconds: peak,
                        decaySeconds: decay,
                        velocityMetersPerSecond: PhysicsVector(x: speed * cos(direction), y: speed * sin(direction)))
    }

    /// Position is part of the sampling boundary, but Gate 4 is spatially uniform.
    func sample(at positionMeters: PhysicsVector, elapsedTime: Double) -> WindSample {
        let envelope = gust?.envelope(at: elapsedTime) ?? (value: 0, phase: .steady)
        return WindSample(
            velocityMetersPerSecond: PhysicsVector(
                x: steadyVelocityMetersPerSecond.x + (gust?.velocityMetersPerSecond.x ?? 0) * envelope.value,
                y: steadyVelocityMetersPerSecond.y + (gust?.velocityMetersPerSecond.y ?? 0) * envelope.value),
            gustEnvelope: envelope.value, phase: envelope.phase
        )
    }
}
