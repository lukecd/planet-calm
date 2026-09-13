import Foundation

enum StoryScoreExporter {
    static let schemaVersion = 1
    static let ticksPerBeat = 480

    static func export(_ score: StoryAudioScore, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let stem = "\(score.storyID)-\(Int(score.duration))-seed-\(score.seed)"
        try midiData(score.midi).write(to: directory.appendingPathComponent(stem + ".mid"),
                                       options: .atomic)
        try Data(cueSheet(score).utf8).write(
            to: directory.appendingPathComponent(stem + "-cues.tsv"), options: .atomic)
        try metadataData(score).write(
            to: directory.appendingPathComponent(stem + "-metadata.json"), options: .atomic)
    }

    static func midiData(_ score: StoryMIDIScore) -> Data {
        let grouped = Dictionary(grouping: score.notes, by: \.track)
        let names = grouped.keys.sorted()
        var tracks: [[UInt8]] = [tempoTrack(score)]
        tracks += names.map {
            noteTrack(name: $0, notes: grouped[$0] ?? [], durationBeats: score.durationBeats)
        }
        var bytes = Array("MThd".utf8)
        bytes += bigEndian(6)
        bytes += [0, 1, UInt8((tracks.count >> 8) & 0xFF), UInt8(tracks.count & 0xFF),
                  UInt8((ticksPerBeat >> 8) & 0xFF), UInt8(ticksPerBeat & 0xFF)]
        for track in tracks {
            bytes += Array("MTrk".utf8) + bigEndian(track.count) + track
        }
        return Data(bytes)
    }

    static func cueSheet(_ score: StoryAudioScore) -> String {
        let header = "time_seconds\tduration_seconds\tbus\tphase\tcue_id\tintensity\tdirection\tsource_moment"
        let rows = score.cues.map { cue in
            [decimal(cue.startTime), decimal(cue.duration), cue.bus.rawValue, cue.phase,
             cue.id, decimal(cue.intensity), cue.direction.map(decimal) ?? "",
             cue.sourceMomentID?.rawValue ?? ""].joined(separator: "\t")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func metadataData(_ score: StoryAudioScore) throws -> Data {
        let value: [String: Any] = [
            "schemaVersion": schemaVersion,
            "story": score.storyID,
            "durationSeconds": score.duration,
            "seed": String(score.seed),
            "beatsPerMinute": score.midi.beatsPerMinute,
            "timeSignature": "\(score.midi.timeSignatureNumerator)/\(score.midi.timeSignatureDenominator)",
            "midiNoteCount": score.midi.notes.count,
            "cueCount": score.cues.count
        ]
        return try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    }

    private struct Message {
        let tick: Int
        let priority: Int
        let bytes: [UInt8]
    }

    private static func tempoTrack(_ score: StoryMIDIScore) -> [UInt8] {
        let micros = Int((60_000_000 / max(1, score.beatsPerMinute)).rounded())
        let denominatorPower = UInt8(max(0, Int(log2(Double(max(1, score.timeSignatureDenominator))))))
        var bytes: [UInt8] = [0, 0xFF, 0x03, 5] + Array("Tempo".utf8)
        bytes += [0, 0xFF, 0x51, 3, UInt8((micros >> 16) & 0xFF),
                  UInt8((micros >> 8) & 0xFF), UInt8(micros & 0xFF)]
        bytes += [0, 0xFF, 0x58, 4, UInt8(score.timeSignatureNumerator),
                  denominatorPower, 24, 8]
        return bytes + variableLength(tick(score.durationBeats)) + [0xFF, 0x2F, 0]
    }

    private static func noteTrack(name: String, notes: [StoryMIDIScore.Note],
                                  durationBeats: Double) -> [UInt8] {
        let nameBytes = Array(name.utf8.prefix(127))
        var bytes: [UInt8] = [0, 0xFF, 0x03, UInt8(nameBytes.count)] + nameBytes
        var messages: [Message] = []
        for note in notes {
            let start = tick(note.startBeat)
            let end = max(start + 1, tick(note.startBeat + note.durationBeats))
            let channel = min(note.channel, 15)
            let key = UInt8(min(max(note.note, 0), 127))
            let velocity = UInt8(min(max(note.velocity, 1), 127))
            messages.append(.init(tick: start, priority: 1,
                                  bytes: [0x90 | channel, key, velocity]))
            messages.append(.init(tick: end, priority: 0,
                                  bytes: [0x80 | channel, key, 0]))
        }
        messages.sort {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.bytes.lexicographicallyPrecedes($1.bytes)
        }
        var previous = 0
        for message in messages {
            bytes += variableLength(message.tick - previous) + message.bytes
            previous = message.tick
        }
        let finalTick = max(previous, tick(durationBeats))
        return bytes + variableLength(finalTick - previous) + [0xFF, 0x2F, 0]
    }

    private static func tick(_ beat: Double) -> Int {
        max(0, Int((beat * Double(ticksPerBeat)).rounded()))
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func bigEndian(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
         UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func variableLength(_ rawValue: Int) -> [UInt8] {
        var value = max(0, rawValue)
        var result = [UInt8(value & 0x7F)]
        value >>= 7
        while value > 0 {
            result.insert(UInt8((value & 0x7F) | 0x80), at: 0)
            value >>= 7
        }
        return result
    }
}

enum SplashAudioScore {
    static func score(for session: PerformanceSession) -> StoryAudioScore {
        let events = SplashMusicDirector.events(for: session)
        let notes = events.map { event in
            StoryMIDIScore.Note(
                id: event.id,
                track: track(for: event.role),
                startBeat: event.startBeat,
                durationBeats: event.gateBeats,
                note: SplashMusicDirector.midiNote(for: event),
                velocity: min(127, max(1, Int((event.intensity * 100).rounded()))),
                channel: channel(for: event.role),
                sourceMomentID: nil)
        }
        return .init(storyID: "splash", duration: session.duration.timeInterval,
                     seed: session.randomSeed,
                     cues: [],
                     midi: .init(beatsPerMinute: 60 / SplashSamplePlan.secondsPerBeat,
                                 timeSignatureNumerator: 4, timeSignatureDenominator: 4,
                                 durationBeats: session.duration.timeInterval
                                    / SplashSamplePlan.secondsPerBeat,
                                 notes: notes))
    }

    private static func track(for role: PerformanceRole) -> String {
        switch role {
        case .drone: "Drone"
        case .pad: "Pads"
        case .chime, .melody: "Melody"
        }
    }

    private static func channel(for role: PerformanceRole) -> UInt8 {
        switch role {
        case .drone: 0
        case .pad: 1
        case .chime, .melody: 2
        }
    }
}
