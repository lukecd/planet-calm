import Foundation

struct StoryPlayer {
    let session: FocusSession

    private let director: any StoryDirector
    private let plan: StoryPlan

    /// Immutable schedule for renderer reconciliation, including past/future identities.
    var scheduledMoments: [StoryMoment] { plan.moments }

    init(session: FocusSession, module: (any StoryModule)? = nil) {
        let resolvedModule = module ?? StoryCatalog.module(for: session.story)
        precondition(resolvedModule.story == session.story)

        let director = resolvedModule.makeDirector()
        self.session = session
        self.director = director
        self.plan = director.makePlan(
            for: StorySessionContext(
                duration: session.duration.timeInterval,
                randomSeed: session.randomSeed
            )
        )
    }

    func performance(at date: Date, reduceMotion: Bool) -> StoryPerformance {
        let elapsedTime = session.elapsedTime(at: date)
        let context = StoryContext(
            progress: session.progress(at: date),
            elapsedTime: elapsedTime,
            duration: session.duration.timeInterval,
            reduceMotion: reduceMotion
        )
        return director.performance(at: context, plan: plan)
    }

    func moments(startingAfter previousDate: Date, through date: Date) -> [StoryMoment] {
        let lowerBound = session.elapsedTime(at: previousDate)
        let upperBound = session.elapsedTime(at: date)
        guard upperBound >= lowerBound else { return [] }

        return plan.moments.filter {
            $0.startTime > lowerBound && $0.startTime <= upperBound
        }
    }
}
