import SwiftUI

enum SplashSceneActorID: String, CaseIterable, Identifiable {
    case background
    case wordmark
    case sun
    case waveRearPeriwinkle
    case waveRearDeep
    case waveWarmReveal
    case waveMiddleLavender
    case waveMiddleBlue
    case waveFrontDeep
    case waveFrontPeriwinkle
    case waveFrontLavender
    case lotusLeft
    case lotusCenter
    case lotusRight
    case navigation

    var id: String { rawValue }
}

enum SplashLotusPetalID: String, CaseIterable, Identifiable {
    case baseLeft
    case baseRight
    case outerLeft
    case outerRight
    case innerLeft
    case innerRight
    case center
    case heart

    var id: String { rawValue }
}

enum SplashMenuItem: String, CaseIterable, Identifiable {
    case start = "Start"
    case stories = "Stories"
    case stats = "Stats"
    case settings = "Settings"

    var id: String { rawValue }
}

/// Settled values are used for the static milestone. These seams are intentionally
/// state-driven so later choreography can animate waves, lotus petals, the sun, and
/// the surrounding UI without changing the scene hierarchy.
struct SplashScenePresentation: Equatable {
    var sceneOpacity: Double
    var wordmarkOpacity: Double
    var sunProgress: CGFloat
    var waveProgress: CGFloat
    var waveMotionPhase: CGFloat
    var lotusCenterOpacity: Double
    var lotusLeftFanProgress: CGFloat
    var lotusRightFanProgress: CGFloat
    var navigationOpacity: Double

    static let presented = SplashScenePresentation(
        sceneOpacity: 1,
        wordmarkOpacity: 1,
        sunProgress: 1,
        waveProgress: 1,
        waveMotionPhase: 0,
        lotusCenterOpacity: 1,
        lotusLeftFanProgress: 1,
        lotusRightFanProgress: 1,
        navigationOpacity: 1
    )
}

enum SplashLayoutMode: Equatable {
    case wideLandscape
    case compactLandscape
    case tabletPortrait
    case phonePortrait
}

struct SplashLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets
    let mode: SplashLayoutMode

    init(size: CGSize, safeAreaInsets: EdgeInsets = EdgeInsets()) {
        self.size = size
        self.safeAreaInsets = safeAreaInsets
        mode = Self.mode(for: size)
    }

    static func mode(for size: CGSize) -> SplashLayoutMode {
        if size.width >= size.height {
            return size.height < 520 ? .compactLandscape : .wideLandscape
        }
        return size.width < 600 ? .phonePortrait : .tabletPortrait
    }

    /// Rotation preserves this dimension on a given device, so art sized from it
    /// keeps the same intrinsic scale in landscape and portrait.
    var shortSide: CGFloat {
        min(size.width, size.height)
    }

    var wordmarkLeading: CGFloat {
        let proportion: CGFloat
        switch mode {
        case .wideLandscape: proportion = 0.09
        case .compactLandscape: proportion = 0.06
        case .tabletPortrait, .phonePortrait: proportion = 0.075
        }
        return max(safeAreaInsets.leading + 24, size.width * proportion)
    }

    var wordmarkTop: CGFloat {
        let proportion: CGFloat
        switch mode {
        case .wideLandscape: proportion = 0.105
        case .compactLandscape: proportion = 0.04
        case .tabletPortrait, .phonePortrait: proportion = 0.045
        }
        return max(safeAreaInsets.top + 18, size.height * proportion)
    }

    var wordmarkFontSize: CGFloat {
        shortSide * 0.115
    }

    var sunCenter: CGPoint {
        switch mode {
        case .wideLandscape: CGPoint(x: size.width * 0.695, y: size.height * 0.325)
        case .compactLandscape: CGPoint(x: size.width * 0.70, y: size.height * 0.28)
        case .tabletPortrait: CGPoint(x: size.width * 0.69, y: size.height * 0.285)
        case .phonePortrait: CGPoint(x: size.width * 0.70, y: size.height * 0.275)
        }
    }

    var sunDiameter: CGFloat {
        shortSide * 0.38
    }

    var waveWorldSize: CGSize {
        CGSize(width: shortSide * 3.0, height: shortSide * 0.52)
    }

    var waveWorldVerticalOffset: CGFloat {
        shortSide * 0.060
    }

    var waveWorldCenter: CGPoint {
        CGPoint(
            x: size.width * 0.5,
            y: size.height * 0.55 + waveWorldVerticalOffset
        )
    }

    var lotusPlacements: [SplashLotusPlacement] {
        switch mode {
        case .wideLandscape:
            [
                .init(id: .lotusLeft, center: .init(x: 0.39, y: 0.62), width: 0.29, style: .lavender),
                .init(id: .lotusCenter, center: .init(x: 0.59, y: 0.53), width: 0.17, style: .blue),
                .init(id: .lotusRight, center: .init(x: 0.76, y: 0.64), width: 0.20, style: .blue)
            ]
        case .compactLandscape:
            [
                .init(id: .lotusLeft, center: .init(x: 0.38, y: 0.56), width: 0.29, style: .lavender),
                .init(id: .lotusCenter, center: .init(x: 0.59, y: 0.49), width: 0.17, style: .blue),
                .init(id: .lotusRight, center: .init(x: 0.77, y: 0.59), width: 0.20, style: .blue)
            ]
        case .tabletPortrait:
            [
                .init(id: .lotusLeft, center: .init(x: 0.25, y: 0.61), width: 0.29, style: .lavender),
                .init(id: .lotusCenter, center: .init(x: 0.58, y: 0.53), width: 0.17, style: .blue),
                .init(id: .lotusRight, center: .init(x: 0.80, y: 0.64), width: 0.20, style: .blue)
            ]
        case .phonePortrait:
            [
                .init(id: .lotusLeft, center: .init(x: 0.22, y: 0.60), width: 0.29, style: .lavender),
                .init(id: .lotusCenter, center: .init(x: 0.58, y: 0.52), width: 0.17, style: .blue),
                .init(id: .lotusRight, center: .init(x: 0.82, y: 0.63), width: 0.20, style: .blue)
            ]
        }
    }

    var navigationFontSize: CGFloat {
        shortSide * (shortSide < 600 ? 0.072 : 0.052)
    }

    var navigationSpacing: CGFloat {
        shortSide * (shortSide < 600 ? 0.065 : 0.075)
    }

    var navigationBottom: CGFloat {
        max(safeAreaInsets.bottom + 14, size.height * (mode == .compactLandscape ? 0.015 : 0.035))
    }

    var navigationLeading: CGFloat {
        max(safeAreaInsets.leading + 24, size.width * (isPortrait ? 0.055 : 0.055))
    }

    var alignsNavigationToLeading: Bool {
        mode == .wideLandscape || mode == .compactLandscape
    }

    private var isPortrait: Bool {
        mode == .tabletPortrait || mode == .phonePortrait
    }
}

