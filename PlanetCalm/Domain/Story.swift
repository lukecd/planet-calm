import Foundation

enum Story: String, CaseIterable, Identifiable, Codable, Sendable {
    case autumnTree
    case contemporaryLotus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autumnTree: "Autumn Tree"
        case .contemporaryLotus: "Contemporary Lotus"
        }
    }

    var subtitle: String {
        switch self {
        case .autumnTree: "A quiet clearing in a soft breeze"
        case .contemporaryLotus: "Two lights on still water"
        }
    }
}

/// Whole-minute public choices, with the original seconds-based Codable format.
struct FocusDuration: RawRepresentable, Hashable, CaseIterable, Identifiable, Codable, Sendable {
    static let minuteRange = 5...55
    let rawValue: Int

    init?(minutes: Int) {
        guard Self.minuteRange.contains(minutes) else { return nil }
        rawValue = minutes * 60
    }

    init?(rawValue: Int) {
        guard rawValue % 60 == 0 else { return nil }
        let minutes = rawValue / 60
        #if DEBUG
        guard Self.minuteRange.contains(minutes) || minutes == 1 || minutes == 2 else { return nil }
        #else
        guard Self.minuteRange.contains(minutes) else { return nil }
        #endif
        self.rawValue = rawValue
    }

    private init(seconds: Int) { rawValue = seconds }
    static let fiveMinutes = Self(seconds: 300)
    static let tenMinutes = Self(seconds: 600)
    static let fifteenMinutes = Self(seconds: 900)
    static let twentyFiveMinutes = Self(seconds: 1_500)
    static let fiftyMinutes = Self(seconds: 3_000)

    #if DEBUG
    static let oneMinute = Self(seconds: 60)
    static let twoMinutes = Self(seconds: 120)
    #endif

    static let `default`: FocusDuration = .twentyFiveMinutes

    var id: Int { rawValue }
    var minutes: Int { rawValue / 60 }

    /// Wider landing zones around five-minute marks, without losing any whole minute.
    /// Accessibility adjustment bypasses the touch mapping and always steps by one.
    static func minutes(at fraction: Double) -> Int {
        guard fraction.isFinite else { return minuteRange.lowerBound }
        let rawMinutes = Double(minuteRange.lowerBound) + min(1, max(0, fraction)) * 50
        let fiveMinuteMark = (rawMinutes / 5).rounded() * 5
        let snapRadius = 0.7
        return Int(abs(rawMinutes - fiveMinuteMark) <= snapRadius
            ? fiveMinuteMark : rawMinutes.rounded())
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let seconds = try container.decode(Int.self)
        guard let duration = Self(rawValue: seconds) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid whole-minute focus duration")
        }
        self = duration
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var timeInterval: TimeInterval {
        TimeInterval(rawValue)
    }

    var title: String {
        "\(rawValue / 60) min"
    }

    static var available: [FocusDuration] {
        #if DEBUG
        [.oneMinute, .twoMinutes] + minuteRange.compactMap { Self(minutes: $0) }
        #else
        minuteRange.compactMap { Self(minutes: $0) }
        #endif
    }
    static var allCases: [Self] { available }
}
