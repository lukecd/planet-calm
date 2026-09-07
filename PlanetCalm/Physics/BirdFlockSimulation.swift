import Foundation

enum BirdFlockConfigurationError: Error, Equatable {
    case unsupportedCount(Int)
    case unsupportedBodyLength(Double)
    case invalidDimension
    case invalidCorrectionScale
}

struct BirdFlockConfiguration: Equatable, Hashable, Sendable {
    static let version = 2
    static let fixedStep = 1.0 / 60.0
    static let approvedCounts = [20, 24, 30]
    static let approvedBodyLengths = [10.0, 14.0, 18.0]

    let width: Double
    let height: Double
    let count: Int
    let seed: UInt32
    let bodyLength: Double
    let routeDuration: TimeInterval
    let eventDuration: TimeInterval
    let routeY: Double
    let separationRadiusBodies: Double
    let alignmentRadiusBodies: Double
    let cohesionRadiusBodies: Double
    let separationWeight: Double
    let alignmentWeight: Double
    let cohesionWeight: Double
    let envelopeWeight: Double
    let routeWeight: Double
    let maxSteerBodies: Double
    let speedBodies: Double
    let minimumSpeedFactor: Double
    let maximumSpeedFactor: Double
    let leaderCorrectionScale: Double

    init(
        width: Double = 390,
        height: Double = 650,
        count: Int = 24,
        seed: UInt32 = 130_363,
        bodyLength: Double = 14,
        routeDuration: TimeInterval = 15,
        eventDuration: TimeInterval = 18,
        routeY: Double = 0.30,
        separationRadiusBodies: Double = 2.25,
        alignmentRadiusBodies: Double = 5,
        cohesionRadiusBodies: Double = 6,
        separationWeight: Double = 1.25,
        alignmentWeight: Double = 0.42,
        cohesionWeight: Double = 0.12,
        envelopeWeight: Double = 0.34,
        routeWeight: Double = 0.54,
        maxSteerBodies: Double = 3.8,
        speedBodies: Double = 3.1,
        minimumSpeedFactor: Double = 0.88,
        maximumSpeedFactor: Double = 1.12,
        leaderCorrectionScale: Double = 1
    ) throws {
        guard Self.approvedCounts.contains(count) else {
            throw BirdFlockConfigurationError.unsupportedCount(count)
        }
        guard Self.approvedBodyLengths.contains(bodyLength) else {
            throw BirdFlockConfigurationError.unsupportedBodyLength(bodyLength)
        }
        guard width.isFinite, height.isFinite, routeDuration.isFinite,
              width > 0, height > 0, routeDuration > 0, eventDuration >= routeDuration else {
            throw BirdFlockConfigurationError.invalidDimension
        }
        guard leaderCorrectionScale.isFinite, (0...1).contains(leaderCorrectionScale) else {
            throw BirdFlockConfigurationError.invalidCorrectionScale
        }
        self.width = width
        self.height = height
        self.count = count
        self.seed = seed
        self.bodyLength = bodyLength
        self.routeDuration = routeDuration
        self.eventDuration = eventDuration
        self.routeY = routeY
        self.separationRadiusBodies = separationRadiusBodies
        self.alignmentRadiusBodies = alignmentRadiusBodies
        self.cohesionRadiusBodies = cohesionRadiusBodies
        self.separationWeight = separationWeight
        self.alignmentWeight = alignmentWeight
        self.cohesionWeight = cohesionWeight
        self.envelopeWeight = envelopeWeight
        self.routeWeight = routeWeight
        self.maxSteerBodies = maxSteerBodies
        self.speedBodies = speedBodies
        self.minimumSpeedFactor = minimumSpeedFactor
        self.maximumSpeedFactor = maximumSpeedFactor
        self.leaderCorrectionScale = leaderCorrectionScale
    }
}

enum BirdFlockEventSeed {
    /// Stable, documented bridge from StoryMoment's 64-bit seed to the accepted
    /// flock implementation's 32-bit seed. A review seed of 130363 is unchanged.
    static func map(_ storySeed: UInt64) -> UInt32 {
        UInt32(truncatingIfNeeded: storySeed) ^ UInt32(truncatingIfNeeded: storySeed >> 32)
    }
}

