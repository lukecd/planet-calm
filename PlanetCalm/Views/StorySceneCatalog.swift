import SwiftUI

/// Renderer input is deliberately separate from StoryDirector. The Director
/// produces performance; each story-owned renderer decides how to depict it.
struct StorySceneRenderContext: Equatable {
    let progress: Double
    let elapsedTime: TimeInterval
    let performance: StoryPerformance
    let reduceMotion: Bool
    let duration: TimeInterval
    let randomSeed: UInt64
    let storyPlan: StoryPlan?

    init(progress: Double, elapsedTime: TimeInterval, performance: StoryPerformance,
         reduceMotion: Bool, duration: TimeInterval = 120, randomSeed: UInt64 = 42,
         storyPlan: StoryPlan? = nil) {
        self.progress = progress
        self.elapsedTime = elapsedTime
        self.performance = performance
        self.reduceMotion = reduceMotion
        self.duration = duration
        self.randomSeed = randomSeed
        self.storyPlan = storyPlan
    }
}

@MainActor
enum StorySceneCatalog {
    @ViewBuilder
    static func scene(for story: Story, context: StorySceneRenderContext) -> some View {
        switch story {
        case .autumnTree:
            AutumnBranchSnapshotView(context: context)

        case .contemporaryLotus:
            ContemporaryLotusStageView(context: context)
        }
    }
}