struct SplashSceneView: View {
    var presentation: SplashScenePresentation = .presented
    var selectedMenu: SplashMenuItem = .start
    var onSelectMenu: (SplashMenuItem) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let layout = SplashLayout(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)

            ZStack(alignment: .topLeading) {
                SplashCanvasBackground()
                    .accessibilityIdentifier(SplashSceneActorID.background.rawValue)

                SplashSunView(progress: presentation.sunProgress)
                    .frame(width: layout.sunDiameter, height: layout.sunDiameter)
                    .position(layout.sunCenter)
                    .accessibilityIdentifier(SplashSceneActorID.sun.rawValue)
                    .accessibilityHidden(true)

                SplashWaveField(
                    layout: layout,
                    progress: presentation.waveProgress,
                    motionPhase: presentation.waveMotionPhase
                )
                    .accessibilityHidden(true)

                ForEach(layout.lotusPlacements) { placement in
                    let lotusWidth = layout.shortSide * placement.width

                    SplashLotusView(
                        actorID: placement.id,
                        style: placement.style,
                        centerOpacity: presentation.lotusCenterOpacity,
                        leftFanProgress: presentation.lotusLeftFanProgress,
                        rightFanProgress: presentation.lotusRightFanProgress
                    )
                    .frame(
                        width: lotusWidth,
                        height: lotusWidth * 0.82
                    )
                    .position(
                        x: layout.size.width * placement.center.x,
                        y: layout.size.height * placement.center.y
                            + layout.waveWorldVerticalOffset
                    )
                    .accessibilityHidden(true)
                }

                Text("Planet\nFocus")
                    .font(PlanetFocusTypography.wordmark(size: layout.wordmarkFontSize))
                    .foregroundStyle(PlanetFocusPalette.typePaleBlue)
                    .lineSpacing(-layout.wordmarkFontSize * 0.36)
                    .fixedSize()
                    .offset(x: layout.wordmarkLeading, y: layout.wordmarkTop)
                    .opacity(presentation.wordmarkOpacity)
                    .accessibilityIdentifier(SplashSceneActorID.wordmark.rawValue)
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    SplashNavigationBar(
                        selectedItem: selectedMenu,
                        fontSize: layout.navigationFontSize,
                        spacing: layout.navigationSpacing,
                        action: onSelectMenu
                    )
                    .frame(maxWidth: .infinity, alignment: layout.alignsNavigationToLeading ? .leading : .center)
                    .padding(.leading, layout.alignsNavigationToLeading ? layout.navigationLeading : 0)
                    .padding(.trailing, layout.alignsNavigationToLeading ? 0 : layout.navigationLeading)
                    .padding(.bottom, layout.navigationBottom)
                    .opacity(presentation.navigationOpacity)
                    .accessibilityIdentifier(SplashSceneActorID.navigation.rawValue)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .opacity(presentation.sceneOpacity)
        }
        .background(PlanetFocusPalette.canvasInk.ignoresSafeArea())
    }
}

private struct SplashCanvasBackground: View {
    var body: some View {
        PlanetFocusPalette.canvasInk
            .overlay {
                Image("CanvasPaperTextureV3")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .accessibilityHidden(true)
            }
            .clipped()
    }
}

#if os(iOS)
private enum SplashScreenStage: Equatable {
    case opening
    case chooser
    case story(Story)
}

