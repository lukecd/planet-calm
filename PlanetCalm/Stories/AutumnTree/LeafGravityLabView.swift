#if DEBUG
import SpriteKit
import SwiftUI
import UIKit

struct LeafGravityLabView: View {
    var body: some View {
        switch (LeafGravityLabConfiguration.gate1Bundled, LeafGravityLabConfiguration.gate2Bundled, LeafGravityLabConfiguration.gate3Bundled, LeafGravityLabConfiguration.gate4Bundled) {
        case (.success(let gate1), .success(let gate2), .success(let gate3), .success(let gate4)):
            if let image = Self.leafImage(assetID: gate2.assetID) {
                LeafGravityLabContent(
                    gate1Configuration: gate1,
                    gate2Configuration: gate2,
                    gate3Configuration: gate3,
                    gate4Configuration: gate4,
                    leafImage: image
                )
            } else {
                failureView("Missing leaf texture: \(gate2.assetID).png")
            }
        case (.failure(let error), _, _, _), (_, .failure(let error), _, _), (_, _, .failure(let error), _), (_, _, _, .failure(let error)):
            failureView(error.localizedDescription)
        }
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Gravity lab unavailable", systemImage: "leaf")
        } description: {
            Text(message)
        }
    }

    private static func leafImage(assetID: String) -> UIImage? {
        guard let url = AutumnTreeSceneResources.assetURL(named: assetID) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct LeafGravityLabContent: View {
    private enum Gate: String, CaseIterable, Identifiable {
        case gate1
        case gate2
        case gate3
        case gate4

        var id: Self { self }

        var label: String {
            switch self {
            case .gate1: "1 · Gravity"
            case .gate2: "2 · Drag"
            case .gate3: "3 · Flutter"
            case .gate4: "4 · Wind"
            }
        }
    }

    @StateObject private var model: LeafGravityLabModel
    @State private var slowMotionEnabled = false
    @State private var selectedGate = ProcessInfo.processInfo.arguments.contains("--gate2-proof-autodrop") ? Gate.gate2
        : ProcessInfo.processInfo.arguments.contains("--gate3-proof-autodrop") ? Gate.gate3 : Gate.gate4
    @AppStorage("leafLab.windTrialSeed") private var trialSeed = 42
    @State private var windMode: WindTrialMode = ProcessInfo.processInfo.arguments.contains("--gate4-gust-proof") ? .gust : .steady
    @State private var didStartProof = false

    private let gate1Configuration: LeafGravityLabConfiguration
    private let gate2Configuration: LeafGravityLabConfiguration
    private let gate3Configuration: LeafGravityLabConfiguration
    private let gate4Configuration: LeafGravityLabConfiguration
    private let leafImage: UIImage

    init(
        gate1Configuration: LeafGravityLabConfiguration,
        gate2Configuration: LeafGravityLabConfiguration,
        gate3Configuration: LeafGravityLabConfiguration,
        gate4Configuration: LeafGravityLabConfiguration,
        leafImage: UIImage
    ) {
        self.gate1Configuration = gate1Configuration
        self.gate2Configuration = gate2Configuration
        self.gate3Configuration = gate3Configuration
        self.gate4Configuration = gate4Configuration
        self.leafImage = leafImage
        _model = StateObject(wrappedValue: LeafGravityLabModel())
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if selectedGate == .gate3 || selectedGate == .gate4 {
                    if geometry.size.width >= 700 {
                        HStack(alignment: .top, spacing: 0) {
                            diagnosticsPanel.frame(width: 340)
                            simulationSurface
                        }
                    } else {
                        VStack(spacing: 0) {
                            simulationSurface
                            ScrollView {
                                diagnosticsPanel.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: geometry.size.height * 0.38)
                        }
                    }
                } else {
                    simulationSurface.overlay(alignment: .topLeading) { diagnosticsPanel }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controls
            }
            .task {
                guard !didStartProof else { return }
                let gate4Proof = ProcessInfo.processInfo.arguments.contains("--gate4-steady-proof")
                    || ProcessInfo.processInfo.arguments.contains("--gate4-gust-proof")
                guard gate4Proof || ProcessInfo.processInfo.arguments.contains("--gate2-proof-autodrop")
                    || ProcessInfo.processInfo.arguments.contains("--gate3-proof-autodrop") else {
                    return
                }
                didStartProof = true
                if gate4Proof {
                    trialSeed = Int(LeafGravityLabDebugConstants.fixedSeed)
                    model.setWindTrial(seed: UInt64(trialSeed), mode: windMode)
                }
                let delay = gate4Proof ? LeafGravityLabDebugConstants.windProofAutodropDelay
                    : LeafGravityLabDebugConstants.proofAutodropDelay
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                model.dropLeaf()
            }
        }
    }

    // Keep Gate 3 instrumentation outside the falling leaf's viewport. Narrow
    // screens scroll the numeric detail instead of hiding the release behind it.
    private var simulationSurface: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.96, green: 0.90, blue: 0.75)
                if let scene = model.scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60,
                               options: [.shouldCullNonVisibleNodes])
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .onAppear { configure(viewport: geometry.size, force: true) }
            .onChange(of: geometry.size) { _, size in configure(viewport: size) }
            .onChange(of: selectedGate) { _, _ in configure(viewport: geometry.size, force: true) }
            .onChange(of: windMode) { _, mode in model.setWindTrial(seed: UInt64(max(0, trialSeed)), mode: mode) }
        }
    }

    private var configuration: LeafGravityLabConfiguration {
        switch selectedGate {
        case .gate1: gate1Configuration
        case .gate2: gate2Configuration
        case .gate3: gate3Configuration
        case .gate4: gate4Configuration
        }
    }

    private var gateTitle: String {
        switch selectedGate {
        case .gate1: "GATE 1 · APPROVED GRAVITY BASELINE"
        case .gate2: "GATE 2 · APPROVED STILL-AIR DRAG"
        case .gate3: "GATE 3 · APPROVED PASSIVE FLUTTER"
        case .gate4: "GATE 4 · APPROVED EXTERNAL WIND"
        }
    }

    private var gateDescription: String {
        switch selectedGate {
        case .gate1: "Gravity only · starts at rest"
        case .gate2: "Still air · drag only · no lift or torque"
        case .gate3: "Still air · lift + off-center drag · zero initial spin"
        case .gate4: "\(windMode.label) · zero initial spin"
        }
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(gateTitle)
                .font(.caption.monospaced().weight(.bold))
            Text(gateDescription)
                .font(.caption)
            Text(slowMotionEnabled ? "0.25× · DIAGNOSTIC ONLY" : "1× · NORMAL SPEED")
                .font(.caption.monospaced().weight(.bold))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                diagnosticRow("State", model.diagnostics.state.rawValue)
                diagnosticRow("Elapsed", model.diagnostics.elapsedTime.formatted(.number.precision(.fractionLength(2))) + " s")
                diagnosticRow("Height", model.diagnostics.verticalPosition.formatted(.number.precision(.fractionLength(1))))
                diagnosticRow("Velocity (pt/s)", vectorText(model.diagnostics.velocity, digits: 1))
                diagnosticRow("Drag force (N)", vectorText(model.diagnostics.dragForceNewtons, digits: 5))
                diagnosticRow("|Drag| (N)", magnitude(model.diagnostics.dragForceNewtons).formatted(.number.precision(.fractionLength(5))))
                if selectedGate == .gate3 || selectedGate == .gate4 {
                    diagnosticRow("Lift (N)", vectorText(model.diagnostics.aerodynamics?.liftForceNewtons ?? .zero, digits: 5))
                    diagnosticRow("Air at P (pt/s)", vectorText(model.diagnostics.aerodynamics?.relativeAirVelocity ?? .zero, digits: 1))
                    diagnosticRow("Angle / spin", String(format: "%.1f° / %.2f rad/s", model.diagnostics.rotationRadians * 180 / .pi, model.diagnostics.angularVelocity))
                    diagnosticRow("Cl / area", String(format: "%.2f / %.2f", model.diagnostics.aerodynamics?.liftCoefficient ?? 0.0, model.diagnostics.aerodynamics?.projectedAreaFraction ?? 0.0))
                }
                diagnosticRow("Gravity (m/s²)", configuration.gravity.y.formatted(.number.precision(.fractionLength(1))))
                if selectedGate == .gate4 {
                    diagnosticRow("World air (m/s)", vectorText(model.diagnostics.wind?.velocityMetersPerSecond ?? gate4Configuration.wind?.steadyVelocityMetersPerSecond ?? .zero, digits: 2))
                    diagnosticRow("Gust / envelope", "\(model.diagnostics.wind?.phase.rawValue ?? windMode.rawValue) / \(String(format: "%.2f", model.diagnostics.wind?.gustEnvelope ?? 0.0))")
                    diagnosticRow("Trial seed", "\(trialSeed)\(windMode == .steady ? " · unused" : "")")
                } else {
                    diagnosticRow("Fixed seed", "\(LeafGravityLabDebugConstants.fixedSeed) · unused")
                }
            }
            .font(.caption.monospacedDigit())

            if selectedGate == .gate2 {
                HStack(spacing: 12) {
                    Label("velocity", systemImage: "arrow.down")
                        .foregroundStyle(Color(red: 0.02, green: 0.42, blue: 0.72))
                    Label("drag force", systemImage: "arrow.up")
                        .foregroundStyle(Color(red: 0.72, green: 0.13, blue: 0.42))
                }
                .font(.caption2.weight(.semibold))
            } else if selectedGate == .gate3 || selectedGate == .gate4 {
                HStack(spacing: 10) {
                    Text("Airflow").foregroundStyle(.teal)
                    Text("Drag").foregroundStyle(Color(red: 0.72, green: 0.13, blue: 0.42))
                    Text("Lift").foregroundStyle(Color(red: 0.12, green: 0.42, blue: 0.16))
                }.font(.caption2.weight(.bold))
                Text("M: center of mass · P: center of pressure")
                    .font(.caption2)
                if selectedGate == .gate4 {
                    Text("Indigo: world air · fixed sample position")
                        .font(.caption2).foregroundStyle(.indigo)
                }
            }
        }
        .foregroundStyle(Color(red: 0.23, green: 0.14, blue: 0.08))
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
            Text(value)
        }
    }

    private func vectorText(_ vector: PhysicsVector, digits: Int) -> String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(digits))
        return "(\(vector.x.formatted(style)), \(vector.y.formatted(style)))"
    }

    private func magnitude(_ vector: PhysicsVector) -> Double {
        hypot(vector.x, vector.y)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Experiment gate", selection: $selectedGate) {
                ForEach(Gate.allCases) { gate in
                    Text(gate.label).tag(gate)
                }
            }
            .pickerStyle(.segmented)

            if selectedGate == .gate4 {
                Picker("External wind experiment", selection: $windMode) {
                    ForEach(WindTrialMode.allCases) { mode in Text(mode.label).tag(mode) }
                }.pickerStyle(.segmented)
            }

            HStack(spacing: 12) {
                Button(selectedGate == .gate4 ? "Replay seed" : "Drop", systemImage: "arrow.down") {
                    model.setWindTrial(seed: UInt64(max(0, trialSeed)), mode: windMode)
                    model.dropLeaf()
                }
                .buttonStyle(.borderedProminent)

                if selectedGate == .gate4 && windMode == .gust {
                    Button("New trial", systemImage: "shuffle") {
                        trialSeed = trialSeed == Int.max ? 0 : max(0, trialSeed) + 1
                        model.setWindTrial(seed: UInt64(trialSeed), mode: windMode)
                        model.dropLeaf()
                    }.buttonStyle(.bordered)
                }

                Button("Reset", systemImage: "arrow.counterclockwise") {
                    model.reset()
                }
                .buttonStyle(.bordered)

                Toggle("0.25× diagnostic", isOn: $slowMotionEnabled)
                    .onChange(of: slowMotionEnabled) { _, enabled in
                        model.setSlowMotion(enabled)
                    }

                Spacer(minLength: 0)

            }
            Text(slowMotionEnabled ? "Diagnostic only — switch to 1× for motion approval" : "Normal-speed playback · Gates 1–4 approved")
                .font(.caption.weight(.semibold))
                .foregroundStyle(slowMotionEnabled ? .orange : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func configure(viewport: CGSize, force: Bool = false) {
        model.configure(
            viewport: viewport,
            configuration: configuration,
            leafImage: leafImage,
            slowMotionEnabled: slowMotionEnabled,
            windSeed: UInt64(max(0, trialSeed)),
            windMode: windMode,
            force: force
        )
    }
}

