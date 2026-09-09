import SwiftUI

/// Renderer input is deliberately separate from StoryDirector. The Director
/// produces performance; each story-owned renderer decides how to depict it.
struct StorySceneRenderContext: Equatable {
    let progress: Double
    let elapsedTime: TimeInterval
    let referenceDate: Date
    let performance: StoryPerformance
    let reduceMotion: Bool
    let showsFocusUI: Bool
}

@MainActor
enum StorySceneCatalog {
    @ViewBuilder
    static func scene(for story: Story, context: StorySceneRenderContext) -> some View {
        switch story {
        case .autumnTree:
            AutumnTreeSceneView(
                progress: context.progress,
                elapsedTime: context.elapsedTime,
                referenceDate: context.referenceDate,
                performance: context.performance,
                reduceMotion: context.reduceMotion,
                showsFocusUI: context.showsFocusUI
            )

        case .contemporaryLotus:
            ContemporaryLotusStageView(context: context)
        }
    }
}