struct SplashScreenView: View {
    @Binding var selectedStory: Story
    @State private var selectedMenu: SplashMenuItem = .start
    @State private var stage: SplashScreenStage

    init(selectedStory: Binding<Story>) {
        _selectedStory = selectedStory
#if DEBUG
        let initialStage: SplashScreenStage = ProcessInfo.processInfo.arguments.contains(
            "--story-chooser-review"
        ) ? .chooser : .opening
#else
        let initialStage: SplashScreenStage = .opening
#endif
        _stage = State(initialValue: initialStage)
    }

    var body: some View {
        ZStack {
            // This canvas never leaves. Future splash-exit choreography removes
            // only the independently addressable foreground actors above it.
            SplashCanvasBackground()
                .ignoresSafeArea()

            switch stage {
            case .opening:
                SplashSceneView(selectedMenu: selectedMenu) { item in
                    guard item == .stories else { return }
                    selectedMenu = item
                    stage = .chooser
                }

            case .chooser:
                StoryChooserView(
                    onChoose: { story in
                        selectedStory = story
                        stage = .story(story)
                    },
                    onBack: {
                        selectedMenu = .start
                        stage = .opening
                    }
                )

            case .story(let story):
                StorySceneLaunchView(story: story) {
                    stage = .chooser
                }
            }
        }
        .background(PlanetFocusPalette.canvasInk.ignoresSafeArea())
    }
}
#endif

private struct SplashSunView: View {
    let progress: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(SplashSunMaterial.cutEdgeColor)
                .offset(
                    x: SplashSunMaterial.cutEdgeX,
                    y: SplashSunMaterial.cutEdgeY
                )

            Circle()
                .fill(PlanetFocusPalette.warmYellow)

            Image("SunPaperTexture")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
                .accessibilityHidden(true)

            Circle()
                .stroke(
                    Color.white.opacity(SplashSunMaterial.edgeHighlightOpacity),
                    lineWidth: SplashSunMaterial.edgeHighlightWidth
                )
        }
            .compositingGroup()
            .shadow(
                color: Color.black.opacity(SplashSunMaterial.contactShadowOpacity),
                radius: SplashSunMaterial.contactShadowRadius,
                x: SplashSunMaterial.contactShadowX,
                y: SplashSunMaterial.contactShadowY
            )
            .shadow(
                color: Color.black.opacity(SplashSunMaterial.castShadowOpacity),
                radius: SplashSunMaterial.castShadowRadius,
                x: SplashSunMaterial.castShadowX,
                y: SplashSunMaterial.castShadowY
            )
            .offset(y: (1 - progress) * 44)
            .opacity(progress)
    }
}

private enum SplashSunMaterial {
    static let cutEdgeColor = Color(red: 214 / 255, green: 134 / 255, blue: 40 / 255)
    static let cutEdgeX: CGFloat = 1.5
    static let cutEdgeY: CGFloat = 2.5

    static let edgeHighlightOpacity = 0.10
    static let edgeHighlightWidth: CGFloat = 0.8

    static let contactShadowOpacity = 0.62
    static let contactShadowRadius: CGFloat = 2.4
    static let contactShadowX: CGFloat = 0
    static let contactShadowY: CGFloat = 1.2

    static let castShadowOpacity = 0.52
    static let castShadowRadius: CGFloat = 7
    static let castShadowX: CGFloat = 6
    static let castShadowY: CGFloat = 10
}

enum SplashWaveEntryEdge: CGFloat {
    case leading = -1
    case trailing = 1
}

struct SplashWaveRibbon: Identifiable {
    let id: SplashSceneActorID
    let color: Color
    let top: [CGPoint]
    let bottom: [CGPoint]
    let entryEdge: SplashWaveEntryEdge
}

/// One low-frequency component in a deterministic ribbon field. Frequencies are
/// expressed in cycles across the complete extra-wide world rather than the
/// current device crop, so rotation never changes the underlying geometry.
struct SplashWaveHarmonic {
    let amplitude: CGFloat
    let cycles: CGFloat
    let phase: CGFloat

    func value(
        at x: CGFloat,
        motionPhase: CGFloat = 0,
        spatialScale: CGFloat = 1
    ) -> CGFloat {
        amplitude * sin(2 * .pi * (cycles * spatialScale * x + phase + motionPhase))
    }
}

struct SplashWaveFunction {
    let base: CGFloat
    let drift: CGFloat
    let harmonics: [SplashWaveHarmonic]

    init(
        base: CGFloat,
        drift: CGFloat = 0,
        harmonics: [SplashWaveHarmonic]
    ) {
        self.base = base
        self.drift = drift
        self.harmonics = harmonics
    }

    func value(
        at x: CGFloat,
        motionPhase: CGFloat = 0,
        spatialScale: CGFloat = 1
    ) -> CGFloat {
        base + drift * (x - 0.5) + harmonics.reduce(0) {
            $0 + $1.value(
                at: x,
                motionPhase: motionPhase,
                spatialScale: spatialScale
            )
        }
    }
}

struct SplashWaveFormula {
    let id: SplashSceneActorID
    let color: Color
    let centerline: SplashWaveFunction
    let thickness: SplashWaveFunction
    let entryEdge: SplashWaveEntryEdge
    let motionRate: CGFloat
}

