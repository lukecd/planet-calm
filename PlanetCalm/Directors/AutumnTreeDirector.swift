import Foundation

struct AutumnTreeDirector: StoryDirector {
    func makePlan(for session: StorySessionContext) -> StoryPlan {
        let plan = AutumnBranchPlan(
            duration: session.duration, seed: session.randomSeed,
            tuning: .standard, isFullTree: true)
        return StoryPlan(
            moments: plan.gusts + plan.encounters.birds.map(\.moment)
                + [plan.deerEnding.moment])
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
        let ending = plan.moments.first { $0.id.rawValue == "autumn.deer.ending" }
        let showsDeer = ending.map { context.elapsedTime >= $0.startTime } ?? false
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

/// Creative policy on top of the shared random scheduler. Decisions are made once
/// per session, never on render frames. Quiet is a real outcome, not a retry loop.
struct AutumnEncounterSchedule: Equatable {
    enum Kind: String { case breeze, bird, quiet }
    struct Decision: Equatable {
        let time: Double
        let kind: Kind
    }
    let decisions: [Decision]
    let breezeTimes: [Double]
    let birds: [AutumnOrigamiFlight]

    init(duration: Double, seed: UInt64, deer: AutumnDeerEncounter, gustDuration: Double = 8) {
        // Short development previews compress decision spacing, never animal motion.
        let previewScale = min(1, max(0.25, duration / 300))
        let opportunities = RandomMomentScheduler().moments(
            for: RandomMomentRule(
                id: "autumn.encounters.v1", progressWindow: 0...1,
                evaluationInterval: (22 * previewScale)...(44 * previewScale),
                triggerChance: 1, cooldown: 0...0, duration: 1...1, intensity: 1...1),
            session: StorySessionContext(duration: duration, randomSeed: seed))
        var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("autumn.choices.v1"))
        var choices: [Decision] = []
        var breezes: [Double] = []
        var flights: [AutumnOrigamiFlight] = []
        var nextBird = 0.0
        var nextAction = 0.0
        let breezeClearance = max(18, gustDuration * 1.3 + 6)
        // No bird can trespass into the closing act, including its departure.
        let birdDeadline = min(duration * 0.82, deer.startTime - 8)
        for opportunity in opportunities {
            let time = opportunity.startTime
            let roll = random.unitInterval()
            var kind = Kind.quiet
            if time >= nextAction && time < deer.startTime - breezeClearance {
                if roll < 0.50 {
                    kind = .breeze
                    breezes.append(time)
                    // Includes the spatial gust's travel across the tree.
                    nextAction = time + breezeClearance
                } else if roll < 0.72 && time >= nextBird {
                    var tuning = AutumnBirdTuning()
                    tuning.speed = random.value(in: 0.92...1.08)
                    tuning.wingbeat = random.value(in: 1.4...1.7)
                    tuning.depth = random.value(in: 0.9...1.15)
                    tuning.perchSeconds = random.value(in: 4...9)
                    let flight = AutumnOrigamiFlight(
                        startTime: time, seed: random.next(), tuning: tuning)
                    if time + flight.duration <= birdDeadline {
                        kind = .bird
                        flights.append(flight)
                        nextAction = time + flight.duration + 8
                        nextBird = time + flight.duration + random.value(in: 90...170)
                    }
                }
            }
            choices.append(Decision(time: time, kind: kind))
        }
        // One quiet closing breeze is authored, like the deer: randomness must not
        // erase the leaf-bed ending. In short previews it overlaps the final rest;
        // normal sessions have enough time for its full spatial passage to fade.
        let closingJitter = random.value(in: 0...min(2, max(0, duration * 0.005)))
        let latestBreeze =
            duration >= 300 ? duration - breezeClearance : duration - 10 + closingJitter
        let lastBreeze = min(latestBreeze, max(duration * 0.88, deer.restingTime) + closingJitter)
        breezes.append(max(0, lastBreeze))
        decisions = choices
        breezeTimes = breezes
        birds = flights
    }

    func bird(at time: Double, manual: AutumnOrigamiFlight? = nil) -> AutumnOrigamiFlight? {
        if let manual, manual.moment.isActive(at: time) { return manual }
        return birds.first { flight in
            guard flight.moment.isActive(at: time) else { return false }
            // A manual study replaces an overlapping visit completely; do not
            // materialize halfway through that automatic flight afterward.
            if let manual {
                return flight.startTime >= manual.startTime + manual.duration + 8
                    || flight.startTime + flight.duration + 8 <= manual.startTime
            }
            return true
        }
    }
}
