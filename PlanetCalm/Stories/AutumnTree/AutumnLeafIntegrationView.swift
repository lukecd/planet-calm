#if DEBUG
import SwiftUI
import SpriteKit

struct AutumnLeafIntegrationView: View {
    @StateObject private var model: AutumnLeafIntegrationModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var diagnostics = false
    @State private var baselines = false
    @State private var proofPrepared = false

    init(model: AutumnLeafIntegrationModel = AutumnLeafIntegrationModel()) {
        _model = StateObject(wrappedValue: model)
    }

    private var reduceMotion: Bool {
        systemReduceMotion || ProcessInfo.processInfo.arguments.contains("--gate6-static")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Autumn Tree · leaves in context").font(.headline)
                    Text("Gate 6 · integration preview · awaiting approval").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Trial \(model.record.session.randomSeed) · \(reduceMotion ? "static" : "1×")")
                    .font(.subheadline.monospacedDigit())
            }.padding(.horizontal, 20).padding(.vertical, 10)
            GeometryReader { geometry in
                ZStack {
                    if let scene = model.scene {
                        SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.shouldCullNonVisibleNodes])
                            .id(ObjectIdentifier(scene))
                            .accessibilityLabel("Autumn canopy, with \(model.record.count) selected leaves and one shared breeze")
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 5) {
                                let remaining = Int(model.record.session.remainingTime(at: context.date).rounded(.up))
                                Text(String(format: "%01d:%02d", remaining / 60, remaining % 60))
                                    .font(.system(size: 46, weight: .light).monospacedDigit())
                                Text("One-minute review · no focus credit").font(.caption)
                            }
                            .foregroundStyle(Color(red: 0.33, green: 0.20, blue: 0.12))
                            .position(x: geometry.size.width * 0.64, y: geometry.size.height * 0.45)
                        }.allowsHitTesting(false)
                    }
                    if let error = model.error {
                        ContentUnavailableView("Autumn preview unavailable", systemImage: "leaf", description: Text(error))
                    }
                }
                .clipped()
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    if !proofPrepared {
                        proofPrepared = true
                        let args = ProcessInfo.processInfo.arguments
                        if args.contains("--gate6-proof-three") || args.contains("--gate6-proof-twelve") {
                            model.start(count: args.contains("--gate6-proof-twelve") ? 12 : 3, seed: 42,
                                reducedMotion: reduceMotion, diagnostics: diagnostics, delay: reduceMotion ? -60 : 2)
                        }
                    }
                    model.configure(size: geometry.size, reducedMotion: reduceMotion, diagnostics: diagnostics)
                }
                .onChange(of: geometry.size) { _, size in
                    model.configure(size: size, reducedMotion: reduceMotion, diagnostics: diagnostics)
                }
            }
            VStack(spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { trialControls; reviewControls }
                    VStack { HStack { trialControls }; HStack { reviewControls } }
                }
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }
        .background(Color(red: 0.98, green: 0.96, blue: 0.90))
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.suspend() } }
        .onChange(of: diagnostics) { _, visible in model.scene?.setDiagnosticsVisible(visible) }
        .onChange(of: reduceMotion) { _, enabled in model.refresh(reducedMotion: enabled, diagnostics: diagnostics) }
        .sheet(isPresented: $baselines, onDismiss: {
            model.refresh(reducedMotion: reduceMotion, diagnostics: diagnostics)
        }) {
            NavigationStack {
                LeafGroupLabView().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { baselines = false } }
                }
            }
        }
    }

    private var trialControls: some View {
        Group {
            Button("Replay", systemImage: "arrow.counterclockwise") {
                model.start(count: model.record.count, seed: model.record.session.randomSeed,
                    reducedMotion: reduceMotion, diagnostics: diagnostics)
            }.buttonStyle(.borderedProminent)
            Button("New trial", systemImage: "shuffle") {
                model.start(count: model.record.count, seed: model.record.session.randomSeed &+ 1,
                    reducedMotion: reduceMotion, diagnostics: diagnostics)
            }.buttonStyle(.bordered)
            Menu("\(model.record.count) leaves") {
                ForEach(AutumnLeafReview.counts, id: \.self) { count in
                    Button("\(count) leaves") {
                        model.start(count: count, seed: model.record.session.randomSeed,
                            reducedMotion: reduceMotion, diagnostics: diagnostics)
                    }
                }
            }.buttonStyle(.bordered)
        }.controlSize(.large)
    }

    private var reviewControls: some View {
        Group {
            Toggle("Diagnostics", isOn: $diagnostics).fixedSize()
            Button("Baselines") { model.suspend(); baselines = true }.buttonStyle(.bordered).controlSize(.large)
        }
    }
}

