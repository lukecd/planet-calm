import Foundation

enum StoryAudioProcessingRoute: String, Equatable, Codable, Sendable {
    case dry
    case melodicEcho
}

/// A recording-ready event. Story directors choose assets and processing once;
/// the streaming engine only schedules this immutable result.
struct StorySampleEvent: Equatable, Sendable {
    let id: String
    let asset: PerformanceAudioAssetReference
    let start: Double
    let end: Double
    let fadeIn: Double
    let fadeOut: Double
    let gainDB: Double
    let pan: Float
    let pitchCents: Float

    var processingRoute: StoryAudioProcessingRoute { asset.processingRoute }
    var resumesAfterInterruption: Bool { asset.kind == .pad || asset.kind == .bassDrone }

    func gain(at time: Double) -> Float {
        guard time >= start, time < end else { return 0 }
        let attack = PerformanceEnvelope.smooth((time - start) / max(fadeIn, 0.001))
        let release = PerformanceEnvelope.smooth((end - time) / max(fadeOut, 0.001))
        return Float(pow(10, gainDB / 20) * attack * release)
    }
}

struct StoryPlayableAudioPlan: Equatable, Sendable {
    let duration: TimeInterval
    let assets: [PerformanceAudioAssetReference]
    let events: [StorySampleEvent]
}

struct StoryMIDIScore: Equatable, Sendable {
    struct Note: Equatable, Sendable {
        let id: String
        let track: String
        let startBeat: Double
        let durationBeats: Double
        let note: Int
        let velocity: Int
        let channel: UInt8
        let sourceMomentID: StoryMomentID?
    }

    let beatsPerMinute: Double
    let timeSignatureNumerator: Int
    let timeSignatureDenominator: Int
    let durationBeats: Double
    let notes: [Note]

    static func empty(duration: TimeInterval, beatsPerMinute: Double = 60) -> Self {
        Self(beatsPerMinute: beatsPerMinute, timeSignatureNumerator: 4,
             timeSignatureDenominator: 4,
             durationBeats: duration * beatsPerMinute / 60, notes: [])
    }
}

/// Composition direction emitted from the authoritative story plan. It contains
/// no rendered-file decisions and is safe to export before sound design begins.
struct StoryAudioScore: Equatable, Sendable {
    struct Cue: Equatable, Sendable {
        let id: String
        let phase: String
        let startTime: TimeInterval
        let duration: TimeInterval
        let bus: StoryAudioBus
        let intensity: Double
        let direction: Double?
        let sourceMomentID: StoryMomentID?
    }

    let storyID: String
    let duration: TimeInterval
    let seed: UInt64
    let cues: [Cue]
    let midi: StoryMIDIScore

    static func silent(story: Story, session: StorySessionContext) -> Self {
        .init(storyID: story.rawValue, duration: session.duration, seed: session.randomSeed,
              cues: [], midi: .empty(duration: session.duration))
    }
}

/// Immutable story-specific plan storage without teaching the shared runtime an
/// enum case for every future story.
struct StoryPlanPayload: @unchecked Sendable, Equatable {
    private let stored: Any
    private let equals: @Sendable (Any) -> Bool

    init<Value: Equatable & Sendable>(_ value: Value) {
        stored = value
        equals = { ($0 as? Value) == value }
    }

    func value<Value>(as type: Value.Type = Value.self) -> Value? {
        stored as? Value
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.equals(rhs.stored) && rhs.equals(lhs.stored)
    }
}
