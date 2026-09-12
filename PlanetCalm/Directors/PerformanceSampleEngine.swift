import AVFoundation
import Foundation

/// Bounded streaming voices: ALAC decoding is handled by AVAudioPlayerNode, so a
/// 55-minute score does not retain 55 minutes of PCM or create a node per event.
/// Note onsets use the audio timeline. The control tick only queues ahead and
/// updates slow gain envelopes; it never advances the performance clock.
// Access is confined to PerformanceAudioPlayback (or one synchronous offline test).
final class PerformanceSampleEngine {
    static let sampleRate = 48_000.0
    static let lookAhead = 0.25
    let engine = AVAudioEngine()
    private(set) var events: [SplashSampleEvent]
    let duration: Double
    private let files: [String: AVAudioFile]
    private let ambientSeed: UInt64?
    private var generatedThrough = 0.0
    private var voices: [Voice] = []
    private var nextEvent = 0
    private var anchorElapsed = 0.0
    private var anchorHost: UInt64 = 0
    private var offline = false
    private var outputVolume: Float = 0.65
    private(set) var scheduledCount = 0

    private final class Voice {
        let player = AVAudioPlayerNode()
        let gain = AVAudioUnitEQ(numberOfBands: 1)
        let pitch: Float
        let handpan: Bool
        var event: SplashSampleEvent?
        var resumedAt = 0.0
        var isPad = false
        init(pitch: Float, handpan: Bool) { self.pitch = pitch; self.handpan = handpan }
    }

    convenience init(session: PerformanceSession, score: [PerformanceNoteEvent], resourceRoot: URL? = nil) throws {
        var loaded: [String: AVAudioFile] = [:]
        for asset in PerformanceAudioAssetCatalog.all {
            loaded[asset.fileName] = try asset.audioFile(resourceRoot: resourceRoot)
        }
        try self.init(duration: session.duration.timeInterval,
                      events: SplashSamplePlan.events(session: session, score: score,
                        durations: loaded.mapValues { Double($0.length) / $0.processingFormat.sampleRate }),
                      files: loaded, ambientSeed: nil)
    }

    convenience init(ambientSeed: UInt64, resourceRoot: URL? = nil) throws {
        var loaded: [String: AVAudioFile] = [:]
        for asset in PerformanceAudioAssetCatalog.all {
            loaded[asset.fileName] = try asset.audioFile(resourceRoot: resourceRoot)
        }
        try self.init(duration: .infinity, events: [], files: loaded, ambientSeed: ambientSeed)
    }

    private init(duration: Double, events: [SplashSampleEvent],
                 files: [String: AVAudioFile], ambientSeed: UInt64?) throws {
        self.duration = duration
        self.events = events
        self.files = files
        self.ambientSeed = ambientSeed
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2)
        else { throw Failure.invalidFormat }

        let handpanBus = AVAudioMixerNode()
        let delay = AVAudioUnitDelay()
        delay.delayTime = SplashSamplePlan.secondsPerBeat * 0.75
        delay.feedback = 18
        delay.lowPassCutoff = 3_500
        delay.wetDryMix = 12
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 14
        for node in [handpanBus, delay, reverb] as [AVAudioNode] { engine.attach(node) }
        engine.connect(handpanBus, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        // Calculate the actual overlap, with space for queued attacks, per fixed
        // processing route. Refuse an unexpectedly dense plan instead of stealing
        // sounding notes. The limit is independent of total session duration.
        // Ambient capacity is fixed from the bounded route budget. The finite
        // path continues to size itself from its complete score below.
        let capacity = ambientSeed == nil ? nil : [24, 6, 3, 6]
        for (routeIndex, (pitch, handpan)) in [(Float(0), false), (Float(1200), false), (Float(-1200), false), (Float(0), true)].enumerated() {
            let route = events.filter { $0.pitchCents == pitch && $0.usesHandpanEffects == handpan }
            var boundaries: [(Double, Int)] = []
            for event in route {
                boundaries.append((event.start - Self.lookAhead, 1))
                boundaries.append((event.end + 0.1, -1))
            }
            boundaries.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
            var count = 0
            var maximum = 0
            for boundary in boundaries { count += boundary.1; maximum = max(maximum, count) }
            let routeCapacity = capacity?[routeIndex] ?? maximum
            guard voices.count + routeCapacity <= 48 else { throw Failure.tooManyVoices }
            for _ in 0..<routeCapacity {
                let voice = Voice(pitch: pitch, handpan: handpan)
                voice.gain.bands.first?.filterType = .lowPass
                voice.gain.bands.first?.frequency = 10_000
                voice.gain.bands.first?.bandwidth = 1
                voice.gain.bands.first?.bypass = true
                engine.attach(voice.player)
                engine.attach(voice.gain)
                let destination = handpan ? handpanBus : engine.mainMixerNode
                if pitch != 0 {
                    let shifter = AVAudioUnitTimePitch()
                    shifter.pitch = pitch
                    shifter.rate = 1
                    engine.attach(shifter)
                    engine.connect(voice.player, to: shifter, format: format)
                    engine.connect(shifter, to: voice.gain, format: format)
                    engine.connect(voice.gain, to: destination, format: format)
                } else {
                    engine.connect(voice.player, to: voice.gain, format: format)
                    engine.connect(voice.gain, to: destination, format: format)
                }
                voices.append(voice)
            }
        }
    }

