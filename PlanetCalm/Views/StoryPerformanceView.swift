import SwiftUI

/// Temporary structural placeholder. Production paper-cut assets replace this view.
struct StoryPerformanceView: View {
    let performance: StoryPerformance

    var body: some View {
        ContentUnavailableView {
            Label("Autumn Tree", systemImage: "leaf")
        } description: {
            Text(description)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .accessibilityLabel("Autumn Tree story, \(performance.beat.rawValue) beat")
    }

    private var description: String {
        switch performance.beat {
        case .autumnWaking: "The clearing is waking."
        case .autumnGathering: "Leaves are beginning to drift."
        case .autumnAlive: "The clearing is alive."
        case .autumnSettling: "The wind is settling."
        case .autumnOpening: "The hills grow quiet."
        case .autumnReveal: "A deer steps into the clearing."
        case .autumnResting: "The story is resting."
        default: "The story continues."
        }
    }
}
