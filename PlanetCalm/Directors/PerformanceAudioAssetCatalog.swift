import AVFoundation
import Foundation

/// The exported Ableton stems are kept as individual assets so the runtime can
/// change a pad bank, drone voice, or transition without replacing a whole mix.
/// The catalog is deliberately data-shaped: a future story can provide another
/// catalog without copying the audio engine.
enum PerformanceAudioAssetKind: String, CaseIterable, Sendable {
    case melody
    case pad
    case bassDrone
    case transition
    case atmosphere
    case bookend
}

struct PerformanceAudioAssetReference: Hashable, Sendable {
    let fileName: String
    let subdirectory: String
    let kind: PerformanceAudioAssetKind
    /// Starting point taken from the Ableton lane fader. This is not per-file
    /// normalization; the rendered source dynamics remain intact.
    let startingGainDB: Double
    let processingRoute: StoryAudioProcessingRoute

    init(fileName: String, subdirectory: String, kind: PerformanceAudioAssetKind,
         startingGainDB: Double, processingRoute: StoryAudioProcessingRoute = .dry) {
        self.fileName = fileName
        self.subdirectory = subdirectory
        self.kind = kind
        self.startingGainDB = startingGainDB
        self.processingRoute = processingRoute
    }

    var resourceURL: URL? {
        Bundle.main.url(
            forResource: fileName,
            withExtension: "m4a",
            subdirectory: subdirectory
        )
    }

    func audioFile(resourceRoot: URL? = nil) throws -> AVAudioFile {
        let overrideURL = resourceRoot?.appendingPathComponent(subdirectory).appendingPathComponent(fileName + ".m4a")
        guard let url = overrideURL ?? resourceURL else {
            throw PerformanceAudioAssetError.missingResource(fileName)
        }
        let file = try AVAudioFile(forReading: url)
        let format = file.fileFormat
        guard format.channelCount == 2 else {
            throw PerformanceAudioAssetError.notStereo(fileName, Int(format.channelCount))
        }
        guard abs(format.sampleRate - 48_000) < 0.5 else {
            throw PerformanceAudioAssetError.unexpectedSampleRate(fileName, format.sampleRate)
        }
        return file
    }
}

enum PerformanceAudioAssetError: LocalizedError, Equatable {
    case missingResource(String)
    case notStereo(String, Int)
    case unexpectedSampleRate(String, Double)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "Missing bundled audio resource: \(name).m4a"
        case .notStereo(let name, let channels):
            return "Audio resource \(name).m4a has \(channels) channel(s); stereo is required"
        case .unexpectedSampleRate(let name, let sampleRate):
            return "Audio resource \(name).m4a is \(sampleRate) Hz; 48 kHz is required"
        }
    }
}

enum PerformanceAudioAssetCatalog {
    /// This order matches the MIDI note pool used by the score and the names in
    /// the Ableton pad clips. It is intentionally explicit rather than relying
    /// on lexical sorting (F2 belongs between E3 and F3 in the source export).
    static let padNoteNames = ["A2", "B2", "C3", "D3", "E3", "F2", "F3", "G2"]

    static let padBanks = [1, 2, 3]
    static let melodyNoteNames = ["A3", "C4", "D4", "E4", "F4"]

    static let all: [PerformanceAudioAssetReference] = {
        let pads = padBanks.flatMap { bank in
            padNoteNames.map { note in
                PerformanceAudioAssetReference(
                    fileName: "pad-\(bank)-\(note)",
                    subdirectory: "Audio/Stories/Splash/Pads/Pad\(bank)",
                    kind: .pad,
                    startingGainDB: 0
                )
            }
        }

        let melody = [
            ("Chimes", "chimes", -0.0),
            ("CyberChord", "cyber-chord", -7.0),
            ("Handpan", "handpan", -3.0)
        ].flatMap { directory, prefix, gain in
            melodyNoteNames.map { note in
                PerformanceAudioAssetReference(
                    fileName: "\(prefix)-\(note)",
                    subdirectory: "Audio/Stories/Splash/Melody/\(directory)",
                    kind: .melody,
                    startingGainDB: gain,
                    processingRoute: prefix == "handpan" ? .melodicEcho : .dry
                )
            }
        }

        let stems = [
            PerformanceAudioAssetReference(
                fileName: "bass-drone-1-F1", subdirectory: "Audio/Stories/Splash/Bass",
                kind: .bassDrone, startingGainDB: -20
            ),
            PerformanceAudioAssetReference(
                fileName: "bass-drone-2-F1", subdirectory: "Audio/Stories/Splash/Bass",
                kind: .bassDrone, startingGainDB: -20
            ),
            PerformanceAudioAssetReference(
                fileName: "rain-stick-1", subdirectory: "Audio/Stories/Splash/Transitions",
                kind: .transition,
                // The source is intentionally gentle, but needs this runtime
                // trim to sit beside rain-stick-2 without changing the export.
                startingGainDB: 18
            ),
            PerformanceAudioAssetReference(
                fileName: "rain-stick-2", subdirectory: "Audio/Stories/Splash/Transitions",
                kind: .transition, startingGainDB: 0
            ),
            PerformanceAudioAssetReference(
                fileName: "koshi-1", subdirectory: "Audio/Stories/Splash/Atmosphere",
                kind: .atmosphere, startingGainDB: -15
            ),
            PerformanceAudioAssetReference(
                fileName: "koshi-2", subdirectory: "Audio/Stories/Splash/Atmosphere",
                kind: .atmosphere, startingGainDB: -15
            ),
            PerformanceAudioAssetReference(
                fileName: "intro", subdirectory: "Audio/Stories/Splash/Bookends",
                kind: .bookend, startingGainDB: -10
            ),
            PerformanceAudioAssetReference(
                fileName: "outro", subdirectory: "Audio/Stories/Splash/Bookends",
                kind: .bookend, startingGainDB: -10
            )
        ]
        return pads + melody + stems
    }()

    static func pad(bank: Int, noteName: String) -> PerformanceAudioAssetReference? {
        guard padBanks.contains(bank), padNoteNames.contains(noteName) else { return nil }
        return all.first {
            $0.fileName == "pad-\(bank)-\(noteName)"
        }
    }

    static func named(_ fileName: String) -> PerformanceAudioAssetReference? {
        all.first { $0.fileName == fileName }
    }
}