struct BirdFormationSlot: Equatable, Sendable {
    let x: Double
    let y: Double
}

struct BirdLeaderCorrection: Equatable, Sendable {
    let startSeconds: TimeInterval
    let durationSeconds: TimeInterval
    let peakRatio: Double
    let amplitude: Double

    var peakTime: TimeInterval {
        startSeconds + durationSeconds * peakRatio
    }

    func offset(at time: TimeInterval) -> Double {
        let progress = (time - startSeconds) / durationSeconds
        guard progress > 0, progress < 1 else { return 0 }
        if progress <= peakRatio {
            return amplitude * BirdFlockMath.smoothstep(progress / peakRatio)
        }
        return amplitude * (1 - BirdFlockMath.smoothstep((progress - peakRatio) / (1 - peakRatio)))
    }

    func velocity(at time: TimeInterval) -> Double {
        let progress = (time - startSeconds) / durationSeconds
        guard progress > 0, progress < 1 else { return 0 }
        if progress <= peakRatio {
            let phase = progress / peakRatio
            return amplitude * 6 * phase * (1 - phase) / (peakRatio * durationSeconds)
        }
        let phase = (progress - peakRatio) / (1 - peakRatio)
        return -amplitude * 6 * phase * (1 - phase) / ((1 - peakRatio) * durationSeconds)
    }
}

struct BirdRouteGuide: Equatable, Sendable {
    let x: Double
    let y: Double
    let velocityX: Double
    let velocityY: Double
    let progress: Double
}

struct BirdAgent: Equatable, Sendable {
    let id: Int
    var x: Double
    var y: Double
    var velocityX: Double
    var velocityY: Double
    let slotX: Double
    let slotY: Double
    let scale: Double
    let wingPhase: Double
    let wingRate: Double
    let breathPhase: Double
    let driftPhase: Double
}

struct BirdFlockState: Equatable, Sendable {
    let configuration: BirdFlockConfiguration
    var time: TimeInterval
    var step: Int
    var agents: [BirdAgent]
    var guide: BirdRouteGuide
    let leaderCorrections: [BirdLeaderCorrection]
    var minimumSeparation: Double
    var minimumSeparationEver: Double
    var exited: Bool
}

struct BirdFlockSimulation: Sendable {
    private(set) var state: BirdFlockState

    init(configuration: BirdFlockConfiguration) {
        var random = Mulberry32(seed: configuration.seed)
        let slots = BirdFlockMath.formationSlots(configuration: configuration)
        let corrections = BirdFlockMath.leaderCorrections(configuration: configuration)
        let guide = BirdFlockMath.guide(at: 0, configuration: configuration)
        let agents = slots.enumerated().map { id, slot in
            let jitterX = (random.nextUnit() - 0.5) * configuration.bodyLength * 0.42
            let jitterY = (random.nextUnit() - 0.5) * configuration.bodyLength * 0.56
            return BirdAgent(
                id: id,
                x: guide.x + slot.x + jitterX,
                y: guide.y + slot.y + jitterY,
                velocityX: max(configuration.bodyLength * 0.2, guide.velocityX) * (0.96 + random.nextUnit() * 0.08),
                velocityY: guide.velocityY + (random.nextUnit() - 0.5) * configuration.bodyLength * 0.15,
                slotX: slot.x,
                slotY: slot.y,
                scale: 0.90 + random.nextUnit() * 0.20,
                wingPhase: random.nextUnit(),
                wingRate: 0.94 + random.nextUnit() * 0.12,
                breathPhase: random.nextUnit() * .pi * 2,
                driftPhase: random.nextUnit() * .pi * 2
            )
        }
        state = BirdFlockState(
            configuration: configuration,
            time: 0,
            step: 0,
            agents: agents,
            guide: guide,
            leaderCorrections: corrections,
            minimumSeparation: .infinity,
            minimumSeparationEver: .infinity,
            exited: false
        )
    }

