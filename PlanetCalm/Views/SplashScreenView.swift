import Foundation
import SwiftUI
import AVFoundation

enum SplashSceneActorID: String, CaseIterable, Identifiable {
    case background
    case wordmark
    case sun
    case waveRearPeriwinkle
    case waveRearDeep
    case waveWarmReveal
    case waveMiddleLavender
    case waveMiddleBlue
    case waveFrontDeep
    case waveFrontPeriwinkle
    case waveFrontLavender
    case lotusLeft
    case lotusCenter
    case lotusRight
    case navigation

    var id: String { rawValue }
}

enum SplashLotusPetalID: String, CaseIterable, Identifiable {
    case baseLeft
    case baseRight
    case outerLeft
    case outerRight
    case innerLeft
    case innerRight
    case center
    case heart

    var id: String { rawValue }
}

enum SplashMenuItem: String, CaseIterable, Identifiable {
    case start = "Start"
    case stories = "Stories"
    case stats = "Stats"
    case settings = "Settings"

    var id: String { rawValue }
}

struct PerformanceClock: Equatable, Sendable {
    let startedAt: Date

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    func elapsed(at date: Date) -> TimeInterval {
        max(date.timeIntervalSince(startedAt), 0)
    }
}

struct PerformanceTempo: Equatable, Sendable {
    let beatsPerMinute: Double
    let beatsPerBar: Int

    var secondsPerBeat: TimeInterval {
        60 / beatsPerMinute
    }
}

private enum SplashPerformancePurpose {
    case splashAudition
    case storyPreview
}

struct SplashWaveMotionPacket: Equatable {
    let amplitude: CGFloat
    let center: CGFloat
    let halfWidth: CGFloat
}

struct SplashWaveMotionSample: Equatable {
    let phase: CGFloat
    let packets: [SplashWaveMotionPacket]
    let packetLimit: CGFloat
    let bedPhase: CGFloat
    let bedAmplitude: CGFloat

    init(phase: CGFloat, amplitude: CGFloat) {
        self.init(phase: phase, packets: [
            .init(amplitude: amplitude, center: 0.5, halfWidth: .infinity)
        ])
    }

    init(
        phase: CGFloat,
        packets: [SplashWaveMotionPacket],
        packetLimit: CGFloat = 1,
        bedPhase: CGFloat = 0,
        bedAmplitude: CGFloat = 0
    ) {
        self.phase = phase
        self.packets = packets
        self.packetLimit = packetLimit
        self.bedPhase = bedPhase
        self.bedAmplitude = bedAmplitude
    }

    var amplitude: CGFloat { packets.map(\.amplitude).max() ?? 0 }

    var totalAmplitude: CGFloat {
        min(amplitude + bedAmplitude, 1)
    }

    var isMoving: Bool {
        totalAmplitude > 0
    }

    func packetAmplitude(at x: CGFloat) -> CGFloat {
        // Combine local disturbances without moving their centers or allowing
        // overlap to exceed the motion budget. A distant attack cannot erase
        // a ripple that is already travelling across the paper.
        let ceiling = packetLimit
        guard ceiling > 0 else { return 0 }
        let remaining = packets.reduce(CGFloat(1)) { remaining, packet in
            let support = SplashWaveGenerator.travelingPacketGain(
                at: x, center: packet.center, halfWidth: packet.halfWidth
            )
            return remaining * (1 - min(max(packet.amplitude / ceiling, 0), 1) * support)
        }
        return ceiling * (1 - remaining)
    }

    static let resting = SplashWaveMotionSample(
        phase: 0,
        amplitude: 0
    )
}

/// A short, note-shaped disturbance that travels through the paper field.
/// It is deliberately defined in wave-world coordinates, rather than screen
/// coordinates, so the same event remains coherent across rotation and crop.
struct SplashWaveResonanceTuning: Equatable {
    var strength: CGFloat
    var halfWidth: CGFloat

    static let standard = SplashWaveResonanceTuning(
        strength: 1,
        halfWidth: 0.115
    )
}

struct SplashWaveResonanceSample: Equatable {
    struct Contribution: Equatable {
        let progress: CGFloat
        let center: CGFloat
        let strength: CGFloat
        let halfWidth: CGFloat
        let targetWaveIndex: Int
    }

    let contributions: [Contribution]

    // These accessors keep the single-event review surface inspectable while
    // the renderer can carry several overlapping generated notes.
    var progress: CGFloat { contributions.first?.progress ?? 0 }
    var center: CGFloat { contributions.first?.center ?? 0 }
    var strength: CGFloat { contributions.first?.strength ?? 0 }
    var halfWidth: CGFloat { contributions.first?.halfWidth ?? 0 }
    var targetWaveIndex: Int { contributions.first?.targetWaveIndex ?? 0 }

    init(
        progress: CGFloat,
        center: CGFloat,
        strength: CGFloat,
        halfWidth: CGFloat,
        targetWaveIndex: Int
    ) {
        contributions = [Contribution(
            progress: progress,
            center: center,
            strength: strength,
            halfWidth: halfWidth,
            targetWaveIndex: targetWaveIndex
        )]
    }

    init(contributions: [Contribution]) {
        self.contributions = contributions
    }

    static let maximumLiftStrength: CGFloat = 1
    static let maximumSeamStrength: CGFloat = 1.35
    static let melodicCenterRange: ClosedRange<CGFloat> = 0.36...0.64

    static func sample(
        event: SplashWaveNoteEvent,
        scoreBeat: Double,
        tuning: SplashWaveResonanceTuning,
        centerRange: ClosedRange<CGFloat>? = nil
    ) -> SplashWaveResonanceSample? {
        let envelope: SplashEnvelopeSample?
        if event.role == .melody || event.role == .chime {
            // The visual response has its own quiet paper attack. It starts at
            // the same score beat as audio, while avoiding the instrument's
            // sharp 120 ms onset.
            envelope = SplashPerformanceScore.waveEnvelopeSample(
                for: event,
                scoreBeat: scoreBeat
            )
        } else {
            envelope = event.sample(at: scoreBeat)
        }
        guard let envelope else { return nil }

        let progress = CGFloat(envelope.lifecycleProgress)
        let center: CGFloat
        if let centerRange {
            center = centerRange.lowerBound
                + (centerRange.upperBound - centerRange.lowerBound) * progress
        } else {
            center = -tuning.halfWidth
                + (1 + tuning.halfWidth * 2) * progress
        }
        // waveEnvelopeSample already applies melody intensity. Keep that
        // value from being multiplied a second time when this helper samples
        // generated melody events; legacy non-melodic review events retain
        // their existing intensity behavior.
        let intensity = event.role == .melody || event.role == .chime
            ? 1 : event.intensity
        return SplashWaveResonanceSample(
            progress: progress,
            center: center,
            strength: tuning.strength * intensity
                * CGFloat(SplashPerformanceScore.visualMotionGain(for: envelope)),
            halfWidth: tuning.halfWidth,
            targetWaveIndex: event.tonalSlot
        )
    }

    /// Samples every active melodic event on the shared score clock. The
    /// contributions stay independent so a new note never relocates an older
    /// highlight; the render-time lift and opacity methods provide the bounds.
    static func melodySample(
        events: [SplashWaveNoteEvent],
        scoreBeat: Double,
        tuning: SplashWaveResonanceTuning
    ) -> SplashWaveResonanceSample? {
        let contributions = events
            .filter { $0.role == .melody || $0.role == .chime }
            .compactMap {
                sample(
                    event: $0,
                    scoreBeat: scoreBeat,
                    tuning: tuning,
                    centerRange: melodicCenterRange
                )?.contributions.first
            }
        guard !contributions.isEmpty else { return nil }
        return SplashWaveResonanceSample(contributions: contributions)
    }

    func verticalShift(at x: CGFloat, waveIndex: Int) -> CGFloat {
        let gains = contributions.compactMap { contribution -> CGFloat? in
            guard waveIndex == contribution.targetWaveIndex else { return nil }
            let distance = (x - contribution.center) / max(contribution.halfWidth, 0.001)
            return contribution.strength * CGFloat(exp(-0.5 * distance * distance))
        }
        return -0.034 * Self.boundedUnion(gains, ceiling: Self.maximumLiftStrength)
    }

    func seamOpacity(for waveIndex: Int) -> Double {
        let strengths = contributions.compactMap { contribution -> CGFloat? in
            waveIndex == contribution.targetWaveIndex ? contribution.strength : nil
        }
        return Double(0.38 * Self.boundedUnion(
            strengths,
            ceiling: Self.maximumSeamStrength
        ))
    }

    func seamOpacity(
        for contribution: Contribution
    ) -> Double {
        Double(0.38 * Self.boundedUnion(
            [contribution.strength],
            ceiling: Self.maximumSeamStrength
        ))
    }

    func seamContributions(for waveIndex: Int) -> [Contribution] {
        contributions.filter { $0.targetWaveIndex == waveIndex }
    }

    private static func boundedUnion(
        _ gains: [CGFloat],
        ceiling: CGFloat
    ) -> CGFloat {
        guard ceiling > 0 else { return 0 }
        let remaining = gains.reduce(CGFloat(1)) { remaining, gain in
            remaining * (1 - min(max(gain / ceiling, 0), 1))
        }
        return ceiling * (1 - remaining)
    }
}

struct SplashWaveVoice: Equatable {
    let actorID: SplashSceneActorID
    let tonalSlot: Int
    let noteName: String
}

struct SplashScheduledPerformanceEvent: Identifiable, Equatable {
    let event: SplashWaveNoteEvent
    let scheduledStartBeat: Double

    var id: String {
        "\(event.id)-\(scheduledStartBeat)"
    }

    var endBeat: Double {
        scheduledStartBeat + event.totalBeats
    }

    func sample(at scoreBeat: Double) -> SplashEnvelopeSample? {
        event.envelope.sample(
            localBeat: scoreBeat - scheduledStartBeat,
            gateBeats: event.gateBeats
        )
    }
}

/// A stable, inspectable plan for the splash's future audio scheduler. It selects
/// a semantic source key when an event starts; the eventual audio engine resolves
/// that key to an imported recording and never reselects it during the release.
struct SplashPerformancePlan: Equatable {
    let session: PerformanceSession
    let scoreEvents: [SplashWaveNoteEvent]

    func atmosphere(at date: Date) -> SplashAtmosphereSample {
        let progress = PerformanceRunner(session: session).sample(at: date).progress
        return SplashAtmosphereDirector.sample(progress: progress)
    }

    func soundSource(
        for scheduledEvent: SplashScheduledPerformanceEvent
    ) -> SplashSoundAssetKey {
        let secondsFromStart = scheduledEvent.scheduledStartBeat
            * SplashPerformanceScore.tempo.secondsPerBeat
        if scheduledEvent.event.role == .pad {
            let bank = SplashSamplePlan.padBank(at: secondsFromStart, duration: session.duration.timeInterval)
            return .init(pool: [.night, .twilight, .daylight][bank - 1], role: .pad,
                tonalSlot: scheduledEvent.event.tonalSlot, octaveOffset: scheduledEvent.event.octaveOffset)
        }
        let eventProgress = min(
            max(secondsFromStart / session.duration.timeInterval, 0),
            1
        )
        let atmosphere = SplashAtmosphereDirector.sample(progress: eventProgress)
        return SplashAtmosphereDirector.soundSource(
            eventID: scheduledEvent.id,
            sessionSeed: session.randomSeed,
            tonalSlot: scheduledEvent.event.tonalSlot,
            role: soundRole(for: scheduledEvent.event.role),
            atmosphere: atmosphere,
            octaveOffset: scheduledEvent.event.octaveOffset
        )
    }

    private func soundRole(
        for role: SplashPerformanceRole
    ) -> SplashSoundRole {
        switch role {
        case .drone: .drone
        case .pad: .pad
        case .chime, .melody: .melodicOneShot
        }
    }
}

struct SplashScoreDiagnostics: Equatable {
    let averageActiveVoices: Double
    let longestSilentBeats: Double
    let averageEventDurationSeconds: Double
    let eventsPerMinute: Double
    let participatingWaveCount: Int
}

struct SplashMotionTuning: Equatable {
    static let standard = SplashMotionTuning()

    private(set) var speedMultiplier: Double
    private(set) var amountMultiplier: Double
    private var phaseTimeAnchor: TimeInterval
    private var activeTimeAnchor: TimeInterval

    init(
        speedMultiplier: Double = 1,
        amountMultiplier: Double = 1,
        phaseTimeAnchor: TimeInterval = 0,
        activeTimeAnchor: TimeInterval = 0
    ) {
        self.speedMultiplier = speedMultiplier
        self.amountMultiplier = amountMultiplier
        self.phaseTimeAnchor = phaseTimeAnchor
        self.activeTimeAnchor = activeTimeAnchor
    }

    func phaseTime(at activeTime: TimeInterval) -> TimeInterval {
        phaseTimeAnchor
            + max(activeTime - activeTimeAnchor, 0) * speedMultiplier
    }

    mutating func setSpeedMultiplier(
        _ newValue: Double,
        performanceElapsed: TimeInterval
    ) {
        let elapsed = max(performanceElapsed, 0)
        phaseTimeAnchor = phaseTime(at: elapsed)
        activeTimeAnchor = elapsed
        speedMultiplier = min(max(newValue, 0.25), 4)
    }

    mutating func setAmountMultiplier(_ newValue: Double) {
        amountMultiplier = min(max(newValue, 0.5), 2)
    }

    mutating func reset(performanceElapsed: TimeInterval) {
        setSpeedMultiplier(1, performanceElapsed: performanceElapsed)
        amountMultiplier = 1
    }

    mutating func restartKeepingValues() {
        phaseTimeAnchor = 0
        activeTimeAnchor = 0
    }
}


enum SplashPerformanceScore {
    static let tempo = PerformanceTempo(beatsPerMinute: 65, beatsPerBar: 4)
    static let defaultSeed: UInt64 = 650_208
    static let droneStartTime: TimeInterval = 0
    static let noteCycleBeats: Double = 32
    static let packetStart: CGFloat = -0.02
    static let packetEnd: CGFloat = 1.02
    static let packetHalfWidth: CGFloat = 0.22
    static let droneFadeInDuration: TimeInterval = 2.4
    static let droneSlots: Set<Int> = [0, 1, 3, 5]
    static let noteBedShare: CGFloat = 0.28
    static let packetShare: CGFloat = 0.86
    static let melodicWaveAttackDuration: TimeInterval = 0.9

    /// Stable visual voices that can later address eight recorded scale tones.
    static let waveVoices: [SplashWaveVoice] = [
        .init(actorID: .waveRearPeriwinkle, tonalSlot: 0, noteName: "F2"),
        .init(actorID: .waveRearDeep, tonalSlot: 1, noteName: "G2"),
        .init(actorID: .waveWarmReveal, tonalSlot: 2, noteName: "A2"),
        .init(actorID: .waveMiddleLavender, tonalSlot: 3, noteName: "B2"),
        .init(actorID: .waveMiddleBlue, tonalSlot: 4, noteName: "C3"),
        .init(actorID: .waveFrontDeep, tonalSlot: 5, noteName: "D3"),
        .init(actorID: .waveFrontPeriwinkle, tonalSlot: 6, noteName: "E3"),
        .init(actorID: .waveFrontLavender, tonalSlot: 7, noteName: "F3")
    ]

    /// Long, staggered pad notes overlap continuously after the initial build.
    /// The future audio scheduler will consume the same starts and envelope.
    static let noteEnvelope = SplashADSREnvelope(
        attackBeats: 3,
        decayBeats: 2,
        sustainLevel: 0.72,
        releaseBeats: 6
    )
    static let noteEvents: [SplashWaveNoteEvent] = [
        .init(id: "drone-f2", tonalSlot: 0, startBeat: 0, gateBeats: 10, envelope: noteEnvelope, role: .drone, intensity: 0.78),
        .init(id: "pad-b2", tonalSlot: 3, startBeat: 4, gateBeats: 10, envelope: noteEnvelope),
        .init(id: "pad-d3", tonalSlot: 5, startBeat: 8, gateBeats: 10, envelope: noteEnvelope),
        .init(id: "pad-g2", tonalSlot: 1, startBeat: 12, gateBeats: 10, envelope: noteEnvelope),
        .init(id: "pad-c3", tonalSlot: 4, startBeat: 16, gateBeats: 10, envelope: noteEnvelope),
        .init(id: "pad-f3", tonalSlot: 7, startBeat: 20, gateBeats: 10, envelope: noteEnvelope),
        .init(id: "pad-a2", tonalSlot: 2, startBeat: 24, gateBeats: 10, envelope: noteEnvelope),
        .init(id: "pad-e3", tonalSlot: 6, startBeat: 28, gateBeats: 10, envelope: noteEnvelope)
    ]

    static func events(seed: UInt64) -> [SplashWaveNoteEvent] {
        guard seed != defaultSeed else { return noteEvents }

        var random = SeededRandomNumberGenerator(seed: seed)
        return noteEvents.enumerated().map { index, event in
            let onsetJitter = index == 0 ? 0 : random.value(in: -0.55...0.55)
            let gateVariation = random.value(in: -1.15...1.15)
            return SplashWaveNoteEvent(
                id: "\(event.id)-seed-\(seed)",
                tonalSlot: event.tonalSlot,
                startBeat: max(event.startBeat + onsetJitter, 0),
                gateBeats: min(max(event.gateBeats + gateVariation, 8), 12),
                envelope: event.envelope,
                role: event.role,
                intensity: event.intensity
            )
        }
    }

    static func noteName(for tonalSlot: Int) -> String {
        waveVoices.first { $0.tonalSlot == tonalSlot }?.noteName ?? "?"
    }

    static func waveName(for tonalSlot: Int) -> String {
        let number = min(max(tonalSlot + 1, 1), waveVoices.count)
        return "Wave \(number)"
    }

    static func scoreBeat(
        for performanceElapsed: TimeInterval,
        tuning: SplashMotionTuning
    ) -> Double {
        tuning.phaseTime(at: max(performanceElapsed, 0)) / tempo.secondsPerBeat
    }

