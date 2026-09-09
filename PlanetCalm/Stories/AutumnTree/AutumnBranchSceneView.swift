import SwiftUI
import UIKit
import simd

/// Cache only: the display asks for transport time, never advances its own clock.
private final class AutumnBranchRenderCache {
    var simulation: AutumnBranchSimulation?
    func frame(plan: AutumnBranchPlan, time: Double) -> AutumnBranchFrame {
        if simulation.map({ !$0.plan.hasSameDynamics(as: plan) }) ?? true,
           case .success(let reference) = LeafGravityLabConfiguration.gate3Bundled {
            simulation = AutumnBranchSimulation(plan: plan, reference: reference)
        }
        return simulation?.sample(at: time) ?? AutumnBranchFrame()
    }
}

struct AutumnBranchSceneView: View {
    let session: PerformanceSession?
    let record: AutumnBranchRecord
    let reduceMotion: Bool
    @State private var cache = AutumnBranchRenderCache()
#if DEBUG
    @State private var auditProgress = 0.0
#endif

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 60,
                                paused: session?.isPaused ?? true)) { timeline in
            let elapsed = session?.elapsedTime(at: timeline.date) ?? 0
            let plan = AutumnBranchPlan(duration: session?.duration.timeInterval ?? 120,
                seed: session?.randomSeed ?? 42, tuning: record.tuning, manualGusts: record.manualGusts)
            let frame = cache.frame(plan: plan, time: elapsed)
            let progress = lightingProgress(at: timeline.date)
            GeometryReader { geometry in
                AutumnBranchCanvas(size: geometry.size, frame: frame, progress: progress,
                    tuning: record.tuning, reduceMotion: reduceMotion)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Autumn").font(PlanetFocusTypography.navigation(size: 38))
                    Text(session == nil ? "Branch · light · breeze" : session!.isPaused ? "Paused" : "A little room to let go")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Color(red: 0.96, green: 0.87, blue: 0.70))
                .padding(.leading, 28).padding(.bottom, 30)
                .allowsHitTesting(false)
            }
#if DEBUG
            .overlay(alignment: .top) {
                if ProcessInfo.processInfo.arguments.contains("--autumn-light-audit") {
                    Button { auditProgress = min(1, auditProgress + 0.05) } label: {
                        Color.clear.frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                        .accessibilityLabel("Advance Autumn light audit")
                        .accessibilityIdentifier("autumnAuditNext")
                        .accessibilityValue(String(format: "%.2f", auditProgress))
                        .padding()
                }
            }
#endif
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Autumn Tree focus story")
    }

    private func lightingProgress(at date: Date) -> Double {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--autumn-light-audit") { return auditProgress }
#endif
        return session?.progress(at: date) ?? record.tuning.sunPosition
    }
}

private struct AutumnBranchCanvas: View {
    let size: CGSize
    let frame: AutumnBranchFrame
    let progress: Double
    let tuning: AutumnBranchTuning
    let reduceMotion: Bool

    private var scale: Double { min(size.width / 820, size.height / 970) }
    private var ground: Double { size.height * 0.86 }
    private var sun: CGPoint { CGPoint(x: size.width * 0.77, y: size.height * (0.34 + 0.52 * progress)) }
    private var sunRadius: Double { min(size.width, size.height) * 0.09 }
    private var displayFrame: AutumnBranchFrame { reduceMotion ? AutumnBranchFrame() : frame }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SunriseSkyView(uniforms: SunriseUniforms(
                viewport: SIMD4(Float(size.width), Float(size.height), Float(sun.x), Float(sun.y)),
                story: SIMD4(Float(progress), Float(ground), Float(sunRadius), 0),
                optics: SIMD4(Float(0.24 - progress * 0.26), Float(tuning.sunIntensity), 0, 0)),
                autumnSky: true)
            Circle()
                .fill(Color(red: 1, green: 0.80 - progress * 0.15, blue: 0.43 - progress * 0.19))
                .overlay { Image("NeutralPaperGrainV1").resizable().blendMode(.softLight).opacity(0.3) }
                .clipShape(Circle())
                .frame(width: sunRadius * 2, height: sunRadius * 2)
                .position(sun)
            terrain("hill-far-left", color: Color(red: 0.47, green: 0.46, blue: 0.55),
                    y: size.height * 0.65, height: size.height * 0.35)
            terrain("hill-mid-right", color: Color(red: 0.36, green: 0.37, blue: 0.44),
                    y: size.height * 0.72, height: size.height * 0.28)
            groundPaper

