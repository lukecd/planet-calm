import Foundation

struct RandomMomentRule: Sendable {
    let id: String
    let progressWindow: ClosedRange<Double>
    let evaluationInterval: ClosedRange<TimeInterval>
    let triggerChance: Double
    let cooldown: ClosedRange<TimeInterval>
    let duration: ClosedRange<TimeInterval>
    let intensity: ClosedRange<Double>
    let quantization: StoryMomentQuantization
    let visualEffect: StoryEffectID?
    let audioCue: StoryAudioCue?

    init(
        id: String,
        progressWindow: ClosedRange<Double>,
        evaluationInterval: ClosedRange<TimeInterval>,
        triggerChance: Double,
        cooldown: ClosedRange<TimeInterval>,
        duration: ClosedRange<TimeInterval>,
        intensity: ClosedRange<Double>,
        quantization: StoryMomentQuantization = .none,
        visualEffect: StoryEffectID? = nil,
        audioCue: StoryAudioCue? = nil
    ) {
        precondition(!id.isEmpty)
        precondition(progressWindow.lowerBound >= 0 && progressWindow.upperBound <= 1)
        precondition(evaluationInterval.lowerBound > 0)
        precondition(cooldown.lowerBound >= 0)
        precondition(duration.lowerBound > 0)
        precondition(intensity.lowerBound >= 0 && intensity.upperBound <= 1)

        self.id = id
        self.progressWindow = progressWindow
        self.evaluationInterval = evaluationInterval
        self.triggerChance = min(max(triggerChance, 0), 1)
        self.cooldown = cooldown
        self.duration = duration
        self.intensity = intensity
        self.quantization = quantization
        self.visualEffect = visualEffect
        self.audioCue = audioCue
    }
}

struct RandomMomentScheduler {
    func moments(for rule: RandomMomentRule, session: StorySessionContext) -> [StoryMoment] {
        guard session.duration > 0 else { return [] }

        let seed = session.randomSeed ^ StableSeed.hash(rule.id)
        var generator = SeededRandomNumberGenerator(seed: seed)
        let windowStart = session.duration * rule.progressWindow.lowerBound
        let windowEnd = session.duration * rule.progressWindow.upperBound
        var evaluationTime = windowStart
        var nextAllowedTime = windowStart
        var evaluationIndex = 0
        var moments: [StoryMoment] = []

        while evaluationTime < windowEnd {
            evaluationTime += random(in: rule.evaluationInterval, using: &generator)
            guard evaluationTime <= windowEnd else { break }

            let roll = randomUnit(using: &generator)
            defer { evaluationIndex += 1 }

            guard roll < rule.triggerChance, evaluationTime >= nextAllowedTime else {
                continue
            }

            let eventSeed = generator.next()
            let eventDuration = random(in: rule.duration, using: &generator)
            let eventIntensity = random(in: rule.intensity, using: &generator)
            let direction = random(in: -1.0...1.0, using: &generator)
            let moment = StoryMoment(
                id: StoryMomentID(rawValue: "\(rule.id)-\(evaluationIndex)"),
                startTime: evaluationTime,
                duration: eventDuration,
                intensity: eventIntensity,
                randomSeed: eventSeed,
                quantization: rule.quantization,
                visualCue: rule.visualEffect.map { StoryVisualCue(effect: $0, direction: direction) },
                audioCue: rule.audioCue
            )
            moments.append(moment)
            nextAllowedTime = evaluationTime + random(in: rule.cooldown, using: &generator)
        }

        return moments
    }

    private func random(
        in range: ClosedRange<Double>,
        using generator: inout SeededRandomNumberGenerator
    ) -> Double {
        guard range.lowerBound != range.upperBound else { return range.lowerBound }
        return range.lowerBound + (range.upperBound - range.lowerBound) * randomUnit(using: &generator)
    }

    private func randomUnit(using generator: inout SeededRandomNumberGenerator) -> Double {
        generator.unitInterval()
    }
}