    static func waveMotionSample(
        for actorID: SplashSceneActorID,
        performanceElapsed: TimeInterval,
        events: [SplashWaveNoteEvent] = noteEvents,
        tuning: SplashMotionTuning = .standard
    ) -> SplashWaveMotionSample {
        guard let voice = waveVoices.first(where: { $0.actorID == actorID }) else {
            return .resting
        }

        let elapsed = max(performanceElapsed, 0)
        let tunedTime = tuning.phaseTime(at: elapsed)
        let scoreBeat = tunedTime / tempo.secondsPerBeat
        let noteEvent = events.first {
            $0.tonalSlot == voice.tonalSlot
        }
        let liveSamples = events.filter { $0.tonalSlot == voice.tonalSlot }.compactMap {
            waveEnvelopeSample(for: $0, scoreBeat: scoreBeat)
        }
        let noteSample = liveSamples.max { $0.value < $1.value }
        let packets = liveSamples.map { sample in
            SplashWaveMotionPacket(
                amplitude: SplashMotionTiming.maximumMotionAmount * packetShare
                    * CGFloat(visualMotionGain(for: sample)) * CGFloat(tuning.amountMultiplier),
                center: packetStart + (packetEnd - packetStart) * CGFloat(sample.lifecycleProgress),
                halfWidth: packetHalfWidth
            )
        }
        // Every voice samples one continuous phase clock. Note events shape the
        // strength and location of motion; they never restart the wave itself.
        let phase = CGFloat(
            tunedTime * SplashMotionTiming.motionPhaseUnitsPerSecond
                + Double(voice.tonalSlot) * 0.17
        )
        let noteMotionGain = noteSample.map {
            visualMotionGain(for: $0)
        } ?? 0

        // A rolling ambient window may begin in the middle of the performance.
        // Only the absolute-zero drone can establish the initial paper bed.
        let isRollingScore = events.contains { $0.id.hasPrefix("ambient-") }
        let isInitialNote = !isRollingScore
            || abs((noteEvent?.startBeat ?? 0) * tempo.secondsPerBeat) < 0.001
        let isInitialFoundation = isInitialNote
            && droneSlots.contains(voice.tonalSlot)
            && scoreBeat < (noteEvent?.startBeat ?? 0)
        let attackHandoff: Double
        let firstAttackBeats = noteEvent.map { waveAttackBeats(for: $0) } ?? 1
        let isFirstAttack = isInitialNote && noteEvent.map {
            scoreBeat >= $0.startBeat
                && scoreBeat < $0.startBeat + firstAttackBeats
        } ?? false
        let firstSample = noteEvent.flatMap { waveEnvelopeSample(for: $0, scoreBeat: scoreBeat) }
        if let firstSample, firstSample.stage == .attack, isFirstAttack {
            attackHandoff = 1 - SplashMotionTiming.smootherStep(
                firstSample.localBeat / firstAttackBeats
            )
        } else {
            attackHandoff = 0
        }
        // Only the waves that already carry a foundation may hand it off.
        // Introducing one on another wave at its first note creates a hard jump.
        let foundationGain = droneSlots.contains(voice.tonalSlot)
            ? max(isInitialFoundation ? 1 : 0, attackHandoff) : 0
        let fadeIn = SplashMotionTiming.smootherStep(
            elapsed / droneFadeInDuration
        )
        let breathCycleBeats = 24 + Double(voice.tonalSlot) * 2
        let breathAngle = 2 * Double.pi
            * (scoreBeat / breathCycleBeats + Double(voice.tonalSlot) * 0.17)
        let breathGain = 0.72 + 0.28 * (0.5 + 0.5 * sin(breathAngle))
        let foundationBedGain = 0.34 * fadeIn * breathGain * foundationGain
        let noteBedGain = Double(noteBedShare) * noteMotionGain
        let bedAmplitude = SplashMotionTiming.maximumMotionAmount
            * CGFloat(max(foundationBedGain, noteBedGain))
            * CGFloat(tuning.amountMultiplier)

        return SplashWaveMotionSample(
            phase: phase,
            packets: packets,
            packetLimit: SplashMotionTiming.maximumMotionAmount * packetShare * CGFloat(tuning.amountMultiplier),
            bedPhase: phase,
            bedAmplitude: bedAmplitude
        )
    }

    static func waveEnvelopeSample(
        for event: SplashWaveNoteEvent,
        scoreBeat: Double
    ) -> SplashEnvelopeSample? {
        guard let scheduled = scheduledSample(for: event, scoreBeat: scoreBeat) else { return nil }
        guard event.role == .melody || event.role == .chime else { return scheduled.envelope }
        // Paper has a slower response than a struck instrument. Keep the exact
        // onset, gate, and release end; do not copy its 110 ms audio attack into
        // a full-width visual kick or change the shared score/audio envelope.
        let envelope = SplashADSREnvelope(
            attackBeats: waveAttackBeats(for: event),
            decayBeats: 0, sustainLevel: 1, releaseBeats: event.envelope.releaseBeats
        )
        guard let sample = envelope.sample(localBeat: scheduled.envelope.localBeat,
            gateBeats: event.gateBeats) else { return nil }
        return SplashEnvelopeSample(value: sample.value * min(max(event.intensity, 0), 1),
            lifecycleProgress: sample.lifecycleProgress, localBeat: sample.localBeat,
            stage: sample.stage)
    }

    static func melodyResonanceSample(
        events: [SplashWaveNoteEvent],
        scoreBeat: Double,
        tuning: SplashWaveResonanceTuning,
        reduceMotion: Bool = false
    ) -> SplashWaveResonanceSample? {
        guard !reduceMotion else { return nil }
        return SplashWaveResonanceSample.melodySample(
            events: events,
            scoreBeat: scoreBeat,
            tuning: tuning
        )
    }

    private static func waveAttackBeats(for event: SplashWaveNoteEvent) -> Double {
        event.role == .melody || event.role == .chime
            ? min(melodicWaveAttackDuration / tempo.secondsPerBeat, event.gateBeats)
            : event.envelope.attackBeats
    }

    /// Preserves the audio ADSR endpoints while making its quieter shoulders
    /// legible as paper motion. The curve and its derivative remain continuous.
    static func visualMotionGain(
        for sample: SplashEnvelopeSample
    ) -> Double {
        sample.value * (2 - sample.value)
    }

    static func repeatingSample(
        for event: SplashWaveNoteEvent,
        scoreBeat: Double,
        cycleBeat: Double
    ) -> SplashEnvelopeSample? {
        scheduledSample(for: event, scoreBeat: scoreBeat)?.envelope
    }

    static func scheduledSample(
        for event: SplashWaveNoteEvent,
        scoreBeat: Double
    ) -> (scheduledStartBeat: Double, envelope: SplashEnvelopeSample)? {
        if !event.isRepeating {
            return event.sample(at: scoreBeat).map { (event.startBeat, $0) }
        }
        let currentCycle = floor(scoreBeat / noteCycleBeats)
        for cycle in [currentCycle, currentCycle - 1] where cycle >= 0 {
            let startBeat = cycle * noteCycleBeats + event.startBeat
            if let envelope = event.envelope.sample(
                localBeat: scoreBeat - startBeat,
                gateBeats: event.gateBeats
            ) {
                return (startBeat, envelope)
            }
        }
        return nil
    }

    static func scheduledEvents(
        around scoreBeat: Double,
        radiusBeats: Double = 16,
        events: [SplashWaveNoteEvent] = noteEvents,
        manualEvent: SplashWaveNoteEvent? = nil
    ) -> [SplashScheduledPerformanceEvent] {
        let lowerBound = max(scoreBeat - radiusBeats, 0)
        let upperBound = scoreBeat + radiusBeats
        let firstCycle = max(Int(floor(lowerBound / noteCycleBeats)) - 1, 0)
        let lastCycle = Int(floor(upperBound / noteCycleBeats)) + 1
        var scheduled: [SplashScheduledPerformanceEvent] = []

        for cycle in firstCycle...lastCycle {
            for event in events where event.isRepeating {
                let scheduledEvent = SplashScheduledPerformanceEvent(
                    event: event,
                    scheduledStartBeat: Double(cycle) * noteCycleBeats + event.startBeat
                )
                if scheduledEvent.endBeat >= lowerBound,
                   scheduledEvent.scheduledStartBeat <= upperBound {
                    scheduled.append(scheduledEvent)
                }
            }
        }

        for event in events where !event.isRepeating && event.endBeat >= lowerBound && event.startBeat <= upperBound {
            scheduled.append(.init(event: event, scheduledStartBeat: event.startBeat))
        }

        if let manualEvent {
            let scheduledEvent = SplashScheduledPerformanceEvent(
                event: manualEvent,
                scheduledStartBeat: manualEvent.startBeat
            )
            if scheduledEvent.endBeat >= lowerBound,
               scheduledEvent.scheduledStartBeat <= upperBound {
                scheduled.append(scheduledEvent)
            }
        }

        return scheduled.sorted { $0.scheduledStartBeat < $1.scheduledStartBeat }
    }

    static func diagnostics(
        durationMinutes: Double = 10,
        events: [SplashWaveNoteEvent] = noteEvents
    ) -> SplashScoreDiagnostics {
        let totalBeats = durationMinutes * 60 / tempo.secondsPerBeat
        let scheduled = scheduledEvents(
            around: totalBeats / 2,
            radiusBeats: totalBeats / 2 + noteCycleBeats,
            events: events
        ).filter { $0.scheduledStartBeat < totalBeats }

        let activeCounts = stride(from: 0.0, to: totalBeats, by: 0.5).map {
            sampleBeat in scheduled.filter { $0.sample(at: sampleBeat) != nil }.count
        }
        let averageActiveVoices = Double(activeCounts.reduce(0, +))
            / Double(max(activeCounts.count, 1))

        var longestSilentBeats = 0.0
        var currentSilentBeats = 0.0
        for activeCount in activeCounts {
            if activeCount == 0 {
                currentSilentBeats += 0.5
                longestSilentBeats = max(longestSilentBeats, currentSilentBeats)
            } else {
                currentSilentBeats = 0
            }
        }

        let averageDuration = scheduled.map {
            $0.event.totalBeats * tempo.secondsPerBeat
        }.reduce(0, +) / Double(max(scheduled.count, 1))

        return SplashScoreDiagnostics(
            averageActiveVoices: averageActiveVoices,
            longestSilentBeats: longestSilentBeats,
            averageEventDurationSeconds: averageDuration,
            eventsPerMinute: Double(scheduled.count) / durationMinutes,
            participatingWaveCount: Set(scheduled.map(\.event.tonalSlot)).count
        )
    }
}

enum SplashSceneMotionState: Equatable {
    case presented
    case entering(elapsed: TimeInterval)
    case living(elapsed: TimeInterval)
    case exiting(elapsed: TimeInterval)
}

enum SplashMotionTiming {
    static let firstRibbonDelay: TimeInterval = 0.25
    static let ribbonEntryDuration: TimeInterval = 2.00
    static let ribbonEntryStagger: TimeInterval = 0.18
    static let ribbonCount = 8

    static let ribbonExitDuration: TimeInterval = 1.15
    static let ribbonExitStagger: TimeInterval = 0.05

    static let sunEntryDelay: TimeInterval = 0.45
    static let sunEntryDuration: TimeInterval = 1.40
    static let wordmarkEntryDelay: TimeInterval = 0.80
    static let wordmarkEntryDuration: TimeInterval = 1.20
    static let navigationEntryDelay: TimeInterval = 2.00
    static let navigationEntryDuration: TimeInterval = 1.20
    /// The cloud assembly arrives only after the paper field and its lotuses have
    /// reached their rest pose. It deliberately does not extend scene settlement.
    static let cloudEntryDelay: TimeInterval = SplashLotusChoreography.entryEnd + 0.20
    static let cloudEntryDuration: TimeInterval = 0.60

    static let sunExitDuration: TimeInterval = 1.00
    static let wordmarkExitDuration: TimeInterval = 0.85
    static let navigationExitDuration: TimeInterval = 0.65
    static let cloudExitDuration: TimeInterval = 0.50

    static let motionPhaseUnitsPerSecond: Double = 0.320
    static let maximumMotionAmount: CGFloat = 0.188

    static var ribbonEntranceCompleteTime: TimeInterval {
        firstRibbonDelay
            + ribbonEntryDuration
            + TimeInterval(ribbonCount - 1) * ribbonEntryStagger
    }

    static var entranceCompleteTime: TimeInterval {
        max(ribbonEntranceCompleteTime, SplashLotusChoreography.entryEnd)
    }

    static var interactionReadyTime: TimeInterval {
        ribbonEntranceCompleteTime
    }

    static var exitCompleteTime: TimeInterval {
        max(
            ribbonExitDuration
                + TimeInterval(ribbonCount - 1) * ribbonExitStagger,
            SplashLotusChoreography.exitDuration
        )
    }

    static var noteScoreStartTime: TimeInterval {
        0
    }

    static func smootherStep(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    static func entryProgress(
        for index: Int,
        elapsed: TimeInterval
    ) -> CGFloat {
        let start = firstRibbonDelay + TimeInterval(index) * ribbonEntryStagger
        return CGFloat(smootherStep((elapsed - start) / ribbonEntryDuration))
    }

    static func exitProgress(
        for index: Int,
        count: Int,
        elapsed: TimeInterval
    ) -> CGFloat {
        let frontToBackOrder = count - 1 - index
        let start = TimeInterval(frontToBackOrder) * ribbonExitStagger
        return CGFloat(smootherStep((elapsed - start) / ribbonExitDuration))
    }

    static func revealProgress(
        elapsed: TimeInterval,
        delay: TimeInterval,
        duration: TimeInterval
    ) -> CGFloat {
        CGFloat(smootherStep((elapsed - delay) / duration))
    }

    static func noteScoreTime(at elapsed: TimeInterval) -> TimeInterval {
        max(elapsed, 0)
    }
}

struct SplashLotusAnimationSample: Equatable {
    let centerOpacity: Double
    let fanProgress: CGFloat
    let heartOpacity: Double

    static let hidden = SplashLotusAnimationSample(
        centerOpacity: 0,
        fanProgress: 0,
        heartOpacity: 0
    )
    static let presented = SplashLotusAnimationSample(
        centerOpacity: 1,
        fanProgress: 1,
        heartOpacity: 1
    )
}

enum SplashLotusChoreography {
    static let order: [SplashSceneActorID] = [
        .lotusLeft,
        .lotusCenter,
        .lotusRight
    ]
    /// Flowers wait until every supporting paper ribbon has finished unfurling.
    static let firstStart: TimeInterval =
        SplashMotionTiming.ribbonEntranceCompleteTime + 0.05
    static let cascadeStagger: TimeInterval = 0.16
    static let centerDuration: TimeInterval = 0.38
    static let fanDelay: TimeInterval = 0.10
    static let fanDuration: TimeInterval = 0.48
    static let heartDelay: TimeInterval = 0.33
    static let heartDuration: TimeInterval = 0.25
    static let exitDuration: TimeInterval = 1.12

    static var entryEnd: TimeInterval {
        firstStart
            + TimeInterval(order.count - 1) * cascadeStagger
            + max(
                centerDuration,
                max(fanDelay + fanDuration, heartDelay + heartDuration)
            )
    }

    static var activeDuration: TimeInterval {
        entryEnd - firstStart
    }

    static func sample(
        for actorID: SplashSceneActorID,
        entryElapsed: TimeInterval
    ) -> SplashLotusAnimationSample {
        guard let index = order.firstIndex(of: actorID) else {
            return .presented
        }
        let localTime = entryElapsed
            - firstStart
            - TimeInterval(index) * cascadeStagger
        return SplashLotusAnimationSample(
            centerOpacity: progress(localTime / centerDuration),
            fanProgress: CGFloat(progress((localTime - fanDelay) / fanDuration)),
            heartOpacity: progress((localTime - heartDelay) / heartDuration)
        )
    }

    private static func progress(_ value: Double) -> Double {
        if value <= 0.000_001 { return 0 }
        if value >= 0.999_999 { return 1 }
        return SplashMotionTiming.smootherStep(value)
    }
}

/// A deterministic sample of the splash performance. Entry/exit travel and
/// note-driven wave packets share one clock without replacing the rest geometry.
struct SplashScenePresentation: Equatable {
    let state: SplashSceneMotionState
    let performanceElapsed: TimeInterval
    let motionTuning: SplashMotionTuning
    let scoreEvents: [SplashWaveNoteEvent]

    static let presented = SplashScenePresentation(
        state: .presented,
        performanceElapsed: 0,
        motionTuning: .standard,
        scoreEvents: SplashPerformanceScore.noteEvents
    )

    static func sample(
        performanceElapsed: TimeInterval,
        exitElapsed: TimeInterval?,
        reduceMotion: Bool,
        motionTuning: SplashMotionTuning = .standard,
        scoreEvents: [SplashWaveNoteEvent] = SplashPerformanceScore.noteEvents
    ) -> SplashScenePresentation {
        guard !reduceMotion else { return .presented }

        let performanceElapsed = max(performanceElapsed, 0)
        if let exitElapsed {
            return SplashScenePresentation(
                state: .exiting(elapsed: max(exitElapsed, 0)),
                performanceElapsed: performanceElapsed,
                motionTuning: motionTuning,
                scoreEvents: scoreEvents
            )
        }
        if performanceElapsed < SplashMotionTiming.entranceCompleteTime {
            return SplashScenePresentation(
                state: .entering(elapsed: performanceElapsed),
                performanceElapsed: performanceElapsed,
                motionTuning: motionTuning,
                scoreEvents: scoreEvents
            )
        }
        return SplashScenePresentation(
            state: .living(elapsed: performanceElapsed),
            performanceElapsed: performanceElapsed,
            motionTuning: motionTuning,
            scoreEvents: scoreEvents
        )
    }

    var sceneOpacity: Double { 1 }
    func lotusAnimation(
        for actorID: SplashSceneActorID
    ) -> SplashLotusAnimationSample {
        switch state {
        case .presented, .living:
            return .presented
        case .entering(let elapsed):
            return SplashLotusChoreography.sample(
                for: actorID,
                entryElapsed: elapsed
            )
        case .exiting(let elapsed):
            let exitStartPerformance = max(performanceElapsed - elapsed, 0)
            let reverseRate = SplashLotusChoreography.activeDuration
                / SplashLotusChoreography.exitDuration
            let reverseEntryElapsed = min(
                SplashLotusChoreography.entryEnd,
                exitStartPerformance
            ) - elapsed * reverseRate
            return SplashLotusChoreography.sample(
                for: actorID,
                entryElapsed: reverseEntryElapsed
            )
        }
    }

    var wordmarkOpacity: Double {
        Double(actorProgress(
            entryDelay: SplashMotionTiming.wordmarkEntryDelay,
            entryDuration: SplashMotionTiming.wordmarkEntryDuration,
            exitDuration: SplashMotionTiming.wordmarkExitDuration
        ))
    }

    var sunProgress: CGFloat {
        actorProgress(
            entryDelay: SplashMotionTiming.sunEntryDelay,
            entryDuration: SplashMotionTiming.sunEntryDuration,
            exitDuration: SplashMotionTiming.sunExitDuration
        )
    }

    var navigationOpacity: Double {
        Double(actorProgress(
            entryDelay: SplashMotionTiming.navigationEntryDelay,
            entryDuration: SplashMotionTiming.navigationEntryDuration,
            exitDuration: SplashMotionTiming.navigationExitDuration
        ))
    }

    var cloudOpacity: Double {
        switch state {
        case .presented:
            return 1
        case .entering(let elapsed), .living(let elapsed):
            return Double(SplashMotionTiming.revealProgress(
                elapsed: elapsed,
                delay: SplashMotionTiming.cloudEntryDelay,
                duration: SplashMotionTiming.cloudEntryDuration
            ))
        case .exiting(let elapsed):
            let exitStart = max(performanceElapsed - elapsed, 0)
            let entryOpacity = SplashMotionTiming.revealProgress(
                elapsed: exitStart,
                delay: SplashMotionTiming.cloudEntryDelay,
                duration: SplashMotionTiming.cloudEntryDuration
            )
            return Double(entryOpacity * (1 - CGFloat(SplashMotionTiming.smootherStep(
                elapsed / SplashMotionTiming.cloudExitDuration
            ))))
        }
    }

    var waveMotionPhase: CGFloat {
        SplashPerformanceScore.waveVoices
            .map {
                let sample = waveMotionSample(for: $0.actorID)
                return max(sample.phase, sample.bedPhase)
            }
            .max() ?? 0
    }

