import SwiftUI

/// Renderer input is deliberately separate from StoryDirector. The Director
/// produces performance; each story-owned renderer decides how to depict it.
struct StorySceneRenderContext: Equatable {
    let progress: Double
    let elapsedTime: TimeInterval
    let performance: StoryPerformance
    let reduceMotion: Bool
    var duration: TimeInterval = 120
    var randomSeed: UInt64 = 42
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
