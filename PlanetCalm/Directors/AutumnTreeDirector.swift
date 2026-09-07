import Foundation

struct AutumnTreeDirector: StoryDirector {
    func makePlan(for session: StorySessionContext) -> StoryPlan {
        StoryPlan(moments: [
            authoredMoment(
                id: .autumnBirdFlock,
                effect: .autumnBirdFlock,
                progressWindow: AutumnCastSchedule.birdProgressWindow,
                duration: AutumnCastSchedule.birdDuration,
                seedStream: "autumn-tree.bird-flock.v2",
                session: session,
                audioCue: StoryAudioCue(assetID: "autumn-bird-flock-intent", bus: .birds, gain: 0.18)
            ),
            authoredMoment(
                id: .autumnRabbitPeek,
                effect: .autumnRabbitPeek,
                progressWindow: AutumnCastSchedule.rabbitProgressWindow,
                duration: AutumnCastSchedule.rabbitDuration,
                seedStream: "autumn-tree.rabbit-peek.v1",
                session: session
            )
        ].compactMap { $0 })
    }

    func performance(at context: StoryContext, plan: StoryPlan) -> StoryPerformance {
        let clampedProgress = min(max(context.progress, 0), 1)
        let beat: StoryBeatID

        switch clampedProgress {
        case ..<0.10: beat = .autumnWaking
        case ..<0.35: beat = .autumnGathering
        case ..<0.65: beat = .autumnAlive
        case ..<0.85: beat = .autumnSettling
        case ..<0.96: beat = .autumnOpening
        case ..<1: beat = .autumnReveal
        default: beat = .autumnResting
        }

        let leafIntensity = context.reduceMotion ? 0 : leafIntensity(for: beat)
        let showsDeer = beat == .autumnReveal || beat == .autumnResting
        let visualState = StoryVisualState(
            channels: [.autumnLeafIntensity: leafIntensity],
            flags: showsDeer ? [.autumnDeerVisible] : []
        )
        let activeMoments = plan.moments.filter { $0.isActive(at: context.elapsedTime) }
        return StoryPerformance(
            beat: beat,
            visualState: visualState,
            activeMoments: activeMoments
        )
    }

    private func leafIntensity(for beat: StoryBeatID) -> Double {
        switch beat {
        case .autumnWaking: 0.15
        case .autumnGathering: 0.45
        case .autumnAlive: 0.8
        case .autumnSettling: 0.35
        case .autumnOpening: 0.1
        default: 0.05
        }
    }

    /// Required authored moments select a bounded onset, not a probability roll.
    /// The latest possible onset subtracts the full event duration, so the
    /// occurrence can never escape its narrative window.
    private func authoredMoment(
        id: StoryMomentID,
        effect: StoryEffectID,
        progressWindow: ClosedRange<Double>,
        duration: TimeInterval,
        seedStream: String,
        session: StorySessionContext,
        audioCue: StoryAudioCue? = nil
    ) -> StoryMoment? {
        guard session.duration > 0 else { return nil }
        let windowStart = session.duration * progressWindow.lowerBound
        let windowEnd = session.duration * progressWindow.upperBound
        let latestStart = windowEnd - duration
        guard latestStart >= windowStart else { return nil }

        var random = SeededRandomNumberGenerator(
            seed: session.randomSeed ^ StableSeed.hash(seedStream)
        )
        let onset = latestStart == windowStart
            ? windowStart
            : windowStart + (latestStart - windowStart) * random.unitInterval()
        let eventSeed = random.next()
        return StoryMoment(
            id: id,
            startTime: onset,
            duration: duration,
            intensity: 1,
            randomSeed: eventSeed,
            quantization: .none,
            visualCue: StoryVisualCue(effect: effect),
            audioCue: audioCue
        )
    }
}

enum AutumnCastSchedule {
    static let birdProgressWindow = 0.35...0.65
    static let birdDuration: TimeInterval = 18
    static let rabbitProgressWindow = 0.70...0.84
    static let rabbitDuration: TimeInterval = 8
}

extension StoryBeatID {
    static let autumnWaking = StoryBeatID(rawValue: "autumn-tree.waking")
    static let autumnGathering = StoryBeatID(rawValue: "autumn-tree.gathering")
    static let autumnAlive = StoryBeatID(rawValue: "autumn-tree.alive")
    static let autumnSettling = StoryBeatID(rawValue: "autumn-tree.settling")
    static let autumnOpening = StoryBeatID(rawValue: "autumn-tree.opening")
    static let autumnReveal = StoryBeatID(rawValue: "autumn-tree.reveal")
    static let autumnResting = StoryBeatID(rawValue: "autumn-tree.resting")
}

extension StoryVisualChannelID {
    static let autumnLeafIntensity = StoryVisualChannelID(rawValue: "autumn-tree.leaf-intensity")
}

extension StoryVisualFlagID {
    static let autumnDeerVisible = StoryVisualFlagID(rawValue: "autumn-tree.deer-visible")
}

extension StoryEffectID {
    static let autumnRabbitPeek = StoryEffectID(rawValue: "autumn-tree.rabbit-peek")
    static let autumnBirdFlock = StoryEffectID(rawValue: "autumn-tree.bird-flock")
}

extension StoryMomentID {
    static let autumnRabbitPeek = StoryMomentID(rawValue: "autumn-tree.rabbit-peek")
    static let autumnBirdFlock = StoryMomentID(rawValue: "autumn-tree.bird-flock")
}
