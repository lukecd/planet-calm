import Foundation

/// The scene-independent, authoritative transport for a generative performance.
/// It owns only in-memory timing and the seed. Directors own their creative plans;
/// renderers and audio schedulers sample the same state and never advance it.
/// Pause/Codable support is for development controls and deterministic tests;
/// production sessions are never saved or restored across process launches.
struct PerformanceSession: Equatable, Codable, Sendable {
    /// Identity belongs to the session lifecycle and survives every live transport
    /// conversion. Existing previews may still create an unpersisted session.
    let id: UUID
    let duration: FocusDuration
    let startedAt: Date
    let randomSeed: UInt64
    private(set) var pausedAt: Date? = nil
    private(set) var accumulatedPause: TimeInterval = 0

    init(
        id: UUID = UUID(),
        duration: FocusDuration,
        startedAt: Date = .now,
        randomSeed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)
    ) {
        self.id = id
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
        startedAt.addingTimeInterval(duration.timeInterval + accumulatedPause)
    }

    func elapsedTime(at date: Date) -> TimeInterval {
        min(max((pausedAt ?? date).timeIntervalSince(startedAt) - accumulatedPause, 0), duration.timeInterval)
    }

    func progress(at date: Date) -> Double {
        min(max(elapsedTime(at: date) / duration.timeInterval, 0), 1)
    }

    func remainingTime(at date: Date) -> TimeInterval {
        max(duration.timeInterval - elapsedTime(at: date), 0)
    }

    var isPaused: Bool { pausedAt != nil }

    mutating func pause(at date: Date) {
        guard pausedAt == nil, progress(at: date) < 1 else { return }
        pausedAt = max(date, startedAt)
    }

    mutating func resume(at date: Date) {
        guard let pausedAt else { return }
        accumulatedPause += max(date.timeIntervalSince(pausedAt), 0)
        self.pausedAt = nil
    }

    func focusSession(for story: Story) -> FocusSession {
        FocusSession(
            story: story,
            duration: duration,
            startedAt: startedAt.addingTimeInterval(accumulatedPause),
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
