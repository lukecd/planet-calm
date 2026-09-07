import Foundation
import SwiftUI
import UIKit

struct AutumnSceneViewportTransform: Equatable, Sendable {
    let viewport: CGSize
    let scale: Double
    let horizontalOffset: Double
    let verticalOffset: Double

    func compositionPoint(fromScreen point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - horizontalOffset) / scale,
            y: (point.y - verticalOffset) / scale
        )
    }

    func compositionLength(fromScreen length: Double) -> Double {
        length / scale
    }

    func screenPoint(fromComposition point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * scale + horizontalOffset,
            y: point.y * scale + verticalOffset
        )
    }
}

enum AutumnCastReviewMode: String, CaseIterable, Identifiable, Sendable {
    case combined
    case rabbit
    case singleBird
    case flock

    var id: String { rawValue }
}

struct AutumnCastRenderOptions: Equatable, Sendable {
    var reviewMode: AutumnCastReviewMode? = nil
    var flockCount = 24
    var birdBodyLength = 14.0
    var diagnostics = false
    var advancesFromReferenceDate = true

    static let production = AutumnCastRenderOptions()
}

enum AutumnCastLayerSlot: Equatable {
    case distantSky
    case behindTreeRoots
}

struct AutumnCastLayer: View {
    let slot: AutumnCastLayerSlot
    let performance: StoryPerformance
    let elapsedTime: TimeInterval
    let referenceDate: Date
    let reduceMotion: Bool
    let composition: AutumnDeviceComposition
    let transform: AutumnSceneViewportTransform
    let options: AutumnCastRenderOptions

    private var relevantMoment: StoryMoment? {
        let effect: StoryEffectID = slot == .distantSky ? .autumnBirdFlock : .autumnRabbitPeek
        return performance.activeMoments.first { $0.visualCue?.effect == effect }
    }

    var body: some View {
        if let moment = relevantMoment {
            if options.advancesFromReferenceDate {
                TimelineView(.animation(minimumInterval: cadence, paused: false)) { context in
                    content(
                        moment: moment,
                        localElapsed: elapsedTime + context.date.timeIntervalSince(referenceDate) - moment.startTime
                    )
                }
            } else {
                content(moment: moment, localElapsed: elapsedTime - moment.startTime)
            }
        }
    }

    private var cadence: TimeInterval {
        if slot == .behindTreeRoots { return reduceMotion ? 1.0 / 30 : 0.2 }
        return reduceMotion ? 1.0 / 30 : 1.0 / 60
    }

    @ViewBuilder
    private func content(moment: StoryMoment, localElapsed: TimeInterval) -> some View {
        switch AutumnCastImages.bundled {
        case .success(let images):
            Canvas(opaque: false, rendersAsynchronously: true) { context, _ in
                switch slot {
                case .distantSky:
                    if options.reviewMode == .singleBird {
                        drawSingleBird(context: &context, images: images, localElapsed: localElapsed)
                    } else {
                        drawFlock(context: &context, images: images, moment: moment, localElapsed: localElapsed)
                    }
                case .behindTreeRoots:
                    drawRabbit(context: &context, images: images, localElapsed: localElapsed)
                }
            }
            .accessibilityHidden(true)

        case .failure(let error):
#if DEBUG
            Text("Autumn cast unavailable: \(error.localizedDescription)")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(8)
                .background(.white.opacity(0.85))
#endif
        }
    }

    private func drawRabbit(
        context: inout GraphicsContext,
        images: AutumnCastImages,
        localElapsed: TimeInterval
    ) {
        let appearance = RabbitPeekConfiguration.appearance(
            at: localElapsed,
            reduceMotion: reduceMotion
        )
        guard appearance.opacity > 0, images.rabbitFrames.indices.contains(appearance.frameIndex) else { return }

        let displayCanvas = min(max(transform.viewport.width * 0.45, 150), 190)
        let rootContact = CGPoint(
            x: composition.tree.x + composition.tree.width * 0.430108,
            y: composition.tree.y + composition.tree.height * 0.918567
        )
        let rootScreen = transform.screenPoint(fromComposition: rootContact)
        let centerScreen = CGPoint(
            x: rootScreen.x + displayCanvas * 0.14 + appearance.horizontalOffset * displayCanvas,
            y: rootScreen.y - (477.0 - 256.0) / 512.0 * displayCanvas
        )
        let center = transform.compositionPoint(fromScreen: centerScreen)
        let canvasLength = transform.compositionLength(fromScreen: displayCanvas)
        let image = Image(uiImage: images.rabbitFrames[appearance.frameIndex])
        context.opacity = appearance.opacity
        context.draw(
            image,
            in: CGRect(
                x: center.x - canvasLength / 2,
                y: center.y - canvasLength / 2,
                width: canvasLength,
                height: canvasLength
            )
        )
    }