    mutating func step(_ deltaTime: TimeInterval = BirdFlockConfiguration.fixedStep) {
        precondition(abs(deltaTime - BirdFlockConfiguration.fixedStep) <= 1e-12)
        let config = state.configuration
        let body = config.bodyLength
        let separationRadius = body * config.separationRadiusBodies
        let alignmentRadius = body * config.alignmentRadiusBodies
        let cohesionRadius = body * config.cohesionRadiusBodies
        let desiredSpeed = body * config.speedBodies
        let maximumSteering = body * config.maxSteerBodies
        let nextTime = state.time + deltaTime
        let nextGuide = BirdFlockMath.guide(at: nextTime, configuration: config)
        var accelerations: [(x: Double, y: Double)] = []
        var currentMinimum = Double.infinity

        for agent in state.agents {
            var separationX = 0.0
            var separationY = 0.0
            var alignmentX = 0.0
            var alignmentY = 0.0
            var cohesionX = 0.0
            var cohesionY = 0.0
            var alignmentCount = 0
            var cohesionCount = 0

            for other in state.agents where other.id != agent.id {
                let dx = agent.x - other.x
                let dy = agent.y - other.y
                let distance = hypot(dx, dy)
                currentMinimum = min(currentMinimum, distance)
                if distance < separationRadius, distance > 1e-6 {
                    let pressure = (separationRadius - distance) / separationRadius
                    separationX += dx / distance * pressure * pressure
                    separationY += dy / distance * pressure * pressure
                }
                if distance < alignmentRadius {
                    alignmentX += other.velocityX
                    alignmentY += other.velocityY
                    alignmentCount += 1
                }
                if distance < cohesionRadius, distance > separationRadius * 1.18 {
                    cohesionX += other.x
                    cohesionY += other.y
                    cohesionCount += 1
                }
            }

            if alignmentCount > 0 {
                alignmentX = alignmentX / Double(alignmentCount) - agent.velocityX
                alignmentY = alignmentY / Double(alignmentCount) - agent.velocityY
            }
            if cohesionCount > 0 {
                cohesionX = cohesionX / Double(cohesionCount) - agent.x
                cohesionY = cohesionY / Double(cohesionCount) - agent.y
                (cohesionX, cohesionY) = BirdFlockMath.normalized(x: cohesionX, y: cohesionY)
            }

            let target = BirdFlockMath.target(
                for: agent,
                guide: nextGuide,
                time: nextTime,
                configuration: config,
                corrections: state.leaderCorrections
            )
            var envelopeX = target.x - agent.x
            var envelopeY = target.y - agent.y
            (envelopeX, envelopeY) = BirdFlockMath.limited(x: envelopeX, y: envelopeY, maximum: body * 2.6)
            let routeVelocityX = max(desiredSpeed * 0.65, nextGuide.velocityX)
            let routeVelocityY = nextGuide.velocityY + target.correctionVelocityY * 4
            let routeX = routeVelocityX - agent.velocityX
            let routeY = routeVelocityY - agent.velocityY
            var accelerationX = separationX * config.separationWeight * maximumSteering
                + alignmentX * config.alignmentWeight
                + cohesionX * config.cohesionWeight * maximumSteering
                + envelopeX * config.envelopeWeight
                + routeX * config.routeWeight
            var accelerationY = separationY * config.separationWeight * maximumSteering
                + alignmentY * config.alignmentWeight
                + cohesionY * config.cohesionWeight * maximumSteering
                + envelopeY * config.envelopeWeight
                + routeY * config.routeWeight
            (accelerationX, accelerationY) = BirdFlockMath.limited(
                x: accelerationX,
                y: accelerationY,
                maximum: maximumSteering
            )
            accelerations.append((accelerationX, accelerationY))
        }

        for index in state.agents.indices {
            state.agents[index].velocityX += accelerations[index].x * deltaTime
            state.agents[index].velocityY += accelerations[index].y * deltaTime
            let speed = hypot(state.agents[index].velocityX, state.agents[index].velocityY)
            let minimumSpeed = desiredSpeed * config.minimumSpeedFactor
            let maximumSpeed = max(minimumSpeed, desiredSpeed * config.maximumSpeedFactor, nextGuide.velocityX * 1.08)
            let targetSpeed = BirdFlockMath.clamp(speed, minimum: minimumSpeed, maximum: maximumSpeed)
            if speed > 1e-9 {
                state.agents[index].velocityX = state.agents[index].velocityX / speed * targetSpeed
                state.agents[index].velocityY = state.agents[index].velocityY / speed * targetSpeed
            }
            state.agents[index].x += state.agents[index].velocityX * deltaTime
            state.agents[index].y += state.agents[index].velocityY * deltaTime
        }

        state.time = nextTime
        state.step += 1
        state.guide = nextGuide
        state.minimumSeparation = currentMinimum
        state.minimumSeparationEver = min(state.minimumSeparationEver, currentMinimum)
        state.exited = state.agents.allSatisfy {
            $0.x - config.bodyLength * $0.scale > config.width
        }
    }