            ForEach(frame.leaves, id: \.id) { leaf in
                leafShadow(leaf)
            }
            branch
            ForEach(frame.leaves, id: \.id) { leaf in
                leafView(leaf)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityHidden(true)
    }

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x * scale, y: ground - y * scale)
    }

    private func image(_ name: String) -> Image {
        if let image = AutumnTreeImageStore.shared.image(named: name) {
            return Image(uiImage: image)
        }
        return Image("NeutralPaperGrainV1")
    }

    private func terrain(_ name: String, color: Color, y: Double, height: Double) -> some View {
        color.overlay {
            Image("NeutralPaperGrainV1").resizable().blendMode(.softLight).opacity(0.35)
        }
        .overlay {
            image(name).resizable().saturation(0).blendMode(.multiply).opacity(0.22)
        }
        .mask { image(name).resizable() }
        .frame(width: size.width, height: height)
        .offset(y: y)
    }

    private var groundPaper: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: ground - 26 * scale))
            path.addCurve(to: CGPoint(x: size.width, y: ground - 28 * scale),
                control1: CGPoint(x: size.width * 0.35, y: ground - 42 * scale),
                control2: CGPoint(x: size.width * 0.62, y: ground - 6 * scale))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
        .fill(Color(red: 0.57, green: 0.39, blue: 0.30))
        .overlay {
            Image("NeutralPaperGrainV1").resizable().blendMode(.softLight).opacity(0.40)
                .mask(Path { path in
                    path.move(to: CGPoint(x: 0, y: ground - 26 * scale))
                    path.addCurve(to: CGPoint(x: size.width, y: ground - 28 * scale),
                        control1: CGPoint(x: size.width * 0.35, y: ground - 42 * scale),
                        control2: CGPoint(x: size.width * 0.62, y: ground - 6 * scale))
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.addLine(to: CGPoint(x: 0, y: size.height)); path.closeSubpath()
                }.fill(.white))
        }
    }

    private var branchPath: Path {
        let pose = displayFrame
        let joints = AutumnBranchSimulation.joints(pose)
        var path = Path()
        let root = point(joints[0].x, joints[0].y)
        let elbow = point(joints[1].x, joints[1].y)
        let tip = point(joints[2].x, joints[2].y)
        path.move(to: CGPoint(x: root.x, y: root.y - 22 * scale))
        path.addQuadCurve(to: CGPoint(x: elbow.x, y: elbow.y - 10 * scale),
                          control: CGPoint(x: root.x + 155 * scale, y: root.y + 30 * scale))
        path.addQuadCurve(to: tip, control: CGPoint(x: elbow.x + 165 * scale, y: elbow.y - 15 * scale))
        path.addQuadCurve(to: CGPoint(x: elbow.x, y: elbow.y + 5 * scale),
                          control: CGPoint(x: elbow.x + 135 * scale, y: elbow.y - 9 * scale))
        path.addQuadCurve(to: CGPoint(x: root.x, y: root.y + 24 * scale),
                          control: CGPoint(x: root.x + 160 * scale, y: root.y + 60 * scale))
        path.closeSubpath()
        for id in 0..<6 {
            let attach = AutumnBranchSimulation.attachment(id: id, frame: pose)
            let end = point(attach.x, attach.y)
            let offset = id % 2 == 0 ? 64.0 : -62.0
            let base = AutumnBranchSimulation.twigRoot(id: id, frame: pose)
            let start = point(base.x, base.y)
            path.move(to: CGPoint(x: start.x - 3 * scale, y: start.y))
            path.addQuadCurve(to: end, control: CGPoint(x: end.x - 44 * scale, y: end.y + offset * scale * 0.3))
            path.addQuadCurve(to: CGPoint(x: start.x + 3 * scale, y: start.y),
                              control: CGPoint(x: end.x - 39 * scale, y: end.y + offset * scale * 0.4))
            path.closeSubpath()
        }
        return path
    }

    private var branch: some View {
        Color(red: 0.27, green: 0.19, blue: 0.23)
            .overlay { Image("NeutralPaperGrainV1").resizable().blendMode(.softLight).opacity(0.6) }
            .mask(branchPath.fill(.white))
            .shadow(color: .black.opacity(0.12), radius: 2 * scale, x: -3 * scale, y: 4 * scale)
    }

    private func renderLeaf(_ leaf: AutumnBranchLeaf) -> AutumnBranchLeaf {
        guard reduceMotion else { return leaf }
        var result = leaf
        if leaf.phase == .attached {
            let anchor = AutumnBranchSimulation.attachment(id: leaf.id, frame: AutumnBranchFrame())
            result.x = anchor.x; result.y = anchor.y; result.angle = anchor.angle; result.turn = 0
        } else if leaf.phase == .falling {
            // Show the narrative change without a travelling object.
            result.y = 16; result.turn = 0; result.groundTilt = 1.28
        }
        return result
    }

    private func leafView(_ source: AutumnBranchLeaf) -> some View {
        let leaf = renderLeaf(source)
        let names = ["leaf-maple-yellow", "leaf-maple-orange", "leaf-maple-red"]
        let name = names[leaf.id % names.count]
        let pigment = [Color(red: 0.94, green: 0.67, blue: 0.26),
                       Color(red: 0.87, green: 0.38, blue: 0.21),
                       Color(red: 0.66, green: 0.24, blue: 0.29)][leaf.id % 3]
        let center = point(leaf.x, leaf.y)
        let lightDirection = simd_normalize(SIMD3<Double>(
            sun.x - center.x, center.y - sun.y, 280 * scale))
        let unfolded = SIMD3<Double>(sin(leaf.turn) * cos(leaf.angle),
            sin(leaf.turn) * sin(leaf.angle), cos(leaf.turn))
        let normal = SIMD3<Double>(unfolded.x,
            unfolded.y * cos(leaf.groundTilt) + unfolded.z * sin(leaf.groundTilt),
            unfolded.z * cos(leaf.groundTilt) - unfolded.y * sin(leaf.groundTilt))
        let facing = max(0, simd_dot(normal, lightDirection))
        let light = (0.40 + 0.60 * facing) * tuning.sunIntensity
        return pigment
            .overlay { image(name).resizable().saturation(0).blendMode(.multiply).opacity(0.30) }
            .overlay { Image("NeutralPaperGrainV1").resizable().blendMode(.softLight).opacity(0.35) }
            .overlay(Color(red: 1, green: 0.69, blue: 0.32).opacity(tuning.backlight * (1 - facing) * 0.30))
            .brightness((light - 0.7) * 0.22)
            .mask { image(name).resizable() }
            .frame(width: 88 * scale, height: 105 * scale)
            .rotation3DEffect(.radians(leaf.turn), axis: (x: 0, y: 1, z: 0), perspective: 0.15)
            .rotationEffect(.radians(-leaf.angle))
            .rotation3DEffect(.radians(leaf.groundTilt), axis: (x: 1, y: 0, z: 0), perspective: 0)
            .shadow(color: .black.opacity(0.15), radius: scale, x: -scale, y: 2 * scale)
            .position(point(leaf.x, leaf.y))
    }

    private func leafShadow(_ source: AutumnBranchLeaf) -> some View {
        let leaf = renderLeaf(source)
        // Directional projection onto the ground. Height increases both displacement
        // and penumbra. This is a shallow receiver, not global illumination.
        let sunHeight = max(80, (ground - sun.y) / scale)
        let sunX = sun.x / scale
        let x = leaf.x + (leaf.x - sunX) * leaf.y / sunHeight
        return Color(red: 0.15, green: 0.11, blue: 0.23)
            .mask { image(["leaf-maple-yellow", "leaf-maple-orange", "leaf-maple-red"][leaf.id % 3]).resizable() }
            .frame(width: 88 * scale, height: 105 * scale)
            .rotationEffect(.radians(-leaf.angle))
            .scaleEffect(x: max(0.25, abs(cos(leaf.turn))), y: 0.25)
            .blur(radius: (1 + leaf.y * 0.015 * tuning.shadowSoftness) * scale)
            .opacity(0.18 + 0.22 * (1 - min(1, leaf.y / 600)))
            .position(x: x * scale, y: ground + 8 * scale)
    }
}

