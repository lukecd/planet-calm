#if DEBUG
import SwiftUI
import SpriteKit

struct LeafGroupLabView: View {
    @StateObject private var model: LeafGroupLabModel
    @AppStorage("leafLab.groupTrialSeed") private var seed = 42
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var diagnosticsVisible = false
    @State private var baselinesVisible = false
    @State private var proofStarted = false
    @State private var terrainEnabled: Bool

    init(model: LeafGroupLabModel = LeafGroupLabModel(), terrainEnabled: Bool = true) {
        _model = StateObject(wrappedValue: model)
        let arguments = ProcessInfo.processInfo.arguments
        _terrainEnabled = State(initialValue: terrainEnabled && !arguments.contains("--group-open-sky")
            && !arguments.contains("--group-proof-a") && !arguments.contains("--group-proof-b"))
    }

    private var reduceMotion: Bool {
        systemReduceMotion || ProcessInfo.processInfo.arguments.contains("--group-static-proof")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Six leaves · one breeze").font(.headline)
                    Text(terrainEnabled ? "Gate 5 · terrain and settling · approved" : "Open-sky group · approved")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu(terrainEnabled ? "Terrain" : "Open sky") {
                    Button("Terrain · Gate 5") { terrainEnabled = true }
                    Button("Open sky · approved") { terrainEnabled = false }
                }.accessibilityLabel("Choose terrain or approved open-sky mode")
                Text("Trial \(seed) · \(reduceMotion ? "static" : "1×")")
                    .font(.subheadline.monospacedDigit())
            }.padding(.horizontal, 20).padding(.vertical, 12)

            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color(red: 0.96, green: 0.90, blue: 0.75)
                    if let scene = model.scene {
                        SpriteView(scene: scene, preferredFramesPerSecond: 60,
                                   options: [.shouldCullNonVisibleNodes])
                            // SpriteView retains its initially presented scene. A new
                            // trial needs a new host, not just a new scene argument.
                            .id(ObjectIdentifier(scene))
                            .accessibilityLabel(reduceMotion ? "Six leaves in a static preview" : "Six leaves sharing one air field")
                    }
                    if let error = model.error {
                        ContentUnavailableView("Leaf review unavailable", systemImage: "leaf", description: Text(error))
                    }
                    if diagnosticsVisible { diagnostics.padding(12) }
                }
                .clipped()
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    let arguments = ProcessInfo.processInfo.arguments
                    let proof = arguments.contains("--group-proof-a") || arguments.contains("--group-proof-b")
                        || arguments.contains("--gate5-proof-a") || arguments.contains("--gate5-proof-b")
                    if proof && !proofStarted {
                        seed = arguments.contains("--group-proof-b") || arguments.contains("--gate5-proof-b") ? 43 : 42
                    }
                    model.configure(size: geometry.size, seed: UInt64(max(0, seed)), reducedMotion: reduceMotion,
                                    diagnostics: diagnosticsVisible, terrainEnabled: terrainEnabled)
                    guard proof && !proofStarted else { return }
                    proofStarted = true
                    try? await Task.sleep(for: .seconds(LeafGravityLabDebugConstants.windProofAutodropDelay))
                    guard !Task.isCancelled, scenePhase == .active else { return }
                    model.scene?.replay()
                }
                .onChange(of: geometry.size) { _, size in
                    model.configure(size: size, seed: UInt64(max(0, seed)), reducedMotion: reduceMotion,
                                    diagnostics: diagnosticsVisible, terrainEnabled: terrainEnabled)
                }
                .onChange(of: terrainEnabled) { _, enabled in
                    model.configure(size: geometry.size, seed: UInt64(max(0, seed)), reducedMotion: reduceMotion,
                                    diagnostics: diagnosticsVisible, terrainEnabled: enabled)
                }
            }

            VStack(spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { trialButtons; reviewButtons }
                    VStack(spacing: 6) {
                        HStack(spacing: 14) { trialButtons }
                        HStack(spacing: 14) { reviewButtons }
                    }
                }
                Text(statusText)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel(statusText)
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Color(red: 0.98, green: 0.96, blue: 0.90))
        .onChange(of: diagnosticsVisible) { _, visible in model.scene?.setDiagnosticsVisible(visible) }
        .onChange(of: reduceMotion) { _, enabled in model.scene?.setReducedMotion(enabled) }
        .onChange(of: scenePhase) { _, phase in
            // This debug trial is not a focus session. Never catch up missed physics frames.
            if phase != .active { model.scene?.reset() }
        }
        .sheet(isPresented: $baselinesVisible) {
            NavigationStack {
                LeafGravityLabView().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { baselinesVisible = false } }
                }
            }
        }
    }

    private var trialButtons: some View {
        Group {
            Button(reduceMotion ? "Show snapshot" : "Replay", systemImage: "arrow.counterclockwise") {
                model.scene?.replay()
            }.buttonStyle(.borderedProminent)
            Button("New trial", systemImage: "shuffle") {
                seed = seed == Int.max ? 0 : max(0, seed) + 1
                model.newTrial(seed: UInt64(seed), reducedMotion: reduceMotion, diagnostics: diagnosticsVisible,
                               terrainEnabled: terrainEnabled)
            }.buttonStyle(.bordered)
            Button("Reset") { model.scene?.reset() }.buttonStyle(.bordered)
        }.controlSize(.large)
    }

    private var statusText: String {
        if reduceMotion { return "Reduce Motion · static arrangement, no falling animation" }
        if model.diagnostics.failed { return "Needs attention · a leaf missed the terrain or did not settle" }
        if terrainEnabled { return "\(model.diagnostics.state.capitalized) · \(model.diagnostics.settled) of 6 leaves settled" }
        return "\(model.diagnostics.state.capitalized) · \(model.diagnostics.finished) of 6 leaves exited"
    }

    private var reviewButtons: some View {
        Group {
            Toggle("Diagnostics", isOn: $diagnosticsVisible).fixedSize()
            Button("Baselines") { baselinesVisible = true }.buttonStyle(.bordered).controlSize(.large)
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(model.diagnostics.elapsed.formatted(.number.precision(.fractionLength(2)))) s · \(model.diagnostics.released)/6 released")
            if terrainEnabled { Text("\(model.diagnostics.contacting) supported · \(model.diagnostics.settled) settled · Brown: ground · Pink: collision core") }
            if let wind = model.diagnostics.wind {
                Text(String(format: "Air (%.2f, %.2f) m/s · %@", wind.velocityMetersPerSecond.x,
                            wind.velocityMetersPerSecond.y, wind.phase.rawValue))
            }
            Text("#   scale   mass (g)   area (cm²)").fontWeight(.semibold)
            ForEach(model.scene?.plan.members ?? []) { member in
                Text(String(format: "%d   %.2f×   %.2f       %.1f", member.id, member.linearScale,
                            member.massKilograms * 1000, member.areaSquareMeters * 10000))
            }
            Text("Indigo: shared air · Teal: relative air\nPurple: net aero force · Numbers: leaf ID")
        }
        .font(.caption.monospaced()).padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

@MainActor
final class LeafGroupLabModel: ObservableObject {
    @Published private(set) var scene: LeafGroupScene?
    @Published private(set) var diagnostics = LeafGroupDiagnostics()
    @Published private(set) var error: String?
    private var viewport: CGSize = .zero

    func configure(size: CGSize, seed: UInt64, reducedMotion: Bool, diagnostics: Bool,
                   terrainEnabled: Bool = false, force: Bool = false) {
        guard size.width > 0, size.height > 0,
              force || scene == nil || size != viewport || scene?.plan.seed != seed
                || (scene?.terrain != nil) != terrainEnabled else { return }
        do {
            let configuration = try LeafGroupConfiguration.bundled.get()
            let reference = try LeafGravityLabConfiguration.gate4Bundled.get()
            let plan = try LeafGroupPlan(configuration: configuration, reference: reference, seed: seed)
            let terrain = terrainEnabled ? try LeafTerrainConfiguration.bundled.get() : nil
            var images: [String: UIImage] = [:]
            for id in configuration.assetIDs + (terrain.map { [$0.assetID] } ?? []) {
                guard let url = AutumnTreeSceneResources.assetURL(named: id), let image = UIImage(contentsOfFile: url.path) else {
                    throw LeafGravityLabConfigurationError.missingResource
                }
                images[id] = image
            }
            let scene = try LeafGroupScene(size: size, reference: reference, plan: plan, images: images, terrain: terrain)
            scene.diagnosticsHandler = { [weak self] value in self?.diagnostics = value }
            scene.setDiagnosticsVisible(diagnostics)
            scene.setReducedMotion(reducedMotion)
            self.scene = scene
            viewport = size
            error = nil
        } catch {
            self.error = error.localizedDescription
            scene = nil
        }
    }

    func newTrial(seed: UInt64, reducedMotion: Bool, diagnostics: Bool, terrainEnabled: Bool = false) {
        configure(size: viewport, seed: seed, reducedMotion: reducedMotion, diagnostics: diagnostics,
                  terrainEnabled: terrainEnabled, force: true)
        scene?.replay()
    }
}
#endif
