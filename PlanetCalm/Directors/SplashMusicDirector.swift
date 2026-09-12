import Foundation

/// One finite plan in absolute beats. The old repeating score remains a calibration
/// fixture only; running performances consume these same events in every subsystem.
enum SplashMusicDirector {
    static func events(for session: PerformanceSession) -> [SplashWaveNoteEvent] {
        let end = session.duration.timeInterval / SplashSamplePlan.secondsPerBeat
        var events: [SplashWaveNoteEvent] = []
        var pads = SeededRandomNumberGenerator(seed: session.randomSeed ^ StableSeed.hash("pads"))
        var melody = SeededRandomNumberGenerator(seed: session.randomSeed ^ StableSeed.hash("melody"))

        func append(_ id: String, _ slot: Int, _ start: Double, _ gate: Double,
                    _ envelope: SplashADSREnvelope, _ role: SplashPerformanceRole,
                    _ intensity: Double, _ octave: Int = 0) {
            let remaining = end - start
            guard remaining > envelope.attackBeats + envelope.decayBeats + 0.5 else { return }
            let release = min(envelope.releaseBeats,
                              remaining - envelope.attackBeats - envelope.decayBeats)
            let boundedGate = min(gate, remaining - release)
            guard boundedGate >= envelope.attackBeats + envelope.decayBeats else { return }
            events.append(.init(id: id, tonalSlot: slot, startBeat: start,
                gateBeats: boundedGate,
                envelope: .init(attackBeats: envelope.attackBeats,
                    decayBeats: envelope.decayBeats, sustainLevel: envelope.sustainLevel,
                    releaseBeats: release),
                role: role, intensity: intensity, isRepeating: false, octaveOffset: octave))
        }

        // A root drone renews before its predecessor releases, keeping pool changes
        // gradual. These are real note events on wave 1, not an unrelated visual bed.
        for (index, start) in stride(from: 0.0, to: end, by: 28).enumerated() {
            append("drone-\(index)", 0, start, 32,
                .init(attackBeats: 3, decayBeats: 2, sustainLevel: 0.82, releaseBeats: 10),
                .drone, 0.66)
        }

        let harmonies = [[2, 4, 6, 7, 1], [2, 4, 5, 1, 7], [1, 4, 5, 6, 3]]
        var onset = 0.0
        var index = 0
        var previousSlot = -1
        while onset < end {
            let harmony = harmonies[(Int(onset / 32) + Int(session.randomSeed % 3)) % harmonies.count]
            let occupied = Set(events.filter {
                $0.role == .pad && $0.endBeat > onset
            }.map(\.tonalSlot))
            let preferred = harmony.filter { !occupied.contains($0) && $0 != previousSlot }
            let fallback = (1...7).filter { !occupied.contains($0) && $0 != previousSlot }
            let choices = !preferred.isEmpty ? preferred : (!fallback.isEmpty ? fallback : harmony)
            let slot = choices[min(Int(pads.unitInterval() * Double(choices.count)), choices.count - 1)]
            append("pad-\(index)", slot, onset, pads.value(in: 16...18),
                .init(attackBeats: pads.value(in: 2.5...3.5), decayBeats: 2,
                      sustainLevel: 0.72, releaseBeats: 7),
                .pad, pads.value(in: 0.48...0.68),
                pads.unitInterval() < 0.16 ? 1 : 0)
            previousSlot = slot
            index += 1
            onset += index < 4 ? 0.8 : pads.value(in: 4.6...5.2)
        }

        // Small, separated phrases with stepwise motion, bounded register, and rests.
        // No randomness occurs in the renderer or audio callback.
        var phraseStart = 9.0
        var phrase = 0
        let melodySlots = [2, 4, 5, 6, 7]
        let instruments = SplashSamplePlan.melodySections(duration: session.duration.timeInterval, seed: session.randomSeed)
        while phraseStart < end - 6 {
            var position = min(Int(melody.unitInterval() * 5), 4)
            var noteStart = phraseStart
            let handpan = SplashSamplePlan.instrument(at: phraseStart * SplashSamplePlan.secondsPerBeat,
                sections: instruments) == .handpan
            let count = (handpan ? 3 : 2) + min(Int(melody.unitInterval() * 3), 2)
            for note in 0..<count {
                append("melody-\(phrase)-\(note)", melodySlots[position], noteStart,
                    melody.value(in: 1.0...2.0),
                    .init(attackBeats: 0.12, decayBeats: 0.6,
                          sustainLevel: 0.30, releaseBeats: 2.5),
                    .melody, melody.value(in: 0.33...0.48), 1)
                let step = melody.unitInterval() < 0.5 ? -1 : 1
                position = min(max(position + step, 0), 4)
                noteStart += handpan ? 1.5 : melody.value(in: 2.0...3.2)
            }
            phraseStart = noteStart + melody.value(in: 7...13)
            phrase += 1
        }
        return events.sorted {
            $0.startBeat == $1.startBeat ? $0.id < $1.id : $0.startBeat < $1.startBeat
        }
    }

    static func midiNote(for event: SplashWaveNoteEvent) -> Int {
        [41, 43, 45, 47, 48, 50, 52, 53][min(max(event.tonalSlot, 0), 7)]
            + 12 * event.octaveOffset
    }

    static func noteName(for event: SplashWaveNoteEvent) -> String {
        let midi = midiNote(for: event)
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[midi % 12])\(midi / 12 - 1)"
    }
}
