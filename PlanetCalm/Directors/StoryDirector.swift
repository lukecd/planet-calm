import Foundation

struct StoryBeatID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct StoryEffectID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct StoryVisualChannelID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct StoryVisualFlagID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct StoryVisualState: Equatable, Sendable {
    private let channels: [StoryVisualChannelID: Double]
    private let flags: Set<StoryVisualFlagID>

    init(
        channels: [StoryVisualChannelID: Double] = [:],
        flags: Set<StoryVisualFlagID> = []
    ) {
        self.channels = channels.mapValues { min(max($0, 0), 1) }
        self.flags = flags
    }

    subscript(channel: StoryVisualChannelID) -> Double {
        channels[channel, default: 0]
    }

    func contains(_ flag: StoryVisualFlagID) -> Bool {
        flags.contains(flag)
    }
}

struct StoryVisualCue: Equatable, Sendable {
    let effect: StoryEffectID
    let direction: Double

    init(effect: StoryEffectID, direction: Double = 0) {
        self.effect = effect
        self.direction = min(max(direction, -1), 1)
    }
}

enum StoryAudioBus: String, Equatable, Codable, Sendable {
    case animals
    case birds
    case leaves
    case atmosphere
    case music
}

enum StoryMomentQuantization: Equatable, Sendable {
    case none
    case nextBeat
    case nextSubdivision(Int)
}

struct StoryAudioCue: Equatable, Sendable {
    let assetID: String
    let bus: StoryAudioBus
    let gain: Double

    init(
        assetID: String,
        bus: StoryAudioBus,
        gain: Double = 1
    ) {
        self.assetID = assetID
        self.bus = bus
        self.gain = min(max(gain, 0), 1)
    }
}

struct StoryMomentID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct StoryMoment: Equatable, Sendable {
    let id: StoryMomentID
    let startTime: TimeInterval
    let duration: TimeInterval
    let intensity: Double
    let randomSeed: UInt64
    let quantization: StoryMomentQuantization
    let visualCue: StoryVisualCue?
    let audioCue: StoryAudioCue?

    var endTime: TimeInterval {
        startTime + duration
    }

    func isActive(at elapsedTime: TimeInterval) -> Bool {
        elapsedTime >= startTime && elapsedTime < endTime
    }
}

struct StorySessionContext: Equatable, Sendable {
    let duration: TimeInterval
    let randomSeed: UInt64
}

struct StoryContext: Equatable, Sendable {
    let progress: Double
    let elapsedTime: TimeInterval
    let duration: TimeInterval
    let reduceMotion: Bool
}

struct StoryPlan: Equatable, Sendable {
    let moments: [StoryMoment]
    let payload: StoryPlanPayload?

    init(moments: [StoryMoment] = [], payload: StoryPlanPayload? = nil) {
        self.moments = moments.sorted {
            if $0.startTime == $1.startTime {
                return $0.id.rawValue < $1.id.rawValue
            }
            return $0.startTime < $1.startTime
        }
        self.payload = payload
    }

    init<Payload: Equatable & Sendable>(moments: [StoryMoment] = [], payload: Payload) {
        self.moments = moments.sorted {
            if $0.startTime == $1.startTime {
                return $0.id.rawValue < $1.id.rawValue
            }
            return $0.startTime < $1.startTime
        }
        self.payload = StoryPlanPayload(payload)
    }

    func payload<Payload>(as type: Payload.Type = Payload.self) -> Payload? {
        payload?.value(as: type)
    }

    static let empty = StoryPlan()
}

struct StoryPerformance: Equatable, Sendable {
    let beat: StoryBeatID
    let visualState: StoryVisualState
    let activeMoments: [StoryMoment]
}

protocol StoryDirector {
    func makePlan(for session: StorySessionContext) -> StoryPlan
    func performance(at context: StoryContext, plan: StoryPlan) -> StoryPerformance
}
