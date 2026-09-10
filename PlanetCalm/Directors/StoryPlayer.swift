import Foundation

struct StoryPlayer {
    let session: FocusSession

    private let director: any StoryDirector
    private let plan: StoryPlan

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
        performance(atElapsedTime: session.elapsedTime(at: date), reduceMotion: reduceMotion)
    }

    /// Shared-transport entry point; never reconstruct a second date-based clock.
    func performance(atElapsedTime elapsedTime: Double, reduceMotion: Bool) -> StoryPerformance {
        let context = StoryContext(
            progress: min(max(elapsedTime / session.duration.timeInterval, 0), 1),
            elapsedTime: elapsedTime,
            duration: session.duration.timeInterval,
            reduceMotion: reduceMotion
        )
        return director.performance(at: context, plan: plan)
    }

}