    var waveMotionAmount: CGFloat {
        SplashPerformanceScore.waveVoices
            .map { waveMotionSample(for: $0.actorID).totalAmplitude }
            .max() ?? 0
    }

    func waveMotionSample(for actorID: SplashSceneActorID) -> SplashWaveMotionSample {
        SplashPerformanceScore.waveMotionSample(
            for: actorID,
            performanceElapsed: performanceElapsed,
            events: scoreEvents,
            tuning: motionTuning
        )
    }

    var isInteractive: Bool {
        switch state {
        case .presented, .living:
            true
        case .entering(let elapsed):
            elapsed >= SplashMotionTiming.interactionReadyTime
        case .exiting:
            false
        }
    }

    func horizontalTravelFactor(
        forWaveAt index: Int,
        edge: SplashWaveEntryEdge,
        count: Int
    ) -> CGFloat {
        switch state {
        case .presented, .living:
            0
        case .entering(let elapsed):
            (1 - SplashMotionTiming.entryProgress(for: index, elapsed: elapsed))
                * edge.rawValue
        case .exiting(let elapsed):
            -SplashMotionTiming.exitProgress(
                for: index,
                count: count,
                elapsed: elapsed
            ) * edge.rawValue
        }
    }

    func waveExtent(
        forWaveAt index: Int,
        edge: SplashWaveEntryEdge,
        count: Int
    ) -> SplashWaveExtent {
        switch state {
        case .presented, .living:
            .full
        case .entering(let elapsed):
            .entering(
                progress: SplashMotionTiming.entryProgress(for: index, elapsed: elapsed),
                edge: edge
            )
        case .exiting(let elapsed):
            .exiting(
                progress: SplashMotionTiming.exitProgress(
                    for: index,
                    count: count,
                    elapsed: elapsed
                ),
                entryEdge: edge
            )
        }
    }

    private func actorProgress(
        entryDelay: TimeInterval,
        entryDuration: TimeInterval,
        exitDuration: TimeInterval
    ) -> CGFloat {
        switch state {
        case .presented, .living:
            1
        case .entering(let elapsed):
            SplashMotionTiming.revealProgress(
                elapsed: elapsed,
                delay: entryDelay,
                duration: entryDuration
            )
        case .exiting(let elapsed):
            1 - CGFloat(SplashMotionTiming.smootherStep(elapsed / exitDuration))
        }
    }
}

enum SplashLayoutMode: Equatable {
    case wideLandscape
    case compactLandscape
    case tabletPortrait
    case phonePortrait
}

struct SplashLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets
    let mode: SplashLayoutMode

    init(size: CGSize, safeAreaInsets: EdgeInsets = EdgeInsets()) {
        self.size = size
        self.safeAreaInsets = safeAreaInsets
        mode = Self.mode(for: size)
    }

    static func mode(for size: CGSize) -> SplashLayoutMode {
        if size.width >= size.height {
            return size.height < 520 ? .compactLandscape : .wideLandscape
        }
        return size.width < 600 ? .phonePortrait : .tabletPortrait
    }

    /// Rotation preserves this dimension on a given device, so art sized from it
    /// keeps the same intrinsic scale in landscape and portrait.
    var shortSide: CGFloat {
        min(size.width, size.height)
    }

    var wordmarkLeading: CGFloat {
        let proportion: CGFloat
        switch mode {
        case .wideLandscape: proportion = 0.09
        case .compactLandscape: proportion = 0.06
        case .tabletPortrait, .phonePortrait: proportion = 0.075
        }
        return max(safeAreaInsets.leading + 24, size.width * proportion)
    }

    var wordmarkTop: CGFloat {
        let proportion: CGFloat
        switch mode {
        case .wideLandscape: proportion = 0.105
        case .compactLandscape: proportion = 0.04
        case .tabletPortrait, .phonePortrait: proportion = 0.045
        }
        return max(safeAreaInsets.top + 18, size.height * proportion)
    }

    var wordmarkFontSize: CGFloat {
        shortSide * 0.115
    }

    var sunCenter: CGPoint {
        switch mode {
        case .wideLandscape: CGPoint(x: size.width * 0.695, y: size.height * 0.325)
        case .compactLandscape: CGPoint(x: size.width * 0.70, y: size.height * 0.28)
        case .tabletPortrait: CGPoint(x: size.width * 0.69, y: size.height * 0.285)
        case .phonePortrait: CGPoint(x: size.width * 0.70, y: size.height * 0.275)
        }
    }

    /// The dawn field shares the sun's responsive placement rather than assuming
    /// a single device's coordinates. That keeps the transition visibly born
    /// behind the sun in every orientation.
    var sunUnitPoint: UnitPoint {
        UnitPoint(
            x: sunCenter.x / max(size.width, 1),
            y: sunCenter.y / max(size.height, 1)
        )
    }

    var sunDiameter: CGFloat {
        shortSide * 0.38
    }

    /// Use the resting envelope so the sun does not bob with pad envelopes.
    var sunriseHorizon: CGFloat {
        let worldX = (sunCenter.x - waveWorldCenter.x) / waveWorldSize.width + 0.5
        let coverage = SplashWaveGenerator.coverageRibbon(palette: .night)
        let index = min(max(Int(worldX * CGFloat(coverage.top.count - 1)), 0), coverage.top.count - 1)
        return waveWorldCenter.y + (coverage.top[index].y - 0.5) * waveWorldSize.height
    }

    func risingSunCenter(progress: Double) -> CGPoint {
        let p = CGFloat(min(max(progress, 0), 1))
        let initialY = sunriseHorizon + sunDiameter * 0.4
        return CGPoint(x: sunCenter.x, y: initialY + (sunCenter.y - initialY) * p)
    }

    var waveWorldSize: CGSize {
        CGSize(width: shortSide * 3.0, height: shortSide * 0.52)
    }

    var waveWorldVerticalOffset: CGFloat {
        shortSide * 0.060
    }

    var waveWorldCenter: CGPoint {
        CGPoint(
            x: size.width * 0.5,
            y: size.height * 0.55 + waveWorldVerticalOffset
        )
    }

    var lotusPlacements: [SplashLotusPlacement] {
        switch mode {
        case .wideLandscape:
            [
                .init(id: .lotusLeft, center: .init(x: 0.39, y: 0.62), width: 0.29, style: .lavender),
                .init(id: .lotusCenter, center: .init(x: 0.59, y: 0.53), width: 0.17, style: .blue),
                .init(id: .lotusRight, center: .init(x: 0.76, y: 0.64), width: 0.20, style: .blue)
            ]
        case .compactLandscape:
            [
                .init(id: .lotusLeft, center: .init(x: 0.38, y: 0.56), width: 0.29, style: .lavender),
                .init(id: .lotusCenter, center: .init(x: 0.59, y: 0.49), width: 0.17, style: .blue),
                .init(id: .lotusRight, center: .init(x: 0.77, y: 0.59), width: 0.20, style: .blue)
            ]
        case .tabletPortrait:
            [
                .init(id: .lotusLeft, center: .init(x: 0.25, y: 0.61), width: 0.29, style: .lavender),
                .init(id: .lotusCenter, center: .init(x: 0.58, y: 0.53), width: 0.17, style: .blue),
                .init(id: .lotusRight, center: .init(x: 0.80, y: 0.64), width: 0.20, style: .blue)
            ]
        case .phonePortrait:
            [
                .init(id: .lotusLeft, center: .init(x: 0.22, y: 0.60), width: 0.29, style: .lavender),
                .init(id: .lotusCenter, center: .init(x: 0.58, y: 0.52), width: 0.17, style: .blue),
                .init(id: .lotusRight, center: .init(x: 0.82, y: 0.63), width: 0.20, style: .blue)
            ]
        }
    }

    var navigationFontSize: CGFloat {
        shortSide * (shortSide < 600 ? 0.064 : 0.052)
    }

    var navigationSpacing: CGFloat {
        shortSide * (shortSide < 600 ? 0.006 : 0.075)
    }

    var navigationBottom: CGFloat {
        max(safeAreaInsets.bottom + 14, size.height * (mode == .compactLandscape ? 0.015 : 0.035))
    }

    var navigationLeading: CGFloat {
        max(safeAreaInsets.leading + 24, size.width * (isPortrait ? 0.055 : 0.055))
    }

    var navigationPhonePortraitInset: CGFloat {
        guard mode == .phonePortrait else { return 0 }
        return max(12, max(safeAreaInsets.leading, safeAreaInsets.trailing) + 8)
    }

    var alignsNavigationToLeading: Bool {
        mode == .wideLandscape || mode == .compactLandscape
    }

    private var isPortrait: Bool {
        mode == .tabletPortrait || mode == .phonePortrait
    }
}

struct SplashSceneView: View {
    var presentation: SplashScenePresentation = .presented
    var atmosphere: SplashAtmosphereSample = .night
    var cloudTime: Double?
    var resonance: SplashWaveResonanceSample?
    var selectedMenu: SplashMenuItem = .start
    var onSelectMenu: (SplashMenuItem) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let layout = SplashLayout(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)
            let restingSunCenter = layout.risingSunCenter(progress: atmosphere.progress)
            let sunCenter = CGPoint(x: restingSunCenter.x,
                                    y: restingSunCenter.y + (1 - presentation.sunProgress) * 44)

            ZStack(alignment: .topLeading) {
                SplashAtmosphereLayer(
                    atmosphere: atmosphere,
                    lightCenter: sunCenter,
                    horizon: layout.sunriseHorizon,
                    sunRadius: layout.sunDiameter / 2,
                    cloudTime: cloudTime
                )
                    .accessibilityIdentifier(SplashSceneActorID.background.rawValue)

                SplashSunView(
                    progress: presentation.sunProgress,
                    palette: atmosphere.palette
                )
                    .frame(width: layout.sunDiameter, height: layout.sunDiameter)
                    .position(sunCenter)
                    .accessibilityIdentifier(SplashSceneActorID.sun.rawValue)
                    .accessibilityHidden(true)

                SplashAtmosphereLayer(
                    atmosphere: atmosphere,
                    lightCenter: sunCenter,
                    horizon: layout.sunriseHorizon,
                    sunRadius: layout.sunDiameter / 2,
                    drawsClouds: true,
                    cloudTime: cloudTime
                )
                .opacity(presentation.cloudOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                SplashWaveField(
                    layout: layout,
                    presentation: presentation,
                    resonance: resonance,
                    palette: atmosphere.palette
                )
                    .accessibilityHidden(true)

                ForEach(layout.lotusPlacements) { placement in
                    let lotusWidth = layout.shortSide * placement.width
                    let lotusAnimation = presentation.lotusAnimation(
                        for: placement.id
                    )

                    SplashLotusView(
                        actorID: placement.id,
                        style: placement.style,
                        palette: atmosphere.palette,
                        centerOpacity: lotusAnimation.centerOpacity,
                        heartOpacity: lotusAnimation.heartOpacity,
                        leftFanProgress: lotusAnimation.fanProgress,
                        rightFanProgress: lotusAnimation.fanProgress
                    )
                    .frame(
                        width: lotusWidth,
                        height: lotusWidth * 0.82
                    )
                    .position(
                        x: layout.size.width * placement.center.x,
                        y: layout.size.height * placement.center.y
                            + layout.waveWorldVerticalOffset
                    )
                    .accessibilityHidden(true)
                }

                // Wordmark presentation is deferred while the scene animation is refined.

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    SplashNavigationBar(
                        selectedItem: selectedMenu,
                        fontSize: layout.navigationFontSize,
                        spacing: layout.navigationSpacing,
                        usesEqualWidthItems: layout.mode == .phonePortrait,
                        ink: atmosphere.sunrise.navigationInk,
                        selectedInk: atmosphere.sunrise.selectedInk,
                        action: onSelectMenu
                    )
                    .frame(maxWidth: .infinity, alignment: layout.alignsNavigationToLeading ? .leading : .center)
                    .padding(.leading, layout.alignsNavigationToLeading ? layout.navigationLeading : 0)
                    .padding(.trailing, layout.alignsNavigationToLeading ? 0 : layout.navigationLeading)
                    .padding(.horizontal, layout.navigationPhonePortraitInset)
                    .padding(.bottom, layout.navigationBottom)
                    .opacity(presentation.navigationOpacity)
                    .accessibilityIdentifier(SplashSceneActorID.navigation.rawValue)
                }
                    .disabled(!presentation.isInteractive)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .opacity(presentation.sceneOpacity)
        }
    }
}

private struct SplashAtmosphereLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var atmosphere: SplashAtmosphereSample = .night
    var lightCenter: CGPoint
    var horizon: CGFloat
    var sunRadius: CGFloat
    var drawsClouds = false
    var cloudTime: Double?

    var body: some View {
        GeometryReader { proxy in
#if os(iOS)
            SunriseSkyView(uniforms: SunriseUniforms(
                viewport: SIMD4(Float(proxy.size.width), Float(proxy.size.height),
                                Float(lightCenter.x), Float(lightCenter.y)),
                story: SIMD4(Float(atmosphere.progress), Float(horizon),
                             Float(sunRadius), Float(reduceMotion ? 0 : cloudTime ?? atmosphere.sunrise.cloudTime)),
                optics: SIMD4(Float(atmosphere.sunrise.solarElevationRadians),
                              Float(atmosphere.sunrise.exposure),
                              Float(atmosphere.sunrise.paperSpread),
                              Float(atmosphere.sunrise.paperAmount))
            ), drawsClouds: drawsClouds)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay {
                if !drawsClouds {
                    Image("NeutralPaperGrainV1")
                        .resizable(resizingMode: .tile)
                        .blendMode(.softLight)
                        // Keep the opening canvas as the approved uninterrupted
                        // ink field. Grain returns with the authored sunrise.
                        .opacity(0.30 * min(max(atmosphere.progress / 0.10, 0), 1))
                        .allowsHitTesting(false)
                }
            }
            .clipped()
#else
            Rectangle().fill(PlanetFocusPalette.canvasInk)
#endif
        }
    }
}

#if os(iOS)
private enum SplashScreenStage: Equatable {
    case opening
    case chooser
    case story(Story)
    case settings
    case stats
}

#if DEBUG
private enum PerformanceDeskSection: Hashable {
    case splashTuning
    case scoreMonitor
    case storyRunner
}

private enum PerformanceDeskContext {
    case splash
    case story(Story)

    var title: String {
        switch self {
        case .splash: "Splash"
        case .story(let story): story.title
        }
    }

    var isSplash: Bool {
        if case .splash = self { return true }
        return false
    }
}
#endif

struct SplashScreenView: View {
    @Binding var selectedStory: Story
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SessionLifecycle.self) private var sessionLifecycle
    @Environment(AppPreferences.self) private var preferences
    @Environment(HealthSessionCoordinator.self) private var healthSync
    @Environment(FocusIdleTimerCoordinator.self) private var idleTimer
    @Environment(LiveActivitySessionCoordinator.self) private var liveActivity
    @Environment(SplashAmbientPlayback.self) private var splashAmbient
    @AppStorage("autumn.branch.record.v1") private var persistedAutumn = Data()
    @State private var autumnRecord = AutumnBranchRecord()
    @State private var synthesizer = PerformanceSynthesizer()
    @State private var auditionEnabled = true
    @State private var sceneVolume = 0.65
    @State private var sceneMuted = false
    @State private var idleTimerRequestID = UUID()
    @State private var liveActivitySceneID = UUID()
    @State private var showsSceneSettings = false
    @State private var runnerDuration: FocusDuration = .fiveMinutes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedMenu: SplashMenuItem = .start
    @State private var stage: SplashScreenStage
    @State private var performanceClock = PerformanceClock()
    @State private var exitStartedAt: Date?
    @State private var motionTuning = SplashMotionTuning.standard
    @State private var resonanceTuning = SplashWaveResonanceTuning.standard
    @State private var manualEvent: SplashWaveNoteEvent?
    @State private var manualEventSequence = 0
    @State private var manualTonalSlot = 4
    @State private var manualGateBeats = 6.0
    @State private var scoreSeed = Int(SplashPerformanceScore.defaultSeed)
    @State private var atmosphereProgress = 0.0
    @State private var activePerformanceSession: PerformanceSession?
    @State private var performancePurpose: SplashPerformancePurpose?
    @State private var activeSplashScoreEvents: [SplashWaveNoteEvent]?
    @State private var ambientVisualScoreEvents: [SplashWaveNoteEvent]?
#if DEBUG
    @State private var isPerformanceDeskVisible: Bool
    @State private var expandedPerformanceDeskSections: Set<PerformanceDeskSection>
    @State private var sunriseAuditIndex = 0
#endif

    init(selectedStory: Binding<Story>) {
        _selectedStory = selectedStory
#if DEBUG
        let initialStage: SplashScreenStage = ProcessInfo.processInfo.arguments.contains(
            "--story-chooser-review"
        ) ? .chooser : ProcessInfo.processInfo.arguments.contains("--autumn-checkpoint") || ProcessInfo.processInfo.arguments.contains("--autumn-light-audit") || ProcessInfo.processInfo.arguments.contains("--session-ui-review") || ProcessInfo.processInfo.arguments.contains("--session-ending-review") || ProcessInfo.processInfo.arguments.contains("--deer-study") ? .story(.autumnTree) : .opening
#else
        let initialStage: SplashScreenStage = .opening
#endif
        _stage = State(initialValue: initialStage)
        _atmosphereProgress = State(
            initialValue: Self.debugAtmosphereProgress
        )
#if DEBUG
        _runnerDuration = State(initialValue: ProcessInfo.processInfo.arguments.contains("--splash-audio-review")
            ? .fiveMinutes : Self.isRunnerReview ? .oneMinute : .twoMinutes)
        _isPerformanceDeskVisible = State(
            initialValue: !Self.isAtmosphereReview && (Self.isRunnerReview || Self.isScoreMonitorReview || Self.isResonanceReview || ProcessInfo.processInfo.arguments.contains("--autumn-checkpoint") || ProcessInfo.processInfo.arguments.contains("--autumn-light-audit"))
        )
        _expandedPerformanceDeskSections = State(
            initialValue: Self.isScoreMonitorReview
                ? [.scoreMonitor]
                : Self.isRunnerReview
                    ? [.storyRunner]
                    : [.splashTuning]
        )
        _activePerformanceSession = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("--splash-audio-review")
                ? PerformanceSession(duration: .fiveMinutes, randomSeed: SplashPerformanceScore.defaultSeed)
                : ProcessInfo.processInfo.arguments.contains("--session-ending-review")
                ? PerformanceSession(duration: .oneMinute, startedAt: .now.addingTimeInterval(-58))
                : Self.isRunnerReview
                ? PerformanceSession(
                    duration: .oneMinute,
                    randomSeed: SplashPerformanceScore.defaultSeed
                )
                : nil
        )
        _performancePurpose = State(initialValue: Self.isRunnerReview
            || ProcessInfo.processInfo.arguments.contains("--splash-audio-review")
            || ProcessInfo.processInfo.arguments.contains("--session-ending-review")
            ? .splashAudition : nil)
