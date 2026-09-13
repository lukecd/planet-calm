import Foundation

/// Semantic composition cues only. No Autumn recording is selected or played
/// until the animation score has been refined and authored audio returns.
enum AutumnAudioScore {
    static func score(for plan: AutumnBranchPlan) -> StoryAudioScore {
        var cues: [StoryAudioScore.Cue] = []

        for (index, moment) in plan.gusts.enumerated() {
            cues.append(.init(id: "autumn.breeze.\(index)", phase: "passage",
                              startTime: moment.startTime, duration: moment.duration,
                              bus: .atmosphere, intensity: moment.intensity,
                              direction: plan.windPassages[index].direction.x,
                              sourceMomentID: moment.id))
        }

        for moment in plan.leafReleases {
            cues.append(.init(id: moment.id.rawValue, phase: "release",
                              startTime: moment.startTime, duration: 0,
                              bus: .leaves, intensity: moment.intensity,
                              direction: moment.visualCue?.direction,
                              sourceMomentID: moment.id))
        }

        for flight in plan.encounters.birds {
            let moment = flight.moment
            let landing = flight.startTime + flight.approachDuration
            let departure = landing + flight.perchDuration
            cues.append(.init(id: "\(moment.id.rawValue).approach", phase: "approach",
                              startTime: flight.startTime, duration: flight.approachDuration,
                              bus: .birds, intensity: 1, direction: nil,
                              sourceMomentID: moment.id))
            cues.append(.init(id: "\(moment.id.rawValue).landing", phase: "landing",
                              startTime: landing, duration: 0, bus: .birds,
                              intensity: 1, direction: nil, sourceMomentID: moment.id))
            cues.append(.init(id: "\(moment.id.rawValue).perch", phase: "perch",
                              startTime: landing, duration: flight.perchDuration,
                              bus: .birds, intensity: 0.6, direction: nil,
                              sourceMomentID: moment.id))
            cues.append(.init(id: "\(moment.id.rawValue).departure", phase: "departure",
                              startTime: departure, duration: flight.departureDuration,
                              bus: .birds, intensity: 1, direction: nil,
                              sourceMomentID: moment.id))
        }

        let deer = plan.deerEnding
        let deerMoment = deer.moment
        let listening = deer.startTime + deer.walkDuration
        let settling = listening + deer.standingDuration
        cues.append(.init(id: "autumn.deer.approach", phase: "approach",
                          startTime: deer.startTime, duration: deer.walkDuration,
                          bus: .animals, intensity: 0.8, direction: -1,
                          sourceMomentID: deerMoment.id))
        cues.append(.init(id: "autumn.deer.listening", phase: "listening",
                          startTime: listening, duration: deer.standingDuration,
                          bus: .animals, intensity: 0.25, direction: nil,
                          sourceMomentID: deerMoment.id))
        cues.append(.init(id: "autumn.deer.settling", phase: "settling",
                          startTime: settling, duration: deer.settlingDuration,
                          bus: .animals, intensity: 0.55, direction: nil,
                          sourceMomentID: deerMoment.id))
        cues.append(.init(id: "autumn.deer.rest", phase: "rest",
                          startTime: deer.restingTime,
                          duration: max(0, plan.duration - deer.restingTime),
                          bus: .animals, intensity: 0.1, direction: nil,
                          sourceMomentID: deerMoment.id))

        return StoryAudioScore(storyID: Story.autumnTree.rawValue, duration: plan.duration,
                               seed: plan.seed, cues: cues.sorted(by: cueOrder),
                               midi: .empty(duration: plan.duration))
    }

    private static func cueOrder(_ lhs: StoryAudioScore.Cue,
                                 _ rhs: StoryAudioScore.Cue) -> Bool {
        lhs.startTime == rhs.startTime ? lhs.id < rhs.id : lhs.startTime < rhs.startTime
    }
}