/// Generates the complete wave field from continuous low-frequency functions.
/// Every ribbon owns an independently phased analytic centerline and thickness
/// field. A hidden analytic coverage sheet closes the outer silhouette; it does
/// not pin, partition, or reshape the visible ribbons. This lets the paper strips
/// cross and occlude one another while remaining suitable for phase animation.
enum SplashWaveGenerator {
    static let sampleCount = 384
    static let ribbonFrequencyScale: CGFloat = 1
    static let centerAmplitudeScale: CGFloat = 1
    static let thicknessAmplitudeScale: CGFloat = 1
    static let maximumRibbonSpanShare: CGFloat = 0.38

    static let formulas: [SplashWaveFormula] = [
        .init(
            id: .waveRearPeriwinkle,
            color: PlanetFocusPalette.wavePeriwinkle,
            centerline: .init(base: 0.241, drift: -0.689, harmonics: [
                .init(amplitude: 0.149, cycles: 2.784, phase: 0.791),
                .init(amplitude: 0.174, cycles: 3.925, phase: 0.994)
            ]),
            thickness: .init(base: 0.252, harmonics: [
                .init(amplitude: 0.005, cycles: 3.545, phase: 0.988),
                .init(amplitude: 0.063, cycles: 4.497, phase: 0.835)
            ]),
            entryEdge: .trailing,
            motionRate: 0.16
        ),
        .init(
            id: .waveRearDeep,
            color: PlanetFocusPalette.waveDeep,
            centerline: .init(base: 0.350, harmonics: [
                .init(amplitude: 0.105, cycles: 2.200, phase: 0.980),
                .init(amplitude: 0.025, cycles: 4.100, phase: 0.983)
            ]),
            thickness: .init(base: 0.200, harmonics: [
                .init(amplitude: 0.050, cycles: 2.000, phase: 0.267),
                .init(amplitude: 0.035, cycles: 3.700, phase: 0.376)
            ]),
            entryEdge: .leading,
            motionRate: -0.11
        ),
        .init(
            id: .waveWarmReveal,
            color: PlanetFocusPalette.warmYellow,
            centerline: .init(base: 0.419, harmonics: [
                .init(amplitude: 0.143, cycles: 2.600, phase: 0.720),
                .init(amplitude: 0.035, cycles: 4.400, phase: 0.887)
            ]),
            thickness: .init(base: 0.045, harmonics: [
                .init(amplitude: 0.020, cycles: 2.500, phase: 0.545),
                .init(amplitude: 0.010, cycles: 4.000, phase: 0.949)
            ]),
            entryEdge: .leading,
            motionRate: 0.08
        ),
        .init(
            id: .waveMiddleLavender,
            color: PlanetFocusPalette.waveLavender,
            centerline: .init(base: 0.379, drift: 0.007, harmonics: [
                .init(amplitude: 0.037, cycles: 1.381, phase: 0.228),
                .init(amplitude: 0.044, cycles: 3.384, phase: 0.633),
                .init(amplitude: 0.090, cycles: 4.979, phase: 0.358)
            ]),
            thickness: .init(base: 0.225, harmonics: [
                .init(amplitude: 0.000, cycles: 1.387, phase: 0.515),
                .init(amplitude: 0.062, cycles: 3.322, phase: 0.253)
            ]),
            entryEdge: .trailing,
            motionRate: -0.09
        ),
        .init(
            id: .waveMiddleBlue,
            color: PlanetFocusPalette.waveMid,
            centerline: .init(base: 0.550, harmonics: [
                .init(amplitude: 0.180, cycles: 2.400, phase: 0.746),
                .init(amplitude: 0.075, cycles: 3.800, phase: 0.243)
            ]),
            thickness: .init(base: 0.200, harmonics: [
                .init(amplitude: 0.050, cycles: 2.300, phase: 0.668),
                .init(amplitude: 0.025, cycles: 4.100, phase: 0.671)
            ]),
            entryEdge: .leading,
            motionRate: 0.12
        ),
        .init(
            id: .waveFrontDeep,
            color: PlanetFocusPalette.waveDeep,
            centerline: .init(base: 0.682, harmonics: [
                .init(amplitude: 0.110, cycles: 1.900, phase: 0.101),
                .init(amplitude: 0.035, cycles: 4.200, phase: 0.603)
            ]),
            thickness: .init(base: 0.180, harmonics: [
                .init(amplitude: 0.040, cycles: 2.000, phase: 0.593),
                .init(amplitude: 0.030, cycles: 4.000, phase: 0.514)
            ]),
            entryEdge: .trailing,
            motionRate: -0.14
        ),
        .init(
            id: .waveFrontPeriwinkle,
            color: PlanetFocusPalette.wavePeriwinkle,
            centerline: .init(base: 0.720, harmonics: [
                .init(amplitude: 0.145, cycles: 2.700, phase: 0.860),
                .init(amplitude: 0.065, cycles: 4.400, phase: 0.189)
            ]),
            thickness: .init(base: 0.200, harmonics: [
                .init(amplitude: 0.040, cycles: 2.500, phase: 0.332),
                .init(amplitude: 0.020, cycles: 4.500, phase: 0.641)
            ]),
            entryEdge: .leading,
            motionRate: 0.10
        ),
        .init(
            id: .waveFrontLavender,
            color: PlanetFocusPalette.waveLavender,
            centerline: .init(base: 0.800, harmonics: [
                .init(amplitude: 0.160, cycles: 2.100, phase: 0.900),
                .init(amplitude: 0.060, cycles: 3.500, phase: 0.242)
            ]),
            thickness: .init(base: 0.160, harmonics: [
                .init(amplitude: 0.030, cycles: 2.200, phase: 0.514),
                .init(amplitude: 0.025, cycles: 3.800, phase: 0.116)
            ]),
            entryEdge: .trailing,
            motionRate: -0.07
        )
    ]

