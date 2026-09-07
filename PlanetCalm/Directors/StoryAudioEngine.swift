import Foundation

@MainActor
protocol StoryAudioEngine: AnyObject {
    func prepare(for story: Story)
    func schedule(_ cue: StoryAudioCue, for moment: StoryMoment, sessionStart: Date)
    func stop()
}

@MainActor
final class SilentStoryAudioEngine: StoryAudioEngine {
    private(set) var scheduledMomentIDs: [StoryMomentID] = []

    func prepare(for story: Story) {}

    func schedule(_ cue: StoryAudioCue, for moment: StoryMoment, sessionStart: Date) {
        scheduledMomentIDs.append(moment.id)
    }

    func stop() {}
}

@MainActor
final class StoryAudioDispatcher {
    private let engine: any StoryAudioEngine
    private var scheduledMomentIDs: Set<StoryMomentID> = []

    init(engine: any StoryAudioEngine) {
        self.engine = engine
    }

    func prepare(for story: Story) {
        scheduledMomentIDs.removeAll()
        engine.prepare(for: story)
    }

    func dispatch(_ moments: [StoryMoment], sessionStart: Date) {
        for moment in moments {
            guard
                let cue = moment.audioCue,
                scheduledMomentIDs.insert(moment.id).inserted
            else {
                continue
            }
            engine.schedule(cue, for: moment, sessionStart: sessionStart)
        }
    }

    func stop() {
        scheduledMomentIDs.removeAll()
        engine.stop()
    }
}