#if DEBUG
struct AutumnBranchMonitor: View {
    let session: PerformanceSession?
    let record: AutumnBranchRecord
    @State private var cache = AutumnBranchRenderCache()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { tick in
            let time = session?.elapsedTime(at: tick.date) ?? 0
            let plan = AutumnBranchPlan(duration: session?.duration.timeInterval ?? 120,
                seed: session?.randomSeed ?? 42, tuning: record.tuning, manualGusts: record.manualGusts)
            let frame = cache.frame(plan: plan, time: time)
            VStack(alignment: .leading, spacing: 5) {
                Text("Wind: \(plan.wind(at: 300, seconds: time), specifier: "%.2f") m/s")
                Text("Leaves: \(frame.leaves.filter { $0.phase == .attached }.count) attached · \(frame.leaves.filter { $0.phase == .falling }.count) falling · \(frame.leaves.filter { $0.phase == .settled }.count) settled")
                Text("Breezes: \(plan.gusts.count) · fixed simulation 120 Hz")
                Text("Warm \(plan.poolWeights(at: time).first * 100, specifier: "%.0f")% · Amber \(plan.poolWeights(at: time).middle * 100, specifier: "%.0f")% · Dusk \(plan.poolWeights(at: time).last * 100, specifier: "%.0f")%")
                Text("Audio cues recorded; Autumn audio is not enabled in this checkpoint.")
                    .foregroundStyle(.secondary)
            }.font(.caption2).monospacedDigit().accessibilityIdentifier("autumnPhysicsMonitor")
        }
    }
}