    mutating func advance(to elapsedTime: TimeInterval) {
        let requestedSteps = Int(floor(elapsedTime / BirdFlockConfiguration.fixedStep + 1e-9))
        while state.step < requestedSteps {
            step()
        }
    }

    static func state(configuration: BirdFlockConfiguration, at elapsedTime: TimeInterval) -> BirdFlockState {
        var simulation = BirdFlockSimulation(configuration: configuration)
        simulation.advance(to: max(0, elapsedTime))
        return simulation.state
    }
}

struct BirdTrajectoryAgent: Equatable, Sendable {
    let id: Int
    let x: Double
    let y: Double
    let velocityX: Double
    let velocityY: Double
    let heading: Double
    let scale: Double
    let wingPhase: Double
    let wingRate: Double

    func wingFrame(at elapsedTime: TimeInterval, frameCount: Int = 12, cycleSeconds: Double = 0.8) -> Int {
        let phase = (wingPhase + elapsedTime * wingRate / cycleSeconds).truncatingRemainder(dividingBy: 1)
        return Int(floor(phase * Double(frameCount))) % frameCount
    }
}

struct BirdFlockTrajectorySample: Equatable, Sendable {
    let time: TimeInterval
    let agents: [BirdTrajectoryAgent]
    let guide: BirdRouteGuide
    let exited: Bool
}

struct BirdFlockTrajectory: Equatable, Sendable {
    let configuration: BirdFlockConfiguration
    let samples: [BirdFlockTrajectorySample]
    let leaderCorrections: [BirdLeaderCorrection]
    let minimumSeparationEver: Double

    init(configuration: BirdFlockConfiguration) {
        var simulation = BirdFlockSimulation(configuration: configuration)
        var samples = [Self.sample(from: simulation.state)]
        let count = Int((configuration.eventDuration / BirdFlockConfiguration.fixedStep).rounded())
        samples.reserveCapacity(count + 1)
        for _ in 0..<count {
            simulation.step()
            samples.append(Self.sample(from: simulation.state))
        }
        self.configuration = configuration
        self.samples = samples
        self.leaderCorrections = simulation.state.leaderCorrections
        self.minimumSeparationEver = simulation.state.minimumSeparationEver
    }