    static func ribbons(motionPhase: CGFloat = 0) -> [SplashWaveRibbon] {
        var topSamples = Array(repeating: [CGPoint](), count: formulas.count)
        var bottomSamples = Array(repeating: [CGPoint](), count: formulas.count)
        for index in 0...sampleCount {
            let x = CGFloat(index) / CGFloat(sampleCount)
            let edges = rawEdges(at: x, motionPhase: motionPhase)
            for formulaIndex in formulas.indices {
                topSamples[formulaIndex].append(
                    CGPoint(x: x, y: edges[formulaIndex].top)
                )
                bottomSamples[formulaIndex].append(
                    CGPoint(x: x, y: edges[formulaIndex].bottom)
                )
            }
        }

        return formulas.indices.map { index in
            let formula = formulas[index]
            return SplashWaveRibbon(
                id: formula.id,
                color: formula.color,
                top: topSamples[index],
                bottom: bottomSamples[index],
                entryEdge: formula.entryEdge
            )
        }
    }

    static func coverageRibbon() -> SplashWaveRibbon {
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        for index in 0...sampleCount {
            let x = CGFloat(index) / CGFloat(sampleCount)
            let edges = envelope(at: x)
            top.append(CGPoint(x: x, y: edges.top))
            bottom.append(CGPoint(x: x, y: edges.bottom))
        }
        return SplashWaveRibbon(
            id: .waveRearDeep,
            color: PlanetFocusPalette.waveDeep,
            top: top,
            bottom: bottom,
            entryEdge: .leading
        )
    }

    private static func rawEdges(
        at x: CGFloat,
        motionPhase: CGFloat
    ) -> [(top: CGFloat, bottom: CGFloat)] {
        let guardEdges = envelope(at: x)
        let availableSpan = max(guardEdges.bottom - guardEdges.top, 0.10)
        return formulas.map { formula in
            let phase = motionPhase * formula.motionRate
            let rawCenter = formula.centerline.value(
                at: x,
                motionPhase: phase,
                spatialScale: ribbonFrequencyScale
            )
            let center = formula.centerline.base
                + centerAmplitudeScale * (rawCenter - formula.centerline.base)
            let thicknessField = formula.thickness.value(
                at: x,
                motionPhase: phase,
                spatialScale: ribbonFrequencyScale
            )
            let rawThickness = formula.thickness.base
                + thicknessAmplitudeScale
                * (thicknessField - formula.thickness.base)
            let positiveThickness = 0.010
                + softplus(rawThickness - 0.010, sharpness: 32)
            let thickness = min(
                positiveThickness,
                maximumRibbonSpanShare * availableSpan
            )
            let halfThickness = thickness / 2
            let boundedCenter = smoothClamp(
                center,
                lower: guardEdges.top + halfThickness,
                upper: guardEdges.bottom - halfThickness
            )
            return (
                top: max(boundedCenter - halfThickness, guardEdges.top),
                bottom: min(boundedCenter + halfThickness, guardEdges.bottom)
            )
        }
    }

    private static func envelope(at x: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let center = 0.4424
            + 0.0151 * cos(2 * .pi * x)
            + 0.0407 * sin(2 * .pi * x)
            - 0.0288 * cos(4 * .pi * x)
            + 0.0259 * sin(4 * .pi * x)
            - 0.0184 * cos(6 * .pi * x)
            - 0.0190 * sin(6 * .pi * x)
            + 0.0463 * cos(8 * .pi * x)
            - 0.0384 * sin(8 * .pi * x)
            + 0.0525 * cos(10 * .pi * x)
            - 0.0861 * sin(10 * .pi * x)
            + 0.0122 * cos(12 * .pi * x)
            - 0.0508 * sin(12 * .pi * x)
        let centered = x - 0.5
        let span = 0.7356
            - 0.0231 * cos(2 * .pi * x)
            + 0.0326 * cos(4 * .pi * x)
            + 0.0284 * cos(6 * .pi * x)
            - 0.0762 * cos(8 * .pi * x)
            - 0.0570 * cos(10 * .pi * x)
            - 0.0735 * cos(12 * .pi * x)
            - 0.0010 * centered * centered
        return (top: center - span / 2, bottom: center + span / 2)
    }

    private static func smoothClamp(
        _ value: CGFloat,
        lower: CGFloat,
        upper: CGFloat
    ) -> CGFloat {
        lower
            + softplus(value - lower, sharpness: 48)
            - softplus(value - upper, sharpness: 48)
    }