    var voiceCount: Int { voices.count }

    func start(elapsed: Double, offline: Bool = false) throws {
        let preparationStarted = mach_absolute_time()
        self.offline = offline
        anchorElapsed = min(max(elapsed, 0), duration)
        if ambientSeed != nil {
            // Keep absolute zero available for the one-time intro when entering
            // Home; later joins retain only the source-derived tail lookback.
            generatedThrough = anchorElapsed < SplashAmbientScore.tailAllowance
                ? 0
                : max(anchorElapsed - SplashAmbientScore.tailAllowance, 0)
        }
        anchorHost = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.08)
        if offline {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2)
            else { throw Failure.invalidFormat }
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 480)
        }
        engine.prepare()
        try engine.start()
        if !offline {
            let now = mach_absolute_time()
            anchorHost = now + AVAudioTime.hostTime(forSeconds: 0.08)
            // Account for engine startup: both audio and visuals still refer to
            // the original session start, rather than delaying the score.
            anchorElapsed = elapsed + AVAudioTime.seconds(forHostTime: now - preparationStarted) + 0.08
        }
        try update(elapsed: anchorElapsed)
    }

    func setVolume(_ volume: Float) {
        outputVolume = min(max(volume, 0), 1)
        if outputVolume == 0 { engine.mainMixerNode.outputVolume = 0 }
    }

    func update(elapsed: Double) throws {
        if let ambientSeed {
            // Refill in coarse chunks only when the playable horizon is nearly
            // exhausted; the control tick never regenerates the score.
            let target = elapsed + Self.ambientWindow
            if generatedThrough < elapsed + Self.ambientLowWaterMark {
                let durations = files.mapValues { Double($0.length) / $0.processingFormat.sampleRate }
                events.append(contentsOf: SplashSamplePlan.ambientEvents(
                    from: generatedThrough, through: target, seed: ambientSeed, durations: durations))
                generatedThrough = target
            }
            // Keep the queue bounded while active tails remain available.
            let removable = events.prefix { $0.end + 0.15 < elapsed }.count
            if removable > 0 {
                events.removeFirst(removable)
                nextEvent = max(nextEvent - removable, 0)
            }
        }
        for voice in voices {
            guard let event = voice.event else { continue }
            if elapsed >= event.end + 0.05 {
                voice.player.stop()
                voice.event = nil
            } else {
                let resumeFade = Float(PerformanceEnvelope.smooth((elapsed - voice.resumedAt) / 0.08))
                let ambientGain = ambientSeed.map { _ in Self.ambientGain(at: elapsed) } ?? 1
                voice.player.volume = event.gain(at: elapsed) / Float(pow(10, event.gainDB / 20))
                    * resumeFade * ambientGain
                if ambientSeed != nil, event.asset.kind == .pad, let band = voice.gain.bands.first {
                    band.bypass = false
                    band.frequency = Float(Self.padFilterFrequency(progress: lightProgress(at: elapsed)))
                    band.bandwidth = 0.5
                    band.gain = 0
                } else {
                    voice.gain.bands.first?.bypass = true
                }
            }
        }
        while nextEvent < events.count && events[nextEvent].start <= elapsed + Self.lookAhead {
            let event = events[nextEvent]
            nextEvent += 1
            guard event.end > elapsed else { continue }
            // Returning from Settings/background never bursts missed one-shots.
            guard (anchorElapsed < 1 && elapsed < 1) || event.start >= elapsed - 0.05 || event.resumesAfterInterruption else { continue }
            guard let file = files[event.asset.fileName],
                  let voice = voices.first(where: {
                      $0.event == nil && $0.pitch == event.pitchCents && $0.handpan == event.usesHandpanEffects
                  }) else { throw Failure.tooManyVoices }
            let onset = max(event.start, elapsed)
            let offset = max(0, onset - event.start)
            let firstFrame = AVAudioFramePosition((offset * Self.sampleRate).rounded())
            let frames = min(file.length - firstFrame,
                AVAudioFramePosition(((event.end - onset) * Self.sampleRate).rounded()))
            guard frames > 0 else { continue }
            voice.event = event
            voice.resumedAt = offset > 0.02 ? onset : event.start - 1
            voice.gain.globalGain = Float(event.gainDB)
            let ambientGain = ambientSeed.map { _ in Self.ambientGain(at: onset) } ?? 1
            voice.player.volume = event.gain(at: onset) / Float(pow(10, event.gainDB / 20)) * ambientGain
            voice.isPad = event.asset.kind == .pad
            if ambientSeed != nil, voice.isPad, let band = voice.gain.bands.first {
                band.bypass = false
                band.frequency = Float(Self.padFilterFrequency(progress: lightProgress(at: onset)))
                band.bandwidth = 0.5
                band.gain = 0
            } else {
                voice.gain.bands.first?.bypass = true
            }
            voice.player.pan = event.pan
            voice.player.scheduleSegment(file, startingFrame: firstFrame,
                frameCount: AVAudioFrameCount(frames), at: nil)
            let when: AVAudioTime
            if offline {
                when = AVAudioTime(sampleTime: AVAudioFramePosition(((onset - anchorElapsed) * Self.sampleRate).rounded()),
                                   atRate: Self.sampleRate)
            } else {
                when = AVAudioTime(hostTime: anchorHost + AVAudioTime.hostTime(forSeconds: max(0, onset - anchorElapsed)))
            }
            voice.player.play(at: when)
            scheduledCount += 1
        }
        let endFade = duration.isFinite ? Float(PerformanceEnvelope.smooth((duration - elapsed) / 10)) : 1
        let startFade = Float(PerformanceEnvelope.smooth((elapsed - anchorElapsed) / 7))
        engine.mainMixerNode.outputVolume = outputVolume * endFade * startFade
    }

    func currentElapsed() -> Double {
        let now = mach_absolute_time()
        return anchorElapsed + (now >= anchorHost ? AVAudioTime.seconds(forHostTime: now - anchorHost) : 0)
    }

    func stop() {
        engine.stop()
        for voice in voices { voice.player.stop(); voice.event = nil }
    }

    enum Failure: LocalizedError {
        case invalidFormat, tooManyVoices, renderFailed
        var errorDescription: String? {
            switch self {
            case .invalidFormat: "Stereo audio format unavailable"
            case .tooManyVoices: "Audio score exceeds its streaming voice limit"
            case .renderFailed: "Offline audio render failed"
            }
        }
    }

    private static let ambientWindow = 20.0
    private static let ambientLowWaterMark = 8.0

    static func ambientProgress(at elapsed: Double) -> Double {
        SplashAmbientScore.lightProgress(at: elapsed)
    }

    static func ambientGain(at elapsed: Double) -> Float {
        // Night is quieter and spacious, while daylight is fuller without
        // disappearing the musical bed at either end of the cycle.
        Float(0.707 + 0.293 * ambientProgress(at: elapsed))
    }

    private func lightProgress(at elapsed: Double) -> Double {
        ambientSeed == nil ? min(1, max(0, elapsed / duration)) : Self.ambientProgress(at: elapsed)
    }

    static func ambientPadFilterFrequency(at elapsed: Double) -> Double {
        padFilterFrequency(progress: SplashAmbientScore.lightProgress(at: elapsed))
    }

    private static func padFilterFrequency(progress: Double) -> Double {
        let low = log(6_500.0), high = log(11_000.0)
        return exp(low + (high - low) * progress)
    }
}