    private func drawSingleBird(
        context: inout GraphicsContext,
        images: AutumnCastImages,
        localElapsed: TimeInterval
    ) {
        guard localElapsed >= 0 else { return }
        let frame = reduceMotion ? 2 : Int(floor(localElapsed / (1.0 / 15.0))) % images.birdFrames.count
        let center = CGPoint(x: transform.viewport.width * 0.62, y: transform.viewport.height * 0.34)
        drawBird(
            context: &context,
            image: images.birdFrames[frame],
            centerScreen: center,
            displayedBodyLength: options.birdBodyLength,
            heading: 0,
            opacity: 1
        )
    }

    private func drawFlock(
        context: inout GraphicsContext,
        images: AutumnCastImages,
        moment: StoryMoment,
        localElapsed: TimeInterval
    ) {
        guard localElapsed >= 0, localElapsed < moment.duration else { return }
        let seed = BirdFlockEventSeed.map(moment.randomSeed)
        guard let configuration = try? BirdFlockConfiguration(
            width: transform.viewport.width,
            height: transform.viewport.height,
            count: options.flockCount,
            seed: seed,
            bodyLength: options.birdBodyLength
        ) else { return }
        let trajectory = BirdFlockTrajectoryCache.shared.trajectory(for: configuration)
        let sampleTime = reduceMotion ? 7 : localElapsed
        let sample = trajectory.sample(at: sampleTime)
        let opacity = reduceMotion ? reducedMotionFlockOpacity(at: localElapsed) : 1
        guard opacity > 0 else { return }

        let ordered = sample.agents.sorted {
            $0.scale == $1.scale ? $0.id < $1.id : $0.scale < $1.scale
        }
        for agent in ordered {
            let frame = reduceMotion ? 2 : agent.wingFrame(at: localElapsed)
            drawBird(
                context: &context,
                image: images.birdFrames[frame],
                centerScreen: CGPoint(x: agent.x, y: agent.y),
                displayedBodyLength: configuration.bodyLength * agent.scale,
                heading: agent.heading,
                opacity: opacity
            )
        }
        if options.diagnostics {
            drawDiagnostics(context: &context, sample: sample, configuration: configuration)
        }
    }

    private func drawBird(
        context: inout GraphicsContext,
        image: UIImage,
        centerScreen: CGPoint,
        displayedBodyLength: Double,
        heading: Double,
        opacity: Double
    ) {
        let center = transform.compositionPoint(fromScreen: centerScreen)
        let sourceScale = transform.compositionLength(fromScreen: displayedBodyLength) / 192
        var birdContext = context
        birdContext.opacity = opacity
        birdContext.translateBy(x: center.x, y: center.y)
        birdContext.rotate(by: .radians(min(max(heading, -.pi / 12), .pi / 12)))
        birdContext.draw(
            Image(uiImage: image),
            in: CGRect(
                x: -300 * sourceScale,
                y: -270 * sourceScale,
                width: 512 * sourceScale,
                height: 512 * sourceScale
            )
        )
    }