@MainActor
final class AutumnLeafIntegrationModel: ObservableObject {
    @Published private(set) var scene: AutumnLeafIntegrationScene?
    @Published private(set) var record: AutumnLeafReviewRecord
    @Published private(set) var status = "Preparing Autumn preview"
    @Published private(set) var error: String?
    private var viewport: CGSize = .zero
    private var suspended = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: AutumnLeafReview.storageKey),
           let saved = try? JSONDecoder().decode(AutumnLeafReviewRecord.self, from: data),
           AutumnLeafReview.counts.contains(saved.count), saved.session.duration == .oneMinute {
            record = saved
        } else {
            record = AutumnLeafReviewRecord(session: FocusSession(story: .autumnTree, duration: .oneMinute,
                startedAt: Date(), randomSeed: 42), count: 3, savedAt: Date())
        }
    }

    func start(count: Int, seed: UInt64, reducedMotion: Bool, diagnostics: Bool, delay: Double = 0) {
        record = AutumnLeafReviewRecord(session: FocusSession(story: .autumnTree, duration: .oneMinute,
            startedAt: Date().addingTimeInterval(delay), randomSeed: seed),
            count: AutumnLeafReview.counts.contains(count) ? count : 3, savedAt: Date())
        persist(record)
        configure(size: viewport, reducedMotion: reducedMotion, diagnostics: diagnostics, force: true, captureCurrent: false)
    }

    func configure(size: CGSize, reducedMotion: Bool, diagnostics: Bool, force: Bool = false, captureCurrent: Bool = true) {
        guard size.width > 0, size.height > 0,
              force || suspended || scene == nil || size != viewport else { return }
        if captureCurrent, let scene, !suspended { persist(scene.checkpoint(at: Date())) }
        do {
            let next = try AutumnLeafIntegrationScene(size: size, record: record,
                resources: AutumnTreeSceneResources.bundled.get(),
                reference: LeafGravityLabConfiguration.gate4Bundled.get(), reduceMotion: reducedMotion)
            next.checkpointHandler = { [weak self, weak next] record in
                guard let self, let next, self.scene === next else { return }
                self.persist(record)
            }
            next.statusHandler = { [weak self, weak next] status in
                guard let self, let next, self.scene === next else { return }
                self.status = status
            }
            next.setDiagnosticsVisible(diagnostics)
            // SwiftUI may retain the retiring SKView for a transition. It must
            // not keep simulating or publish into the replacement session.
            scene?.checkpointHandler = nil
            scene?.statusHandler = nil
            scene?.suspend(at: Date())
            scene = next
            viewport = size
            suspended = false
            error = nil
        } catch {
            self.error = error.localizedDescription
            scene = nil
        }
    }

    func refresh(reducedMotion: Bool, diagnostics: Bool) {
        configure(size: viewport, reducedMotion: reducedMotion, diagnostics: diagnostics, force: true)
    }

    func suspend() {
        guard !suspended else { return }
        scene?.suspend(at: Date())
        suspended = true
    }

    private func persist(_ value: AutumnLeafReviewRecord) {
        record = value
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: AutumnLeafReview.storageKey) }
    }
}
#endif