    func sample(at elapsedTime: TimeInterval) -> BirdFlockTrajectorySample {
        let clamped = BirdFlockMath.clamp(elapsedTime, minimum: 0, maximum: configuration.eventDuration)
        let exactIndex = clamped / BirdFlockConfiguration.fixedStep
        let lowerIndex = min(Int(floor(exactIndex)), samples.count - 1)
        let upperIndex = min(lowerIndex + 1, samples.count - 1)
        let fraction = exactIndex - Double(lowerIndex)
        guard lowerIndex != upperIndex, fraction > 1e-12 else { return samples[lowerIndex] }
        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]
        let agents = zip(lower.agents, upper.agents).map { first, second in
            let velocityX = BirdFlockMath.interpolate(first.velocityX, second.velocityX, fraction)
            let velocityY = BirdFlockMath.interpolate(first.velocityY, second.velocityY, fraction)
            return BirdTrajectoryAgent(
                id: first.id,
                x: BirdFlockMath.interpolate(first.x, second.x, fraction),
                y: BirdFlockMath.interpolate(first.y, second.y, fraction),
                velocityX: velocityX,
                velocityY: velocityY,
                heading: atan2(velocityY, velocityX),
                scale: first.scale,
                wingPhase: first.wingPhase,
                wingRate: first.wingRate
            )
        }
        return BirdFlockTrajectorySample(
            time: clamped,
            agents: agents,
            guide: BirdRouteGuide(
                x: BirdFlockMath.interpolate(lower.guide.x, upper.guide.x, fraction),
                y: BirdFlockMath.interpolate(lower.guide.y, upper.guide.y, fraction),
                velocityX: BirdFlockMath.interpolate(lower.guide.velocityX, upper.guide.velocityX, fraction),
                velocityY: BirdFlockMath.interpolate(lower.guide.velocityY, upper.guide.velocityY, fraction),
                progress: BirdFlockMath.interpolate(lower.guide.progress, upper.guide.progress, fraction)
            ),
            exited: fraction < 1 ? lower.exited : upper.exited
        )
    }

    private static func sample(from state: BirdFlockState) -> BirdFlockTrajectorySample {
        BirdFlockTrajectorySample(
            time: state.time,
            agents: state.agents.map {
                BirdTrajectoryAgent(
                    id: $0.id,
                    x: $0.x,
                    y: $0.y,
                    velocityX: $0.velocityX,
                    velocityY: $0.velocityY,
                    heading: atan2($0.velocityY, $0.velocityX),
                    scale: $0.scale,
                    wingPhase: $0.wingPhase,
                    wingRate: $0.wingRate
                )
            },
            guide: state.guide,
            exited: state.exited
        )
    }
}

private struct Mulberry32 {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    mutating func nextUnit() -> Double {
        state &+= 0x6D2B79F5
        var value = state
        value = (value ^ (value >> 15)) &* (value | 1)
        value ^= value &+ ((value ^ (value >> 7)) &* (value | 61))
        return Double(value ^ (value >> 14)) / 4_294_967_296
    }
}

private enum BirdFlockMath {
    struct Target {
        let x: Double
        let y: Double
        let correctionVelocityY: Double
    }