    private static func softplus(_ value: CGFloat, sharpness: CGFloat) -> CGFloat {
        let scaled = sharpness * value
        return (max(scaled, 0) + log1p(exp(-abs(scaled)))) / sharpness
    }
}

private struct SplashWaveField: View {
    let layout: SplashLayout
    let progress: CGFloat
    let motionPhase: CGFloat

    var body: some View {
        let worldSize = layout.waveWorldSize
        let ribbons = SplashWaveGenerator.ribbons(motionPhase: motionPhase)
        let coverage = SplashWaveGenerator.coverageRibbon()

        ZStack {
            SplashWaveRibbonShape(top: coverage.top, bottom: coverage.bottom)
                .fill(PlanetFocusPalette.waveDeep)
                .frame(width: worldSize.width, height: worldSize.height)
                .accessibilityIdentifier("waveCoverageBacking")

            ForEach(ribbons) { ribbon in
                let shape = SplashWaveRibbonShape(top: ribbon.top, bottom: ribbon.bottom)

                SplashWavePaperLayer(
                    shape: shape,
                    faceColor: ribbon.color,
                    cutEdgeColor: SplashWaveMaterial.cutEdgeColor(for: ribbon.id)
                )
                    .frame(width: worldSize.width, height: worldSize.height)
                    .offset(
                        x: (1 - progress) * ribbon.entryEdge.rawValue * worldSize.width
                    )
                    .accessibilityIdentifier(ribbon.id.rawValue)
            }
        }
        .frame(width: worldSize.width, height: worldSize.height)
        .position(layout.waveWorldCenter)
    }
}

private struct SplashWavePaperLayer: View {
    let shape: SplashWaveRibbonShape
    let faceColor: Color
    let cutEdgeColor: Color

    var body: some View {
        ZStack {
            shape
                .fill(cutEdgeColor)
                .offset(
                    x: SplashWaveMaterial.cutEdgeX,
                    y: SplashWaveMaterial.cutEdgeY
                )

            ZStack {
                shape.fill(faceColor)

                Image("WavePaperTexture")
                    .resizable(resizingMode: .tile)
                    .mask(shape)
                    .blendMode(.softLight)
                    .opacity(SplashWaveMaterial.textureOpacity)
                    .accessibilityHidden(true)

                shape.stroke(
                    Color.white.opacity(SplashWaveMaterial.edgeHighlightOpacity),
                    lineWidth: SplashWaveMaterial.edgeHighlightWidth
                )
            }
            .compositingGroup()
        }
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(SplashWaveMaterial.contactShadowOpacity),
            radius: SplashWaveMaterial.contactShadowRadius,
            x: SplashWaveMaterial.contactShadowX,
            y: SplashWaveMaterial.contactShadowY
        )
        .shadow(
            color: Color.black.opacity(SplashWaveMaterial.castShadowOpacity),
            radius: SplashWaveMaterial.castShadowRadius,
            x: SplashWaveMaterial.castShadowX,
            y: SplashWaveMaterial.castShadowY
        )
    }
}

private enum SplashWaveMaterial {
    static let cutEdgeX: CGFloat = 1.2
    static let cutEdgeY: CGFloat = 2.0

    static let textureOpacity = 0.68

    static let edgeHighlightOpacity = 0.14
    static let edgeHighlightWidth: CGFloat = 0.75

    static let contactShadowOpacity = 0.26
    static let contactShadowRadius: CGFloat = 1.6
    static let contactShadowX: CGFloat = 0
    static let contactShadowY: CGFloat = 1.4

    static let castShadowOpacity = 0.18
    static let castShadowRadius: CGFloat = 5.5
    static let castShadowX: CGFloat = 3.5
    static let castShadowY: CGFloat = 6.5

    static func cutEdgeColor(for id: SplashSceneActorID) -> Color {
        switch id {
        case .waveRearDeep, .waveFrontDeep:
            Color(red: 8 / 255, green: 40 / 255, blue: 108 / 255)
        case .waveMiddleBlue:
            Color(red: 32 / 255, green: 63 / 255, blue: 131 / 255)
        case .waveRearPeriwinkle, .waveFrontPeriwinkle:
            Color(red: 59 / 255, green: 81 / 255, blue: 139 / 255)
        case .waveMiddleLavender, .waveFrontLavender:
            Color(red: 102 / 255, green: 85 / 255, blue: 141 / 255)
        case .waveWarmReveal:
            Color(red: 214 / 255, green: 134 / 255, blue: 40 / 255)
        default:
            PlanetFocusPalette.canvasInk
        }
    }
}

private struct SplashWaveRibbonShape: Shape {
    let top: [CGPoint]
    let bottom: [CGPoint]

    func path(in rect: CGRect) -> Path {
        let scaledTop = top.map { scale($0, in: rect) }
        let scaledBottom = bottom.map { scale($0, in: rect) }
        guard let firstTop = scaledTop.first else {
            return Path()
        }

        var path = Path()
        path.move(to: firstTop)
        for point in scaledTop.dropFirst() {
            path.addLine(to: point)
        }
        for point in scaledBottom.reversed() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func scale(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
    }
}

enum SplashLotusStyle {
    case blue
    case lavender

