import ActivityKit
import Foundation

/// The minimal information the app and Live Activity extension share. The displayed
/// countdown is driven by `scheduledEndAt`; it is not a second session clock.
struct PlanetFocusCountdownAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let scheduledEndAt: Date
    }

    let sessionID: UUID
    let storyTitle: String
}

struct PlanetFocusCountdownDescriptor: Equatable, Sendable {
    let sessionID: UUID
    let storyTitle: String
    let scheduledEndAt: Date
}

/// A Live Activity needs a wall-clock range for the system-rendered timer. This
/// helper makes expiry safe at the exact boundary rather than ever constructing
/// an invalid range.
enum PlanetFocusCountdownDisplay {
    static func timerInterval(
        endingAt endDate: Date,
        now: Date = .now
    ) -> ClosedRange<Date>? {
        guard endDate > now else { return nil }
        return now...endDate
    }
}
