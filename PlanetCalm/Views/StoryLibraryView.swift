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
            performance: player.performance(at: referenceDate, reduceMotion: true),
            reduceMotion: true,
            duration: session.duration.timeInterval,
            randomSeed: session.randomSeed,
            storyPlan: player.plan
        )
    }
}

@MainActor
private final class StoryPlayerCache {
    private struct Key: Equatable {
        let story: Story
        let duration: FocusDuration
        let seed: UInt64
        let autumnRecord: AutumnBranchRecord
    }

    private var key: Key?
    private var player: StoryPlayer?

    func player(for session: FocusSession, autumnRecord: AutumnBranchRecord) -> StoryPlayer {
        let key = Key(story: session.story, duration: session.duration,
                      seed: session.randomSeed, autumnRecord: autumnRecord)
        if self.key == key, let player {
            return player
        }
        let module: (any StoryModule)? = session.story == .autumnTree
            ? AutumnTreeStoryModule(record: autumnRecord) : nil
        let player = StoryPlayer(session: session, module: module)
        self.key = key
        self.player = player
        return player
    }
}

struct StorySceneLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var preferences

    let story: Story
    let onBack: () -> Void
    @State private var duration = FocusDuration.fiveMinutes
    @State private var confirmsExit = false
    @Binding private var volume: Double
    @Binding private var isMuted: Bool
    @Binding private var showsSettings: Bool
    let audioAvailable: Bool

    private let debugSession: PerformanceSession?
    let runtime: SessionRuntime?
    let durableOutcome: SessionAttempt.Outcome?
    let persistenceError: String?
    private let autumnRecord: AutumnBranchRecord
    let onStart: (FocusDuration) async throws -> Void
    let onComplete: () async throws -> Void
    let onCancel: () async throws -> Void
    @State private var isStarting = false
    @State private var isFinishing = false
    @State private var lifecycleError: String?
    @State private var storyPlayerCache = StoryPlayerCache()

    init(
        story: Story,
        session: PerformanceSession? = nil,
        runtime: SessionRuntime? = nil,
        durableOutcome: SessionAttempt.Outcome? = nil,
        persistenceError: String? = nil,
        autumnRecord: AutumnBranchRecord = .init(),
        volume: Binding<Double>,
        isMuted: Binding<Bool>,
        showsSettings: Binding<Bool>,
        audioAvailable: Bool = false,
        onStart: @escaping (FocusDuration) async throws -> Void,
        onComplete: @escaping () async throws -> Void,
        onCancel: @escaping () async throws -> Void,
        onBack: @escaping () -> Void
    ) {
        self.story = story
        self.onBack = onBack
        _volume = volume
        _isMuted = isMuted
        _showsSettings = showsSettings
        self.audioAvailable = audioAvailable
        self.debugSession = session
        self.runtime = runtime
        self.durableOutcome = durableOutcome
        self.persistenceError = persistenceError
        self.autumnRecord = autumnRecord
        self.onStart = onStart
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let headerOffset =
                landscape ? -geometry.size.width * SessionPaperStyle.landscapeHeaderShift : 0
            let headerTop = landscape ? max(80, geometry.size.height * 0.2) : 56
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let session = playbackSession
                let transport = transportState(for: session, at: context.date)
                let focusSession = focusSession(for: session)
                let player = storyPlayerCache.player(for: focusSession, autumnRecord: autumnRecord)
                ZStack(alignment: .top) {
                    Group {
                        if story == .autumnTree {
                            AutumnBranchSceneView(
                                session: session,
                                runtime: runtime,
                                record: autumnRecord,
                                reduceMotion: reduceMotion,
                                storyPlan: player.plan
                            )
                        } else {
                            StorySceneCatalog.scene(
                                for: story,
                                context: StorySceneRenderContext(
                                    progress: transport?.progress ?? 0,
                                    elapsedTime: transport?.elapsedTime ?? 0,
                                    performance: player.performance(
                                        atElapsedTime: transport?.elapsedTime ?? 0,
                                        reduceMotion: reduceMotion),
                                    reduceMotion: reduceMotion,
                                    duration: session?.duration.timeInterval
                                        ?? duration.timeInterval,
                                    randomSeed: session?.randomSeed ?? 42,
                                    storyPlan: player.plan
                                )
                            )
                        }
                    }
                    .ignoresSafeArea()

                    // Animate only the interface, never the scene or its transport.
                    ZStack(alignment: .top) {
                        let reachedEnd = transport?.isComplete == true
                        let savedTerminal = durableOutcome != nil
                        let complete = durableOutcome == .completed || (runtime == nil && reachedEnd)
                        if session == nil {
                            let spacious = geometry.size.width >= 600
                            beginButton
                                .padding(.top, headerTop)
                                .offset(x: headerOffset)
                                .transition(.opacity)
                            Button("Back", action: onBack)
                                .font(PlanetFocusTypography.interface(.title3))
                                .foregroundStyle(SessionPaperStyle.ink)
                                .frame(minWidth: 60, minHeight: 44)
                                .buttonStyle(.plain)
                                .disabled(isStarting)
                                .accessibilityIdentifier("sessionBack")
                                .padding(.leading, 12).padding(.top, spacious ? 52 : 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        } else {
                            Button {
                                if savedTerminal { onBack() }
                                else if reachedEnd { completeSession() }
                                else { confirmsExit = true }
                            } label: {
                                VStack(spacing: -14) {
                                    Text(sessionStatusTitle(
                                        complete: complete,
                                        durableOutcome: durableOutcome,
                                        reachedEnd: reachedEnd,
                                        remaining: transport?.remainingTime
                                    ))
                                        .font(PlanetFocusTypography.navigation(size: 56))
                                        .tracking(1)
                                    Text(sessionStatusSubtitle(
                                        complete: complete,
                                        durableOutcome: durableOutcome,
                                        reachedEnd: reachedEnd
                                    ))
                                        .font(PlanetFocusTypography.interface(.title3))
                                }
                                .foregroundStyle(SessionPaperStyle.ink)
                                .shadow(color: SessionPaperStyle.shadow, radius: 2, y: 1)
                                .padding(.horizontal, 24).padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(complete ? "Session complete" : savedTerminal ? "Session ended" : reachedEnd ? "Saving session" : "Time remaining")
                            .accessibilityValue(sessionStatusTitle(
                                complete: complete,
                                durableOutcome: durableOutcome,
                                reachedEnd: reachedEnd,
                                remaining: transport?.remainingTime
                            ))
                            .accessibilityHint(
                                savedTerminal ? "Return to stories" : reachedEnd
                                    ? "Double tap to retry saving this session."
                                    : "Double tap to end the session. You will be asked to confirm."
                            )
                            .accessibilityIdentifier("sessionCountdown")
                            .padding(.top, headerTop)
                            .offset(x: headerOffset)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.animation(
                                        reduceMotion ? nil : .easeInOut(duration: 0.45).delay(0.25)),
                                    removal: .opacity))
                        }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: session == nil)
                    VStack(alignment: .trailing, spacing: 8) {
                        Button {
                            showsSettings.toggle()
                        } label: {
                            Label("Scene settings", systemImage: "slider.horizontal.3")
                                .font(PlanetFocusTypography.interface(.body))
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .background(
                                    PlanetFocusPalette.canvasInk.opacity(0.92),
                                    in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sceneSettings")
                        .accessibilityValue(showsSettings ? "Open" : "Closed")
                        if showsSettings {
                            settingsPanel
                                .frame(
                                    width: min(340, geometry.size.width - 32),
                                    height: min(440, geometry.size.height - 92))
                        }
                    }
                    .foregroundStyle(SessionPaperStyle.ink)
                    .padding(.top, 8).padding(.trailing, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
        }
        .alert("End this session?", isPresented: $confirmsExit) {
            Button("Keep focusing", role: .cancel) {}
            Button("End session", role: .destructive, action: cancelSession)
        } message: {
            Text("This attempt will be retained with zero mindful minutes.")
        }
        .alert("Couldn’t update this session", isPresented: Binding(
            get: { lifecycleError != nil },
            set: { if !$0 { lifecycleError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lifecycleError ?? "Please try again.")
        }
        .onAppear {
            if playbackSession == nil {
                duration = preferences.lastDuration
            }
        }
    }

    private var durationLabel: some View {
        Text("\(playbackSession?.duration.minutes ?? duration.minutes) minutes")
            .font(PlanetFocusTypography.interface(.title3))
            .monospacedDigit()
            .accessibilityValue("\(playbackSession?.duration.minutes ?? duration.minutes) minutes")
            .accessibilityIdentifier("sessionDuration")
    }

    private var durationSlider: some View {
        PaperDurationSlider(
            minutes: Binding(
                get: { duration.minutes },
                set: {
                    if let value = FocusDuration(minutes: $0) {
                        duration = value
                        preferences.lastDuration = value
                    }
                }))
    }

    private var beginButton: some View {
        Button {
            showsSettings = false
            startSession()
        } label: {
            VStack(spacing: -20) {
                Text("\(duration.minutes) minutes")
                    .font(PlanetFocusTypography.navigation(size: 56))
                Text("Tap to begin")
                    .font(PlanetFocusTypography.navigation(size: 36))
            }
            .foregroundStyle(SessionPaperStyle.ink)
            .padding(.horizontal, 24).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Begin session")
        .accessibilityValue("\(duration.minutes) minutes")
        .accessibilityIdentifier("sessionBegin")
        .disabled(isStarting)
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Scene settings").font(
                    PlanetFocusTypography.interface(.title2, weight: .medium))
                Spacer()
                Button("Done") { showsSettings = false }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("sceneSettingsDone")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Duration")
                        Spacer()
                        durationLabel
                    }
                    durationSlider
                        .disabled(playbackSession != nil)
                        .opacity(playbackSession == nil ? 1 : 0.45)
                    if playbackSession != nil {
                        Text("Duration is fixed for this session.")
                    }
                    Divider().overlay(SessionPaperStyle.ink.opacity(0.25))
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text("\(Int((volume * 100).rounded()))%")
                            .monospacedDigit().accessibilityIdentifier("sceneVolumeValue")
                    }
                    Slider(value: $volume, in: 0...1)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Scene volume")
                        .accessibilityValue("\(Int((volume * 100).rounded())) percent")
                        .accessibilityIdentifier("sceneVolume")
                    Toggle("Mute audio", isOn: $isMuted)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("sceneMute")
                    if !audioAvailable {
                        Text(
                            "This story’s audio isn’t connected yet. Your volume and mute choices are ready for it."
                        )
                        .font(PlanetFocusTypography.interface(.body))
                        .accessibilityIdentifier("sceneAudioStatus")
                    }
                }
            }
        }
        .font(PlanetFocusTypography.interface(.title3))
        .buttonStyle(.plain)
        .tint(PlanetFocusPalette.warmYellow)
        .padding(20)
        .background(
            PlanetFocusPalette.canvasInk.opacity(0.97), in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SessionPaperStyle.ink.opacity(0.2)))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
    }

    private var playbackSession: PerformanceSession? {
        runtime?.session ?? debugSession
    }

    private func focusSession(for session: PerformanceSession?) -> FocusSession {
        session?.focusSession(for: story)
            ?? FocusSession(story: story, duration: duration,
                            startedAt: Date(timeIntervalSinceReferenceDate: 0), randomSeed: 42)
    }

    private func transportState(for session: PerformanceSession?, at date: Date) -> PerformanceState? {
        guard let session else { return nil }
        return runtime?.sample() ?? PerformanceRunner(session: session).sample(at: date)
    }

    private func countdown(remaining: TimeInterval?) -> String {
        let remaining = Int(ceil(remaining ?? duration.timeInterval))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private func sessionStatusTitle(
        complete: Bool,
        durableOutcome: SessionAttempt.Outcome?,
        reachedEnd: Bool,
        remaining: TimeInterval?
    ) -> String {
        if complete { return "Complete" }
        if durableOutcome != nil { return "Ended" }
        if reachedEnd { return persistenceError == nil ? "Saving…" : "Try again" }
        return countdown(remaining: remaining)
    }

    private func sessionStatusSubtitle(
        complete: Bool,
        durableOutcome: SessionAttempt.Outcome?,
        reachedEnd: Bool
    ) -> String {
        if complete { return "Return to stories" }
        if durableOutcome != nil { return "No mindful minutes credited" }
        if reachedEnd { return persistenceError == nil ? "Saving session" : "Couldn’t save session" }
        return "End session"
    }

    private func startSession() {
        guard !isStarting else { return }
        isStarting = true
        preferences.lastDuration = duration
        Task {
            defer { isStarting = false }
            do {
                try await onStart(duration)
            } catch {
                lifecycleError = error.localizedDescription
            }
        }
    }

    private func completeSession() {
        guard !isFinishing else { return }
        isFinishing = true
        Task {
            defer { isFinishing = false }
            do {
                try await onComplete()
                onBack()
            } catch {
                lifecycleError = error.localizedDescription
            }
        }
    }

    private func cancelSession() {
        guard !isFinishing else { return }
        isFinishing = true
        Task {
            defer { isFinishing = false }
            do {
                try await onCancel()
                onBack()
            } catch {
                lifecycleError = error.localizedDescription
            }
        }
    }
}

