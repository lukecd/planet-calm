import Foundation

protocol StoryModule {
    var story: Story { get }
    func makeDirector() -> any StoryDirector
}

struct AutumnTreeStoryModule: StoryModule {
    let story: Story = .autumnTree

    func makeDirector() -> any StoryDirector {
        AutumnTreeDirector()
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