    static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        max(minimum, min(maximum, value))
    }

    static func interpolate(_ first: Double, _ second: Double, _ fraction: Double) -> Double {
        first + (second - first) * fraction
    }

    static func normalized(x: Double, y: Double) -> (Double, Double) {
        let magnitude = hypot(x, y)
        return magnitude > 1e-9 ? (x / magnitude, y / magnitude) : (0, 0)
    }

    static func limited(x: Double, y: Double, maximum: Double) -> (Double, Double) {
        let magnitude = hypot(x, y)
        guard magnitude > maximum, magnitude >= 1e-9 else { return (x, y) }
        return (x * maximum / magnitude, y * maximum / magnitude)
    }

    static func smoothstep(_ value: Double) -> Double {
        let t = clamp(value, minimum: 0, maximum: 1)
        return t * t * (3 - 2 * t)
    }

    static func mixSeed(_ seed: UInt32, value: UInt32) -> UInt32 {
        var mixed = seed ^ ((value &+ 1) &* 0x9E3779B1)
        mixed ^= mixed >> 16
        mixed &*= 0x7FEB352D
        mixed ^= mixed >> 15
        mixed &*= 0x846CA68B
        return mixed ^ (mixed >> 16)
    }

    static func formationSlots(configuration: BirdFlockConfiguration) -> [BirdFormationSlot] {
        var slots = [BirdFormationSlot(x: 0, y: 0)]
        var random = Mulberry32(seed: mixSeed(configuration.seed, value: 41))
        let rowGap = configuration.bodyLength * 1.82
        let laneGap = configuration.bodyLength * 1.76
        var row = 1
        while slots.count < configuration.count {
            let capacity = row + 1
            for position in 0..<capacity where slots.count < configuration.count {
                let centered = Double(position) - Double(capacity - 1) / 2
                slots.append(BirdFormationSlot(
                    x: -Double(row) * rowGap + (random.nextUnit() - 0.5) * configuration.bodyLength * 0.24,
                    y: centered * laneGap + (random.nextUnit() - 0.5) * configuration.bodyLength * 0.24
                ))
            }
            row += 1
        }
        return slots
    }

    static func guide(at time: TimeInterval, configuration: BirdFlockConfiguration) -> BirdRouteGuide {
        let body = configuration.bodyLength
        let slotsWidth = ceil(Double(configuration.count) / 4) * body * 1.8
        let startX = -slotsWidth - body * 5
        let endX = configuration.width + slotsWidth + body * 7
        let progress = clamp(time / configuration.routeDuration, minimum: 0, maximum: 1)
        let eased = progress * progress * (3 - 2 * progress)
        let x = startX + (endX - startX) * eased
        let y = configuration.height * configuration.routeY
            + sin(progress * .pi * 1.2 - 0.35) * body * 0.75
            + sin(progress * .pi * 2.4) * body * 0.18
        let derivative = 6 * progress * (1 - progress) / configuration.routeDuration
        let velocityX = (endX - startX) * derivative
        let velocityY = (
            cos(progress * .pi * 1.2 - 0.35) * .pi * 1.2 * body * 0.75
            + cos(progress * .pi * 2.4) * .pi * 2.4 * body * 0.18
        ) / configuration.routeDuration
        return BirdRouteGuide(x: x, y: y, velocityX: velocityX, velocityY: velocityY, progress: progress)
    }

    static func leaderCorrections(configuration: BirdFlockConfiguration) -> [BirdLeaderCorrection] {
        let scheduleSeed = mixSeed(configuration.seed, value: 73)
        var random = Mulberry32(seed: scheduleSeed)
        let count = 2 - Int(scheduleSeed & 1)
        let firstDirection = random.nextUnit() < 0.5 ? -1.0 : 1.0
        return (0..<count).map { index in
            let start = configuration.routeDuration * (0.48 + Double(index) * 0.16)
                + (random.nextUnit() - 0.5) * configuration.routeDuration * 0.03
            let duration = 1.7 + random.nextUnit() * 0.9
            let magnitude = (2.2 + random.nextUnit() * 1.6)
                * (configuration.bodyLength / 14) * configuration.leaderCorrectionScale
            return BirdLeaderCorrection(
                startSeconds: start,
                durationSeconds: duration,
                peakRatio: 0.38 + random.nextUnit() * 0.18,
                amplitude: magnitude * (index.isMultiple(of: 2) ? firstDirection : -firstDirection)
            )
        }
    }

    static func correctionOffset(at time: TimeInterval, corrections: [BirdLeaderCorrection]) -> Double {
        corrections.reduce(0) { $0 + $1.offset(at: time) }
    }

    static func correctionVelocity(at time: TimeInterval, corrections: [BirdLeaderCorrection]) -> Double {
        corrections.reduce(0) { $0 + $1.velocity(at: time) }
    }

    static func response(
        for agent: BirdAgent,
        time: TimeInterval,
        configuration: BirdFlockConfiguration,
        corrections: [BirdLeaderCorrection],
        velocity: Bool
    ) -> Double {
        let rowDepth = max(0, Int((-agent.slotX / (configuration.bodyLength * 1.82)).rounded(.toNearestOrAwayFromZero)))
        guard rowDepth <= 2 else { return 0 }
        let gain = rowDepth == 0 ? 1.0 : rowDepth == 1 ? 0.55 : 0.28
        let delay = rowDepth == 0 ? 0
            : rowDepth == 1 ? 0.30 + Double(agent.id) * 0.025
            : 0.58 + Double(agent.id) * 0.018
        let sampleTime = time - delay
        return gain * (velocity
            ? correctionVelocity(at: sampleTime, corrections: corrections)
            : correctionOffset(at: sampleTime, corrections: corrections))
    }

    static func target(
        for agent: BirdAgent,
        guide: BirdRouteGuide,
        time: TimeInterval,
        configuration: BirdFlockConfiguration,
        corrections: [BirdLeaderCorrection]
    ) -> Target {
        let breath = 1 + 0.035 * sin(time * 0.62 + agent.breathPhase)
        let drift = sin(time * 0.47 + agent.driftPhase) * configuration.bodyLength * 0.17
        return Target(
            x: guide.x + agent.slotX * breath,
            y: guide.y + agent.slotY * breath + drift
                + response(for: agent, time: time, configuration: configuration, corrections: corrections, velocity: false),
            correctionVelocityY: response(
                for: agent,
                time: time,
                configuration: configuration,
                corrections: corrections,
                velocity: true
            )
        )
    }
}
