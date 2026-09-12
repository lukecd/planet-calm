import Foundation

/// All creative choices are made once from the session seed. The streaming engine
/// consumes this plan, including during offline renders; it never rolls randomness.
struct SplashSampleEvent: Equatable, Sendable {
    let id: String
    let asset: PerformanceAudioAssetReference
    let start: Double
    let end: Double
    let fadeIn: Double
    let fadeOut: Double
    let gainDB: Double
    let pan: Float
    let pitchCents: Float

    var usesHandpanEffects: Bool { asset.fileName.hasPrefix("handpan-") }
    var resumesAfterInterruption: Bool { asset.kind == .pad || asset.kind == .bassDrone }

    func gain(at time: Double) -> Float {
        guard time >= start, time < end else { return 0 }
        let attack = PerformanceEnvelope.smooth((time - start) / max(fadeIn, 0.001))
        let release = PerformanceEnvelope.smooth((end - time) / max(fadeOut, 0.001))
        return Float(pow(10, gainDB / 20) * attack * release)
    }
}

enum SplashMelodyInstrument: String, CaseIterable, Sendable {
    case chimes, cyberChord = "cyber-chord", handpan
}

struct SplashMelodySection: Equatable, Sendable {
    let start: Double
    let instrument: SplashMelodyInstrument
}

enum SplashSamplePlan {
    static let secondsPerBeat = 60.0 / 65.0
    static let slotNames = ["F2", "G2", "A2", "B2", "C3", "D3", "E3", "F3"]

    static func padBank(at time: Double, duration: Double) -> Int {
        min(3, max(1, 1 + Int(time / max(duration / 3, 1))))
    }

