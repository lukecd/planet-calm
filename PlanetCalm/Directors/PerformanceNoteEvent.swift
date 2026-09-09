import Foundation

// Shared score contracts. Compatibility aliases preserve the approved splash consumer.
enum PerformanceRole: String, CaseIterable, Equatable, Sendable {
    case drone
    case pad
    case chime
    case melody
}

enum PerformanceEnvelopeStage: Equatable, Sendable {
    case attack
    case decay
    case sustain
    case release
}

struct PerformanceEnvelopeSample: Equatable, Sendable {
    let value: Double
    let lifecycleProgress: Double
    let localBeat: Double
    let stage: PerformanceEnvelopeStage
}

struct PerformanceEnvelope: Equatable, Sendable {
    static func smooth(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    let attackBeats: Double
    let decayBeats: Double
    let sustainLevel: Double
    let releaseBeats: Double

    func sample(
        localBeat: Double,
        gateBeats: Double
    ) -> PerformanceEnvelopeSample? {
        let totalBeats = gateBeats + releaseBeats
        guard localBeat >= 0, localBeat < totalBeats else { return nil }

        let value: Double
        let stage: PerformanceEnvelopeStage
        if localBeat < attackBeats {
            value = PerformanceEnvelope.smooth(localBeat / attackBeats)
            stage = .attack
        } else if localBeat < attackBeats + decayBeats {
            let decayProgress = PerformanceEnvelope.smooth(
                (localBeat - attackBeats) / decayBeats
            )
            value = 1 - (1 - sustainLevel) * decayProgress
            stage = .decay
        } else if localBeat < gateBeats {
            value = sustainLevel
            stage = .sustain
        } else {
            let releaseProgress = PerformanceEnvelope.smooth(
                (localBeat - gateBeats) / releaseBeats
            )
            value = sustainLevel * (1 - releaseProgress)
            stage = .release
        }

        return PerformanceEnvelopeSample(
            value: value,
            lifecycleProgress: localBeat / totalBeats,
            localBeat: localBeat,
            stage: stage
        )
    }
}

struct PerformanceNoteEvent: Equatable, Sendable {
    let id: String
    let tonalSlot: Int
    let startBeat: Double
    let gateBeats: Double
    let envelope: PerformanceEnvelope
    let role: PerformanceRole
    let intensity: Double
    let isRepeating: Bool
    let octaveOffset: Int

    init(
        id: String? = nil,
        tonalSlot: Int,
        startBeat: Double,
        gateBeats: Double,
        envelope: PerformanceEnvelope,
        role: PerformanceRole = .pad,
        intensity: Double = 1,
        isRepeating: Bool = true,
        octaveOffset: Int = 0
    ) {
        self.id = id ?? "slot-\(tonalSlot)-beat-\(startBeat)"
        self.tonalSlot = tonalSlot
        self.startBeat = startBeat
        self.gateBeats = gateBeats
        self.envelope = envelope
        self.role = role
        self.intensity = intensity
        self.isRepeating = isRepeating
        self.octaveOffset = octaveOffset
    }

    var endBeat: Double {
        startBeat + gateBeats + envelope.releaseBeats
    }

    var totalBeats: Double {
        gateBeats + envelope.releaseBeats
    }

    func sample(at scoreBeat: Double) -> PerformanceEnvelopeSample? {
        envelope.sample(
            localBeat: scoreBeat - startBeat,
            gateBeats: gateBeats
        )
    }
}


/// Pool identities belong to a story; source lookup and envelope timing do not.
enum PerformanceSoundRole: String, Equatable, Sendable {
    case drone, pad, melodicOneShot
}
struct PerformanceSoundAssetKey<Pool: Equatable & Sendable>: Equatable, Sendable {
    let pool: Pool
    let role: PerformanceSoundRole
    let tonalSlot: Int
    let octaveOffset: Int
}
struct PerformancePoolBlend: Equatable, Sendable {
    let first: Double
    let middle: Double
    let last: Double

    static func sample(progress: Double) -> Self {
        let p = progress.isFinite ? min(1, max(0, progress)) : 0
        return p <= 0.5 ? Self(first: 1 - p * 2, middle: p * 2, last: 0)
            : Self(first: 0, middle: 1 - (p - 0.5) * 2, last: (p - 0.5) * 2)
    }

    func index(forUnit unit: Double) -> Int {
        if unit < first { return 0 }
        if unit < first + middle { return 1 }
        return 2
    }
}

typealias SplashPerformanceRole = PerformanceRole
typealias SplashEnvelopeStage = PerformanceEnvelopeStage
typealias SplashEnvelopeSample = PerformanceEnvelopeSample
typealias SplashADSREnvelope = PerformanceEnvelope
typealias SplashWaveNoteEvent = PerformanceNoteEvent
