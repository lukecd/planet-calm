import SwiftUI
import UIKit

struct AutumnTreeSceneView: View {
    let progress: Double
    let elapsedTime: TimeInterval
    let referenceDate: Date
    let performance: StoryPerformance
    let reduceMotion: Bool
    let showsFocusUI: Bool
    let castOptions: AutumnCastRenderOptions

    init(
        progress: Double,
        elapsedTime: TimeInterval = 0,
        referenceDate: Date = .now,
        performance: StoryPerformance? = nil,
        reduceMotion: Bool = false,
        showsFocusUI: Bool = true,
        castOptions: AutumnCastRenderOptions = .production
    ) {
        let clampedProgress = min(max(progress, 0), 1)
        self.progress = clampedProgress
        self.elapsedTime = elapsedTime
        self.referenceDate = referenceDate
        self.reduceMotion = reduceMotion
        self.showsFocusUI = showsFocusUI
        self.castOptions = castOptions
        self.performance = performance ?? AutumnTreeDirector().performance(
            at: StoryContext(
                progress: clampedProgress,
                elapsedTime: elapsedTime,
                duration: 1,
                reduceMotion: reduceMotion
            ),
            plan: .empty
        )
    }

    var body: some View {
        switch AutumnTreeSceneResources.bundled {
        case .success(let resources):
            GeometryReader { geometry in
                let composition = resources.composition(for: geometry.size)
                let scale = max(
                    geometry.size.width / composition.width,
                    geometry.size.height / composition.height
                )
                let horizontalOffset = (geometry.size.width - composition.width * scale) / 2
                let verticalOffset = (geometry.size.height - composition.height * scale) / 2
                let transform = AutumnSceneViewportTransform(
                    viewport: geometry.size,
                    scale: scale,
                    horizontalOffset: horizontalOffset,
                    verticalOffset: verticalOffset
                )

                AutumnTreeCanvas(
                    progress: progress,
                    elapsedTime: elapsedTime,
                    referenceDate: referenceDate,
                    performance: performance,
                    reduceMotion: reduceMotion,
                    showsFocusUI: showsFocusUI,
                    castOptions: castOptions,
                    composition: composition,
                    leafLayout: resources.leafLayout,
                    terrainAdjustments: resources.terrainAdjustments,
                    transform: transform
                )
                .frame(width: composition.width, height: composition.height)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: horizontalOffset, y: verticalOffset)
            }
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Autumn Tree focus story")

        case .failure(let error):
            ContentUnavailableView {
                Label("Autumn Tree unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            }
        }
    }

}

private struct AutumnTreeCanvas: View {
    let progress: Double
    let elapsedTime: TimeInterval
    let referenceDate: Date
    let performance: StoryPerformance
    let reduceMotion: Bool
    let showsFocusUI: Bool
    let castOptions: AutumnCastRenderOptions
    let composition: AutumnDeviceComposition
    let leafLayout: AutumnLeafLayout
    let terrainAdjustments: AutumnTerrainAdjustments
    let transform: AutumnSceneViewportTransform

    var body: some View {
        ZStack(alignment: .topLeading) {
            sceneImage("sky-paper", width: composition.width, height: composition.height)

            terrainImage("hill-far-left", placement: composition.terrain.farLeft)
            terrainImage("hill-far-right", placement: composition.terrain.farRight)
            terrainImage("hill-mid-left", placement: composition.terrain.midLeft)
            terrainImage("hill-mid-right", placement: composition.terrain.midRight)
            terrainImage("hill-foreground-left", placement: composition.terrain.foregroundLeft)
            terrainImage("hill-foreground-right", placement: composition.terrain.foregroundRight)
            groundImage

            castLayer(.distantSky)

            canopy(depth: "behind")

            castLayer(.behindTreeRoots)

            sceneImage(
                "tree-trunk-branches",
                width: composition.tree.width,
                height: composition.tree.height
            )
            .offset(x: composition.tree.x, y: composition.tree.y)

            canopy(depth: "front")
            groundLeaves
            if showsFocusUI { focusUI }
        }
        .frame(width: composition.width, height: composition.height, alignment: .topLeading)
        .background(Color(red: 0.97, green: 0.92, blue: 0.81))
    }

    private func castLayer(_ slot: AutumnCastLayerSlot) -> some View {
        AutumnCastLayer(
            slot: slot,
            performance: performance,
            elapsedTime: elapsedTime,
            referenceDate: referenceDate,
            reduceMotion: reduceMotion,
            composition: composition,
            transform: transform,
            options: castOptions
        )
        .frame(width: composition.width, height: composition.height)
    }

