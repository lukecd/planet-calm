import SwiftUI

struct RootView: View {
    @State private var selectedStory: Story = .autumnTree

    var body: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--contemporary-lotus-review") {
            ContemporaryLotusReviewView()
        } else if ProcessInfo.processInfo.arguments.contains("--autumn-cast-review") {
            AutumnCastReviewView()
        } else if ProcessInfo.processInfo.arguments.contains(where: {
            $0.hasPrefix("--gate1") || $0.hasPrefix("--gate2") || $0.hasPrefix("--gate3")
                || $0.hasPrefix("--gate4") || $0 == "--single-leaf-baselines"
        }) {
            LeafGravityLabView()
        } else if ProcessInfo.processInfo.arguments.contains(where: {
            $0.hasPrefix("--gate5") || $0.hasPrefix("--group")
        }) {
            LeafGroupLabView()
        } else {
            SplashScreenView(selectedStory: $selectedStory)
        }
#else
        SplashScreenView(selectedStory: $selectedStory)
#endif
    }
}