#endif
    }

    private static var debugAtmosphereProgress: Double {
#if DEBUG
        let prefix = "--atmosphere-progress="
        let argumentValue = ProcessInfo.processInfo.arguments.first(
            where: { $0.hasPrefix(prefix) }
        ).flatMap { Double($0.dropFirst(prefix.count)) }
        let environmentValue = ProcessInfo.processInfo.environment[
            "SPLASH_ATMOSPHERE_PROGRESS"
        ].flatMap(Double.init)
        guard let value = argumentValue ?? environmentValue else {
            return 0
        }
        return min(max(value, 0), 1)
#else
        return 0
#endif
    }

    private static var isAmbientReview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--splash-ambient-review")
#else
        false
#endif
    }

    private static var ambientReviewElapsed: TimeInterval? {
#if DEBUG
        let prefix = "--splash-ambient-elapsed="
        return ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })
            .flatMap { Double($0.dropFirst(prefix.count)) }
            ?? ProcessInfo.processInfo.environment["SPLASH_AMBIENT_ELAPSED"].flatMap(Double.init)
#else
        nil
#endif
    }

    private static var hasDebugAtmosphereOverride: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--atmosphere-progress=") }
            || ProcessInfo.processInfo.environment["SPLASH_ATMOSPHERE_PROGRESS"] != nil
#else
        false
#endif
    }

    private static var isResonanceReview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--resonance-review")
#else
        false
#endif
    }

    private static var isScoreMonitorReview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--score-monitor-review")
#else
        false
#endif
    }

    private static var isRunnerReview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--performance-runner-review")
            || ProcessInfo.processInfo.environment[
                "PERFORMANCE_RUNNER_REVIEW"
            ] == "1"
#else
        false
#endif
    }

    private static var isDevelopmentSession: Bool {
#if DEBUG
        isRunnerReview
            || ProcessInfo.processInfo.arguments.contains("--session-ui-review")
            || ProcessInfo.processInfo.arguments.contains("--session-ending-review")
            || ProcessInfo.processInfo.arguments.contains("--autumn-checkpoint")
            || ProcessInfo.processInfo.arguments.contains("--autumn-light-audit")
            || ProcessInfo.processInfo.arguments.contains("--autumn-encounter-review")
#else
        false
#endif
    }

    private func activeRuntime(for story: Story) -> SessionRuntime? {
        guard sessionLifecycle.activeStoryID == story.rawValue else { return nil }
        return sessionLifecycle.activeRuntime
    }

    /// Static, clean-canvas review mode for the 5% visual audit.  It deliberately
    /// avoids the running transport and the debug desk so each screenshot represents
    /// one exact, reproducible atmosphere sample.
    private static var isAtmosphereReview: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["SPLASH_ATMOSPHERE_REVIEW"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--sunrise-audit")
#else
        false
#endif
    }

    private var reviewProgress: Double? {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--sunrise-audit") {
            return Double(sunriseAuditIndex) / 20
        }
#endif
        return nil
    }

    private var manualAtmosphereProgress: Double? {
#if DEBUG
        guard (isPerformanceDeskVisible || Self.isAtmosphereReview || Self.hasDebugAtmosphereOverride),
              activePerformanceSession == nil, !splashAmbient.isActive else { return nil }
        return atmosphereProgress
#else
        nil
#endif
    }

    private static var isResonancePeakReview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--resonance-peak-review")
#else
        false
#endif
    }

    private static func reviewEvent(
        at scoreBeat: Double
    ) -> SplashWaveNoteEvent? {
        let event = SplashWaveNoteEvent(
            id: "resonance-review",
            tonalSlot: 4,
            startBeat: 0,
            gateBeats: 6,
            envelope: SplashPerformanceScore.noteEnvelope,
            intensity: 1
        )
        if isResonancePeakReview {
            return SplashWaveNoteEvent(
                id: event.id,
                tonalSlot: event.tonalSlot,
                startBeat: scoreBeat - event.totalBeats / 2,
                gateBeats: event.gateBeats,
                envelope: event.envelope
            )
        }
        if isResonanceReview {
            let localBeat = scoreBeat.truncatingRemainder(
                dividingBy: event.totalBeats + 1
            )
            guard localBeat < event.totalBeats else { return nil }
            return SplashWaveNoteEvent(
                id: event.id,
                tonalSlot: event.tonalSlot,
                startBeat: scoreBeat - localBeat,
                gateBeats: event.gateBeats,
                envelope: event.envelope
            )
        }
        return nil
    }

    private static func resonance(
        manualEvent: SplashWaveNoteEvent?,
        scoreBeat: Double,
        tuning: SplashWaveResonanceTuning,
        scoreEvents: [SplashWaveNoteEvent],
        reduceMotion: Bool
    ) -> SplashWaveResonanceSample? {
        guard !reduceMotion else { return nil }

        var contributions = SplashPerformanceScore.melodyResonanceSample(
            events: scoreEvents,
            scoreBeat: scoreBeat,
            tuning: tuning,
            reduceMotion: reduceMotion
        )?.contributions ?? []

        let reviewSampleEvent = manualEvent ?? reviewEvent(at: scoreBeat)
        if let reviewSampleEvent,
           let sample = SplashWaveResonanceSample.sample(
               event: reviewSampleEvent,
               scoreBeat: scoreBeat,
               tuning: tuning
           ) {
            contributions.append(contentsOf: sample.contributions)
        }

        return contributions.isEmpty
            ? nil
            : SplashWaveResonanceSample(contributions: contributions)
    }

    var body: some View {
        finalContent
    }

    private var baseContent: AnyView {
        AnyView(ZStack {
            // A neutral fallback remains continuous while splash actors enter and leave.
            // The scene owns the full, measured atmospheric canvas below.
            PlanetFocusPalette.canvasInk.ignoresSafeArea()
            AnyView(stageContent)
            AnyView(debugOverlay)
        })
    }

    private var presentationObservedContent: AnyView {
        AnyView(baseContent
            .background(PlanetFocusPalette.canvasInk.ignoresSafeArea())
            .onAppear(perform: prepareSplashView)
            .onChange(of: autumnRecord) { _, record in
                persistedAutumn = (try? JSONEncoder().encode(record.settingsOnly)) ?? Data()
            }
            .onChange(of: activePerformanceSession) { _, _ in synchronizeAudio() }
            .onChange(of: splashAmbient.randomSeed) { _, _ in
                refreshAmbientVisualScore()
                synchronizeAudio()
            }
            .onChange(of: auditionEnabled) { _, _ in synchronizeAudio() }
            .onChange(of: sceneVolume) { _, _ in synchronizeSceneOutput() }
            .onChange(of: sceneMuted) { _, _ in synchronizeSceneOutput() })
    }

    private var idleTimerObservedContent: AnyView {
        AnyView(presentationObservedContent
            .onChange(of: preferences.volume) { _, value in sceneVolume = value }
            .onChange(of: preferences.isMuted) { _, value in sceneMuted = value }
            .onChange(of: preferences.keepScreenAwake) { _, _ in synchronizeIdleTimer() }
            .onChange(of: sessionLifecycle.activeRuntime?.id) { _, _ in synchronizeIdleTimer() }
            .onChange(of: sessionLifecycle.activeStoryID) { _, _ in synchronizeIdleTimer() }
            .onChange(of: sessionLifecycle.activeOutcome) { _, _ in synchronizeIdleTimer() }
            .onChange(of: sessionLifecycle.hasPendingTerminalEvent) { _, _ in synchronizeIdleTimer() }
            .onChange(of: stage) { _, _ in synchronizeIdleTimer() })
    }

    private var finalContent: some View {
        idleTimerObservedContent
#if DEBUG
            .onChange(of: showsSceneSettings) { _, shown in if shown { isPerformanceDeskVisible = false } }
            .onChange(of: isPerformanceDeskVisible) { _, shown in if shown { showsSceneSettings = false } }
#endif
            .onChange(of: scenePhase) { _, phase in
                synchronizeAudio()
                synchronizeIdleTimer()
                if phase == .active { refreshAmbientVisualScore() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification), perform: handleAudioInterruption)
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification), perform: handleAudioRouteChange)
            .task(id: activePerformanceSession) { await fadeSplashAudioAtSessionEnd(activePerformanceSession) }
            .task(id: splashAmbient.randomSeed) { await maintainAmbientVisualScore() }
            .task(id: sessionLifecycle.activeRuntime?.id) { await maintainIdleTimerEligibility() }
            .task(id: liveActivitySynchronizationID) { await synchronizeLiveActivity() }
            .onDisappear(perform: tearDownSplashView)
#if DEBUG
            .onAppear(perform: requestSunriseLandscapeIfNeeded)
#endif
    }

    private func synchronizeAudio() {
        synchronizeSceneOutput()
        guard scenePhase == .active else { synthesizer.stop(); return }
        guard auditionEnabled,
              ProcessInfo.processInfo.environment["SPLASH_AUDIO_DISABLED"] != "1" else {
            synthesizer.fadeOut()
            return
        }
        if performancePurpose == .splashAudition,
           let session = activePerformanceSession, !session.isPaused {
            synthesizer.play(session: session, events: splashScoreEvents + (manualEvent.map { [$0] } ?? []))
            return
        }
        guard performancePurpose != .storyPreview,
              activePerformanceSession == nil,
              sessionLifecycle.activeRuntime == nil,
              splashAmbient.isActive,
              let seed = splashAmbient.randomSeed else {
            synthesizer.fadeOut()
            return
        }
        guard let startedAt = splashAmbient.startedAt else {
            synthesizer.fadeOut()
            return
        }
        synthesizer.playAmbient(seed: seed, startedAt: startedAt)
    }

    @MainActor
    private func maintainAmbientVisualScore() async {
        guard let seed = splashAmbient.randomSeed else { return }
        while !Task.isCancelled, splashAmbient.isActive,
              splashAmbient.randomSeed == seed {
            let elapsed = splashAmbient.elapsed(at: .now)
            ambientVisualScoreEvents = SplashAmbientScore.events(
                from: max(0, elapsed - SplashAmbientScore.tailAllowance),
                through: elapsed + 30,
                seed: seed
            )
            try? await Task.sleep(for: .seconds(10))
        }
        if splashAmbient.randomSeed == seed { ambientVisualScoreEvents = nil }
    }

    @MainActor
    private func refreshAmbientVisualScore() {
        guard activePerformanceSession == nil, splashAmbient.isActive,
              let seed = splashAmbient.randomSeed else { return }
        let elapsed = splashAmbient.elapsed(at: .now)
        ambientVisualScoreEvents = SplashAmbientScore.events(
            from: max(0, elapsed - SplashAmbientScore.tailAllowance),
            through: elapsed + 30,
            seed: seed
        )
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .opening:
            TimelineView(.animation(
                minimumInterval: reduceMotion ? 1 : 1.0 / 60.0,
                paused: Self.isAtmosphereReview
            )) { context in
                let transportState = activePerformanceSession.map {
                    PerformanceRunner(session: $0).sample(at: context.date)
                }
                let performanceElapsed = transportState?.elapsedTime
                    ?? (splashAmbient.isActive
                        ? splashAmbient.elapsed(at: context.date)
                        : performanceClock.elapsed(at: context.date))
                let visualScoreEvents = renderedScoreEvents
                let presentation = SplashScenePresentation.sample(
                    performanceElapsed: Self.isAtmosphereReview ? 20 : performanceElapsed,
                    exitElapsed: exitStartedAt.map { context.date.timeIntervalSince($0) },
                    reduceMotion: reduceMotion,
                    motionTuning: renderedMotionTuning,
                    scoreEvents: visualScoreEvents
                )
                let ambientProgress = reduceMotion ? 0 : splashAmbient.progress(at: context.date)
                let atmosphere = SplashAtmosphereDirector.sample(
                    progress: reviewProgress ?? transportState?.progress
                        ?? manualAtmosphereProgress ?? ambientProgress
                )
                let resonance = Self.resonance(
                    manualEvent: manualEvent,
                    scoreBeat: SplashPerformanceScore.scoreBeat(for: performanceElapsed, tuning: renderedMotionTuning),
                    tuning: resonanceTuning,
                    scoreEvents: visualScoreEvents,
                    reduceMotion: reduceMotion
                )
                SplashSceneView(
                    presentation: presentation,
                    atmosphere: atmosphere,
                    cloudTime: reviewProgress == nil && transportState == nil
                        && manualAtmosphereProgress == nil
                        ? splashAmbient.elapsed(at: context.date) : nil,
                    resonance: resonance,
                    selectedMenu: selectedMenu,
                    onSelectMenu: selectMenu
                )
                .ignoresSafeArea()
            }
            .task(id: exitStartedAt) { await finishExitIfNeeded() }
        case .chooser:
            StoryChooserView(onChoose: chooseStory, onBack: resetSplash)
        case let .story(story):
            storyLaunchView(for: story)
        case .settings:
            PreferencesView(onBack: resetSplash)
        case .stats:
            StatsDestinationView(onBack: resetSplash)
        }
    }

    private func chooseStory(_ story: Story) {
        selectedStory = story
        stage = .story(story)
    }

    @ViewBuilder
    private var debugOverlay: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ambient-route-test") {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                Text("Ambient route state")
                    .opacity(0.001)
                    .accessibilityIdentifier("ambientRouteState")
                    .accessibilityValue(ambientRouteState(at: context.date))
                    .accessibilityHidden(false)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--sunrise-audit") {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button { sunriseAuditIndex = min(20, sunriseAuditIndex + 1) } label: {
                        Color.clear.frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Advance sunrise audit")
                    .accessibilityIdentifier("sunriseAuditNext")
                    .accessibilityValue(String(sunriseAuditIndex))
                }
            }
        }
        if let context = performanceDeskContext, isPerformanceDeskVisible {
            PerformanceDesk(
                expandedSections: $expandedPerformanceDeskSections, context: context,
                autumnRecord: $autumnRecord, onAutumnGust: triggerAutumnGust,
                onAutumnBird: triggerAutumnBird, onAutumnDeer: triggerAutumnDeer,
                speedMultiplier: motionSpeedBinding, amountMultiplier: motionAmountBinding,
                atmosphereProgress: $atmosphereProgress, resonanceStrength: resonanceStrengthBinding,
                resonanceWidth: resonanceWidthBinding, tonalSlot: $manualTonalSlot,
                gateBeats: $manualGateBeats, scoreSeed: $scoreSeed,
                onTriggerEvent: triggerPerformanceEvent, onReset: resetMotionTuning,
                performanceClock: PerformanceClock(startedAt: splashAmbient.startedAt ?? performanceClock.startedAt), motionTuning: renderedMotionTuning,
                manualEvent: manualEvent, scoreEvents: renderedScoreEvents,
                isAmbientPlayback: activePerformanceSession == nil && splashAmbient.isActive,
                runnerDuration: $runnerDuration, activePerformanceSession: activePerformanceSession,
                onRun: runCurrentScene, onStop: stopCurrentScene,
                onPauseResume: togglePerformancePause, auditionEnabled: $auditionEnabled,
                audioStatus: performanceDeskAudioStatus,
                onHide: { isPerformanceDeskVisible = false }
            )
            .padding(.top, 10).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        } else if performanceDeskContext != nil, !Self.isAtmosphereReview {
            Button {
                showsSceneSettings = false
                isPerformanceDeskVisible = true
            } label: {
                Label(stage == .opening ? "Controls" : "Dev controls", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("developerControls")
            .buttonStyle(.borderedProminent)
            .tint(PlanetFocusPalette.canvasInk.opacity(0.92))
            .padding(.top, 10).padding(.trailing, 16).padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                alignment: stage == .opening ? .topTrailing : .bottomTrailing)
        }
#endif
    }

#if DEBUG
    private func ambientRouteState(at date: Date) -> String {
        let started = splashAmbient.startedAt?.timeIntervalSince1970 ?? -1
        let audioStart = synthesizer.isPlayingAmbient ? started : -1
        let audioSeed = synthesizer.isPlayingAmbient ? (synthesizer.ambientSeed ?? UInt64.max) : UInt64.max
        let purpose: String
        switch performancePurpose {
        case .splashAudition: purpose = "splash"
        case .storyPreview: purpose = "story"
        case nil: purpose = "none"
        }
        return "start=\(started);elapsed=\(splashAmbient.elapsed(at: date));purpose=\(purpose);audioStart=\(audioStart);audioSeed=\(audioSeed)"
    }
#endif

    private func storyLaunchView(for story: Story) -> some View {
        let liveRuntime = activeRuntime(for: story)
        let liveSessionID = liveRuntime?.id
        return StorySceneLaunchView(
            story: story,
            // Splash Controls can keep auditioning while someone browses setup,
            // but they must never become a story's apparent meditation session.
            session: performancePurpose == .storyPreview ? activePerformanceSession : nil,
            runtime: liveRuntime,
            durableOutcome: liveSessionID == nil ? nil : sessionLifecycle.activeOutcome,
            persistenceError: liveSessionID == nil ? nil : sessionLifecycle.lastError?.localizedDescription,
            autumnRecord: autumnRecord,
            volume: $sceneVolume,
            isMuted: $sceneMuted,
            showsSettings: $showsSceneSettings,
            onStart: { duration in
                autumnRecord.manualGusts = []
                autumnRecord.bird?.flight = nil
                autumnRecord.deer?.encounter = nil
                if Self.isDevelopmentSession {
                    activePerformanceSession = PerformanceSession(duration: duration)
                    performancePurpose = .storyPreview
                    splashAmbient.stop()
                }
                else {
                    _ = try await splashAmbient.stopAfterSuccessfulFocusStart {
                        try await sessionLifecycle.begin(
                            story: story,
                            duration: duration,
                            healthWriteRequested: healthSync.shouldRequestWriteForNewSession
                        )
                    }
                    // A persisted focus attempt is the boundary between browsing
                    // ambience and meditation. Failed starts leave ambience intact.
                    activePerformanceSession = nil
                    performancePurpose = nil
                    activeSplashScoreEvents = nil
                    synthesizer.fadeOut()
                }
            },
            onComplete: {
                if activePerformanceSession == nil {
                    guard let liveSessionID else { throw SessionLedgerError.attemptNotFound }
                    _ = try await sessionLifecycle.completeIfDue(id: liveSessionID)
                }
            },
            onCancel: {
                if activePerformanceSession == nil {
                    guard let liveSessionID else { throw SessionLedgerError.attemptNotFound }
                    _ = try await sessionLifecycle.cancel(id: liveSessionID)
                }
            }
        ) {
            showsSceneSettings = false
            if let liveSessionID { sessionLifecycle.dismissActivePresentation(id: liveSessionID) }
            if performancePurpose == .storyPreview {
                activePerformanceSession = nil
                activeSplashScoreEvents = nil
                performancePurpose = nil
            }
            autumnRecord = autumnRecord.settingsOnly
            stage = .chooser
        }
    }

    private func prepareSplashView() {
        splashAmbient.beginIfNeeded()
#if DEBUG
        if Self.isAmbientReview, let elapsed = Self.ambientReviewElapsed {
            splashAmbient.restart(at: Date().addingTimeInterval(-max(elapsed, 0)))
        }
#endif
        if activePerformanceSession == nil, !Self.isAtmosphereReview {
            manualEvent = nil
        }
        // Migrate away from resumable sessions. Only development settings survive
        // process termination; backgrounding keeps the in-memory clock running.
        UserDefaults.standard.removeObject(forKey: "splash.performance.session.v1")
        UserDefaults.standard.removeObject(forKey: "performance.activeStory.v1")
        if !ProcessInfo.processInfo.arguments.contains("--autumn-light-audit"),
           !ProcessInfo.processInfo.arguments.contains("--autumn-fresh"),
           let record = try? JSONDecoder().decode(AutumnBranchRecord.self, from: persistedAutumn) {
            autumnRecord = record.settingsOnly
            persistedAutumn = (try? JSONEncoder().encode(record.settingsOnly)) ?? Data()
        }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--autumn-encounter-review") {
            let duration: FocusDuration = ProcessInfo.processInfo.arguments.contains("--encounter-long")
                ? FocusDuration(minutes: 55)! : .fiveMinutes
            let plan = AutumnBranchPlan(duration: duration.timeInterval, seed: 42,
                tuning: .standard, isFullTree: true)
            let onset = plan.encounters.birds.first?.startTime ?? 30
            autumnRecord = .init()
            stage = .story(.autumnTree)
            activePerformanceSession = PerformanceSession(duration: duration,
                startedAt: .now.addingTimeInterval(-max(0, onset - 3)), randomSeed: 42)
            performancePurpose = .storyPreview
        }
        if ProcessInfo.processInfo.arguments.contains("--deer-study") {
            let prefix = "--deer-pose="
            let pose = ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }
                .flatMap { Double($0.dropFirst(prefix.count)) }
            triggerAutumnDeer(pose)
        }
