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

/// Audio time is a host-time projection of the same session elapsed time used by
/// SwiftUI. No frames advance the transport. Resume samples held notes at their
/// current envelope positions instead of replaying missed attacks.
@MainActor @Observable
final class PerformanceSynthesizer {
    private(set) var status = "Sound off"
    private(set) var outputLevel: Float = 0
    private var runToken = UUID()
    private var engine: AVAudioEngine?
    private var fadeTask: Task<Void, Never>?
    private(set) var volume: Float = 0.65
    private(set) var isMuted = false
    var effectiveVolume: Float { isMuted ? 0 : volume }

    /// Output-only control: never rebuild the score or alter the shared transport.
    func setOutput(volume: Double, isMuted: Bool) {
        self.volume = volume.isFinite ? Float(min(1, max(0, volume))) : 0
        self.isMuted = isMuted
        engine?.mainMixerNode.outputVolume = effectiveVolume
    }

    func play(session: PerformanceSession, events: [SplashWaveNoteEvent]) {
        stop()
        guard !session.isPaused, session.progress(at: .now) < 1 else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            let engine = AVAudioEngine()
            let rate = audioSession.sampleRate
            guard rate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)
            else { status = "Audio format unavailable"; return }
            let plan = SplashPerformancePlan(session: session, scoreEvents: events)
            let voices = events.map { event in
                PerformanceSynthVoice(event: event, source: plan.soundSource(
                    for: .init(event: event, scheduledStartBeat: event.startBeat)))
            }
            let hostAnchor = ProcessInfo.processInfo.systemUptime
            let elapsedAnchor = session.elapsedTime(at: .now)
            let duration = session.duration.timeInterval
            let node = AVAudioSourceNode(format: format) { @Sendable isSilent, timestamp, frameCount, audioBufferList in
                let hostSeconds = AVAudioTime.seconds(forHostTime: timestamp.pointee.mHostTime)
                let start = elapsedAnchor + hostSeconds - hostAnchor
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    data.assumingMemoryBound(to: Float.self).initialize(repeating: 0, count: Int(frameCount))
                }
                guard start < duration else { isSilent.pointee = true; return noErr }
                for voice in voices {
                    let secondsPerBeat = voice.secondsPerBeat
                    guard voice.event.endBeat * secondsPerBeat > start,
                          voice.event.startBeat * secondsPerBeat < start + Double(frameCount) / rate else { continue }
                    let pan = Double(voice.event.tonalSlot) / 7 * 0.5 - 0.25
                    for frame in 0..<Int(frameCount) {
                        let elapsed = start + Double(frame) / rate
                        let startFade = min(max((elapsed - elapsedAnchor) / 0.03, 0), 1)
                        let sample = voice.sample(at: elapsed) * startFade
                        for (channel, buffer) in buffers.enumerated() {
                            guard let data = buffer.mData else { continue }
                            let balance = channel == 0 ? 1 - pan : 1 + pan
                            data.assumingMemoryBound(to: Float.self)[frame] += Float(sample * balance)
                        }
                    }
                }
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    let samples = data.assumingMemoryBound(to: Float.self)
                    for frame in 0..<Int(frameCount) { samples[frame] = tanh(samples[frame]) }
                }
                isSilent.pointee = false
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = effectiveVolume
            let token = UUID()
            runToken = token
            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { @Sendable [weak self] buffer, _ in
                guard let samples = buffer.floatChannelData?[0] else { return }
                var peak: Float = 0
                for frame in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[frame])) }
                let measuredPeak = peak
                Task { @MainActor [weak self] in
                    guard let self, self.runToken == token, self.engine != nil else { return }
                    self.outputLevel = measuredPeak
                }
            }
            try engine.start()
            self.engine = engine
            status = "Synth audition · drone, pads + melody"
        } catch {
            status = "Audio unavailable: \(error.localizedDescription)"
        }
    }

    func fadeOut() {
        fadeTask?.cancel()
        guard let fadingEngine = engine else { status = "Sound off"; return }
        engine = nil
        status = "Sound off"
        outputLevel = 0
        fadeTask = Task {
            let volume = fadingEngine.mainMixerNode.outputVolume
            for step in (0..<6).reversed() {
                guard !Task.isCancelled else { break }
                fadingEngine.mainMixerNode.outputVolume = volume * Float(step) / 6
                try? await Task.sleep(for: .milliseconds(5))
            }
            fadingEngine.stop()
        }
    }

    func stop() {
        fadeTask?.cancel()
        engine?.stop()
        engine = nil
        outputLevel = 0
        status = "Sound off"
    }
}
