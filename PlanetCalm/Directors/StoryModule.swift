import Foundation

protocol StoryModule {
    var story: Story { get }
    func makeDirector() -> any StoryDirector
    func makeAudioScore(for session: StorySessionContext, plan: StoryPlan) -> StoryAudioScore
}

extension StoryModule {
    func makeAudioScore(for session: StorySessionContext, plan: StoryPlan) -> StoryAudioScore {
        .silent(story: story, session: session)
    }
}

struct AutumnTreeStoryModule: StoryModule {
    let story: Story = .autumnTree
    let record: AutumnBranchRecord

    init(record: AutumnBranchRecord = .init()) {
        self.record = record.settingsOnly
    }

    func makeDirector() -> any StoryDirector {
        AutumnTreeDirector(record: record)
    }

    func makeAudioScore(for session: StorySessionContext, plan: StoryPlan) -> StoryAudioScore {
        guard let autumn = plan.payload(as: AutumnBranchPlan.self) else {
            return .silent(story: story, session: session)
        }
        return AutumnAudioScore.score(for: autumn)
    }
}

struct ContemporaryLotusStoryModule: StoryModule {
    let story: Story = .contemporaryLotus

    func makeDirector() -> any StoryDirector {
        ContemporaryLotusDirector()
    }
}

enum StoryCatalog {
    static func module(for story: Story) -> any StoryModule {
        switch story {
        case .autumnTree:
            AutumnTreeStoryModule()
        case .contemporaryLotus:
            ContemporaryLotusStoryModule()
        }
    }
}