private enum SessionPaperStyle {
    static let ink = Color(red: 0.98, green: 0.90, blue: 0.75)
    static let shadow = Color(red: 0.13, green: 0.13, blue: 0.20).opacity(0.45)
    static let handleInset = 16.0
    // The left-hand sky balances the sun without covering the central canopy.
    static let landscapeHeaderShift = 0.32
}

/// Code-native paper artwork with a larger invisible touch area. One-minute
/// values use the same mapping for taps, drags, and accessibility adjustment.
private struct PaperDurationSlider: View {
    @Binding var minutes: Int
    var body: some View {
        GeometryReader { geometry in
            let inset = SessionPaperStyle.handleInset
            let travel = max(1, geometry.size.width - inset * 2)
            let x = inset + Double(minutes - 5) / 50 * travel
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(SessionPaperStyle.ink.opacity(0.6))
                    .frame(width: travel, height: 3)
                    .position(x: geometry.size.width / 2, y: 22)
                Circle()
                    .fill(SessionPaperStyle.ink)
                    .overlay {
                        Image("NeutralPaperGrainV1").resizable().scaledToFill()
                            .blendMode(.multiply).opacity(0.18)
                            .clipShape(Circle())
                    }
                    .frame(width: 22, height: 22)
                    .shadow(color: SessionPaperStyle.shadow, radius: 2, x: 0, y: 2)
                    .position(x: x, y: 22)
                HStack {
                    Text("5")
                    Spacer()
                    Text("55")
                }
                .font(PlanetFocusTypography.interface(.title3))
                .monospacedDigit()
                .foregroundStyle(SessionPaperStyle.ink)
                .padding(.horizontal, 12).offset(y: 36)
            }
            .frame(width: geometry.size.width, height: 64)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    minutes = FocusDuration.minutes(at: (drag.location.x - inset) / travel)
                })
        }
        .frame(height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session duration")
        .accessibilityValue("\(minutes) minutes")
        .accessibilityHint("Adjusts one minute at a time, from 5 to 55 minutes")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = min(55, minutes + 1)
            case .decrement: minutes = max(5, minutes - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("sessionDurationSlider")
        .sensoryFeedback(.selection, trigger: minutes) { _, value in value.isMultiple(of: 5) }
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