    private func drawDiagnostics(
        context: inout GraphicsContext,
        sample: BirdFlockTrajectorySample,
        configuration: BirdFlockConfiguration
    ) {
        var diagnosticContext = context
        diagnosticContext.opacity = 0.48
        diagnosticContext.stroke(
            Path { path in
                let y = transform.compositionPoint(
                    fromScreen: CGPoint(x: 0, y: transform.viewport.height * configuration.routeY)
                ).y
                path.move(to: CGPoint(x: transform.compositionPoint(fromScreen: .zero).x, y: y))
                path.addLine(to: CGPoint(
                    x: transform.compositionPoint(fromScreen: CGPoint(x: transform.viewport.width, y: 0)).x,
                    y: y
                ))
            },
            with: .color(.teal),
            style: StrokeStyle(lineWidth: transform.compositionLength(fromScreen: 1), dash: [5, 4])
        )
        let guide = transform.compositionPoint(fromScreen: CGPoint(x: sample.guide.x, y: sample.guide.y))
        let radius = transform.compositionLength(fromScreen: 4)
        diagnosticContext.fill(
            Path(ellipseIn: CGRect(x: guide.x - radius, y: guide.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.teal)
        )
        for agent in sample.agents {
            let center = transform.compositionPoint(fromScreen: CGPoint(x: agent.x, y: agent.y))
            let separation = transform.compositionLength(
                fromScreen: configuration.bodyLength * configuration.separationRadiusBodies
            )
            diagnosticContext.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - separation,
                    y: center.y - separation,
                    width: separation * 2,
                    height: separation * 2
                )),
                with: .color(.teal.opacity(0.24)),
                lineWidth: transform.compositionLength(fromScreen: 0.5)
            )
        }
    }

    private func reducedMotionFlockOpacity(at elapsed: TimeInterval) -> Double {
        if elapsed < 2 { return max(0, elapsed / 2) }
        if elapsed < 10 { return 1 }
        if elapsed < 13 { return 1 - (elapsed - 10) / 3 }
        return 0
    }
}

enum RabbitPeekConfiguration {
    static let revealDuration: TimeInterval = 1.4
    static let preGestureHold: TimeInterval = 0.4
    static let gestureDuration: TimeInterval = 2.4
    static let postGestureHold: TimeInterval = 2.0
    static let retreatDuration: TimeInterval = 1.8
    static let frameDuration: TimeInterval = 0.2
    static let frameCount = 12
    static let stableFrameIndex = 0
    static let hiddenHorizontalOffset = -0.22

    struct Appearance: Equatable {
        let frameIndex: Int
        let horizontalOffset: Double
        let opacity: Double
    }

    static func appearance(at elapsed: TimeInterval, reduceMotion: Bool) -> Appearance {
        guard elapsed >= 0, elapsed < AutumnCastSchedule.rabbitDuration else {
            return Appearance(frameIndex: stableFrameIndex, horizontalOffset: hiddenHorizontalOffset, opacity: 0)
        }
        if reduceMotion {
            let opacity: Double
            if elapsed < 1.5 { opacity = smoothstep(elapsed / 1.5) }
            else if elapsed < 6 { opacity = 1 }
            else { opacity = 1 - smoothstep((elapsed - 6) / 2) }
            return Appearance(frameIndex: stableFrameIndex, horizontalOffset: 0, opacity: opacity)
        }

        let gestureStart = revealDuration + preGestureHold
        let gestureEnd = gestureStart + gestureDuration
        let retreatStart = gestureEnd + postGestureHold
        if elapsed < revealDuration {
            let amount = smoothstep(elapsed / revealDuration)
            return Appearance(
                frameIndex: stableFrameIndex,
                horizontalOffset: hiddenHorizontalOffset * (1 - amount),
                opacity: amount
            )
        }
        if elapsed < gestureStart {
            return Appearance(frameIndex: stableFrameIndex, horizontalOffset: 0, opacity: 1)
        }
        if elapsed < gestureEnd {
            let frame = min(frameCount - 1, Int(floor((elapsed - gestureStart) / frameDuration)))
            return Appearance(frameIndex: frame, horizontalOffset: 0, opacity: 1)
        }
        if elapsed < retreatStart {
            return Appearance(frameIndex: stableFrameIndex, horizontalOffset: 0, opacity: 1)
        }
        let amount = smoothstep((elapsed - retreatStart) / retreatDuration)
        return Appearance(
            frameIndex: stableFrameIndex,
            horizontalOffset: hiddenHorizontalOffset * amount,
            opacity: 1 - amount
        )
    }