@MainActor
private final class LeafGravityLabModel: ObservableObject {
    @Published private(set) var scene: LeafGravityLabScene?
    @Published private(set) var diagnostics = LeafGravityDiagnostics.ready

    private var viewport: CGSize = .zero

    func configure(
        viewport: CGSize,
        configuration: LeafGravityLabConfiguration,
        leafImage: UIImage,
        slowMotionEnabled: Bool,
        windSeed: UInt64,
        windMode: WindTrialMode,
        force: Bool = false
    ) {
        guard viewport.width > 0, viewport.height > 0,
              force || viewport != self.viewport else { return }

        let scene = LeafGravityLabScene(
            size: viewport,
            configuration: configuration,
            leafImage: leafImage,
            windSeed: windSeed,
            windMode: windMode
        )
        scene.diagnosticsHandler = { [weak self] diagnostics in
            self?.diagnostics = diagnostics
            if ProcessInfo.processInfo.arguments.contains("--leaf-lab-trace") {
                print(String(format: "leaf,%@,%.3f,%.2f,%.2f,%.3f,%.3f,%.3f,%.3f",
                             diagnostics.state.rawValue, diagnostics.elapsedTime,
                             diagnostics.horizontalPosition, diagnostics.verticalPosition,
                             diagnostics.velocity.x, diagnostics.velocity.y,
                             diagnostics.rotationRadians, diagnostics.angularVelocity))
                if let wind = diagnostics.wind {
                    print(String(format: "wind,%.3f,%@,%.4f,%.4f,%.4f", diagnostics.elapsedTime,
                                 wind.phase.rawValue, wind.gustEnvelope,
                                 wind.velocityMetersPerSecond.x, wind.velocityMetersPerSecond.y))
                }
            }
        }
        scene.setSlowMotion(slowMotionEnabled)
        self.scene = scene
        self.viewport = viewport
        diagnostics = .ready
        scene.reset()
    }

    func dropLeaf() {
        scene?.dropLeaf()
    }

    func reset() {
        scene?.reset()
    }

    func setWindTrial(seed: UInt64, mode: WindTrialMode) {
        scene?.setWindTrial(seed: seed, mode: mode)
    }

    func setSlowMotion(_ enabled: Bool) {
        scene?.setSlowMotion(enabled)
    }
}
#endif
