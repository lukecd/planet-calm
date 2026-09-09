import Foundation

enum Story: String, CaseIterable, Identifiable, Codable {
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

enum FocusDuration: Int, CaseIterable, Identifiable, Codable {
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case twentyFiveMinutes = 1_500
    case fiftyMinutes = 3_000

    #if DEBUG
    case oneMinute = 60
    case twoMinutes = 120
    #endif

    static let `default`: FocusDuration = .twentyFiveMinutes

    var id: Int { rawValue }

    var timeInterval: TimeInterval {
        TimeInterval(rawValue)
    }

    var title: String {
        "\(rawValue / 60) min"
    }

    static var available: [FocusDuration] {
        #if DEBUG
        [.oneMinute, .twoMinutes, .fiveMinutes, .tenMinutes, .fifteenMinutes, .twentyFiveMinutes, .fiftyMinutes]
        #else
        [.fiveMinutes, .tenMinutes, .fifteenMinutes, .twentyFiveMinutes, .fiftyMinutes]
        #endif
    }
}