#endif
        if let session = activePerformanceSession {
            activeSplashScoreEvents = SplashMusicDirector.events(for: session)
        }
        sceneVolume = preferences.volume
        sceneMuted = preferences.isMuted
        refreshAmbientVisualScore()
        synchronizeAudio()
        synchronizeIdleTimer()
    }

    private func tearDownSplashView() {
        synthesizer.fadeOut()
        idleTimer.remove(requestID: idleTimerRequestID)
        liveActivity.sceneDidDisappear(liveActivitySceneID)
    }

    private func handleAudioInterruption(_ notification: Notification) {
        if let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
           raw == AVAudioSession.InterruptionType.began.rawValue {
            synthesizer.stopImmediately()
        } else {
            synchronizeAudio()
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else {
            return
        }
        // Losing headphones silences audio, never pauses a focus session.
        auditionEnabled = false
        synthesizer.stopImmediately()
    }

    private func fadeSplashAudioAtSessionEnd(_ session: PerformanceSession?) async {
        guard let session, !session.isPaused else { return }
        try? await Task.sleep(for: .seconds(session.remainingTime(at: .now)))
        guard !Task.isCancelled else { return }
        synthesizer.fadeOut()
    }

    private func synchronizeSceneOutput() {
        synthesizer.setOutput(volume: sceneVolume, isMuted: sceneMuted)
        preferences.volume = sceneVolume
        preferences.isMuted = sceneMuted
    }

    private func synchronizeIdleTimer() {
        idleTimer.update(requestID: idleTimerRequestID, isEligible: isIdleTimerEligible)
    }

    private var liveActivitySynchronizationID: String {
        [
            sessionLifecycle.activeRuntime?.id.uuidString ?? "none",
            sessionLifecycle.activeStoryID ?? "none",
            sessionLifecycle.activeOutcome?.rawValue ?? "running",
            preferences.lockScreenCountdownEnabled.description,
            scenePhase == .active ? "foreground" : "background"
        ].joined(separator: ":")
    }

    private func synchronizeLiveActivity() async {
        let descriptor: PlanetFocusCountdownDescriptor?
        if preferences.lockScreenCountdownEnabled,
           sessionLifecycle.activeOutcome == nil,
           let runtime = sessionLifecycle.activeRuntime,
           let storyID = sessionLifecycle.activeStoryID,
           let story = Story(rawValue: storyID) {
            descriptor = PlanetFocusCountdownDescriptor(runtime: runtime, story: story)
        } else {
            descriptor = nil
        }
        await liveActivity.synchronize(
            descriptor: descriptor,
            isEnabled: preferences.lockScreenCountdownEnabled,
            sceneID: liveActivitySceneID,
            isForeground: scenePhase == .active
        )
    }

    private var isIdleTimerEligible: Bool {
        guard preferences.keepScreenAwake,
              scenePhase == .active,
              case let .story(story) = stage,
              let runtime = activeRuntime(for: story),
              sessionLifecycle.activeStoryID == story.rawValue,
              sessionLifecycle.activeOutcome == nil,
              !sessionLifecycle.hasPendingTerminalEvent else {
            return false
        }
        return !runtime.sample().isComplete
    }

    private func maintainIdleTimerEligibility() async {
        while !Task.isCancelled {
            synchronizeIdleTimer()
            guard let runtime = sessionLifecycle.activeRuntime,
                  !sessionLifecycle.hasPendingTerminalEvent,
                  !runtime.sample().isComplete else {
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

#if DEBUG
    private var performanceDeskAudioStatus: String {
        synthesizer.status + (synthesizer.outputLevel > 0.00001
            ? String(format: " · %.0f dB peak", 20 * log10(synthesizer.outputLevel)) : "")
    }

    private func triggerAutumnGust() {
        guard let session = activePerformanceSession, !session.isPaused else { return }
        autumnRecord.manualGusts.append(session.elapsedTime(at: .now))
    }

    private func requestSunriseLandscapeIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--sunrise-audit-landscape")
                || ProcessInfo.processInfo.arguments.contains("--autumn-landscape"),
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft)) { error in
            print("Sunrise landscape audit unavailable: \(error.localizedDescription)")
        }
    }

    private func togglePerformancePause() {
        guard var session = activePerformanceSession else { return }
        if session.isPaused { session.resume(at: .now) }
        else { session.pause(at: .now) }
        activePerformanceSession = session
    }
#endif

    private func startSplashRun(_ duration: FocusDuration) {
        let session = PerformanceSession(duration: duration, randomSeed: UInt64(max(scoreSeed, 0)))
        motionTuning = SplashMotionTuning(amountMultiplier: motionTuning.amountMultiplier)
        manualEvent = nil
        activeSplashScoreEvents = SplashMusicDirector.events(for: session)
        activePerformanceSession = session
        performancePurpose = .splashAudition
    }

    private func selectMenu(_ item: SplashMenuItem) {
        guard exitStartedAt == nil else { return }
        selectedMenu = item
        if item == .start {
            stage = .story(selectedStory)
            return
        }
        if item == .settings {
            stage = .settings
            return
        }
        if item == .stats {
            stage = .stats
            return
        }

        guard !reduceMotion else {
            stage = .chooser
            return
        }
        exitStartedAt = Date()
    }

    @MainActor
    private func finishExitIfNeeded() async {
        guard let exitStartedAt else { return }

        let elapsed = Date().timeIntervalSince(exitStartedAt)
        let remaining = max(SplashMotionTiming.exitCompleteTime - elapsed, 0)
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }

        guard !Task.isCancelled, self.exitStartedAt == exitStartedAt else { return }
        stage = .chooser
    }

    private func resetSplash() {
        selectedMenu = .start
        if !splashAmbient.isActive {
            splashAmbient.restart()
            performanceClock = PerformanceClock()
            motionTuning.restartKeepingValues()
            manualEvent = nil
            atmosphereProgress = 0
#if DEBUG
            isPerformanceDeskVisible = false
#endif
        }
        exitStartedAt = nil
        stage = .opening
        synchronizeAudio()
    }

    private var renderedScoreEvents: [SplashWaveNoteEvent] {
        activePerformanceSession == nil && splashAmbient.isActive
            ? (ambientVisualScoreEvents ?? []) : splashScoreEvents
    }

    private var renderedMotionTuning: SplashMotionTuning {
        activePerformanceSession == nil && splashAmbient.isActive
            ? SplashMotionTuning(amountMultiplier: motionTuning.amountMultiplier) : motionTuning
    }

    private var splashScoreEvents: [SplashWaveNoteEvent] {
        activeSplashScoreEvents ?? SplashPerformanceScore.events(
            seed: UInt64(max(scoreSeed, 0))
        )
    }

#if DEBUG
    private var motionSpeedBinding: Binding<Double> {
        Binding(
            get: { motionTuning.speedMultiplier },
            set: { newValue in
                guard !splashAmbient.isActive else { return }
                motionTuning.setSpeedMultiplier(
                    newValue,
                    performanceElapsed: performanceClock.elapsed(at: Date())
                )
            }
        )
    }

    private var motionAmountBinding: Binding<Double> {
        Binding(
            get: { motionTuning.amountMultiplier },
            set: { motionTuning.setAmountMultiplier($0) }
        )
    }

    private var resonanceStrengthBinding: Binding<Double> {
        Binding(
            get: { Double(resonanceTuning.strength) },
            set: { resonanceTuning.strength = CGFloat($0) }
        )
    }

    private var resonanceWidthBinding: Binding<Double> {
        Binding(
            get: { Double(resonanceTuning.halfWidth) },
            set: { resonanceTuning.halfWidth = CGFloat($0) }
        )
    }

    private func triggerPerformanceEvent() {
        guard activePerformanceSession?.isPaused != true,
              activePerformanceSession != nil || !splashAmbient.isActive else { return }
        let performanceElapsed = activePerformanceSession?.elapsedTime(at: .now)
            ?? performanceClock.elapsed(at: Date())
        let scoreBeat = SplashPerformanceScore.scoreBeat(
            for: performanceElapsed,
            tuning: motionTuning
        )
        manualEventSequence += 1
        let attack = min(SplashPerformanceScore.noteEnvelope.attackBeats, manualGateBeats * 0.6)
        let decay = min(SplashPerformanceScore.noteEnvelope.decayBeats, manualGateBeats - attack)
        manualEvent = SplashWaveNoteEvent(
            id: "manual-\(manualEventSequence)",
            tonalSlot: manualTonalSlot,
            startBeat: scoreBeat,
            gateBeats: manualGateBeats,
            envelope: .init(attackBeats: attack, decayBeats: decay,
                            sustainLevel: SplashPerformanceScore.noteEnvelope.sustainLevel,
                            releaseBeats: SplashPerformanceScore.noteEnvelope.releaseBeats),
            role: .pad,
            intensity: 1,
            isRepeating: false
        )
        synchronizeAudio()
    }

    private func resetMotionTuning() {
        if activePerformanceSession != nil {
            motionTuning = .standard
            resonanceTuning = .standard
            return
        }
        if splashAmbient.isActive {
            motionTuning = .standard
            resonanceTuning = .standard
            manualEvent = nil
            return
        }
        motionTuning.reset(
            performanceElapsed: performanceClock.elapsed(at: Date())
        )
        resonanceTuning = .standard
        manualEvent = nil
        atmosphereProgress = 0
    }

    private var performanceDeskContext: PerformanceDeskContext? {
        switch stage {
        case .opening: .splash
        case .story(let story): .story(story)
        case .chooser, .settings, .stats: nil
        }
    }

    private func runCurrentScene(_ duration: FocusDuration) {
        switch stage {
        case .opening:
            startSplashRun(duration)
        case .story:
            autumnRecord.manualGusts = []
            autumnRecord.bird?.flight = nil
            autumnRecord.deer?.encounter = nil
            activePerformanceSession = PerformanceSession(
                duration: duration,
                randomSeed: UInt64(max(scoreSeed, 0))
            )
            performancePurpose = .storyPreview
            activeSplashScoreEvents = nil
        case .chooser, .settings, .stats:
            break
        }
    }

    private func triggerAutumnBird() {
        var study = autumnRecord.bird ?? AutumnBirdStudy()
        let prototype = AutumnOrigamiFlight(startTime: 0, seed: UInt64(max(scoreSeed, 0)), tuning: study.tuning)
        // Near the end, start a fresh run so the finite study has time to finish.
        if activePerformanceSession == nil ||
            (activePerformanceSession?.remainingTime(at: .now) ?? 0) < prototype.duration + 1 {
            runCurrentScene(runnerDuration)
        }
        guard var session = activePerformanceSession else { return }
        if session.isPaused { session.resume(at: .now); activePerformanceSession = session }
        study.flight = AutumnOrigamiFlight(startTime: session.elapsedTime(at: .now),
            seed: session.randomSeed, tuning: study.tuning)
        autumnRecord.bird = study
    }

    private func triggerAutumnDeer(_ poseTime: Double?) {
        var study = autumnRecord.deer ?? AutumnDeerStudy()
        let encounter = AutumnDeerEncounter.scheduled(duration:120,tuning:study.tuning)
        var session = PerformanceSession(duration:.twoMinutes,
            startedAt:.now.addingTimeInterval(-encounter.startTime-(poseTime ?? 0)),
            randomSeed:UInt64(max(scoreSeed,0)))
        if poseTime != nil { session.pause(at:.now) }
        study.encounter = encounter
        autumnRecord.deer = study
        autumnRecord.bird?.flight = nil
        autumnRecord.manualGusts = []
        activePerformanceSession = session
        performancePurpose = .storyPreview
        activeSplashScoreEvents = nil
    }

    private func stopCurrentScene() {
        activePerformanceSession = nil
        performancePurpose = nil
        activeSplashScoreEvents = nil
        // Ending a story leaves its scene and contextual tuning available.
    }
#endif
}

#if DEBUG
private struct PerformanceDesk: View {
    @Binding var expandedSections: Set<PerformanceDeskSection>
    let context: PerformanceDeskContext
    @Binding var autumnRecord: AutumnBranchRecord
    let onAutumnGust: () -> Void
    let onAutumnBird: () -> Void
    let onAutumnDeer: (Double?) -> Void
    @Binding var speedMultiplier: Double
    @Binding var amountMultiplier: Double
    @Binding var atmosphereProgress: Double
    @Binding var resonanceStrength: Double
    @Binding var resonanceWidth: Double
    @Binding var tonalSlot: Int
    @Binding var gateBeats: Double
    @Binding var scoreSeed: Int
    let onTriggerEvent: () -> Void
    let onReset: () -> Void
    let performanceClock: PerformanceClock
    let motionTuning: SplashMotionTuning
    let manualEvent: SplashWaveNoteEvent?
    let scoreEvents: [SplashWaveNoteEvent]
    let isAmbientPlayback: Bool
    @Binding var runnerDuration: FocusDuration
    let activePerformanceSession: PerformanceSession?
    let onRun: (FocusDuration) -> Void
    let onStop: () -> Void
    let onPauseResume: () -> Void
    @Binding var auditionEnabled: Bool
    let audioStatus: String
    let onHide: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                HStack {
                    Label("Performance desk", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    Button("Hide", action: onHide)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(PlanetFocusPalette.warmYellow)
                }

                deskSection(.splashTuning, title: "\(context.title) tuning", icon: "water.waves") {
                    if context.isSplash {
                        SplashTuningControls(
                            speedMultiplier: $speedMultiplier,
                            amountMultiplier: $amountMultiplier,
                            atmosphereProgress: $atmosphereProgress,
                            resonanceStrength: $resonanceStrength,
                            resonanceWidth: $resonanceWidth,
                            tonalSlot: $tonalSlot,
                            gateBeats: $gateBeats,
                        scoreSeed: $scoreSeed,
                        isTransportDrivingLight: activePerformanceSession != nil || isAmbientPlayback,
                        isAmbientPlayback: isAmbientPlayback,
                        onTriggerEvent: onTriggerEvent,
                            onReset: onReset
                        )
                    } else if case .story(.autumnTree) = context {
                        AutumnBranchControls(record: $autumnRecord, seed: $scoreSeed,
                            session: activePerformanceSession, onGust: onAutumnGust, onBird: onAutumnBird,
                            onDeer: onAutumnDeer)
                    } else {
                        Text("This section is reserved for controls published by the active story director. It does not alter the splash while \(context.title) is open.")
                            .font(.caption)
                            .foregroundStyle(PlanetFocusPalette.typePaleBlue.opacity(0.72))
                    }
                }

                deskSection(.scoreMonitor, title: "\(context.title) monitor", icon: "music.note.list") {
                    if context.isSplash {
                        ScrollView {
                            SplashScoreMonitorContent(
                                performanceClock: performanceClock,
                                motionTuning: motionTuning,
                            manualEvent: manualEvent,
                            scoreEvents: scoreEvents,
                            seed: activePerformanceSession?.randomSeed
                                ?? UInt64(max(scoreSeed, 0)),
                            performanceSession: activePerformanceSession
                            )
                            .padding(.trailing, 2)
                        }
                        .frame(maxHeight: 330)
                    } else {
                        StoryTransportMonitor(
                            title: context.title,
                            session: activePerformanceSession
                        )
                        if case .story(.autumnTree) = context {
                            AutumnBranchMonitor(session: activePerformanceSession, record: autumnRecord)
                        }
                    }
                }

                deskSection(.storyRunner, title: "\(context.title) runner", icon: "play.circle") {
                    StoryRunnerControls(
                        contextTitle: context.title,
                        duration: $runnerDuration,
                        activeSession: activePerformanceSession,
                        onRun: onRun,
                        onStop: onStop,
                        onPauseResume: onPauseResume
                    )
                    if context.isSplash {
                        Toggle("Recorded instruments", isOn: $auditionEnabled)
                            .font(.caption)
                            .tint(PlanetFocusPalette.warmYellow)
                        Text(audioStatus)
                            .font(.caption2)
                        Text("Your Splash instruments, with gentle variation.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        }
        .frame(maxWidth: 370, maxHeight: 620, alignment: .top)
        .background(PlanetFocusPalette.canvasInk.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(PlanetFocusPalette.typePaleBlue.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 7, y: 3)
        .foregroundStyle(PlanetFocusPalette.typePaleBlue)
    }

    private func deskSection<Content: View>(
        _ section: PerformanceDeskSection,
        title: String,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        PerformanceDeskAccordion(
            title: title,
            icon: icon,
            isExpanded: expansionBinding(for: section),
            content: content
        )
    }

    private func expansionBinding(
        for section: PerformanceDeskSection
    ) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedSections.insert(section)
                } else {
                    expandedSections.remove(section)
                }
            }
        )
    }
}