    private static func smoothstep(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

struct AutumnCastManifest: Decodable, Sendable {
    struct Family: Decodable, Sendable {
        struct Frame: Decodable, Sendable {
            let file: String
            let sha256: String
        }
        let dimensions: [Int]
        let frameDurationSeconds: Double
        let frames: [Frame]
    }
    let rabbit: Family
    let bird: Family
}

struct AutumnCastResources: Sendable {
    let manifest: AutumnCastManifest
    let rabbitURLs: [URL]
    let birdURLs: [URL]

    init(bundle: Bundle) throws {
        guard let manifestURL = bundle.url(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "CastV1"
        ) else {
            throw AutumnCastResourceError.missingManifest
        }
        do {
            manifest = try JSONDecoder().decode(
                AutumnCastManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw AutumnCastResourceError.invalidManifest
        }
        rabbitURLs = try Self.urls(for: manifest.rabbit, family: "Rabbit", bundle: bundle)
        birdURLs = try Self.urls(for: manifest.bird, family: "Bird", bundle: bundle)
        guard rabbitURLs.count == 12, birdURLs.count == 12 else {
            throw AutumnCastResourceError.invalidManifest
        }
    }

    private static func urls(
        for family: AutumnCastManifest.Family,
        family name: String,
        bundle: Bundle
    ) throws -> [URL] {
        try family.frames.map { frame in
            let filename = URL(fileURLWithPath: frame.file).deletingPathExtension().lastPathComponent
            guard let url = bundle.url(
                forResource: filename,
                withExtension: "png",
                subdirectory: "CastV1/\(name)"
            ) else {
                throw AutumnCastResourceError.missingFrame(frame.file)
            }
            return url
        }
    }
}

enum AutumnCastResourceError: LocalizedError, Sendable {
    case missingManifest
    case invalidManifest
    case missingFrame(String)
    case invalidFrame(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest: "Missing Autumn CastV1 manifest."
        case .invalidManifest: "Could not decode the Autumn CastV1 manifest."
        case .missingFrame(let path): "Missing Autumn cast frame: \(path)"
        case .invalidFrame(let path): "Could not decode Autumn cast frame: \(path)"
        }
    }
}

final class AutumnCastImages: @unchecked Sendable {
    static let bundled: Result<AutumnCastImages, AutumnCastResourceError> = {
        do {
            return .success(try AutumnCastImages(bundle: .main))
        } catch let error as AutumnCastResourceError {
            return .failure(error)
        } catch {
            return .failure(.invalidManifest)
        }
    }()

    let resources: AutumnCastResources
    let rabbitFrames: [UIImage]
    let birdFrames: [UIImage]

    init(bundle: Bundle) throws {
        resources = try AutumnCastResources(bundle: bundle)
        rabbitFrames = try Self.images(urls: resources.rabbitURLs)
        birdFrames = try Self.images(urls: resources.birdURLs)
    }

    private static func images(urls: [URL]) throws -> [UIImage] {
        try urls.map { url in
            guard let image = UIImage(contentsOfFile: url.path),
                  image.cgImage?.width == 512,
                  image.cgImage?.height == 512 else {
                throw AutumnCastResourceError.invalidFrame(url.lastPathComponent)
            }
            return image
        }
    }
}

private final class BirdFlockTrajectoryBox {
    let value: BirdFlockTrajectory
    init(_ value: BirdFlockTrajectory) { self.value = value }
}

private final class BirdFlockTrajectoryCache: @unchecked Sendable {
    static let shared = BirdFlockTrajectoryCache()
    private let cache = NSCache<NSString, BirdFlockTrajectoryBox>()

    func trajectory(for configuration: BirdFlockConfiguration) -> BirdFlockTrajectory {
        let key = [
            String(BirdFlockConfiguration.version),
            String(configuration.width.bitPattern),
            String(configuration.height.bitPattern),
            String(configuration.count),
            String(configuration.seed),
            String(configuration.bodyLength.bitPattern),
            String(configuration.leaderCorrectionScale.bitPattern)
        ].joined(separator: ":") as NSString
        if let cached = cache.object(forKey: key) { return cached.value }
        let trajectory = BirdFlockTrajectory(configuration: configuration)
        cache.setObject(BirdFlockTrajectoryBox(trajectory), forKey: key)
        return trajectory
    }
}