    fileprivate func color(for petal: SplashLotusPetalID) -> Color {
        return switch (self, petal) {
        case (_, .heart): PlanetFocusPalette.warmYellow
        case (.blue, .center), (.blue, .innerLeft), (.blue, .innerRight): PlanetFocusPalette.waveMid
        case (.blue, .baseLeft), (.blue, .baseRight): PlanetFocusPalette.waveMid
        case (.blue, _): PlanetFocusPalette.waveDeep
        case (.lavender, _): PlanetFocusPalette.waveLavender
        }
    }
}

struct SplashLotusPlacement: Identifiable {
    let id: SplashSceneActorID
    let center: CGPoint
    let width: CGFloat
    let style: SplashLotusStyle
}

private struct SplashLotusPetal: Identifiable {
    let id: SplashLotusPetalID
    let family: SplashLotusPetalFamily
    let side: SplashLotusPetalSide
    let width: CGFloat
    let height: CGFloat
    let horizontalOffset: CGFloat
    let bottomOffset: CGFloat
    let restingRotation: Double
    let depth: Double

    var isCenter: Bool { id == .center || id == .heart }
}

private enum SplashLotusPetalFamily {
    case center
    case inner
    case outer
    case bowl
    case heart
}

private enum SplashLotusPetalSide {
    case left
    case center
    case right
}

private struct SplashLotusView: View {
    let actorID: SplashSceneActorID
    let style: SplashLotusStyle
    let centerOpacity: Double
    let leftFanProgress: CGFloat
    let rightFanProgress: CGFloat

    private var petals: [SplashLotusPetal] {
        [
            .init(id: .baseLeft, family: .bowl, side: .left, width: 0.23, height: 0.36, horizontalOffset: -0.006, bottomOffset: 0.022, restingRotation: -79, depth: 0),
            .init(id: .baseRight, family: .bowl, side: .right, width: 0.22, height: 0.35, horizontalOffset: 0.008, bottomOffset: 0.024, restingRotation: 78, depth: 0),
            .init(id: .outerLeft, family: .outer, side: .left, width: 0.46, height: 0.52, horizontalOffset: -0.015, bottomOffset: 0.010, restingRotation: -64, depth: 1),
            .init(id: .outerRight, family: .outer, side: .right, width: 0.44, height: 0.51, horizontalOffset: 0.017, bottomOffset: 0.012, restingRotation: 63, depth: 1),
            .init(id: .innerLeft, family: .inner, side: .left, width: 0.41, height: 0.65, horizontalOffset: -0.006, bottomOffset: -0.006, restingRotation: -35, depth: 2),
            .init(id: .innerRight, family: .inner, side: .right, width: 0.39, height: 0.63, horizontalOffset: 0.008, bottomOffset: -0.002, restingRotation: 34, depth: 2),
            .init(id: .center, family: .center, side: .center, width: 0.41, height: 0.75, horizontalOffset: 0, bottomOffset: -0.014, restingRotation: 0, depth: 3),
            .init(id: .heart, family: .heart, side: .center, width: 0.176, height: 0.22, horizontalOffset: 0.002, bottomOffset: 0.014, restingRotation: 0, depth: 4)
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            let base = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.93)

            ZStack(alignment: .topLeading) {
                ForEach(petals) { petal in
                    let petalWidth = proxy.size.width * petal.width
                    let petalHeight = proxy.size.width * petal.height
                    let activeProgress = progress(for: petal)

                    SplashLotusPetalShape(family: petal.family)
                        .fill(style.color(for: petal.id))
                        .overlay(
                            SplashLotusPetalShape(family: petal.family)
                                .stroke(PlanetFocusPalette.typePaleBlue.opacity(0.20), lineWidth: 0.6)
                        )
                        .shadow(
                            color: PlanetFocusPalette.canvasInk.opacity(0.52),
                            radius: max(1.4, proxy.size.width * 0.012),
                            y: max(1.7, proxy.size.width * 0.015)
                        )
                        .frame(width: petalWidth, height: petalHeight)
                        .rotationEffect(
                            .degrees(petal.restingRotation * Double(activeProgress)),
                            anchor: .bottom
                        )
                        .position(
                            x: base.x + proxy.size.width * petal.horizontalOffset * activeProgress,
                            y: base.y
                                + proxy.size.height * petal.bottomOffset * activeProgress
                                - petalHeight / 2
                        )
                        .opacity(petal.isCenter ? centerOpacity : Double(activeProgress))
                        .zIndex(petal.depth)
                        .accessibilityIdentifier("\(actorID.rawValue)-\(petal.id.rawValue)")
                }
            }
        }
        .accessibilityIdentifier(actorID.rawValue)
    }

    private func progress(for petal: SplashLotusPetal) -> CGFloat {
        switch petal.side {
        case .left: leftFanProgress
        case .center: 1
        case .right: rightFanProgress
        }
    }
}

private struct SplashLotusPetalShape: Shape {
    let family: SplashLotusPetalFamily