private struct PerformanceDeskAccordion<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .frame(width: 18)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .overlay(PlanetFocusPalette.typePaleBlue.opacity(0.24))
                    content()
                }
                .padding(10)
            }
        }
        .background(PlanetFocusPalette.typePaleBlue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

private struct StoryRunnerControls: View {
    let contextTitle: String
    @Binding var duration: FocusDuration
    let activeSession: PerformanceSession?
    let onRun: (FocusDuration) -> Void
    let onStop: () -> Void
    let onPauseResume: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let activeSession {
                HStack {
                    Text("Length")
                    Spacer()
                    Text(activeSession.duration.title)
                        .monospacedDigit()
                }
            } else {
                Picker("Length", selection: $duration) {
                    ForEach(FocusDuration.available) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("storyRunnerLength")
            }

            if let activeSession {
                StoryRunProgress(session: activeSession, contextTitle: contextTitle)
                if let onPauseResume {
                    Button(activeSession.isPaused ? "Resume" : "Pause", action: onPauseResume)
                        .accessibilityIdentifier("performancePauseResume")
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                }
                Button("End run", action: onStop)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
            } else {
                Text("Starts \(contextTitle) with the same session transport used by its director.")
                    .font(.caption)
                    .foregroundStyle(PlanetFocusPalette.typePaleBlue.opacity(0.72))
            }

            Button {
                onRun(duration)
            } label: {
                Label(activeSession == nil ? "Run \(contextTitle)" : "Restart \(contextTitle)", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(PlanetFocusPalette.warmYellow)
            .foregroundStyle(PlanetFocusPalette.canvasInk)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
    }
}

private struct StoryRunProgress: View {
    let session: PerformanceSession
    let contextTitle: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let state = PerformanceRunner(session: session).sample(at: context.date)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(
                        state.isComplete
                            ? "\(contextTitle) complete"
                            : (session.isPaused ? "Paused \(contextTitle)" : "Running \(contextTitle)")
                    )
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(Int(state.progress * 100))%")
                        .monospacedDigit()
                }
                ProgressView(value: state.progress)
                    .tint(PlanetFocusPalette.warmYellow)
                Text("\(clockString(state.elapsedTime)) elapsed - \(clockString(state.remainingTime)) remaining")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PlanetFocusPalette.typePaleBlue.opacity(0.72))
            }
            .padding(9)
            .background(PlanetFocusPalette.warmYellow.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    private func clockString(_ interval: TimeInterval) -> String {
        let totalSeconds = max(Int(interval.rounded(.down)), 0)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct StoryTransportMonitor: View {
    let title: String
    let session: PerformanceSession?

    var body: some View {
        if let session {
            StoryRunProgress(session: session, contextTitle: title)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(title) is ready")
                    .font(.caption.weight(.semibold))
                Text("Run this scene to expose its live transport, timing, and future score events here.")
                    .font(.caption)
                    .foregroundStyle(PlanetFocusPalette.typePaleBlue.opacity(0.72))
            }
            .padding(9)
            .background(PlanetFocusPalette.typePaleBlue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }
}

private struct SplashTuningControls: View {
    @Binding var speedMultiplier: Double
    @Binding var amountMultiplier: Double
    @Binding var atmosphereProgress: Double
    @Binding var resonanceStrength: Double
    @Binding var resonanceWidth: Double
    @Binding var tonalSlot: Int
    @Binding var gateBeats: Double
    @Binding var scoreSeed: Int
    let isTransportDrivingLight: Bool
    var isAmbientPlayback = false
    let onTriggerEvent: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("Splash tuning")
                    .fontWeight(.semibold)

                Spacer()

                Button("Reset", action: onReset)
                    .foregroundStyle(PlanetFocusPalette.warmYellow)
            }

            tuningRow(
                label: "Speed",
                value: $speedMultiplier,
                range: 0.25...4
            )
            .disabled(isTransportDrivingLight)
            tuningRow(
                label: "Amount",
                value: $amountMultiplier,
                range: 0.5...2
            )

            Divider()
                .overlay(PlanetFocusPalette.typePaleBlue.opacity(0.24))

            tuningRow(
                label: "Light",
                value: $atmosphereProgress,
                range: 0...1,
                valueLabel: isTransportDrivingLight
                    ? "Transport"
                    : SplashAtmosphereDirector.sample(
                        progress: atmosphereProgress
                    ).displayLabel
            )
            .disabled(isTransportDrivingLight)

            if isTransportDrivingLight {
                Text("The runner owns speed, light, and sound pools. Amount still adjusts visual strength.")
                    .font(.caption)
                    .foregroundStyle(PlanetFocusPalette.typePaleBlue.opacity(0.72))
            }

            Divider()
                .overlay(PlanetFocusPalette.typePaleBlue.opacity(0.24))

            Button(action: onTriggerEvent) {
                Label("Trigger scored note", systemImage: "waveform.path")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(PlanetFocusPalette.warmYellow)
            .foregroundStyle(PlanetFocusPalette.canvasInk)
            .accessibilityIdentifier("splashResonanceTrigger")
            .disabled(isAmbientPlayback)

            Stepper(value: $tonalSlot, in: 0...7) {
                HStack {
                    Text("Note / wave")
                    Spacer()
                    Text(
                        "\(SplashPerformanceScore.noteName(for: tonalSlot)) - \(SplashPerformanceScore.waveName(for: tonalSlot))"
                    )
                    .monospacedDigit()
                }
            }

            tuningRow(
                label: "Gate",
                value: $gateBeats,
                range: 2...16,
                valueLabel: String(
                    format: "%.0f beats", gateBeats
                )
            )
            tuningRow(
                label: "Intensity",
                value: $resonanceStrength,
                range: 0...2
            )
            tuningRow(
                label: "Seam width",
                value: $resonanceWidth,
                range: 0.04...0.22,
                valueLabel: String(format: "%.2f", resonanceWidth)
            )

            Stepper(value: $scoreSeed, in: 1...999_999) {
                HStack {
                    Text("Score seed")
                    Spacer()
                    Text("\(scoreSeed)")
                        .monospacedDigit()
                }
            }
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(PlanetFocusPalette.typePaleBlue)
    }

    private func tuningRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueLabel: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 48, alignment: .leading)

            Slider(value: value, in: range)
                .tint(PlanetFocusPalette.warmYellow)

            Text(valueLabel ?? String(format: "%.2fx", value.wrappedValue))
            .monospacedDigit()
            .frame(width: valueLabel == nil ? 42 : 82, alignment: .trailing)
        }
    }
}

private struct SplashScoreMonitorContent: View {
    let performanceClock: PerformanceClock
    let motionTuning: SplashMotionTuning
    let manualEvent: SplashWaveNoteEvent?
    let scoreEvents: [SplashWaveNoteEvent]
    let seed: UInt64
    let performanceSession: PerformanceSession?

