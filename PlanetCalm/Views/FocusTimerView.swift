import SwiftUI

struct FocusTimerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let session: FocusSession
    private let player: StoryPlayer
    @State private var showsAbandonConfirmation = false

    init(session: FocusSession) {
        self.session = session
        self.player = StoryPlayer(session: session)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let performance = player.performance(at: context.date, reduceMotion: reduceMotion)
            let elapsed = session.elapsedTime(at: context.date)

            ZStack {
                StorySceneCatalog.scene(
                    for: session.story,
                    context: StorySceneRenderContext(
                        progress: session.progress(at: context.date),
                        elapsedTime: elapsed,
                        referenceDate: context.date,
                        performance: performance,
                        reduceMotion: reduceMotion,
                        showsFocusUI: false
                    )
                )
                .ignoresSafeArea()

                VStack(spacing: 8) {
                    Text(timeString(remaining: session.remainingTime(at: context.date)))
                        .font(.system(size: 64, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel("\(Int(session.remainingTime(at: context.date))) seconds remaining")

                    Text(performance.beat.displayName)
                        .font(.subheadline)
                }
                .foregroundStyle(Color(red: 0.33, green: 0.20, blue: 0.12))
                .padding(22)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(session.story.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End") { showsAbandonConfirmation = true }
                }
            }
        }
        .alert("End this story?", isPresented: $showsAbandonConfirmation) {
            Button("Keep focusing", role: .cancel) {}
            Button("End without credit", role: .destructive) { model.abandonSession() }
        } message: {
            Text("This story will restart next time and no focus minutes will be recorded.")
        }
    }

    private func timeString(remaining: TimeInterval) -> String {
        let wholeSeconds = max(Int(remaining.rounded(.up)), 0)
        return String(format: "%02d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }
}

private extension StoryBeatID {
    var displayName: String {
        rawValue.split(separator: ".").last.map(String.init)?.capitalized ?? rawValue
    }
}
