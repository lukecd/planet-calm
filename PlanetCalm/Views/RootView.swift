import SwiftUI

struct RootView: View {
    @State private var selectedStory: Story = .autumnTree

    var body: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--contemporary-lotus-review") {
            ContemporaryLotusReviewView()
        } else {
            SplashScreenView(selectedStory: $selectedStory)
        }
#else
        SplashScreenView(selectedStory: $selectedStory)
#endif
    }
}