struct AutumnBranchControls: View {
    @Binding var record: AutumnBranchRecord
    @Binding var seed: Int
    let session: PerformanceSession?
    let onGust: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Branch · light · breeze").font(.caption.weight(.semibold))
            Group {
                slider("Breeze", value: $record.tuning.windStrength, range: 0.15...1.2)
                slider("Gust seconds", value: $record.tuning.gustDuration, range: 3...15)
                slider("Flexibility", value: $record.tuning.flexibility, range: 0.4...2)
                slider("Damping", value: $record.tuning.damping, range: 0.4...1.8)
                slider("Release", value: $record.tuning.releaseSensitivity, range: 0.5...1.6)
                Stepper("Seed \(seed)", value: $seed, in: 0...999999)
                    .font(.caption).accessibilityIdentifier("autumnSeed")
                Button("Reset parameters") { record = .init() }
            }.disabled(session != nil)
            Text("End the run to change physics; restart repeats the same seed.")
                .font(.caption2).foregroundStyle(.secondary)
            slider("Sun position", value: $record.tuning.sunPosition, range: 0...1)
                .disabled(session != nil)
            Text(session == nil ? "Manual light inspection" : "Sun position follows the runner")
                .font(.caption2).foregroundStyle(.secondary)
            slider("Sunlight", value: $record.tuning.sunIntensity, range: 0.5...1.5)
            slider("Shadow softness", value: $record.tuning.shadowSoftness, range: 0...1)
            slider("Backlight", value: $record.tuning.backlight, range: 0...1)
            Button("Send a breeze", action: onGust)
                .disabled(session == nil || session?.isPaused == true || session?.progress(at: .now) == 1)
                .accessibilityIdentifier("autumnGust")
        }
        .font(.caption)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 2) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(2))).monospacedDigit() }
            Slider(value: value, in: range).tint(PlanetFocusPalette.warmYellow).accessibilityLabel(title)
        }
    }
}
#endif