    func path(in rect: CGRect) -> Path {
        let contour = contour(for: family)
        var path = Path()
        path.move(to: point(contour.base, in: rect))
        path.addCurve(
            to: point(contour.tip, in: rect),
            control1: point(contour.leftBaseControl, in: rect),
            control2: point(contour.leftTipControl, in: rect)
        )
        path.addCurve(
            to: point(contour.base, in: rect),
            control1: point(contour.rightTipControl, in: rect),
            control2: point(contour.rightBaseControl, in: rect)
        )
        path.closeSubpath()
        return path
    }

    private func point(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
    }

    private func contour(for family: SplashLotusPetalFamily) -> SplashLotusPetalContour {
        switch family {
        case .center:
            .init(base: .init(x: 0.50, y: 1), tip: .init(x: 0.52, y: 0), leftBaseControl: .init(x: 0.08, y: 0.72), leftTipControl: .init(x: 0.16, y: 0.22), rightTipControl: .init(x: 0.84, y: 0.17), rightBaseControl: .init(x: 0.91, y: 0.72))
        case .inner:
            .init(base: .init(x: 0.50, y: 1), tip: .init(x: 0.48, y: 0.01), leftBaseControl: .init(x: 0.04, y: 0.70), leftTipControl: .init(x: 0.12, y: 0.24), rightTipControl: .init(x: 0.86, y: 0.17), rightBaseControl: .init(x: 0.94, y: 0.68))
        case .outer:
            .init(base: .init(x: 0.50, y: 1), tip: .init(x: 0.46, y: 0.03), leftBaseControl: .init(x: 0.02, y: 0.72), leftTipControl: .init(x: 0.08, y: 0.30), rightTipControl: .init(x: 0.90, y: 0.18), rightBaseControl: .init(x: 0.98, y: 0.66))
        case .bowl:
            .init(base: .init(x: 0.50, y: 1), tip: .init(x: 0.43, y: 0.05), leftBaseControl: .init(x: 0.02, y: 0.76), leftTipControl: .init(x: 0.05, y: 0.33), rightTipControl: .init(x: 0.92, y: 0.18), rightBaseControl: .init(x: 0.97, y: 0.62))
        case .heart:
            .init(base: .init(x: 0.50, y: 1), tip: .init(x: 0.50, y: 0), leftBaseControl: .init(x: 0.03, y: 0.68), leftTipControl: .init(x: 0.15, y: 0.22), rightTipControl: .init(x: 0.85, y: 0.22), rightBaseControl: .init(x: 0.97, y: 0.68))
        }
    }
}

private struct SplashLotusPetalContour {
    let base: CGPoint
    let tip: CGPoint
    let leftBaseControl: CGPoint
    let leftTipControl: CGPoint
    let rightTipControl: CGPoint
    let rightBaseControl: CGPoint
}

private struct SplashNavigationBar: View {
    let selectedItem: SplashMenuItem
    let fontSize: CGFloat
    let spacing: CGFloat
    let action: (SplashMenuItem) -> Void
    @State private var hoveredItem: SplashMenuItem?
    @Namespace private var indicatorNamespace

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(SplashMenuItem.allCases) { item in
                let activeItem = hoveredItem ?? selectedItem

                Button {
                    action(item)
                } label: {
                    VStack(spacing: max(4, fontSize * 0.12)) {
                        Text(item.rawValue)
                            .font(PlanetFocusTypography.navigation(size: fontSize))
                            .foregroundStyle(
                                item == activeItem
                                    ? PlanetFocusPalette.warmYellow
                                    : PlanetFocusPalette.typePaleBlue
                            )
                            .lineLimit(1)

                        ZStack {
                            if item == activeItem {
                                Circle()
                                    .fill(PlanetFocusPalette.warmYellow)
                                    .matchedGeometryEffect(
                                        id: SplashNavigationMotion.dotID,
                                        in: indicatorNamespace
                                    )
                            }
                        }
                        .frame(width: max(7, fontSize * 0.22), height: max(7, fontSize * 0.22))

                        ZStack {
                            if item == activeItem {
                                Capsule()
                                    .fill(PlanetFocusPalette.warmYellow)
                                    .matchedGeometryEffect(
                                        id: SplashNavigationMotion.underlineID,
                                        in: indicatorNamespace
                                    )
                            }
                        }
                        .frame(width: max(48, fontSize * 2.60), height: max(2, fontSize * 0.055))
                    }
                    .frame(minWidth: max(54, fontSize * 2.05), minHeight: 44, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    withAnimation(SplashNavigationMotion.hoverTransition) {
                        if isHovering {
                            hoveredItem = item
                        } else if hoveredItem == item {
                            hoveredItem = nil
                        }
                    }
                }
                .accessibilityLabel(item.rawValue)
                .accessibilityValue(item == selectedItem ? "Selected" : "Not selected")
                .accessibilityHint(item == .stories ? "Open stories" : "Not available yet")
                .accessibilityIdentifier("splash-menu-\(item.rawValue.lowercased())")
            }
        }
    }
}

private enum SplashNavigationMotion {
    static let hoverFadeDuration = 0.14
    static let hoverTransition = Animation.easeInOut(duration: hoverFadeDuration)
    static let dotID = "splash-navigation-dot"
    static let underlineID = "splash-navigation-underline"
}
