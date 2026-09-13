import Foundation

@main
struct StoryScoreExportCommand {
    static func main() throws {
        let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        let score: StoryAudioScore
        switch options.story {
        case "splash":
            let session = PerformanceSession(duration: options.duration,
                                             startedAt: Date(timeIntervalSince1970: 0),
                                             randomSeed: options.seed)
            score = SplashAudioScore.score(for: session)
        case "autumn-tree":
            let plan = AutumnBranchPlan(duration: options.duration.timeInterval,
                                        seed: options.seed, tuning: .standard,
                                        isFullTree: true)
            score = AutumnAudioScore.score(for: plan)
        default:
            throw Failure.invalidStory(options.story)
        }
        try StoryScoreExporter.export(score, to: options.output)
        print("Exported \(score.storyID), \(options.minutes) minutes, seed \(options.seed) to \(options.output.path)")
    }

    private struct Options {
        let story: String
        let minutes: Int
        let seed: UInt64
        let output: URL
        var duration: FocusDuration { FocusDuration(minutes: minutes)! }

        init(arguments: [String]) throws {
            func value(after flag: String) -> String? {
                arguments.firstIndex(of: flag).flatMap { index in
                    arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
                }
            }
            story = value(after: "--story") ?? ""
            guard let rawMinutes = value(after: "--minutes"),
                  let minutes = Int(rawMinutes), FocusDuration(minutes: minutes) != nil else {
                throw Failure.invalidMinutes
            }
            self.minutes = minutes
            guard let rawSeed = value(after: "--seed"), let seed = UInt64(rawSeed) else {
                throw Failure.invalidSeed
            }
            self.seed = seed
            guard let rawOutput = value(after: "--output"), !rawOutput.isEmpty else {
                throw Failure.missingOutput
            }
            output = URL(fileURLWithPath: rawOutput, isDirectory: true)
        }
    }

    private enum Failure: LocalizedError {
        case invalidStory(String), invalidMinutes, invalidSeed, missingOutput
        var errorDescription: String? {
            switch self {
            case .invalidStory(let value):
                "Unsupported story '\(value)'; use splash or autumn-tree"
            case .invalidMinutes: "--minutes must be a whole number from 5 through 55"
            case .invalidSeed: "--seed must be an unsigned integer"
            case .missingOutput: "--output is required"
            }
        }
    }
}
