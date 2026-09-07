import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var activeSession: FocusSession?
    @Published var selectedStory: Story = .autumnTree
    @Published var selectedDuration: FocusDuration = .default

    var isFocusing: Bool { activeSession?.isComplete(at: .now) == false }

    func startSession(at date: Date = .now) {
        activeSession = FocusSession(story: selectedStory, duration: selectedDuration, startedAt: date)
    }

    func abandonSession() {
        activeSession = nil
    }
}