    /// A shuffled bag visits every instrument before repeating one. Each stays for
    /// 48–72 seconds, and selection is held for an entire musical phrase.
    static func melodySections(duration: Double, seed: UInt64) -> [SplashMelodySection] {
        var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("melody-instruments"))
        var result: [SplashMelodySection] = []
        var time = 0.0
        while time < duration {
            var bag = SplashMelodyInstrument.allCases
            for index in stride(from: bag.count - 1, through: 1, by: -1) {
                bag.swapAt(index, random.integer(in: 0...index))
            }
            if bag.first == result.last?.instrument { bag.swapAt(0, 1) }
            for instrument in bag where time < duration {
                result.append(.init(start: time, instrument: instrument))
                time += random.value(in: 48...72)
            }
        }
        return result
    }

    static func instrument(at time: Double, sections: [SplashMelodySection]) -> SplashMelodyInstrument {
        sections.last { $0.start <= time }?.instrument ?? .chimes
    }

    /// Returns a small absolute-time slice of the browsing score. A cycle gets a
    /// deterministic continuation, while the event type remains the same shared
    /// score consumed by the paper scene and the sample transport.
    static func ambientScoreEvents(from start: Double, through end: Double,
                                   seed: UInt64) -> [PerformanceNoteEvent] {
        SplashAmbientScore.events(from: start, through: end, seed: seed)
    }

    /// Maps only the requested slice to imported recordings. The caller owns the
    /// rolling window, so this function never constructs a session-length plan.
    static func ambientEvents(from start: Double, through end: Double,
                              seed: UInt64, durations: [String: Double]) -> [SplashSampleEvent] {
        let score = ambientScoreEvents(from: start, through: end, seed: seed)
        var result: [SplashSampleEvent] = []

        func append(id: String, name: String, start: Double, length: Double,
                    attack: Double, release: Double, trim: Double = 0,
                    pan: Float = 0, pitch: Float = 0) {
            guard let asset = PerformanceAudioAssetCatalog.named(name),
                  let sourceDuration = durations[name], sourceDuration > 0 else { return }
            // Query boundaries are scheduling boundaries, never musical ones.
            // Keeping the natural source end makes adjacent rolling windows
            // produce byte-for-byte identical event descriptors.
            let eventEnd = start + min(length, sourceDuration)
            guard start >= 0, eventEnd > start else { return }
            result.append(.init(id: id, asset: asset, start: start, end: eventEnd,
                fadeIn: min(attack, (eventEnd - start) / 2),
                fadeOut: min(release, (eventEnd - start) / 2),
                gainDB: asset.startingGainDB + trim, pan: pan, pitchCents: pitch))
        }

        if start <= 0, end > 0 {
            append(id: "ambient-intro", name: "intro", start: 0,
                length: 60, attack: 0.02, release: 2)
        }

        for event in score {
            let eventStart = event.startBeat * secondsPerBeat
            var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("ambient-sample-" + event.id))
            let variation = random.value(in: -1.5...1.0)
            switch event.role {
            case .pad:
                let bank = SplashAmbientScore.padBank(at: eventStart, seed: seed)
                let name = "pad-\(bank)-\(slotNames[min(max(event.tonalSlot, 0), 7)])"
                append(id: event.id, name: name, start: eventStart,
                    length: event.totalBeats * secondsPerBeat,
                    attack: event.envelope.attackBeats * secondsPerBeat,
                    release: event.envelope.releaseBeats * secondsPerBeat,
                    trim: [-3.0, 7.0, 6.0][bank - 1] + variation,
                    pan: Float(random.value(in: -0.15...0.15)),
                    pitch: Float(event.octaveOffset * 1200))
            case .drone:
                let parts = event.id.split(separator: "-")
                let droneIndex = Int(parts.last ?? "0") ?? 0
                let name = "bass-drone-\(droneIndex % 2 + 1)-F1"
                append(id: event.id, name: name, start: eventStart,
                    length: event.totalBeats * secondsPerBeat,
                    attack: 3, release: 8, trim: variation,
                    pitch: random.unitInterval() < 0.20 ? -1200 : 0)
            case .melody, .chime:
                let parts = event.id.split(separator: "-")
                let voice = SplashAmbientScore.melodyInstrument(for: event, seed: seed)
                let names = [2: "A3", 4: "C4", 5: "D4", 6: "E4", 7: "F4"]
                guard let name = names[event.tonalSlot] else { continue }
                let pan = voice == .handpan
                    ? Float((Int(parts.last ?? "0") ?? 0) % 2 == 0 ? -0.22 : 0.22)
                    : Float(random.value(in: -0.15...0.15))
                append(id: event.id, name: "\(voice.rawValue)-\(name)", start: eventStart,
                    length: 120, attack: 0.008, release: 1.2,
                    trim: variation, pan: pan)
            }
        }
        // Accents are indexed independently of retrieval windows and musical blocks.
        let firstTransition = max(1, Int(floor(max(start, 0) / 108)) - 1)
        let lastTransition = max(firstTransition, Int(floor(max(end, 0) / 108)) + 1)
        for index in firstTransition...lastTransition {
            let onset = SplashAmbientScore.padTransition(index, seed: seed)
            guard onset >= start, onset < end else { continue }
            var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("ambient-rain-\(index)"))
            append(id: "ambient-rain-\(index)", name: "rain-stick-\(1 + (index + Int(seed % 2)) % 2)",
                start: onset, length: 60, attack: 0.1, release: 3, trim: random.value(in: -6 ... -4))
        }
        let firstAccent = max(0, Int(floor(max(start - 85, 0) / 90)))
        let lastAccent = max(firstAccent, Int(floor(max(end, 0) / 90)))
        for index in firstAccent...lastAccent {
            var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("ambient-koshi-\(index)"))
            let onset = 65 + Double(index) * 90 + random.value(in: -12...12)
            guard onset >= start, onset < end else { continue }
            let section = SplashAmbientScore.padSection(at: onset, seed: seed)
            guard abs(onset - SplashAmbientScore.padTransition(section, seed: seed)) > 22,
                  abs(onset - SplashAmbientScore.padTransition(section + 1, seed: seed)) > 22 else { continue }
            append(id: "ambient-koshi-\(index)", name: "koshi-\(random.integer(in: 1...2))",
                start: onset, length: 60, attack: 0.02, release: 3,
                trim: random.value(in: -3...0), pan: Float(random.value(in: -0.1...0.1)))
        }
        return result.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }

    static func events(session: PerformanceSession, score: [PerformanceNoteEvent],
                       durations: [String: Double]) -> [SplashSampleEvent] {
        let duration = session.duration.timeInterval
        let sections = melodySections(duration: duration, seed: session.randomSeed)
        var result: [SplashSampleEvent] = []
        var droneIndex = 0
        var phraseInstruments: [String: SplashMelodyInstrument] = [:]

        func append(id: String, name: String, start: Double, length: Double,
                    attack: Double, release: Double, trim: Double = 0,
                    pan: Float = 0, pitch: Float = 0) {
            guard let asset = PerformanceAudioAssetCatalog.named(name),
                  let sourceDuration = durations[name], sourceDuration > 0 else { return }
            let end = min(duration, start + min(length, sourceDuration))
            guard start >= 0, end > start else { return }
            result.append(.init(id: id, asset: asset, start: start, end: end,
                fadeIn: min(attack, (end - start) / 2),
                fadeOut: min(release, (end - start) / 2),
                gainDB: asset.startingGainDB + trim, pan: pan, pitchCents: pitch))
        }

        for event in score.sorted(by: { $0.startBeat == $1.startBeat ? $0.id < $1.id : $0.startBeat < $1.startBeat }) {
            let start = event.startBeat * secondsPerBeat
            var random = SeededRandomNumberGenerator(seed: session.randomSeed ^ StableSeed.hash("sample-" + event.id))
            let variation = random.value(in: -1.5...1.0)
            switch event.role {
            case .pad:
                let bank = padBank(at: start, duration: duration)
                // Slot identity is explicit: these filenames use the original MIDI
                // export convention, not an inferred octave from an FFT harmonic.
                let name = "pad-\(bank)-\(slotNames[min(max(event.tonalSlot, 0), 7)])"
                let bankTrim = [-3.0, 7.0, 6.0][bank - 1]
                append(id: event.id, name: name, start: start, length: event.totalBeats * secondsPerBeat,
                    attack: event.envelope.attackBeats * secondsPerBeat,
                    release: event.envelope.releaseBeats * secondsPerBeat,
                    trim: bankTrim + variation, pan: Float(random.value(in: -0.15...0.15)),
                    pitch: Float(event.octaveOffset * 1200))
            case .drone:
                let name = "bass-drone-\(droneIndex % 2 + 1)-F1"
                droneIndex += 1
                append(id: event.id, name: name, start: start, length: event.totalBeats * secondsPerBeat,
                    attack: 3, release: 8, trim: variation,
                    pitch: random.unitInterval() < 0.20 ? -1200 : 0)
            case .melody, .chime:
                let parts = event.id.split(separator: "-")
                let phraseID = parts.count >= 3 ? parts.prefix(2).joined(separator: "-") : event.id
                let voice = phraseInstruments[phraseID] ?? instrument(at: start, sections: sections)
                phraseInstruments[phraseID] = voice
                let names = [2: "A3", 4: "C4", 5: "D4", 6: "E4", 7: "F4"]
                guard let name = names[event.tonalSlot] else { continue }
                let pan = voice == .handpan
                    ? Float((Int(parts.last ?? "0") ?? 0) % 2 == 0 ? -0.22 : 0.22)
                    : Float(random.value(in: -0.15...0.15))
                // Melody samples keep their authored tails; the old oscillator's
                // short ADSR would otherwise cut off the chimes and cyber texture.
                append(id: event.id, name: "\(voice.rawValue)-\(name)", start: start,
                    length: duration - start, attack: 0.008, release: 1.2,
                    trim: variation, pan: pan)
            }
        }

        append(id: "bookend-intro", name: "intro", start: 0, length: duration,
               attack: 0.02, release: 2)
        let outroLength = min(durations["outro"] ?? 24, duration / 3)
        append(id: "bookend-outro", name: "outro", start: duration - outroLength,
               length: outroLength, attack: 0.02, release: 3)
        var accents = SeededRandomNumberGenerator(seed: session.randomSeed ^ StableSeed.hash("accents"))
        let firstRain = accents.integer(in: 1...2)
        for index in 1...2 {
            append(id: "transition-\(index)", name: "rain-stick-\(index == 1 ? firstRain : 3 - firstRain)",
                   start: duration * Double(index) / 3, length: duration / 3,
                   attack: 0.1, release: 3, trim: accents.value(in: -6 ... -4))
        }
        var nextAccent = accents.value(in: 45...75)
        var accentIndex = 0
        while nextAccent < duration - 40 {
            // Leave space around the rainsticks and bookends.
            if abs(nextAccent - duration / 3) > 22 && abs(nextAccent - duration * 2 / 3) > 22 {
                append(id: "koshi-\(accentIndex)", name: "koshi-\(accents.integer(in: 1...2))",
                    start: nextAccent, length: 35.5, attack: 0.02, release: 3,
                    trim: accents.value(in: -3...0), pan: Float(accents.value(in: -0.1...0.1)))
                accentIndex += 1
            }
            nextAccent += accents.value(in: 60...90)
        }
        return result.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
}

