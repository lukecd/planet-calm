import SwiftUI
import UIKit

/// The Lotus renderer stays story-owned while receiving timing and narrative
/// state from the shared StoryPlayer boundary.
struct ContemporaryLotusStageView: View {
    let context: StorySceneRenderContext

    var body: some View {
        switch ContemporaryLotusStageResources.bundled {
        case .success(let resources):
            GeometryReader { geometry in
                let layout = resources.layout
                let scale = max(
                    geometry.size.width / layout.width,
                    geometry.size.height / layout.height
                )
                let horizontalOffset = (geometry.size.width - layout.width * scale) / 2
                let verticalOffset = (geometry.size.height - layout.height * scale) / 2

                ContemporaryLotusCanvas(layout: layout)
                    .frame(width: layout.width, height: layout.height, alignment: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: horizontalOffset, y: verticalOffset)
            }
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Contemporary Lotus focus story, still pond with one lotus pad")

        case .failure(let error):
            ContentUnavailableView {
                Label("Contemporary Lotus unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            }
        }
    }
}

private struct ContemporaryLotusCanvas: View {
    let layout: ContemporaryLotusStageLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            sceneImage(layout.background)
            sceneImage(layout.mainPadStem)
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .background(Color(red: 0.018, green: 0.055, blue: 0.075))
        .clipped()
    }

    @ViewBuilder
    private func sceneImage(_ placement: ContemporaryLotusAssetPlacement) -> some View {
        if let image = ContemporaryLotusImageStore.shared.image(named: placement.assetID) {
            Image(uiImage: image)
                .resizable()
                .frame(width: placement.width, height: placement.height)
                .offset(x: placement.x, y: placement.y)
                .accessibilityHidden(true)
        }
    }
}

private final class ContemporaryLotusImageStore: @unchecked Sendable {
    static let shared = ContemporaryLotusImageStore()

    private let cache = NSCache<NSString, UIImage>()

    func image(named name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }
        guard
            let url = ContemporaryLotusStageResources.assetURL(named: name),
            let image = UIImage(contentsOfFile: url.path)
        else {
            return nil
        }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

#if DEBUG
/// A deterministic native review route that traverses the same module,
/// Director, player, performance, and renderer catalog used by a real session.
struct ContemporaryLotusReviewView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let referenceDate = Date(timeIntervalSinceReferenceDate: 750)
    private let session = FocusSession(
        story: .contemporaryLotus,
        duration: .twentyFiveMinutes,
        startedAt: Date(timeIntervalSinceReferenceDate: 0),
        randomSeed: 94
    )

    var body: some View {
        let player = StoryPlayer(session: session)
        StorySceneCatalog.scene(
            for: session.story,
            context: StorySceneRenderContext(
                progress: session.progress(at: referenceDate),
                elapsedTime: session.elapsedTime(at: referenceDate),
                performance: player.performance(at: referenceDate, reduceMotion: reduceMotion),
                reduceMotion: reduceMotion,
                duration: session.duration.timeInterval,
                randomSeed: session.randomSeed
            )
        )
        .ignoresSafeArea()
    }
}
#endif