    @ViewBuilder
    private func terrainImage(_ name: String, placement: AutumnVerticalPlacement) -> some View {
        sceneImage(name, width: composition.width, height: placement.height)
            .offset(y: placement.y)
    }

    private var groundImage: some View {
        let placement = composition.terrain.ground
        let overlap = terrainAdjustments.groundVerticalOverlap[composition.id] ?? 0

        return sceneImage(
            "ground-base",
            width: composition.width,
            height: placement.height + overlap
        )
        .offset(y: placement.y - overlap)
    }

    private func canopy(depth: String) -> some View {
        let leaves = leafLayout.canopy.filter {
            $0.depth == depth && $0.dropAt > progress
        }

        return ForEach(leaves) { leaf in
            let anchorX = composition.tree.x + leaf.x * composition.tree.width
            let anchorY = composition.tree.y + leaf.y * composition.tree.height
            let size = composition.tree.width * 0.105 * leaf.scale

            sceneImage(leaf.assetId, width: size, height: size, aspectFit: true)
                .rotationEffect(
                    .degrees(leaf.rotation),
                    anchor: UnitPoint(x: 0.5, y: 0.86)
                )
                .offset(x: anchorX - size / 2, y: anchorY - size * 0.86)
        }
    }

    private var groundLeaves: some View {
        ForEach(leafLayout.groundLeaves) { leaf in
            let tabletScale = composition.id == "iphone" ? 1.0 : 0.65
            let size = composition.width * leaf.size * tabletScale
            let anchorX = composition.width * leaf.x
            let anchorY = composition.height * leaf.y

            sceneImage(leaf.assetId, width: size, height: size, aspectFit: true)
                .rotationEffect(
                    .degrees(leaf.rotation),
                    anchor: UnitPoint(x: 0.5, y: 0.72)
                )
                .offset(x: anchorX - size / 2, y: anchorY - size * 0.72)
        }
    }

    private var focusUI: some View {
        let ui = composition.ui
        let isComplete = progress >= 1
        let timerText = isComplete ? "Complete" : "25:00"
        let timerSize = isComplete ? ui.timerSize * 0.72 : ui.timerSize
        let subtitle = isComplete ? "Focus session finished" : "Focus session"
        let subtitleSize = (timerSize * 0.31).rounded()
        let actionText = isComplete ? "Well focused" : "Begin"
        let actionSize = (timerSize * 0.33).rounded()
        let sessionText = isComplete ? "Today · 3 sessions" : "Today · 2 sessions"
        let sessionSize = (timerSize * 0.24).rounded()

        return ZStack(alignment: .topLeading) {
            baselineText(
                timerText,
                x: ui.timerX,
                baselineY: ui.timerY,
                size: timerSize,
                weight: .light
            )
            baselineText(
                subtitle,
                x: ui.timerX,
                baselineY: ui.subtitleY,
                size: subtitleSize
            )

            if !isComplete {
                sceneImage(
                    "focus-button-play",
                    width: ui.buttonSize,
                    height: ui.buttonSize,
                    aspectFit: true
                )
                .offset(
                    x: ui.buttonX - ui.buttonSize / 2,
                    y: ui.buttonY - ui.buttonSize / 2
                )
                .accessibilityHidden(true)
            }

            baselineText(
                actionText,
                x: ui.buttonX,
                baselineY: isComplete ? ui.buttonY : ui.beginY,
                size: actionSize,
                color: Color(red: 0.73, green: 0.29, blue: 0.14)
            )
            baselineText(
                sessionText,
                x: composition.width / 2,
                baselineY: ui.completionY,
                size: sessionSize
            )
        }
    }

    private func baselineText(
        _ text: String,
        x: Double,
        baselineY: Double,
        size: Double,
        weight: Font.Weight = .regular,
        color: Color = Color(red: 0.33, green: 0.20, blue: 0.12)
    ) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
            .fixedSize()
            .position(x: x, y: baselineY - size * 0.35)
    }

    @ViewBuilder
    private func sceneImage(
        _ name: String,
        width: Double,
        height: Double,
        aspectFit: Bool = false
    ) -> some View {
        if let image = AutumnTreeImageStore.shared.image(named: name) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: aspectFit ? .fit : .fill)
                .frame(width: width, height: height)
                .clipped()
                .accessibilityHidden(true)
        }
    }
}

private final class AutumnTreeImageStore: @unchecked Sendable {
    static let shared = AutumnTreeImageStore()

    private let cache = NSCache<NSString, UIImage>()

    func image(named name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }
        guard
            let url = AutumnTreeSceneResources.assetURL(named: name),
            let image = UIImage(contentsOfFile: url.path)
        else {
            return nil
        }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}
