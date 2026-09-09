import SwiftUI

/// The chooser is deliberately transparent: the splash owns the continuous blue
/// paper canvas beneath both states, so later exit choreography can remove the
/// wordmark, sun, waves, lotuses, and navigation without revealing a new surface.
struct StoryChooserView: View {
    let onChoose: (Story) -> Void
    let onBack: () -> Void

    @State private var hoveredStory: Story?

    var body: some View {
        GeometryReader { proxy in
            let layout = StoryChooserLayout(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)

            ZStack {
                Button(action: onBack) {
                    Text("Back")
                        .font(PlanetFocusTypography.navigation(size: layout.backFontSize))
                        .foregroundStyle(PlanetFocusPalette.typePaleBlue)
                        .frame(minWidth: 64, minHeight: 44)
                }
                .buttonStyle(.plain)
                .position(layout.backCenter)
                .accessibilityHint("Return to the opening scene")

                VStack(spacing: layout.titleToChoicesSpacing) {
                    Text("Choose a story")
                        .font(PlanetFocusTypography.wordmark(size: layout.titleFontSize))
                        .foregroundStyle(PlanetFocusPalette.typePaleBlue)
                        .accessibilityAddTraits(.isHeader)

                    HStack(alignment: .top, spacing: layout.choiceSpacing) {
                        ForEach(Story.allCases) { story in
                            Button {
                                onChoose(story)
                            } label: {
                                StoryChoiceTile(
                                    story: story,
                                    side: layout.previewSide,
                                    isHovered: hoveredStory == story
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovering in
                                withAnimation(StoryChooserMotion.hoverTransition) {
                                    if isHovering {
                                        hoveredStory = story
                                    } else if hoveredStory == story {
                                        hoveredStory = nil
                                    }
                                }
                            }
                            .accessibilityLabel(story.title)
                            .accessibilityHint("Open this story")
                            .accessibilityIdentifier("story-choice-\(story.rawValue)")
                        }
                    }
                }
                .position(layout.chooserCenter)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct StoryChoiceTile: View {
    let story: Story
    let side: CGFloat
    let isHovered: Bool

    var body: some View {
        VStack(spacing: max(10, side * 0.065)) {
            StorySceneThumbnail(story: story)
                .frame(width: side, height: side)
                .clipShape(Rectangle())
                .overlay {
                    Rectangle()
                        .stroke(
                            isHovered
                                ? PlanetFocusPalette.warmYellow
                                : PlanetFocusPalette.typePaleBlue.opacity(0.34),
                            lineWidth: isHovered ? 2 : 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(0.48),
                    radius: max(5, side * 0.035),
                    x: 0,
                    y: max(4, side * 0.028)
                )

            Text(story.title)
                .font(PlanetFocusTypography.navigation(size: max(26, side * 0.15)))
                .foregroundStyle(
                    isHovered
                        ? PlanetFocusPalette.warmYellow
                        : PlanetFocusPalette.typePaleBlue
                )
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .animation(StoryChooserMotion.hoverTransition, value: isHovered)
    }
}

private struct StorySceneThumbnail: View {
    let story: Story

    var body: some View {
        StorySceneCatalog.scene(for: story, context: renderContext)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var renderContext: StorySceneRenderContext {
        let session = FocusSession(
            story: story,
            duration: .twentyFiveMinutes,
            startedAt: StoryChooserPreview.startDate,
            randomSeed: story == .autumnTree ? 230_003 : 94
        )
        let player = StoryPlayer(session: session)
        let referenceDate = StoryChooserPreview.referenceDate(for: story)

        return StorySceneRenderContext(
            progress: session.progress(at: referenceDate),
            elapsedTime: session.elapsedTime(at: referenceDate),
            referenceDate: referenceDate,
            performance: player.performance(at: referenceDate, reduceMotion: true),
            reduceMotion: true,
            showsFocusUI: false
        )
    }
}

struct StorySceneLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let story: Story
    let onBack: () -> Void
    let onStart: (FocusDuration) -> Void
    let onPauseResume: () -> Void
    @State private var duration = FocusDuration.fiveMinutes

    private let session: PerformanceSession?
    private let player: StoryPlayer
    private let autumnRecord: AutumnBranchRecord

    init(
        story: Story,
        session: PerformanceSession? = nil,
        autumnRecord: AutumnBranchRecord = .init(),
        onStart: @escaping (FocusDuration) -> Void,
        onPauseResume: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.story = story
        self.onBack = onBack
        self.onStart = onStart
        self.onPauseResume = onPauseResume

        let resolvedSession = session?.focusSession(for: story) ?? FocusSession(
            story: story,
            duration: .twentyFiveMinutes,
            startedAt: .now
        )
        self.session = session
        self.autumnRecord = autumnRecord
        self.player = StoryPlayer(session: resolvedSession)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
            if story == .autumnTree {
                AutumnBranchSceneView(session: session, record: autumnRecord, reduceMotion: reduceMotion)
            } else {
            StorySceneCatalog.scene(
                for: story,
                context: StorySceneRenderContext(
                    progress: session?.progress(at: context.date) ?? 0,
                    elapsedTime: session?.elapsedTime(at: context.date) ?? 0,
                    referenceDate: context.date,
                    performance: player.performance(atElapsedTime: session?.elapsedTime(at: context.date) ?? 0, reduceMotion: reduceMotion),
                    reduceMotion: reduceMotion,
                    showsFocusUI: false
                )
            )
            }
            }
            .overlay(alignment: .topLeading) {
                Button(action: onBack) {
                    Text("Stories")
                        .font(PlanetFocusTypography.navigation(size: 30))
                        .foregroundStyle(PlanetFocusPalette.typePaleBlue)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(PlanetFocusPalette.canvasInk.opacity(0.76))
                }
                .buttonStyle(.plain)
                .padding(.top, 46)
                .padding(.leading, 10)
                .accessibilityHint("Return to the story chooser")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            HStack {
                if session == nil {
                    Picker("Duration", selection: $duration) {
                        ForEach(FocusDuration.available) { value in Text(value.title).tag(value) }
                    }.tint(PlanetFocusPalette.typePaleBlue)
                }
                Button(session == nil ? "Begin" : session!.progress(at: .now) >= 1 ? "Again" : session!.isPaused ? "Resume" : "Pause") {
                    if session == nil || session!.progress(at: .now) >= 1 { onStart(duration) }
                    else { onPauseResume() }
                }
                .accessibilityIdentifier("autumnPlayback")
                .buttonStyle(.borderedProminent)
                .tint(PlanetFocusPalette.canvasInk)
            }.padding(24)
        }
        .ignoresSafeArea()
    }
}

struct StoryChooserLayout {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    var shortSide: CGFloat { min(size.width, size.height) }

    var previewSide: CGFloat {
        min(max(shortSide * 0.31, 126), 244)
    }

    var choiceSpacing: CGFloat {
        min(max(size.width * 0.045, 18), 54)
    }

    var titleFontSize: CGFloat {
        min(max(shortSide * 0.09, 40), 70)
    }

    var backFontSize: CGFloat {
        min(max(shortSide * 0.05, 25), 34)
    }

    var titleToChoicesSpacing: CGFloat {
        min(max(shortSide * 0.07, 24), 52)
    }

    var chooserCenter: CGPoint {
        CGPoint(x: size.width * 0.5, y: size.height * 0.51)
    }

    var backCenter: CGPoint {
        CGPoint(
            x: max(safeAreaInsets.leading + 44, size.width * 0.06),
            y: max(safeAreaInsets.top + 30, size.height * 0.06)
        )
    }
}

private enum StoryChooserPreview {
    static let startDate = Date(timeIntervalSinceReferenceDate: 0)

    static func referenceDate(for story: Story) -> Date {
        switch story {
        case .autumnTree:
            Date(timeIntervalSinceReferenceDate: 930)
        case .contemporaryLotus:
            Date(timeIntervalSinceReferenceDate: 750)
        }
    }
}

private enum StoryChooserMotion {
    static let hoverTransition = Animation.easeInOut(duration: 0.14)
}
