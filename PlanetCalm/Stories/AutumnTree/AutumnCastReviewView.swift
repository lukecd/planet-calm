#if DEBUG
import SwiftUI

struct AutumnCastReviewView: View {
    @StateObject private var clock: AutumnCastReviewClock
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var mode: AutumnCastReviewMode
    @State private var seed: UInt64
    @State private var seedText: String
    @State private var flockCount: Int
    @State private var birdBodyLength: Double
    @State private var forceReduceMotion: Bool
    @State private var diagnostics: Bool

    init() {
        let launch = AutumnCastReviewLaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
        _clock = StateObject(wrappedValue: AutumnCastReviewClock(
            elapsed: launch.elapsed,
            isPlaying: !launch.paused,
            rate: launch.rate
        ))
        _mode = State(initialValue: launch.mode)
        _seed = State(initialValue: launch.seed)
        _seedText = State(initialValue: String(launch.seed))
        _flockCount = State(initialValue: launch.flockCount)
        _birdBodyLength = State(initialValue: launch.birdBodyLength)
        _forceReduceMotion = State(initialValue: launch.reduceMotion)
        _diagnostics = State(initialValue: launch.diagnostics)
    }

    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !clock.isPlaying)) { context in
            let maximum = maximumDuration
            let elapsed = min(clock.elapsed(at: context.date), maximum)
            VStack(spacing: 0) {
                header(elapsed: elapsed)
                GeometryReader { geometry in
                    AutumnTreeSceneView(
                        progress: sceneProgress(at: elapsed),
                        elapsedTime: elapsed,
                        referenceDate: context.date,
                        performance: performance(at: elapsed),
                        reduceMotion: reduceMotion,
                        showsFocusUI: false,
                        castOptions: AutumnCastRenderOptions(
                            reviewMode: mode,
                            flockCount: flockCount,
                            birdBodyLength: birdBodyLength,
                            diagnostics: diagnostics,
                            advancesFromReferenceDate: false
                        )
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityLabel("Native Autumn cast review")
                }
                controls(now: context.date, elapsed: elapsed, maximum: maximum)
            }
            .background(Color(red: 0.98, green: 0.96, blue: 0.90))
        }
    }

    private func header(elapsed: TimeInterval) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Autumn cast · native integration").font(.headline)
                Text("DEBUG review · no focus credit").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(elapsed, format: .number.precision(.fractionLength(2))) s · seed \(seed)")
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func controls(now: Date, elapsed: TimeInterval, maximum: TimeInterval) -> some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { elapsed },
                    set: { clock.scrub(to: $0, at: now) }
                ),
                in: 0...maximum
            )
            .accessibilityLabel("Review timeline")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Picker("Mode", selection: $mode) {
                        Text("Combined").tag(AutumnCastReviewMode.combined)
                        Text("Rabbit").tag(AutumnCastReviewMode.rabbit)
                        Text("Single bird").tag(AutumnCastReviewMode.singleBird)
                        Text("Flock").tag(AutumnCastReviewMode.flock)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 380)
                    .onChange(of: mode) { _, _ in clock.replay(at: now) }

                    Button(clock.isPlaying ? "Pause" : "Play", systemImage: clock.isPlaying ? "pause.fill" : "play.fill") {
                        clock.toggle(at: now, maximum: maximum)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Replay", systemImage: "arrow.counterclockwise") { clock.replay(at: now) }
                        .buttonStyle(.bordered)

                    Picker("Speed", selection: Binding(
                        get: { clock.rate },
                        set: { clock.setRate($0, at: now, maximum: maximum) }
                    )) {
                        Text("0.25×").tag(0.25)
                        Text("0.5×").tag(0.5)
                        Text("1×").tag(1.0)
                        Text("2×").tag(2.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)

                    Picker("Bird count", selection: $flockCount) {
                        ForEach(BirdFlockConfiguration.approvedCounts, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    Picker("Bird size", selection: $birdBodyLength) {
                        ForEach(BirdFlockConfiguration.approvedBodyLengths, id: \.self) { Text("\(Int($0)) pt").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)

                    TextField("Seed", text: $seedText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 118)
                        .accessibilityLabel("Flock seed")
                        .onSubmit { applySeed() }
                    Button("Use seed") { applySeed() }.buttonStyle(.bordered)
                    Button("New seed", systemImage: "shuffle") {
                        seed &+= 1
                        seedText = String(seed)
                        clock.replay(at: now)
                    }
                    .buttonStyle(.bordered)

                    Toggle("Reduce Motion", isOn: $forceReduceMotion).fixedSize()
                    Toggle("Diagnostics", isOn: $diagnostics).fixedSize()
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.thinMaterial)
    }

    private var maximumDuration: TimeInterval {
        switch mode {
        case .combined: 30
        case .rabbit: AutumnCastSchedule.rabbitDuration
        case .singleBird: 4.8
        case .flock: AutumnCastSchedule.birdDuration
        }
    }

    private func sceneProgress(at elapsed: TimeInterval) -> Double {
        switch mode {
        case .combined: elapsed < 20 ? 0.5 : 0.75
        case .rabbit: 0.75
        case .singleBird, .flock: 0.5
        }
    }

    private func performance(at elapsed: TimeInterval) -> StoryPerformance {
        let plan = StoryPlan(moments: reviewMoments)
        return AutumnTreeDirector().performance(
            at: StoryContext(
                progress: sceneProgress(at: elapsed),
                elapsedTime: elapsed,
                duration: maximumDuration,
                reduceMotion: reduceMotion
            ),
            plan: plan
        )
    }

    private var reviewMoments: [StoryMoment] {
        switch mode {
        case .combined:
            [birdMoment(start: 0), rabbitMoment(start: 21)]
        case .rabbit:
            [rabbitMoment(start: 0)]
        case .singleBird, .flock:
            [birdMoment(start: 0)]
        }
    }

    private func birdMoment(start: TimeInterval) -> StoryMoment {
        StoryMoment(
            id: .autumnBirdFlock,
            startTime: start,
            duration: mode == .singleBird ? 4.8 : AutumnCastSchedule.birdDuration,
            intensity: 1,
            randomSeed: seed,
            quantization: .none,
            visualCue: StoryVisualCue(effect: .autumnBirdFlock),
            audioCue: nil
        )
    }

    private func rabbitMoment(start: TimeInterval) -> StoryMoment {
        StoryMoment(
            id: .autumnRabbitPeek,
            startTime: start,
            duration: AutumnCastSchedule.rabbitDuration,
            intensity: 1,
            randomSeed: seed,
            quantization: .none,
            visualCue: StoryVisualCue(effect: .autumnRabbitPeek),
            audioCue: nil
        )
    }

    private func applySeed() {
        guard let value = UInt64(seedText) else {
            seedText = String(seed)
            return
        }
        seed = value
        clock.replay(at: .now)
    }
}

@MainActor
final class AutumnCastReviewClock: ObservableObject {
    @Published private(set) var isPlaying: Bool
    @Published private(set) var rate: Double
    private var anchorDate = Date.now
    private var anchorElapsed: TimeInterval

    init(elapsed: TimeInterval = 0, isPlaying: Bool = true, rate: Double = 1) {
        anchorElapsed = max(0, elapsed)
        self.isPlaying = isPlaying
        self.rate = rate
    }

    func elapsed(at date: Date) -> TimeInterval {
        isPlaying ? anchorElapsed + max(0, date.timeIntervalSince(anchorDate)) * rate : anchorElapsed
    }

    func toggle(at date: Date, maximum: TimeInterval) {
        if isPlaying {
            anchorElapsed = min(elapsed(at: date), maximum)
            isPlaying = false
        } else {
            if anchorElapsed >= maximum { anchorElapsed = 0 }
            anchorDate = date
            isPlaying = true
        }
    }

    func replay(at date: Date) {
        anchorElapsed = 0
        anchorDate = date
        isPlaying = true
    }

    func scrub(to elapsed: TimeInterval, at date: Date) {
        anchorElapsed = max(0, elapsed)
        anchorDate = date
    }

    func setRate(_ nextRate: Double, at date: Date, maximum: TimeInterval) {
        anchorElapsed = min(elapsed(at: date), maximum)
        anchorDate = date
        rate = nextRate
    }
}

private struct AutumnCastReviewLaunchConfiguration {
    var mode: AutumnCastReviewMode = .combined
    var seed: UInt64 = 130_363
    var flockCount = 24
    var birdBodyLength = 14.0
    var elapsed: TimeInterval = 0
    var rate = 1.0
    var paused = false
    var reduceMotion = false
    var diagnostics = false

    init(arguments: [String]) {
        for argument in arguments {
            if let value = Self.value(after: "--autumn-cast-mode=", in: argument),
               let parsed = AutumnCastReviewMode(rawValue: value) { mode = parsed }
            if let value = Self.value(after: "--autumn-cast-seed=", in: argument),
               let parsed = UInt64(value) { seed = parsed }
            if let value = Self.value(after: "--autumn-cast-count=", in: argument),
               let parsed = Int(value), BirdFlockConfiguration.approvedCounts.contains(parsed) { flockCount = parsed }
            if let value = Self.value(after: "--autumn-cast-size=", in: argument),
               let parsed = Double(value), BirdFlockConfiguration.approvedBodyLengths.contains(parsed) { birdBodyLength = parsed }
            if let value = Self.value(after: "--autumn-cast-time=", in: argument),
               let parsed = Double(value), parsed.isFinite { elapsed = max(0, parsed) }
            if let value = Self.value(after: "--autumn-cast-rate=", in: argument),
               let parsed = Double(value), [0.25, 0.5, 1, 2].contains(parsed) { rate = parsed }
        }
        paused = arguments.contains("--autumn-cast-paused")
        reduceMotion = arguments.contains("--autumn-cast-review-reduce-motion")
        diagnostics = arguments.contains("--autumn-cast-diagnostics")
    }

    private static func value(after prefix: String, in argument: String) -> String? {
        guard argument.hasPrefix(prefix) else { return nil }
        return String(argument.dropFirst(prefix.count))
    }
}
#endif
