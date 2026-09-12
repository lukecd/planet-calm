import AVFoundation
import Foundation
import Observation

/// Temporary, recording-free audition voice. Timing and ADSR are the score event,
/// not a second synthesizer schedule. Immutable data is safe on the audio thread.
struct PerformanceSynthVoice: Sendable {
    let event: SplashWaveNoteEvent
    let source: SplashSoundAssetKey
    let frequency: Double
    let secondsPerBeat: Double

    init(event: SplashWaveNoteEvent, source: SplashSoundAssetKey) {
        self.event = event
        self.source = source
        frequency = 440 * pow(2, Double(SplashMusicDirector.midiNote(for: event) - 69) / 12)
        secondsPerBeat = SplashPerformanceScore.tempo.secondsPerBeat
    }

    func sample(at elapsed: Double) -> Double {
        let beat = elapsed / secondsPerBeat
        guard let envelope = event.sample(at: beat) else { return 0 }
        let age = elapsed - event.startBeat * secondsPerBeat
        let phase = 2 * Double.pi * frequency * age
        let brightness = [0.12, 0.25, 0.42][source.pool.rawValue]
        let melodic = event.role == .melody || event.role == .chime
        // A slow spectral tilt stands in for filter modulation on the eventual pads.
        let breath = 0.75 + 0.25 * sin(2 * Double.pi * age / 23)
        let tone: Double
        if melodic {
            tone = sin(phase) + 0.22 * exp(-age / 1.2) * sin(phase * 2.01)
                + brightness * 0.16 * exp(-age / 0.6) * sin(phase * 3.98)
        } else {
            tone = sin(phase) + 0.18 * sin(phase * 1.002)
                + brightness * breath * (0.45 * sin(phase * 2) + 0.15 * sin(phase * 3))
        }
        let gain = event.role == .drone ? 0.075 : (melodic ? 0.080 : 0.043)
        return tone * envelope.value * event.intensity * gain
    }
}

/// UI state stays on the main actor; graph construction, file opening, and
/// scheduling belong to one audio actor so they cannot interrupt a wave frame.
@MainActor @Observable
final class PerformanceSynthesizer {
    private(set) var status = "Sound off"
    private(set) var outputLevel: Float = 0
    private var runToken = UUID()
    private var playback: PerformanceAudioPlayback?
    private var playingSessionID: UUID?
    private var playingAmbientSeed: UInt64?
    private var ambientAudioReady = false
    private var playingEvents: [SplashWaveNoteEvent] = []
    private var schedulingTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private(set) var volume: Float = 0.65
    private(set) var isMuted = false
    var effectiveVolume: Float { isMuted ? 0 : volume }
    var isPlayingAmbient: Bool { playingAmbientSeed != nil && playback != nil && ambientAudioReady }
    var ambientSeed: UInt64? { playingAmbientSeed }

    func setOutput(volume: Double, isMuted: Bool) {
        self.volume = volume.isFinite ? Float(min(1, max(0, volume))) : 0
        self.isMuted = isMuted
        let level = effectiveVolume
        if let playback { Task { await playback.setVolume(level) } }
    }

    func play(session: PerformanceSession, events: [SplashWaveNoteEvent]) {
        guard !session.isPaused, session.progress(at: .now) < 1 else { return }
        guard playingSessionID != session.id || playingEvents != events || playback == nil else { return }
        stop()
        let playback = PerformanceAudioPlayback(volume: effectiveVolume)
        let token = UUID()
        runToken = token
        self.playback = playback
        playingSessionID = session.id
        playingEvents = events
        status = "Preparing Splash recordings"
        schedulingTask = Task { [weak self] in
            do {
                try await playback.start(session: session, events: events) { [weak self] peak in
                    Task { @MainActor [weak self] in
                        guard let self, self.runToken == token else { return }
                        self.outputLevel = peak
                    }
                }
                try Task.checkCancellation()
                guard let self, self.runToken == token else { await playback.stop(); return }
                self.status = "Splash recordings · stereo"
                try await playback.run()
                if self.runToken == token { self.stop() }
            } catch is CancellationError {
                // stop/fadeOut owns cleanup; a cancelled old task must not
                // tear down a replacement performance or cut its release tail.
            } catch {
                await playback.stop()
                guard let self, self.runToken == token else { return }
                self.stop()
                self.status = "Audio unavailable: \(error.localizedDescription)"
            }
        }
    }

