import Foundation

/// Story-owned narrative state for the Contemporary Lotus scene. The first
/// native milestone is intentionally static; its alternating blooms will be
/// introduced as authored moments only after the pond stage is accepted.
struct ContemporaryLotusDirector: StoryDirector {
    func makePlan(for session: StorySessionContext) -> StoryPlan {
        .empty
    }

    func performance(at context: StoryContext, plan: StoryPlan) -> StoryPerformance {
        StoryPerformance(
            beat: .contemporaryLotusPondStill,
            visualState: StoryVisualState(flags: [.contemporaryLotusPondStage]),
            activeMoments: []
        )
    }
}

extension StoryBeatID {
    static let contemporaryLotusPondStill = StoryBeatID(rawValue: "contemporary-lotus.pond-still")
}

extension StoryVisualFlagID {
    static let contemporaryLotusPondStage = StoryVisualFlagID(rawValue: "contemporary-lotus.pond-stage")
}
