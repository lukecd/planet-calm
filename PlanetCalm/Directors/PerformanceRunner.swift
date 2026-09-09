import Foundation

/// The scene-independent, authoritative transport for a generative performance.
/// It owns only persistent timing and the seed. Directors own their creative plans;
/// renderers and audio schedulers sample the same state and never advance it.
struct PerformanceSession: Equatable, Codable, Sendable {
    let duration: FocusDuration
    let startedAt: Date
    let randomSeed: UInt64

    init(
        duration: FocusDuration,
        startedAt: Date = .now,
        randomSeed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)
    ) {
        self.duration = duration
        self.startedAt = startedAt
        self.randomSeed = randomSeed
    }

    init(focusSession: FocusSession) {
        self.init(
            duration: focusSession.duration,
            startedAt: focusSession.startedAt,
            randomSeed: focusSession.randomSeed
        )
    }

    var endDate: Date {
        startedAt.addingTimeInterval(duration.timeInterval)
    }

    func elapsedTime(at date: Date) -> TimeInterval {
        min(max(date.timeIntervalSince(startedAt), 0), duration.timeInterval)
    }

    func progress(at date: Date) -> Double {
        min(max(elapsedTime(at: date) / duration.timeInterval, 0), 1)
    }

    func remainingTime(at date: Date) -> TimeInterval {
        max(endDate.timeIntervalSince(date), 0)
    }

    func focusSession(for story: Story) -> FocusSession {
        FocusSession(
            story: story,
            duration: duration,
            startedAt: startedAt,
            randomSeed: randomSeed
        )
    }
}

struct PerformanceState: Equatable, Sendable {
    let elapsedTime: TimeInterval
    let progress: Double
    let remainingTime: TimeInterval
    let isComplete: Bool
}

/// The sole sampler for a running performance. It intentionally has no mutable
/// playback position: suspending and resuming derives the correct state from date.
struct PerformanceRunner: Equatable, Sendable {
    let session: PerformanceSession

    func sample(at date: Date) -> PerformanceState {
        let elapsedTime = session.elapsedTime(at: date)
        let progress = session.progress(at: date)
        return PerformanceState(
            elapsedTime: elapsedTime,
            progress: progress,
            remainingTime: session.remainingTime(at: date),
            isComplete: progress >= 1
        )
    }
}