    /// Starts the process-scoped browsing atmosphere. Its score is generated in
    /// short absolute-time windows by PerformanceSampleEngine and therefore keeps
    /// moving across the 10-minute light cycle without rebuilding the graph.
    func playAmbient(seed: UInt64, startedAt: Date) {
        guard playingAmbientSeed != seed || playback == nil else { return }
        stop()
        let playback = PerformanceAudioPlayback(volume: effectiveVolume)
        let token = UUID()
        runToken = token
        self.playback = playback
        playingAmbientSeed = seed
        ambientAudioReady = false
        status = "Preparing home atmosphere"
        schedulingTask = Task { [weak self] in
            do {
                try await playback.startAmbient(seed: seed, startedAt: startedAt) { [weak self] peak in
                    Task { @MainActor [weak self] in
                        guard let self, self.runToken == token else { return }
                        self.outputLevel = peak
                    }
                }
                try Task.checkCancellation()
                guard let self, self.runToken == token else { await playback.stop(); return }
                self.ambientAudioReady = true
                self.status = "Home atmosphere · stereo"
                try await playback.run()
            } catch is CancellationError {
            } catch {
                await playback.stop()
                guard let self, self.runToken == token else { return }
                self.stop()
                self.status = "Audio unavailable: \(error.localizedDescription)"
            }
        }
    }

    func fadeOut() {
        guard fadeTask == nil, let fading = playback else { return }
        schedulingTask?.cancel()
        schedulingTask = nil
        runToken = UUID()
        playingSessionID = nil
        playingAmbientSeed = nil
        ambientAudioReady = false
        playingEvents = []
        outputLevel = 0
        status = "Sound off"
        // Keep ownership until the release finishes, so mute/volume changes
        // still reach the fading graph and a new run can stop it immediately.
        fadeTask = Task { [weak self] in
            await fading.fadeOut()
            guard let self, self.playback === fading else { return }
            self.playback = nil
            self.fadeTask = nil
        }
    }

    func stop() {
        schedulingTask?.cancel()
        schedulingTask = nil
        let stopped = playback
        clearPlayback()
        if let stopped { Task { await stopped.stop() } }
    }

    /// Used for route loss and interruptions where even a short release tail can
    /// leak to a newly selected output device.
    func stopImmediately() { stop() }

    private func clearPlayback() {
        fadeTask?.cancel()
        fadeTask = nil
        runToken = UUID()
        playback = nil
        playingSessionID = nil
        playingAmbientSeed = nil
        ambientAudioReady = false
        playingEvents = []
        outputLevel = 0
        status = "Sound off"
    }
}

/// Each performance exclusively owns its engine. No AVAudioEngine or file is
/// passed across actors; only the immutable score and peak measurements cross.
private actor PerformanceAudioPlayback {
    private var engine: PerformanceSampleEngine?
    private var volume: Float
    private var stopped = false

    init(volume: Float) { self.volume = volume }

    func start(session: PerformanceSession, events: [PerformanceNoteEvent],
               onPeak: @escaping @Sendable (Float) -> Void) throws {
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try audioSession.setActive(true)
        let prepared = try PerformanceSampleEngine(session: session, score: events)
        try Task.checkCancellation()
        prepared.setVolume(volume)
        prepared.engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            var peak: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channels[channel][frame])) }
            }
            onPeak(peak)
        }
        do {
            // Sample the original session clock AFTER preparation. The visuals
            // keep running during preparation; audio joins that same timeline.
            try prepared.start(elapsed: session.elapsedTime(at: .now))
            engine = prepared
        } catch {
            prepared.stop()
            throw error
        }
    }

    func startAmbient(seed: UInt64, startedAt: Date,
                      onPeak: @escaping @Sendable (Float) -> Void) throws {
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try audioSession.setActive(true)
        let prepared = try PerformanceSampleEngine(ambientSeed: seed)
        try Task.checkCancellation()
        prepared.setVolume(volume)
        prepared.engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            var peak: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channels[channel][frame])) }
            }
            onPeak(peak)
        }
        do {
            // Derive elapsed after file opening and graph setup. This keeps audio
            // on the same absolute browsing clock even when preparation is slow.
            try prepared.start(elapsed: Date().timeIntervalSince(startedAt))
            engine = prepared
        } catch {
            prepared.stop()
            throw error
        }
    }

    func run() async throws {
        while let engine, !stopped {
            try Task.checkCancellation()
            let elapsed = engine.currentElapsed()
            try engine.update(elapsed: elapsed)
            if engine.duration.isFinite && elapsed >= engine.duration { stop(); return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        engine?.setVolume(volume)
    }

    func fadeOut() async {
        guard let fading = engine else { stop(); return }
        let relativeLevel = volume > 0 ? fading.engine.mainMixerNode.outputVolume / volume : 0
        let clock = ContinuousClock()
        let started = clock.now
        while engine === fading, !Task.isCancelled {
            let duration = started.duration(to: clock.now).components
            let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            let release = Float(1 - PerformanceEnvelope.smooth(elapsed / 2))
            fading.engine.mainMixerNode.outputVolume = volume * relativeLevel * release
            if elapsed >= 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        stop()
    }

    func stop() {
        stopped = true
        engine?.stop()
        engine = nil
    }
}