    @State private var frozenScoreBeat: Double?
    @State private var reviewOffsetBeats = 0.0
    @State private var cachedDiagnostics: SplashScoreDiagnostics?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { context in
                let elapsedTime = performanceSession.map {
                    PerformanceRunner(session: $0).sample(at: context.date).elapsedTime
                } ?? performanceClock.elapsed(at: context.date)
                let liveScoreBeat = SplashPerformanceScore.scoreBeat(
                    for: elapsedTime,
                    tuning: motionTuning
                )
                let atmosphere = performanceSession.map {
                    SplashPerformancePlan(
                        session: $0,
                        scoreEvents: scoreEvents
                    ).atmosphere(at: context.date)
                }
                let scoreBeat = frozenScoreBeat
                    ?? liveScoreBeat + reviewOffsetBeats
                let scheduledEvents = SplashPerformanceScore.scheduledEvents(
                    around: scoreBeat,
                    radiusBeats: 16,
                    events: scoreEvents,
                    manualEvent: manualEvent
                )
                let activeEvents = scheduledEvents.filter {
                    $0.sample(at: scoreBeat) != nil
                }

                VStack(alignment: .leading, spacing: 14) {
                        transportHeader(
                            scoreBeat: scoreBeat,
                            isFrozen: frozenScoreBeat != nil,
                            atmosphere: atmosphere,
                            onFreezeToggle: {
                                frozenScoreBeat = frozenScoreBeat == nil
                                    ? scoreBeat
                                    : nil
                            }
                        )

                        scoreDiagnostics

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active events")
                                .font(.headline)
                            if activeEvents.isEmpty {
                                Text("No active event at this beat")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(activeEvents) { scheduledEvent in
                                    activeEventRow(
                                        scheduledEvent,
                                        scoreBeat: scoreBeat
                                    )
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("24-beat score roll")
                                .font(.headline)
                            Text("Every bar is a real score event. Its wave, ADSR, and synth voice share this exact start and end.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            SplashScoreRoll(
                                scoreBeat: scoreBeat,
                                events: scheduledEvents
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Event log")
                                .font(.headline)
                            ForEach(scheduledEvents) { scheduledEvent in
                                eventLogRow(scheduledEvent, scoreBeat: scoreBeat)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Fast review")
                                .font(.headline)
                            Text("Inspect the score without changing the live splash transport.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Slider(value: $reviewOffsetBeats, in: 0...max((performanceSession?.duration.timeInterval ?? 600) / SplashPerformanceScore.tempo.secondsPerBeat, 1))
                                .tint(PlanetFocusPalette.warmYellow)
                            Text(String(format: "+%.0f beats  |  +%.1f min", reviewOffsetBeats, reviewOffsetBeats * SplashPerformanceScore.tempo.secondsPerBeat / 60))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                }
        }
    }

    private func transportHeader(
        scoreBeat: Double,
        isFrozen: Bool,
        atmosphere: SplashAtmosphereSample?,
        onFreezeToggle: @escaping () -> Void
    ) -> some View {
        let bar = Int(floor(scoreBeat / Double(SplashPerformanceScore.tempo.beatsPerBar))) + 1
        let beat = scoreBeat.truncatingRemainder(
            dividingBy: Double(SplashPerformanceScore.tempo.beatsPerBar)
        ) + 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("65 BPM - F Lydian")
                        .font(.headline)
                    Text(String(format: "Seed %llu  |  Bar %d  |  Beat %.2f", seed, bar, beat))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isFrozen ? "Resume live" : "Freeze", action: onFreezeToggle)
                    .buttonStyle(.bordered)
            }
            Text(isFrozen ? "Monitor frozen; splash transport continues live." : "Live transport; recorded instruments are controlled in the runner.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let atmosphere {
                Text(String(
                    format: "Sound pool mix  Night %.0f%%  Twilight %.0f%%  Daylight %.0f%%",
                    atmosphere.weights.night * 100,
                    atmosphere.weights.twilight * 100,
                    atmosphere.weights.daylight * 100
                ))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(PlanetFocusPalette.canvasInk.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var scoreDiagnostics: some View {
        let diagnostics = cachedDiagnostics ?? SplashScoreDiagnostics(
            averageActiveVoices: 0, longestSilentBeats: 0, averageEventDurationSeconds: 0,
            eventsPerMinute: 0, participatingWaveCount: 0)
        return VStack(alignment: .leading, spacing: 8) {
            Text(performanceSession == nil ? "10-minute structural check" : "Full-run structural check")
                .font(.headline)
            HStack(spacing: 12) {
                diagnostic("Avg voices", String(format: "%.1f", diagnostics.averageActiveVoices))
                diagnostic("Longest gap", String(format: "%.1f beats", diagnostics.longestSilentBeats))
            }
            HStack(spacing: 12) {
                diagnostic("Avg note", String(format: "%.1fs", diagnostics.averageEventDurationSeconds))
                diagnostic("Wave coverage", "\(diagnostics.participatingWaveCount)/8")
            }
        }
        .task(id: "\(seed)-\(performanceSession?.duration.rawValue ?? 600)-\(scoreEvents.count)") {
            cachedDiagnostics = SplashPerformanceScore.diagnostics(
                durationMinutes: (performanceSession?.duration.timeInterval ?? 600) / 60,
                events: scoreEvents)
        }
    }

    private func diagnostic(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(PlanetFocusPalette.canvasInk.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func activeEventRow(
        _ scheduledEvent: SplashScheduledPerformanceEvent,
        scoreBeat: Double
    ) -> some View {
        let sample = scheduledEvent.sample(at: scoreBeat)
        return HStack {
            Text(SplashMusicDirector.noteName(for: scheduledEvent.event))
                .font(.headline.monospaced())
                .frame(width: 42, alignment: .leading)
            VStack(alignment: .leading) {
                Text("\(SplashPerformanceScore.waveName(for: scheduledEvent.event.tonalSlot)) - \(scheduledEvent.event.role.rawValue.capitalized)")
                Text("\(sample?.stage.label ?? "off")  |  \(String(format: "%.0f", scheduledEvent.event.gateBeats)) beat gate + \(String(format: "%.0f", scheduledEvent.event.envelope.releaseBeats)) release")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let source = performancePlan?.soundSource(for: scheduledEvent) {
                    Text("\(source.pool.displayName) pool - \(source.role.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(String(format: "%.0f%%", (sample?.value ?? 0) * 100))
                .font(.caption.monospacedDigit())
        }
        .padding(10)
        .background(PlanetFocusPalette.warmYellow.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func eventLogRow(
        _ scheduledEvent: SplashScheduledPerformanceEvent,
        scoreBeat: Double
    ) -> some View {
        let isActive = scheduledEvent.sample(at: scoreBeat) != nil
        return HStack(spacing: 10) {
            Text(String(format: "%.1f", scheduledEvent.scheduledStartBeat))
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .leading)
            Text(SplashMusicDirector.noteName(for: scheduledEvent.event))
                .font(.subheadline.monospaced())
                .frame(width: 30, alignment: .leading)
            Text(SplashPerformanceScore.waveName(for: scheduledEvent.event.tonalSlot))
                .font(.subheadline)
            Spacer()
            Text("\(String(format: "%.0f", scheduledEvent.event.totalBeats)) beats")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if isActive {
                Circle()
                    .fill(PlanetFocusPalette.warmYellow)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 3)
    }

    private var performancePlan: SplashPerformancePlan? {
        performanceSession.map {
            SplashPerformancePlan(session: $0, scoreEvents: scoreEvents)
        }
    }
}

private struct SplashScoreRoll: View {
    let scoreBeat: Double
    let events: [SplashScheduledPerformanceEvent]
    private let windowStartOffset = 8.0
    private let windowBeats = 24.0

    var body: some View {
        VStack(spacing: 5) {
            ForEach(SplashPerformanceScore.waveVoices, id: \.tonalSlot) { voice in
                HStack(spacing: 8) {
                    Text(voice.noteName)
                        .font(.caption.monospaced())
                        .frame(width: 26, alignment: .leading)
                    GeometryReader { proxy in
                        let start = scoreBeat - windowStartOffset
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(PlanetFocusPalette.canvasInk.opacity(0.12))
                                .frame(height: 9)
                            ForEach(events.filter { $0.event.tonalSlot == voice.tonalSlot }) { event in
                                let x = max(event.scheduledStartBeat - start, 0)
                                let visibleEnd = min(event.endBeat - start, windowBeats)
                                if visibleEnd > x {
                                    Capsule()
                                        .fill(PlanetFocusPalette.warmYellow.opacity(0.78))
                                        .frame(
                                            width: proxy.size.width * CGFloat((visibleEnd - x) / windowBeats),
                                            height: 9
                                        )
                                        .offset(x: proxy.size.width * CGFloat(x / windowBeats))
                                }
                            }
                        }
                    }
                    .frame(height: 12)
                }
            }
        }
        .padding(10)
        .background(PlanetFocusPalette.canvasInk.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private extension SplashEnvelopeStage {
    var label: String {
        switch self {
        case .attack: "attack"
        case .decay: "decay"
        case .sustain: "sustain"
        case .release: "release"
        }
    }
}
#endif
#endif

private struct SplashSunView: View {
    let progress: CGFloat
    let palette: SplashAtmospherePalette

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.sunCutEdge.color)
                .offset(
                    x: SplashSunMaterial.cutEdgeX,
                    y: SplashSunMaterial.cutEdgeY
                )

            Circle()
                .fill(palette.accent.color)

            Image("NeutralPaperGrainV1")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
                .blendMode(.softLight)
                .opacity(0.52)
                .accessibilityHidden(true)

            Circle()
                .stroke(
                    Color.white.opacity(SplashSunMaterial.edgeHighlightOpacity),
                    lineWidth: SplashSunMaterial.edgeHighlightWidth
                )
        }
            .compositingGroup()
            .shadow(
                color: Color.black.opacity(SplashSunMaterial.contactShadowOpacity),
                radius: SplashSunMaterial.contactShadowRadius,
                x: SplashSunMaterial.contactShadowX,
                y: SplashSunMaterial.contactShadowY
            )
            .shadow(
                color: Color.black.opacity(SplashSunMaterial.castShadowOpacity),
                radius: SplashSunMaterial.castShadowRadius,
                x: SplashSunMaterial.castShadowX,
                y: SplashSunMaterial.castShadowY
            )
            .opacity(progress)
    }
}

private enum SplashSunMaterial {
    static let cutEdgeColor = Color(red: 214 / 255, green: 134 / 255, blue: 40 / 255)
    static let cutEdgeX: CGFloat = 1.5
    static let cutEdgeY: CGFloat = 2.5

    static let edgeHighlightOpacity = 0.10
    static let edgeHighlightWidth: CGFloat = 0.8

    static let contactShadowOpacity = 0.62
    static let contactShadowRadius: CGFloat = 2.4
    static let contactShadowX: CGFloat = 0
    static let contactShadowY: CGFloat = 1.2

    static let castShadowOpacity = 0.52
    static let castShadowRadius: CGFloat = 7
    static let castShadowX: CGFloat = 6
    static let castShadowY: CGFloat = 10
}

enum SplashWaveEntryEdge: CGFloat {
    case leading = -1
    case trailing = 1
}

enum SplashWaveExtent: Equatable {
    case full
    case entering(progress: CGFloat, edge: SplashWaveEntryEdge)
    case exiting(progress: CGFloat, entryEdge: SplashWaveEntryEdge)
}

struct SplashWaveRibbon: Identifiable {
    let id: SplashSceneActorID
    let color: Color
    let top: [CGPoint]
    let bottom: [CGPoint]
    let entryEdge: SplashWaveEntryEdge
}

/// One low-frequency component in a deterministic ribbon field. Frequencies are
/// expressed in cycles across the complete extra-wide world rather than the
/// current device crop, so rotation never changes the underlying geometry.
struct SplashWaveHarmonic {
    let amplitude: CGFloat
    let cycles: CGFloat
    let phase: CGFloat

    func value(
        at x: CGFloat,
        motionPhase: CGFloat = 0,
        spatialScale: CGFloat = 1
    ) -> CGFloat {
        amplitude * sin(2 * .pi * (cycles * spatialScale * x + phase + motionPhase))
    }
}

struct SplashWaveFunction {
    let base: CGFloat
    let drift: CGFloat
    let harmonics: [SplashWaveHarmonic]

    init(
        base: CGFloat,
        drift: CGFloat = 0,
        harmonics: [SplashWaveHarmonic]
    ) {
        self.base = base
        self.drift = drift
        self.harmonics = harmonics
    }

    func value(
        at x: CGFloat,
        motionPhase: CGFloat = 0,
        spatialScale: CGFloat = 1
    ) -> CGFloat {
        base + drift * (x - 0.5) + harmonics.reduce(0) {
            $0 + $1.value(
                at: x,
                motionPhase: motionPhase,
                spatialScale: spatialScale
            )
        }
    }
}

struct SplashWaveFormula {
    let id: SplashSceneActorID
    let color: Color
    let centerline: SplashWaveFunction
    let thickness: SplashWaveFunction
    let entryEdge: SplashWaveEntryEdge
    let motionRate: CGFloat
    let thicknessMotionRate: CGFloat
}

/// Generates the complete wave field from continuous low-frequency functions.
/// Every ribbon owns an independently phased analytic centerline and thickness
/// field. A hidden analytic coverage sheet closes the outer silhouette; it does
/// not pin, partition, or reshape the visible ribbons. This lets the paper strips
/// cross and occlude one another while remaining suitable for phase animation.
enum SplashWaveGenerator {
    static let sampleCount = 384
    static let ribbonFrequencyScale: CGFloat = 1
    static let centerAmplitudeScale: CGFloat = 1
    static let thicknessAmplitudeScale: CGFloat = 1
    static let maximumRibbonSpanShare: CGFloat = 0.38
    static let headTaperLength: CGFloat = 0.09

    static let formulas: [SplashWaveFormula] = [
        .init(
            id: .waveRearPeriwinkle,
            color: PlanetFocusPalette.wavePeriwinkle,
            centerline: .init(base: 0.241, drift: -0.689, harmonics: [
                .init(amplitude: 0.149, cycles: 2.784, phase: 0.791),
                .init(amplitude: 0.174, cycles: 3.925, phase: 0.994)
            ]),
            thickness: .init(base: 0.252, harmonics: [
                .init(amplitude: 0.005, cycles: 3.545, phase: 0.988),
                .init(amplitude: 0.063, cycles: 4.497, phase: 0.835)
            ]),
            entryEdge: .trailing,
            motionRate: 0.16,
            thicknessMotionRate: -0.052
        ),
        .init(
            id: .waveRearDeep,
            color: PlanetFocusPalette.waveDeep,
            centerline: .init(base: 0.350, harmonics: [
                .init(amplitude: 0.105, cycles: 2.200, phase: 0.980),
                .init(amplitude: 0.025, cycles: 4.100, phase: 0.983)
            ]),
            thickness: .init(base: 0.200, harmonics: [
                .init(amplitude: 0.050, cycles: 2.000, phase: 0.267),
                .init(amplitude: 0.035, cycles: 3.700, phase: 0.376)
            ]),
            entryEdge: .leading,
            motionRate: -0.11,
            thicknessMotionRate: 0.041
        ),
        .init(
            id: .waveWarmReveal,
            color: PlanetFocusPalette.warmYellow,
            centerline: .init(base: 0.419, harmonics: [
                .init(amplitude: 0.143, cycles: 2.600, phase: 0.720),
                .init(amplitude: 0.035, cycles: 4.400, phase: 0.887)
            ]),
            thickness: .init(base: 0.045, harmonics: [
                .init(amplitude: 0.020, cycles: 2.500, phase: 0.545),
                .init(amplitude: 0.010, cycles: 4.000, phase: 0.949)
            ]),
            entryEdge: .leading,
            motionRate: 0.08,
            thicknessMotionRate: -0.031
        ),
        .init(
            id: .waveMiddleLavender,
            color: PlanetFocusPalette.waveLavender,
            centerline: .init(base: 0.379, drift: 0.007, harmonics: [
                .init(amplitude: 0.037, cycles: 1.381, phase: 0.228),
                .init(amplitude: 0.044, cycles: 3.384, phase: 0.633),
                .init(amplitude: 0.090, cycles: 4.979, phase: 0.358)
            ]),
            thickness: .init(base: 0.225, harmonics: [
                .init(amplitude: 0.000, cycles: 1.387, phase: 0.515),
                .init(amplitude: 0.062, cycles: 3.322, phase: 0.253)
            ]),
            entryEdge: .trailing,
            motionRate: -0.09,
            thicknessMotionRate: 0.047
        ),
        .init(
            id: .waveMiddleBlue,
            color: PlanetFocusPalette.waveMid,
            centerline: .init(base: 0.550, harmonics: [
                .init(amplitude: 0.180, cycles: 2.400, phase: 0.746),
                .init(amplitude: 0.075, cycles: 3.800, phase: 0.243)
            ]),
            thickness: .init(base: 0.200, harmonics: [
                .init(amplitude: 0.050, cycles: 2.300, phase: 0.668),
                .init(amplitude: 0.025, cycles: 4.100, phase: 0.671)
            ]),
            entryEdge: .leading,
            motionRate: 0.12,
            thicknessMotionRate: -0.044
        ),
        .init(
            id: .waveFrontDeep,
            color: PlanetFocusPalette.waveDeep,
            centerline: .init(base: 0.682, harmonics: [
                .init(amplitude: 0.110, cycles: 1.900, phase: 0.101),
                .init(amplitude: 0.035, cycles: 4.200, phase: 0.603)
            ]),
            thickness: .init(base: 0.180, harmonics: [
                .init(amplitude: 0.040, cycles: 2.000, phase: 0.593),
                .init(amplitude: 0.030, cycles: 4.000, phase: 0.514)
            ]),
            entryEdge: .trailing,
            motionRate: -0.14,
            thicknessMotionRate: 0.038
        ),
        .init(
            id: .waveFrontPeriwinkle,
            color: PlanetFocusPalette.wavePeriwinkle,
            centerline: .init(base: 0.720, harmonics: [
                .init(amplitude: 0.145, cycles: 2.700, phase: 0.860),
                .init(amplitude: 0.065, cycles: 4.400, phase: 0.189)
            ]),
            thickness: .init(base: 0.200, harmonics: [
                .init(amplitude: 0.040, cycles: 2.500, phase: 0.332),
                .init(amplitude: 0.020, cycles: 4.500, phase: 0.641)
            ]),
            entryEdge: .leading,
            motionRate: 0.10,
            thicknessMotionRate: -0.036
        ),
        .init(
            id: .waveFrontLavender,
            color: PlanetFocusPalette.waveLavender,
            centerline: .init(base: 0.800, harmonics: [
                .init(amplitude: 0.160, cycles: 2.100, phase: 0.900),
                .init(amplitude: 0.060, cycles: 3.500, phase: 0.242)
            ]),
            thickness: .init(base: 0.160, harmonics: [
                .init(amplitude: 0.030, cycles: 2.200, phase: 0.514),
                .init(amplitude: 0.025, cycles: 3.800, phase: 0.116)
            ]),
            entryEdge: .trailing,
            motionRate: -0.07,
            thicknessMotionRate: 0.029
        )
    ]

    static func ribbons(
        motionPhase: CGFloat = 0,
        motionAmount: CGFloat = 1,
        resonance: SplashWaveResonanceSample? = nil,
        palette: SplashAtmospherePalette = .night
    ) -> [SplashWaveRibbon] {
        ribbons(
            motionSamples: Array(
                repeating: SplashWaveMotionSample(
                    phase: motionPhase,
                    amplitude: motionAmount
                ),
                count: formulas.count
            ),
            resonance: resonance,
            palette: palette
        )
    }

    static func ribbons(
        motionSamples: [SplashWaveMotionSample],
        resonance: SplashWaveResonanceSample? = nil,
        palette: SplashAtmospherePalette = .night
    ) -> [SplashWaveRibbon] {
        var topSamples = Array(repeating: [CGPoint](), count: formulas.count)
        var bottomSamples = Array(repeating: [CGPoint](), count: formulas.count)
        for index in 0...sampleCount {
            let x = CGFloat(index) / CGFloat(sampleCount)
            let edges = rawEdges(
                at: x,
                motionSamples: motionSamples,
                resonance: resonance
            )
            for formulaIndex in formulas.indices {
                topSamples[formulaIndex].append(
                    CGPoint(x: x, y: edges[formulaIndex].top)
                )
                bottomSamples[formulaIndex].append(
                    CGPoint(x: x, y: edges[formulaIndex].bottom)
                )
            }
        }

        return formulas.indices.map { index in
            let formula = formulas[index]
            return SplashWaveRibbon(
                id: formula.id,
                color: palette.waveColor(for: formula.id),
                top: topSamples[index],
                bottom: bottomSamples[index],
                entryEdge: formula.entryEdge
            )
        }
    }

    static func coverageRibbon(
        palette: SplashAtmospherePalette = .night
    ) -> SplashWaveRibbon {
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        for index in 0...sampleCount {
            let x = CGFloat(index) / CGFloat(sampleCount)
            let edges = envelope(at: x)
            top.append(CGPoint(x: x, y: edges.top))
            bottom.append(CGPoint(x: x, y: edges.bottom))
        }
        return SplashWaveRibbon(
            id: .waveRearDeep,
            color: palette.waveDeep.color,
            top: top,
            bottom: bottom,
            entryEdge: .leading
        )
    }

    static func applying(
        _ extent: SplashWaveExtent,
        to ribbon: SplashWaveRibbon
    ) -> SplashWaveRibbon {
        switch extent {
        case .full:
            ribbon
        case .entering(let progress, let edge):
            enteringRibbon(ribbon, progress: progress, edge: edge)
        case .exiting(let progress, let entryEdge):
            exitingRibbon(ribbon, progress: progress, entryEdge: entryEdge)
        }
    }

    private static func enteringRibbon(
        _ ribbon: SplashWaveRibbon,
        progress: CGFloat,
        edge: SplashWaveEntryEdge
    ) -> SplashWaveRibbon {
        let progress = min(max(progress, 0), 1)
        guard progress > 0 else { return emptyRibbon(copying: ribbon) }
        guard progress < 1 else { return ribbon }

        switch edge {
        case .leading:
            return partialRibbon(
                ribbon,
                lowerBound: 0,
                upperBound: progress,
                taperOrigin: progress
            )
        case .trailing:
            return partialRibbon(
                ribbon,
                lowerBound: 1 - progress,
                upperBound: 1,
                taperOrigin: 1 - progress
            )
        }
    }

    private static func exitingRibbon(
        _ ribbon: SplashWaveRibbon,
        progress: CGFloat,
        entryEdge: SplashWaveEntryEdge
    ) -> SplashWaveRibbon {
        let progress = min(max(progress, 0), 1)
        guard progress > 0 else { return ribbon }
        guard progress < 1 else { return emptyRibbon(copying: ribbon) }

        switch entryEdge {
        case .leading:
            return partialRibbon(
                ribbon,
                lowerBound: progress,
                upperBound: 1,
                taperOrigin: progress
            )
        case .trailing:
            return partialRibbon(
                ribbon,
                lowerBound: 0,
                upperBound: 1 - progress,
                taperOrigin: 1 - progress
            )
        }
    }

    private static func partialRibbon(
        _ ribbon: SplashWaveRibbon,
        lowerBound: CGFloat,
        upperBound: CGFloat,
        taperOrigin: CGFloat
    ) -> SplashWaveRibbon {
        let lowerBound = min(max(lowerBound, 0), 1)
        let upperBound = min(max(upperBound, lowerBound), 1)
        guard upperBound > lowerBound else {
            return emptyRibbon(copying: ribbon)
        }

        var xValues = [lowerBound]
        xValues.append(contentsOf: ribbon.top.lazy.map(\.x).filter {
            $0 > lowerBound && $0 < upperBound
        })
        xValues.append(upperBound)

        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        top.reserveCapacity(xValues.count)
        bottom.reserveCapacity(xValues.count)

        for x in xValues {
            let edges = interpolatedEdges(in: ribbon, at: x)
            let center = (edges.top.y + edges.bottom.y) / 2
            let halfThickness = (edges.bottom.y - edges.top.y) / 2
            let distanceFromTip = abs(x - taperOrigin)
            let taperProgress = min(distanceFromTip / headTaperLength, 1)
            let thicknessScale = CGFloat(
                SplashMotionTiming.smootherStep(Double(taperProgress))
            )
            let taperedHalfThickness = halfThickness * thicknessScale

            top.append(CGPoint(x: x, y: center - taperedHalfThickness))
            bottom.append(CGPoint(x: x, y: center + taperedHalfThickness))
        }

        return SplashWaveRibbon(
            id: ribbon.id,
            color: ribbon.color,
            top: top,
            bottom: bottom,
            entryEdge: ribbon.entryEdge
        )
    }

    private static func interpolatedEdges(
        in ribbon: SplashWaveRibbon,
        at x: CGFloat
    ) -> (top: CGPoint, bottom: CGPoint) {
        let count = min(ribbon.top.count, ribbon.bottom.count)
        guard count > 1 else {
            let point = CGPoint(x: x, y: 0)
            return (point, point)
        }

        let samplePosition = min(max(x, 0), 1) * CGFloat(count - 1)
        let lowerIndex = min(Int(floor(samplePosition)), count - 1)
        let upperIndex = min(lowerIndex + 1, count - 1)
        let fraction = samplePosition - CGFloat(lowerIndex)

        return (
            top: interpolatedPoint(
                from: ribbon.top[lowerIndex],
                to: ribbon.top[upperIndex],
                x: x,
                fraction: fraction
            ),
            bottom: interpolatedPoint(
                from: ribbon.bottom[lowerIndex],
                to: ribbon.bottom[upperIndex],
                x: x,
                fraction: fraction
            )
        )
    }

    private static func interpolatedPoint(
        from start: CGPoint,
        to end: CGPoint,
        x: CGFloat,
        fraction: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: x,
            y: start.y + (end.y - start.y) * fraction
        )
    }

    private static func emptyRibbon(
        copying ribbon: SplashWaveRibbon
    ) -> SplashWaveRibbon {
        SplashWaveRibbon(
            id: ribbon.id,
            color: ribbon.color,
            top: [],
            bottom: [],
            entryEdge: ribbon.entryEdge
        )
    }

    private static func rawEdges(
        at x: CGFloat,
        motionSamples: [SplashWaveMotionSample],
        resonance: SplashWaveResonanceSample? = nil
    ) -> [(top: CGFloat, bottom: CGFloat)] {
        let guardEdges = envelope(at: x)
        let availableSpan = max(guardEdges.bottom - guardEdges.top, 0.10)

        return formulas.enumerated().map { index, formula in
            let sample = index < motionSamples.count
                ? motionSamples[index]
                : .resting
            let packetAmount = sample.packetAmplitude(at: x)
            let bedAmount = min(max(sample.bedAmplitude, 0), 1)
            let packetCenterPhase = -sample.phase * abs(formula.motionRate)
            let bedCenterPhase = -sample.bedPhase * abs(formula.motionRate)
            let packetThicknessPhase = -sample.phase * abs(formula.thicknessMotionRate)
            let bedThicknessPhase = -sample.bedPhase * abs(formula.thicknessMotionRate)

            let restingCenterField = formula.centerline.value(
                at: x,
                spatialScale: ribbonFrequencyScale
            )
            let packetCenterField = formula.centerline.value(
                at: x,
                motionPhase: packetCenterPhase,
                spatialScale: ribbonFrequencyScale
            )
            let bedCenterField = formula.centerline.value(
                at: x,
                motionPhase: bedCenterPhase,
                spatialScale: ribbonFrequencyScale
            )
            let restingCenter = formula.centerline.base
                + centerAmplitudeScale
                * (restingCenterField - formula.centerline.base)
            let packetCenter = formula.centerline.base
                + centerAmplitudeScale
                * (packetCenterField - formula.centerline.base)
            let bedCenter = formula.centerline.base
                + centerAmplitudeScale
                * (bedCenterField - formula.centerline.base)
            let center = restingCenter
                + bedAmount * (bedCenter - restingCenter)
                + packetAmount * (packetCenter - restingCenter)
                + (resonance?.verticalShift(at: x, waveIndex: index) ?? 0)

            let restingThicknessField = formula.thickness.value(
                at: x,
                spatialScale: ribbonFrequencyScale
            )
            let packetThicknessField = formula.thickness.value(
                at: x,
                motionPhase: packetThicknessPhase,
                spatialScale: ribbonFrequencyScale
            )
            let bedThicknessField = formula.thickness.value(
                at: x,
                motionPhase: bedThicknessPhase,
                spatialScale: ribbonFrequencyScale
            )
            let restingThickness = formula.thickness.base
                + thicknessAmplitudeScale
                * (restingThicknessField - formula.thickness.base)
            let packetThickness = formula.thickness.base
                + thicknessAmplitudeScale
                * (packetThicknessField - formula.thickness.base)
            let bedThickness = formula.thickness.base
                + thicknessAmplitudeScale
                * (bedThicknessField - formula.thickness.base)
            let rawThickness = restingThickness
                + bedAmount * 0.32 * (bedThickness - restingThickness)
                + packetAmount * 0.50 * (packetThickness - restingThickness)

            let positiveThickness = 0.010
                + softplus(rawThickness - 0.010, sharpness: 32)
            let thickness = min(
                positiveThickness,
                maximumRibbonSpanShare * availableSpan
            )
            let halfThickness = thickness / 2
            let boundedCenter = smoothClamp(
                center,
                lower: guardEdges.top + halfThickness,
                upper: guardEdges.bottom - halfThickness
            )
            return (
                top: max(boundedCenter - halfThickness, guardEdges.top),
                bottom: min(boundedCenter + halfThickness, guardEdges.bottom)
            )
        }
    }

    static func travelingPacketGain(
        at x: CGFloat,
        center: CGFloat,
        halfWidth: CGFloat
    ) -> CGFloat {
        guard halfWidth.isFinite else { return 1 }
        guard halfWidth > 0 else { return 0 }

        let normalizedDistance = abs(x - center) / halfWidth
        guard normalizedDistance < 1 else { return 0 }

        return CGFloat(
            SplashMotionTiming.smootherStep(
                Double(1 - normalizedDistance)
            )
        )
    }

    private static func envelope(at x: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let center = 0.4424
            + 0.0151 * cos(2 * .pi * x)
            + 0.0407 * sin(2 * .pi * x)
            - 0.0288 * cos(4 * .pi * x)
            + 0.0259 * sin(4 * .pi * x)
            - 0.0184 * cos(6 * .pi * x)
            - 0.0190 * sin(6 * .pi * x)
            + 0.0463 * cos(8 * .pi * x)
            - 0.0384 * sin(8 * .pi * x)
            + 0.0525 * cos(10 * .pi * x)
            - 0.0861 * sin(10 * .pi * x)
            + 0.0122 * cos(12 * .pi * x)
            - 0.0508 * sin(12 * .pi * x)
        let centered = x - 0.5
        let span = 0.7356
            - 0.0231 * cos(2 * .pi * x)
            + 0.0326 * cos(4 * .pi * x)
            + 0.0284 * cos(6 * .pi * x)
            - 0.0762 * cos(8 * .pi * x)
            - 0.0570 * cos(10 * .pi * x)
            - 0.0735 * cos(12 * .pi * x)
            - 0.0010 * centered * centered
        return (top: center - span / 2, bottom: center + span / 2)
    }

    private static func smoothClamp(
        _ value: CGFloat,
        lower: CGFloat,
        upper: CGFloat
    ) -> CGFloat {
        lower
            + softplus(value - lower, sharpness: 44)
            - softplus(value - upper, sharpness: 44)
    }

    private static func softplus(_ value: CGFloat, sharpness: CGFloat) -> CGFloat {
        let scaled = sharpness * value
        return (max(scaled, 0) + log1p(exp(-abs(scaled)))) / sharpness
    }
}

private struct SplashWaveField: View {
    let layout: SplashLayout
    let presentation: SplashScenePresentation
    let resonance: SplashWaveResonanceSample?
    let palette: SplashAtmospherePalette

    var body: some View {
        let worldSize = layout.waveWorldSize
        let motionSamples = SplashWaveGenerator.formulas.map {
            presentation.waveMotionSample(for: $0.id)
        }
        let fullRibbons = SplashWaveGenerator.ribbons(
            motionSamples: motionSamples,
            resonance: resonance,
            palette: palette
        )
        let ribbons = fullRibbons.enumerated().map { index, ribbon in
            SplashWaveGenerator.applying(
                presentation.waveExtent(
                    forWaveAt: index,
                    edge: ribbon.entryEdge,
                    count: fullRibbons.count
                ),
                to: ribbon
            )
        }
        let fullCoverage = SplashWaveGenerator.coverageRibbon(palette: palette)
        let coverageIndex = SplashWaveGenerator.formulas.firstIndex {
            $0.id == .waveRearDeep
        } ?? 0
        let coverageEdge = SplashWaveGenerator.formulas[coverageIndex].entryEdge
        let coverage = SplashWaveGenerator.applying(
            presentation.waveExtent(
                forWaveAt: coverageIndex,
                edge: coverageEdge,
                count: fullRibbons.count
            ),
            to: fullCoverage
        )

        ZStack {
            SplashWaveRibbonShape(top: coverage.top, bottom: coverage.bottom)
                .fill(palette.waveDeep.color)
                .frame(width: worldSize.width, height: worldSize.height)
                .accessibilityIdentifier("waveCoverageBacking")

            ForEach(ribbons) { ribbon in
                let shape = SplashWaveRibbonShape(top: ribbon.top, bottom: ribbon.bottom)

                SplashWavePaperLayer(
                    shape: shape,
                    faceColor: ribbon.color,
                    cutEdgeColor: palette.waveCutEdgeColor(for: ribbon.id),
                    resonance: resonance,
                    waveIndex: SplashWaveGenerator.formulas.firstIndex {
                        $0.id == ribbon.id
                    } ?? 0
                )
                    .frame(width: worldSize.width, height: worldSize.height)
                    .accessibilityIdentifier(ribbon.id.rawValue)
            }
        }
        .frame(width: worldSize.width, height: worldSize.height)
        .position(layout.waveWorldCenter)
    }
}

private struct SplashWavePaperLayer: View {
    let shape: SplashWaveRibbonShape
    let faceColor: Color
    let cutEdgeColor: Color
    let resonance: SplashWaveResonanceSample?
    let waveIndex: Int

    var body: some View {
        ZStack {
            shape
                .fill(cutEdgeColor)
                .offset(
                    x: SplashWaveMaterial.cutEdgeX,
                    y: SplashWaveMaterial.cutEdgeY
                )

            ZStack {
                shape.fill(faceColor)

                Image("NeutralPaperGrainV1")
                    .resizable(resizingMode: .tile)
                    .mask(shape)
                    .blendMode(.softLight)
                    .opacity(SplashWaveMaterial.textureOpacity)
                    .accessibilityHidden(true)

                shape.stroke(
                    Color.white.opacity(SplashWaveMaterial.edgeHighlightOpacity),
                    lineWidth: SplashWaveMaterial.edgeHighlightWidth
                )

                if let resonance {
                    let seamContributions = resonance.seamContributions(for: waveIndex)
                    if !seamContributions.isEmpty {
                        ZStack {
                            ForEach(Array(seamContributions.enumerated()), id: \.offset) { item in
                                let contribution = item.element
                                let normalizedOpacity = min(
                                    max(
                                        contribution.strength
                                            / SplashWaveResonanceSample.maximumSeamStrength,
                                        0
                                    ),
                                    1
                                )
                                if normalizedOpacity > 0 {
                                    SplashWaveResonanceSeam(
                                        points: shape.top,
                                        contributions: [contribution]
                                    )
                                    .stroke(
                                        Color.white.opacity(Double(normalizedOpacity)),
                                        style: StrokeStyle(lineWidth: 1.45, lineCap: .round)
                                    )
                                }
                            }
                        }
                        .compositingGroup()
                        .opacity(
                            0.38 * Double(SplashWaveResonanceSample.maximumSeamStrength)
                        )
                    }
                }
            }
            .compositingGroup()
        }
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(SplashWaveMaterial.contactShadowOpacity),
            radius: SplashWaveMaterial.contactShadowRadius,
            x: SplashWaveMaterial.contactShadowX,
            y: SplashWaveMaterial.contactShadowY
        )
        .shadow(
            color: Color.black.opacity(SplashWaveMaterial.castShadowOpacity),
            radius: SplashWaveMaterial.castShadowRadius,
            x: SplashWaveMaterial.castShadowX,
            y: SplashWaveMaterial.castShadowY
        )
    }
}

/// The bright, temporary cut-edge that rides the focal wave with a resonance.
/// It draws the same sampled analytic curve as the ribbon, never a separate
/// overlay, so the light follows the paper rather than crossing through it.
private struct SplashWaveResonanceSeam: Shape {
    let points: [CGPoint]
    let contributions: [SplashWaveResonanceSample.Contribution]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let firstPoint = points.first, let lastPoint = points.last else {
            return path
        }
        for contribution in contributions {
            let lowerBound = max(
                contribution.center - contribution.halfWidth * 2.1, firstPoint.x
            )
            let upperBound = min(
                contribution.center + contribution.halfWidth * 2.1, lastPoint.x
            )
            guard upperBound > lowerBound, points.count > 1 else { continue }

            // Interpolate the moving endpoints instead of snapping them to
            // the nearest analytic sample. This keeps the edge highlight's
            // travel continuous at the geometry sample boundaries.
            let lowerPoint = interpolatedPoint(at: lowerBound)
            let upperPoint = interpolatedPoint(at: upperBound)
            let segment = points.filter {
                $0.x > lowerBound && $0.x < upperBound
            }

            path.move(to: CGPoint(
                x: lowerPoint.x * rect.width,
                y: lowerPoint.y * rect.height
            ))
            for point in segment {
                path.addLine(to: CGPoint(x: point.x * rect.width, y: point.y * rect.height))
            }
            path.addLine(to: CGPoint(
                x: upperPoint.x * rect.width,
                y: upperPoint.y * rect.height
            ))
        }
        return path
    }

    private func interpolatedPoint(at x: CGFloat) -> CGPoint {
        let upperIndex = points.firstIndex { $0.x >= x } ?? points.count - 1
        let lowerIndex = max(upperIndex - 1, 0)
        let span = points[upperIndex].x - points[lowerIndex].x
        let fraction = span > 0
            ? (x - points[lowerIndex].x) / span
            : 0
        return CGPoint(
            x: x,
            y: points[lowerIndex].y
                + (points[upperIndex].y - points[lowerIndex].y) * fraction
        )
    }
}

private enum SplashWaveMaterial {
    static let cutEdgeX: CGFloat = 1.2
    static let cutEdgeY: CGFloat = 2.0

    static let textureOpacity = 0.68

    static let edgeHighlightOpacity = 0.14
    static let edgeHighlightWidth: CGFloat = 0.75

    static let contactShadowOpacity = 0.26
    static let contactShadowRadius: CGFloat = 1.6
    static let contactShadowX: CGFloat = 0
    static let contactShadowY: CGFloat = 1.4

    static let castShadowOpacity = 0.18
    static let castShadowRadius: CGFloat = 5.5
    static let castShadowX: CGFloat = 3.5
    static let castShadowY: CGFloat = 6.5

    static func cutEdgeColor(for id: SplashSceneActorID) -> Color {
        switch id {
        case .waveRearDeep, .waveFrontDeep:
            Color(red: 8 / 255, green: 40 / 255, blue: 108 / 255)
        case .waveMiddleBlue:
            Color(red: 32 / 255, green: 63 / 255, blue: 131 / 255)
        case .waveRearPeriwinkle, .waveFrontPeriwinkle:
            Color(red: 59 / 255, green: 81 / 255, blue: 139 / 255)
        case .waveMiddleLavender, .waveFrontLavender:
            Color(red: 102 / 255, green: 85 / 255, blue: 141 / 255)
        case .waveWarmReveal:
            Color(red: 214 / 255, green: 134 / 255, blue: 40 / 255)
        default:
            PlanetFocusPalette.canvasInk
        }
    }
}

private struct SplashWaveRibbonShape: Shape {
    let top: [CGPoint]
    let bottom: [CGPoint]

    func path(in rect: CGRect) -> Path {
        let scaledTop = top.map { scale($0, in: rect) }
        let scaledBottom = bottom.map { scale($0, in: rect) }
        guard let firstTop = scaledTop.first else {
            return Path()
        }

        var path = Path()
        path.move(to: firstTop)
        for point in scaledTop.dropFirst() {
            path.addLine(to: point)
        }
        for point in scaledBottom.reversed() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func scale(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
    }
}

enum SplashLotusStyle {
    case blue
    case lavender

    fileprivate func color(
        for petal: SplashLotusPetalID,
        palette: SplashAtmospherePalette
    ) -> Color {
        return switch (self, petal) {
        case (_, .heart): palette.accent.color
        case (.blue, .center), (.blue, .innerLeft), (.blue, .innerRight): palette.waveMid.color
        case (.blue, .baseLeft), (.blue, .baseRight): palette.waveMid.color
        case (.blue, _): palette.waveDeep.color
        case (.lavender, _): palette.waveLavender.color
        }
    }
}

struct SplashLotusPlacement: Identifiable {
    let id: SplashSceneActorID
    let center: CGPoint
    let width: CGFloat
    let style: SplashLotusStyle
}

private struct SplashLotusPetal: Identifiable {
    let id: SplashLotusPetalID
    let family: SplashLotusPetalFamily
    let side: SplashLotusPetalSide
    let width: CGFloat
    let height: CGFloat
    let horizontalOffset: CGFloat
    let bottomOffset: CGFloat
    let restingRotation: Double
    let depth: Double

}

private enum SplashLotusPetalFamily {
    case center
    case inner
    case outer
    case bowl
    case heart
}

private enum SplashLotusPetalSide {
    case left
    case center
    case right
}

private struct SplashLotusView: View {
    let actorID: SplashSceneActorID
    let style: SplashLotusStyle
    let palette: SplashAtmospherePalette
    let centerOpacity: Double
    let heartOpacity: Double
    let leftFanProgress: CGFloat
    let rightFanProgress: CGFloat

    private var petals: [SplashLotusPetal] {
        [
            .init(id: .baseLeft, family: .bowl, side: .left, width: 0.23, height: 0.36, horizontalOffset: -0.006, bottomOffset: 0.022, restingRotation: -79, depth: 0),
            .init(id: .baseRight, family: .bowl, side: .right, width: 0.22, height: 0.35, horizontalOffset: 0.008, bottomOffset: 0.024, restingRotation: 78, depth: 0),
            .init(id: .outerLeft, family: .outer, side: .left, width: 0.46, height: 0.52, horizontalOffset: -0.015, bottomOffset: 0.010, restingRotation: -64, depth: 1),
            .init(id: .outerRight, family: .outer, side: .right, width: 0.44, height: 0.51, horizontalOffset: 0.017, bottomOffset: 0.012, restingRotation: 63, depth: 1),
            .init(id: .innerLeft, family: .inner, side: .left, width: 0.41, height: 0.65, horizontalOffset: -0.006, bottomOffset: -0.006, restingRotation: -35, depth: 2),
            .init(id: .innerRight, family: .inner, side: .right, width: 0.39, height: 0.63, horizontalOffset: 0.008, bottomOffset: -0.002, restingRotation: 34, depth: 2),
            .init(id: .center, family: .center, side: .center, width: 0.41, height: 0.75, horizontalOffset: 0, bottomOffset: -0.014, restingRotation: 0, depth: 3),
            .init(id: .heart, family: .heart, side: .center, width: 0.176, height: 0.22, horizontalOffset: 0.002, bottomOffset: 0.014, restingRotation: 0, depth: 4)
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            let base = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.93)

            ZStack(alignment: .topLeading) {
                ForEach(petals) { petal in
                    let petalWidth = proxy.size.width * petal.width
                    let petalHeight = proxy.size.width * petal.height
                    let activeProgress = progress(for: petal)

                    SplashLotusPetalShape(family: petal.family)
                        .fill(style.color(for: petal.id, palette: palette))
                        .overlay(
                            SplashLotusPetalShape(family: petal.family)
                                .stroke(palette.type.color.opacity(0.20), lineWidth: 0.6)
                        )
                        .shadow(
                            color: Color.black.opacity(0.38),
                            radius: max(1.4, proxy.size.width * 0.012),
                            y: max(1.7, proxy.size.width * 0.015)
                        )
                        .frame(width: petalWidth, height: petalHeight)
                        .rotationEffect(
                            .degrees(petal.restingRotation * Double(activeProgress)),
                            anchor: .bottom
                        )
                        .position(
                            x: base.x + proxy.size.width * petal.horizontalOffset * activeProgress,
                            y: base.y
                                + proxy.size.height * petal.bottomOffset * activeProgress
                                - petalHeight / 2
                        )
                        .opacity(opacity(for: petal, fanProgress: activeProgress))
                        .zIndex(petal.depth)
                        .accessibilityIdentifier("\(actorID.rawValue)-\(petal.id.rawValue)")
                }
            }
        }
        .accessibilityIdentifier(actorID.rawValue)
    }

    private func progress(for petal: SplashLotusPetal) -> CGFloat {
        switch petal.side {
        case .left: leftFanProgress
        case .center: 1
        case .right: rightFanProgress
        }
    }

    private func opacity(
        for petal: SplashLotusPetal,
        fanProgress: CGFloat
    ) -> Double {
        switch petal.id {
        case .center: centerOpacity
        case .heart: heartOpacity
        default: Double(fanProgress)
        }
    }
}

private struct SplashLotusPetalShape: Shape {
    let family: SplashLotusPetalFamily

    func path(in rect: CGRect) -> Path {
        let contour = contour(for: family)
        var path = Path()
        path.move(to: point(contour.base, in: rect))
        path.addCurve(
            to: point(contour.tip, in: rect),
            control1: point(contour.leftBaseControl, in: rect),
            control2: point(contour.leftTipControl, in: rect)
        )
        path.addCurve(
            to: point(contour.base, in: rect),
            control1: point(contour.rightTipControl, in: rect),
            control2: point(contour.rightBaseControl, in: rect)
        )
        path.closeSubpath()
        return path
    }

    private func point(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
    }

    private func contour(for family: SplashLotusPetalFamily) -> SplashLotusPetalContour {
        switch family {
        case .center:
            .init(base: .init(x: 0.50, y: 1), tip: .init(x: 0.52, y: 0), leftBaseControl: .init(x: 0.08, y: 0.72), leftTipControl: .init(x: 0.16, y: 0.22), rightTipControl: .init(x: 0.84, y: 0.17), rightBaseControl: .init(x: 0.91, y: 0.72))
        case .inner:
            .init(base: .init(x: 0.50, y: 1), tip: .init(x: 0.48, y: 0.01), leftBaseControl: .init(x: 0.04, y: 0.70), leftTipControl: .init(x: 0.12, y: 0.24), rightTipControl: .init(x: 0.86, y: 0.17), rightBaseControl: .init(x: 0.94, y: 0.68))
        case .outer:
            .init(base: .init(x: 0.50, y: 1), tip: .init(x: 0.46, y: 0.03), leftBaseControl: .init(x: 0.02, y: 0.72), leftTipControl: .init(x: 0.08, y: 0.30), rightTipControl: .init(x: 0.90, y: 0.18), rightBaseControl: .init(x: 0.98, y: 0.66))
        case .bowl:
            .init(base: .init(x: 0.50, y: 1), tip: .init(x: 0.43, y: 0.05), leftBaseControl: .init(x: 0.02, y: 0.76), leftTipControl: .init(x: 0.05, y: 0.33), rightTipControl: .init(x: 0.92, y: 0.18), rightBaseControl: .init(x: 0.97, y: 0.62))
        case .heart:
            .init(base: .init(x: 0.50, y: 1), tip: .init(x: 0.50, y: 0), leftBaseControl: .init(x: 0.03, y: 0.68), leftTipControl: .init(x: 0.15, y: 0.22), rightTipControl: .init(x: 0.85, y: 0.22), rightBaseControl: .init(x: 0.97, y: 0.68))
        }
    }
}

private struct SplashLotusPetalContour {
    let base: CGPoint
    let tip: CGPoint
    let leftBaseControl: CGPoint
    let leftTipControl: CGPoint
    let rightTipControl: CGPoint
    let rightBaseControl: CGPoint
}

private struct SplashNavigationBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let selectedItem: SplashMenuItem
    let fontSize: CGFloat
    let spacing: CGFloat
    let usesEqualWidthItems: Bool
    let ink: SplashColorComponents
    let selectedInk: SplashColorComponents
    let action: (SplashMenuItem) -> Void
    @State private var hoveredItem: SplashMenuItem?
    @Namespace private var indicatorNamespace

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 2),
                    spacing: 4
                ) {
                    menuItems
                }
                .padding(.top, 14)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(PlanetFocusPalette.canvasInk)
            } else {
                HStack(alignment: .top, spacing: spacing) {
                    menuItems
                }
            }
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        let usesEqualColumns = usesEqualWidthItems || dynamicTypeSize.isAccessibilitySize
        let navigationInk = dynamicTypeSize.isAccessibilitySize
            ? PlanetFocusPalette.typePaleBlue
            : ink.color
        let selectedNavigationInk = dynamicTypeSize.isAccessibilitySize
            ? PlanetFocusPalette.warmYellow
            : selectedInk.color
        ForEach(SplashMenuItem.allCases) { item in
            let activeItem = hoveredItem ?? selectedItem

            Button {
                action(item)
            } label: {
                VStack(spacing: max(4, fontSize * 0.12)) {
                    Text(item.rawValue)
                        .font(PlanetFocusTypography.navigation(size: fontSize))
                        .foregroundStyle(
                            item == activeItem
                                ? selectedNavigationInk
                                : navigationInk
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: usesEqualColumns ? .infinity : nil)

                    ZStack {
                        if item == activeItem {
                            Circle()
                                .fill(selectedNavigationInk)
                                .matchedGeometryEffect(
                                    id: SplashNavigationMotion.dotID,
                                    in: indicatorNamespace
                                )
                        }
                    }
                    .frame(width: max(7, fontSize * 0.22), height: max(7, fontSize * 0.22))

                    ZStack {
                        if item == activeItem {
                            Capsule()
                                .fill(selectedNavigationInk)
                                .matchedGeometryEffect(
                                    id: SplashNavigationMotion.underlineID,
                                    in: indicatorNamespace
                                )
                        }
                    }
                    .frame(width: usesEqualColumns ? nil : max(48, fontSize * 2.60),
                           height: max(2, fontSize * 0.055))
                }
                .frame(
                    minWidth: usesEqualColumns ? nil : max(54, fontSize * 2.05),
                    maxWidth: usesEqualColumns ? .infinity : nil,
                    minHeight: 44,
                    alignment: .top
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                withAnimation(SplashNavigationMotion.hoverTransition) {
                    if isHovering {
                        hoveredItem = item
                    } else if hoveredItem == item {
                        hoveredItem = nil
                    }
                }
            }
            .accessibilityLabel(item.rawValue)
            .accessibilityValue(item == selectedItem ? "Selected" : "Not selected")
            .accessibilityHint(item.accessibilityHint)
            .accessibilityIdentifier("splash-menu-\(item.rawValue.lowercased())")
        }
    }

}

private extension SplashMenuItem {
    var accessibilityHint: String {
        switch self {
        case .start: "Begin the selected story"
        case .stories: "Browse stories"
        case .stats: "View focus statistics"
        case .settings: "Open settings"
        }
    }
}

private enum SplashNavigationMotion {
    static let hoverFadeDuration = 0.14
    static let hoverTransition = Animation.easeInOut(duration: hoverFadeDuration)
    static let dotID = "splash-navigation-dot"
    static let underlineID = "splash-navigation-underline"
}
