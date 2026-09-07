import Foundation

struct FocusSession: Equatable, Codable {
    let story: Story
    let duration: FocusDuration
    let startedAt: Date
    let randomSeed: UInt64

    init(
        story: Story,
        duration: FocusDuration,
        startedAt: Date,
        randomSeed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)
    ) {
        self.story = story
        self.duration = duration
        self.startedAt = startedAt
        self.randomSeed = randomSeed
    }

    var endDate: Date {
        startedAt.addingTimeInterval(TimeInterval(duration.rawValue))
    }

    func progress(at date: Date) -> Double {
        min(max(elapsedTime(at: date) / duration.timeInterval, 0), 1)
    }

    func elapsedTime(at date: Date) -> TimeInterval {
        min(max(date.timeIntervalSince(startedAt), 0), duration.timeInterval)
    }

    func remainingTime(at date: Date) -> TimeInterval {
        max(endDate.timeIntervalSince(date), 0)
    }

    func isComplete(at date: Date) -> Bool {
        progress(at: date) >= 1
    }
}