/// A deterministic absolute-time score. Musical blocks continue through the
/// light cycle; query boundaries never become note or phrase boundaries.
enum SplashAmbientScore {
    static let cycleDuration: TimeInterval = 600
    static let tailAllowance: TimeInterval = 60
    static let blockBeats = 32.0
    static let blockDuration = blockBeats * SplashSamplePlan.secondsPerBeat

    static func lightProgress(at time: Double) -> Double {
        let phase = max(time, 0).truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return 0.5 - 0.5 * cos(2 * .pi * phase)
    }

    static func cycleIndex(at time: Double) -> Int { max(0, Int(floor(time / cycleDuration))) }

    static func padTransition(_ index: Int, seed: UInt64) -> Double {
        guard index > 0 else { return 0 }
        var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("ambient-pad-change-\(index)"))
        return Double(index) * 108 + random.value(in: -8...8)
    }

    static func padSection(at time: Double, seed: UInt64) -> Int {
        var index = max(0, Int(floor(max(time, 0) / 108)))
        if time < padTransition(index, seed: seed) { index = max(0, index - 1) }
        if time >= padTransition(index + 1, seed: seed) { index += 1 }
        return index
    }

    static func padBank(at time: Double, seed: UInt64) -> Int {
        1 + padSection(at: time, seed: seed) % 3
    }

    /// Each 180-second bag contains all three voices. The last voice is kept
    /// distinct from either possible first voice in the following bag, allowing
    /// bounded random access without replaying the entire listening history.
    static func instrument(at time: TimeInterval, seed: UInt64) -> SplashMelodyInstrument {
        let group = max(0, Int(floor(max(time, 0) / 180)))
        let local = max(time, 0) - Double(group) * 180
        var baseRandom = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("ambient-voice-order"))
        var voices = SplashMelodyInstrument.allCases
        for index in stride(from: 2, through: 1, by: -1) {
            voices.swapAt(index, baseRandom.integer(in: 0...index))
        }
        var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("ambient-voices-\(group)"))
        if random.unitInterval() < 0.5 { voices.swapAt(0, 1) }
        let first = random.value(in: 52...68)
        let second = random.value(in: 56...64)
        return local < first ? voices[0] : (local < first + second ? voices[1] : voices[2])
    }

    static func phraseStart(_ block: Int, seed: UInt64) -> Double {
        var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("ambient-phrase-start-\(block)"))
        return Double(block) * blockDuration + random.value(in: 7...10)
    }

    static func melodyInstrument(for event: PerformanceNoteEvent, seed: UInt64) -> SplashMelodyInstrument {
        let parts = event.id.split(separator: "-")
        let block = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
        return instrument(at: phraseStart(block, seed: seed), seed: seed)
    }

    /// Small close voicings around F using only the imported natural-note pool.
    /// F and the upper C remain common tones, so movement comes from a nearby
    /// color tone rather than from extra layers or independent octave jumps.
    static let harmonicPalette: [[Int]] = [
        [0, 2, 4, 5], // F, A, C, D
        [0, 1, 4, 6], // F, G, C, E
        [0, 2, 4, 7], // F, A, C, F
        [0, 2, 4, 6], // F, A, C, E
        [0, 1, 4, 5]  // F, G, C, D
    ]

    static let supportedMelodySlots: [Int] = [2, 4, 5, 6, 7]

    // Semitone offsets from the lowest imported F, not array-index distances.
    static let slotSemitones = [0, 2, 4, 6, 7, 9, 11, 12]

    /// A harmony lasts about 89 seconds. Some paired sections retain it for
    /// twice as long; lookup remains bounded regardless of listening duration.
    static func harmony(at block: Int, seed: UInt64) -> [Int] {
        var section = max(block, 0) / 3
        var holdRandom = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("ambient-hold-\(section / 2)"))
        if section % 2 == 1, holdRandom.unitInterval() < 0.25 { section -= 1 }
        var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("ambient-harmony-\(section)"))
        let light = lightProgress(at: Double(section * 3) * blockDuration)
        // Open root/fifth colors at night; major-seventh colors join in daylight.
        let choices = light < 0.3 ? [0, 2, 4] : [0, 1, 3, 4]
        return harmonicPalette[choices[random.integer(in: 0...(choices.count - 1))]]
    }

    static func melodySlot(position: Int, harmony: [Int]) -> Int {
        let target = supportedMelodySlots[min(max(position, 0), supportedMelodySlots.count - 1)]
        let pitchClasses = Set(harmony.map { slotSemitones[$0] % 12 })
        let choices = supportedMelodySlots.filter { pitchClasses.contains(slotSemitones[$0] % 12) }
        return choices.min { abs(slotSemitones[$0] - slotSemitones[target]) < abs(slotSemitones[$1] - slotSemitones[target]) } ?? target
    }

    static func events(from start: TimeInterval, through end: TimeInterval,
                       seed: UInt64) -> [PerformanceNoteEvent] {
        guard start.isFinite, end.isFinite, end > start, end > 0 else { return [] }
        var result: [PerformanceNoteEvent] = []
        func append(_ id: String, slot: Int, seconds: Double, gate: Double,
                    envelope: PerformanceEnvelope, role: PerformanceRole,
                    intensity: Double, octave: Int = 0) {
            guard seconds >= max(start, 0), seconds < end else { return }
            result.append(.init(id: id, tonalSlot: slot,
                startBeat: seconds / SplashSamplePlan.secondsPerBeat, gateBeats: gate,
                envelope: envelope, role: role, intensity: intensity,
                isRepeating: false, octaveOffset: octave))
        }
        let firstBlock = max(0, Int(floor(max(start, 0) / blockDuration)) - 1)
        let lastBlock = max(firstBlock, Int(floor(end / blockDuration)))
        for block in firstBlock...lastBlock {
            let base = Double(block) * blockDuration
            let light = lightProgress(at: base)
            var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("ambient-block-\(block)"))
            let blockHarmony = Self.harmony(at: block, seed: seed)
            // C enters last and carries its existing recorded tail across the
            // next boundary. The next block changes other voices before C returns.
            // Night omits the lower color voice, keeping the same sparse density.
            let padSlots = light < 0.4
                ? [blockHarmony[0], blockHarmony[3], blockHarmony[2]]
                : [blockHarmony[0], blockHarmony[1], blockHarmony[3], blockHarmony[2]]
            for (note, slot) in padSlots.enumerated() {
                let seconds = base + Double(note) * blockDuration / Double(padSlots.count)
                    + random.value(in: 0...0.7)
                let gate = random.value(in: 20...24)
                let attack = random.value(in: 2.5...3.5)
                let intensity = random.value(in: 0.48...0.64)
                // Keep the old draw in the stream while the ambient palette
                // stays in one register. This preserves later phrase timing.
                _ = random.unitInterval()
                append("ambient-pad-\(block)-\(note)", slot: slot,
                    seconds: seconds, gate: gate,
                    envelope: .init(attackBeats: attack, decayBeats: 2,
                                    sustainLevel: 0.72, releaseBeats: 8),
                    role: .pad, intensity: intensity,
                    octave: 0)
            }
            let onset = phraseStart(block, seed: seed)
            let phraseLight = lightProgress(at: onset)
            // At night one block in three becomes a longer melodic breath.
            if phraseLight < 0.45 && block % 3 == 2 { continue }
            let handpan = instrument(at: onset, seed: seed) == .handpan
            var motifRandom = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("ambient-motif-\(block / 3)"))
            var position = motifRandom.integer(in: 0...4)
            var motif = [position]
            for _ in 1..<5 {
                position = min(4, max(0, position + (motifRandom.unitInterval() < 0.5 ? -1 : 1)))
                motif.append(position)
            }
            let count = handpan ? (phraseLight < 0.45 ? 3 : 4 + random.integer(in: 0...1))
                : (phraseLight < 0.45 ? 2 : 3 + random.integer(in: 0...1))
            var noteStart = onset
            for note in 0..<count {
                var pitch = motif[note]
                if note == count - 1 && block % 3 == 2 {
                    pitch = min(4, max(0, pitch + (random.unitInterval() < 0.5 ? -1 : 1)))
                }
                append("ambient-melody-\(block)-\(note)", slot: melodySlot(position: pitch, harmony: blockHarmony),
                    seconds: noteStart, gate: random.value(in: 1...2),
                    envelope: .init(attackBeats: 0.12, decayBeats: 0.6,
                                    sustainLevel: 0.30, releaseBeats: 2.5),
                    role: .melody, intensity: random.value(in: 0.33...0.48), octave: 1)
                noteStart += (handpan ? 1.5 : random.value(in: 2.2...3.2)) * SplashSamplePlan.secondsPerBeat
            }
        }
        let droneInterval = 28 * SplashSamplePlan.secondsPerBeat
        let firstDrone = max(0, Int(floor(max(start, 0) / droneInterval)) - 1)
        let lastDrone = max(firstDrone, Int(floor(end / droneInterval)))
        for index in firstDrone...lastDrone {
            append("ambient-drone-\(index)", slot: 0, seconds: Double(index) * droneInterval,
                gate: 32, envelope: .init(attackBeats: 3, decayBeats: 2,
                                        sustainLevel: 0.82, releaseBeats: 10),
                role: .drone, intensity: 0.66)
        }
        return result.sorted { $0.startBeat == $1.startBeat ? $0.id < $1.id : $0.startBeat < $1.startBeat }
    }
}
