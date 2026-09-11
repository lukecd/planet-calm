import SwiftUI
import UIKit
import simd

/// Cache only: the display asks for transport time, never advances its own clock.
private final class AutumnBranchRenderCache {
    var simulation: AutumnBranchSimulation?
    private var cachedPlan: AutumnBranchPlan?
    private var cachedRecord: AutumnBranchRecord?
    func plan(duration: Double, seed: UInt64, record: AutumnBranchRecord) -> AutumnBranchPlan {
        if let cachedPlan, cachedPlan.duration == duration, cachedPlan.seed == seed,
           cachedRecord == record { return cachedPlan }
        let plan = AutumnBranchPlan(duration: duration, seed: seed, tuning: record.tuning,
            manualGusts: record.manualGusts, isFullTree: true,
            deerTuning: record.deer?.tuning ?? .init())
        cachedRecord = record
        cachedPlan = plan
        return plan
    }
    func frame(plan: AutumnBranchPlan, time: Double) -> AutumnBranchFrame {
        if simulation.map({ !$0.plan.hasSameDynamics(as: plan) }) ?? true,
           case .success(let reference) = LeafGravityLabConfiguration.gate3Bundled {
            simulation = AutumnBranchSimulation(plan: plan, reference: reference)
        }
        return simulation?.sample(at: time) ?? AutumnCanopy.frame()
    }
}

struct AutumnBranchSceneView: View {
    let session: PerformanceSession?
    let runtime: SessionRuntime?
    let record: AutumnBranchRecord
    let reduceMotion: Bool
    @State private var cache = AutumnBranchRenderCache()
#if DEBUG
    @State private var auditProgress = 0.0
#endif

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 60,
                                paused: session?.isPaused ?? true)) { timeline in
            let elapsed = runtime?.sample().elapsedTime ?? session?.elapsedTime(at: timeline.date) ?? 0
            let plan = cache.plan(duration: session?.duration.timeInterval ?? 120,
                seed: session?.randomSeed ?? 42, record: record)
            let frame = cache.frame(plan: plan, time: elapsed)
            let progress = lightingProgress(at: timeline.date)
            GeometryReader { geometry in
                AutumnBranchCanvas(size: geometry.size, frame: frame, progress: progress,
                    tuning: record.tuning, reduceMotion: reduceMotion,
                    birdFlight: session == nil ? nil : plan.encounters.bird(at: elapsed, manual: record.bird?.flight),
                    elapsedTime: elapsed, birdPlan: plan,
                    deerEncounter: session == nil ? nil : record.deer?.encounter
                        ?? plan.deerEnding)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Autumn").font(PlanetFocusTypography.navigation(size: 38))
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
        return runtime?.sample().progress ?? session?.progress(at: date) ?? record.tuning.sunPosition
    }
}

/// Catalog callers supply their existing transport snapshot; this adds no clock.
struct AutumnBranchSnapshotView: View {
    let context: StorySceneRenderContext
    @State private var cache = AutumnBranchRenderCache()

    var body: some View {
        let plan = cache.plan(duration: context.duration, seed: context.randomSeed, record: .init())
        let frame = context.reduceMotion ? AutumnCanopy.frame()
            : cache.frame(plan: plan, time: context.elapsedTime)
        GeometryReader { geometry in
            AutumnBranchCanvas(size: geometry.size, frame: frame, progress: context.progress,
                               tuning: .standard, reduceMotion: context.reduceMotion,
                               birdFlight: plan.encounters.bird(at: context.elapsedTime),
                               elapsedTime:context.elapsedTime,birdPlan:plan,deerEncounter:plan.deerEnding)
        }
    }
}

struct AutumnBranchCanvas: View {
    // Native layout snapshots cannot render the Metal-backed UIView.
    var includesAtmosphere = true
    let size: CGSize
    let frame: AutumnBranchFrame
    let progress: Double
    let tuning: AutumnBranchTuning
    let reduceMotion: Bool

    var birdFlight: AutumnOrigamiFlight? = nil
    var elapsedTime = 0.0
    var birdPlan: AutumnBranchPlan? = nil
    var deerEncounter: AutumnDeerEncounter? = nil

    private var deerPose: AutumnDeerEncounter.Pose? {
        guard scale.isFinite, scale > 0 else { return nil }
        return deerEncounter?.sample(at:elapsedTime,stage:.init(left:-horizontalOffset/scale,
            right:(size.width-horizontalOffset)/scale),reduceMotion:reduceMotion)
    }

    private var birdStage: AutumnBirdStage {
        AutumnBirdStage(camera: AutumnBirdCamera(center: SIMD2(
            (size.width * 0.5 - horizontalOffset) / scale, (ground - size.height * 0.45) / scale)),
            left: -horizontalOffset / scale, right: (size.width - horizontalOffset) / scale,
            sun: SIMD2((sun.x - horizontalOffset) / scale, (ground - sun.y) / scale))
    }

    private var birdPose: AutumnBirdPose? {
        guard let flight = birdFlight,
              let calm = flight.sample(at: elapsedTime, frame: frame, stage: birdStage, wind: .zero,
                                       reduceMotion: reduceMotion) else { return nil }
        let air = birdPlan?.air(at: SIMD2(calm.position.x, calm.position.y), seconds: elapsedTime) ?? .zero
        return flight.sample(at: elapsedTime, frame: frame, stage: birdStage,
                             wind: air, reduceMotion: reduceMotion)
    }

    @ViewBuilder private func bird(behindTree: Bool) -> some View {
        if let pose = birdPose {
            AutumnOrigamiBirdLayer(pose: pose, stage: birdStage, scale: scale,
                offset: horizontalOffset, ground: ground, sunlight: tuning.sunIntensity,
                backlight: tuning.backlight, behindTree: behindTree)
        }
    }

    private var scale: Double { min(size.width / 900, size.height * 0.72 / 800) }
    private var horizontalOffset: Double { (size.width - 740 * scale) * 0.5 }
    private var ground: Double { size.height * 0.86 }
    private var sun: CGPoint { CGPoint(x: size.width * 0.77, y: size.height * (0.34 + 0.52 * progress)) }
    private var sunRadius: Double { min(size.width, size.height) * 0.09 }
    private var displayFrame: AutumnBranchFrame { reduceMotion ? AutumnCanopy.frame() : frame }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if includesAtmosphere {
                SunriseSkyView(uniforms: SunriseUniforms(
                    viewport: SIMD4(Float(size.width), Float(size.height), Float(sun.x), Float(sun.y)),
                    story: SIMD4(Float(progress), Float(ground), Float(sunRadius), 0),
                    optics: SIMD4(Float(0.24 - progress * 0.26), Float(tuning.sunIntensity), 0, 0)),
                    autumnSky: true)
            } else {
                Color(red: 0.15, green: 0.20, blue: 0.28)
            }
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

            bird(behindTree: true)
            Ellipse().fill(Color.black.opacity(0.13))
                .frame(width: 380 * scale, height: 38 * scale)
                .blur(radius: 12 * scale)
                .position(point(345, -9))
            canopyLeaves(front: false)
            branch
            treeBark
            if let pose = birdPose {
                let anchor = AutumnOrigamiFlight.perch(in: displayFrame)
                let contact = max(0, 1 - simd_distance(pose.position, anchor) / 18)
                Ellipse().fill(Color.black.opacity(0.30 * contact))
                    .frame(width: 25 * scale, height: 7 * scale)
                    .blur(radius: 1.2 * scale)
                    .position(point(anchor.x + 4, anchor.y - 2))
                    .mask(treePath.fill(.white))
            }
            canopyLeaves(front: true)
            if let pose = deerPose {
                AutumnOrigamiDeerLayer(pose:pose,scale:scale,offset:horizontalOffset,ground:ground,
                    sun:SIMD2((sun.x-horizontalOffset)/scale,(ground-sun.y)/scale),tuning:tuning)
                canopyLeaves(front:true,foregroundDeerLeaves:true)
            }
            bird(behindTree: false)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .accessibilityHidden(true)
    }

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: horizontalOffset + x * scale, y: ground - y * scale)
    }

    private func image(_ name: String) -> Image {
        if let image = AutumnArtworkCache.shared.image(named: name) {
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

    private var groundPath: Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: ground - 26 * scale))
            path.addCurve(to: CGPoint(x: size.width, y: ground - 28 * scale),
                control1: CGPoint(x: size.width * 0.35, y: ground - 42 * scale),
                control2: CGPoint(x: size.width * 0.62, y: ground - 6 * scale))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height))
            path.closeSubpath()
        }
    }

    private var groundPaper: some View {
        groundPath
            .fill(Color(red: 0.57, green: 0.39, blue: 0.30))
            .overlay {
                Image("NeutralPaperGrainV1").resizable().blendMode(.softLight).opacity(0.40)
                    .mask(groundPath.fill(.white))
            }
    }

    private func canopyPaper(_ artwork: Int, shadow: Bool = false) -> some View {
        let name = ["leaf-maple-yellow", "leaf-maple-orange", "leaf-maple-red"][artwork]
        let pigment = [Color(red: 0.94, green: 0.67, blue: 0.26),
                       Color(red: 0.87, green: 0.38, blue: 0.21),
                       Color(red: 0.66, green: 0.24, blue: 0.29)][artwork]
        return (shadow ? Color(red: 0.15, green: 0.11, blue: 0.23) : pigment)
            .overlay { image(name).resizable().saturation(0).blendMode(.multiply).opacity(shadow ? 0 : 0.30) }
            .overlay { Image("NeutralPaperGrainV1").resizable().blendMode(.softLight).opacity(shadow ? 0 : 0.35) }
            .mask { image(name).resizable() }
            .frame(width: AutumnBranchLeafGeometry.width, height: AutumnBranchLeafGeometry.height)
            .compositingGroup()
    }

    /// Three reusable paper symbols, transformed per leaf. Avoid hundreds of live
    /// SwiftUI texture/mask stacks while retaining individual poses and lighting.
    private func canopyLeaves(front: Bool, foregroundDeerLeaves: Bool = false) -> some View {
        Canvas { context, _ in
            let deer = deerPose
            for source in frame.leaves {
                let leaf = deerAdjustedLeaf(renderLeaf(source), pose:deer)
                let isFront = leaf.phase != .attached || leaf.id % 4 != 0
                guard front == isFront, let paper = context.resolveSymbol(id: leaf.artwork) else { continue }
                if let deer, leaf.phase == .landed || leaf.phase == .settled {
                    let near = leaf.groundLevel < deer.ground
                    if foregroundDeerLeaves != near { continue }
                } else if foregroundDeerLeaves { continue }
                let center = point(leaf.x, leaf.y)
                if leaf.phase != .attached, let silhouette = context.resolveSymbol(id: leaf.artwork + 3) {
                    let shadow = leaf.groundShadow(sunX: (sun.x - horizontalOffset) / scale,
                        sunHeight: (ground - sun.y) / scale)
                    var shade = context
                    let height = max(0, leaf.y - leaf.groundLevel)
                    shade.opacity = 0.18 + 0.22 * (1 - min(1, height / 600))
                    shade.addFilter(.blur(radius: (1 + height * 0.015 * tuning.shadowSoftness) * scale))
                    shade.translateBy(x: horizontalOffset + shadow.x * scale, y: ground - leaf.groundLevel * scale + 0.5 * scale)
                    shade.scaleBy(x: scale * leaf.size, y: scale * leaf.size * shadow.verticalScale)
                    shade.rotate(by: .radians(-leaf.angle))
                    shade.scaleBy(x: cos(leaf.turn), y: 1)
                    shade.draw(silhouette, at: .zero)
                }
                let direction = simd_normalize(SIMD3<Double>(sun.x-center.x, center.y-sun.y, 280*scale))
                let unfolded = SIMD3<Double>(sin(leaf.turn)*cos(leaf.angle), sin(leaf.turn)*sin(leaf.angle), cos(leaf.turn))
                let normal = SIMD3<Double>(unfolded.x,
                    unfolded.y*cos(leaf.groundTilt)+unfolded.z*sin(leaf.groundTilt),
                    unfolded.z*cos(leaf.groundTilt)-unfolded.y*sin(leaf.groundTilt))
                let facing = max(0, simd_dot(normal, direction))
                var ink = context
                ink.addFilter(.brightness(((0.40 + 0.60*facing)*tuning.sunIntensity - 0.7)*0.22
                    + tuning.backlight*(1-facing)*0.07))
                if !front { ink.addFilter(.brightness(-0.08)) }
                if leaf.phase == .attached {
                    ink.addFilter(.shadow(color: .black.opacity(0.14), radius: 0.7 * scale,
                        x: -0.8 * scale, y: 1.2 * scale))
                }
                ink.translateBy(x: center.x, y: center.y)
                ink.scaleBy(x: scale * leaf.size, y: scale * leaf.size * cos(leaf.groundTilt))
                ink.rotate(by: .radians(-leaf.angle))
                ink.scaleBy(x: cos(leaf.turn), y: 1)
                ink.draw(paper, at: .zero)
            }
        } symbols: {
            ForEach(0..<3, id: \.self) { index in
                canopyPaper(index).tag(index)
                canopyPaper(index, shadow: true).tag(index + 3)
            }
        }
        .allowsHitTesting(false)
    }

    private var treePath: Path {
        let pose = displayFrame
        var path = Path()
        // Root flare is seated on the same receiver as fallen leaves.
        path.move(to: point(274, -3))
        path.addCurve(to: point(338, 71), control1: point(308, 3), control2: point(337, 38))
        path.addLine(to: point(369, 70))
        path.addCurve(to: point(426, -4), control1: point(373, 33), control2: point(397, 5))
        path.addQuadCurve(to: point(350, 2), control: point(391, -1))
        path.addQuadCurve(to: point(274, -3), control: point(316, -6))
        path.closeSubpath()
        for (index, curve) in pose.canopyCurves.enumerated() {
            let limb = AutumnCanopy.limbs[index]
            if index > 0 {
                let center = point(curve.start.x, curve.start.y)
                let radius = limb.width * scale * 0.49
                path.addEllipse(in: CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2))
            }
            var left: [CGPoint] = [], right: [CGPoint] = []
            for step in 0...18 {
                let t = Double(step)/18
                let center = curve.point(t), tangent = curve.tangent(t)
                let length = max(0.001, hypot(tangent.x, tangent.y))
                let normal = SIMD2(-tangent.y, tangent.x)/length
                let halfWidth = (limb.tipWidth + (limb.width-limb.tipWidth)*pow(1-t, 1.15))*0.5
                let a = center + normal*halfWidth, b = center - normal*halfWidth
                left.append(point(a.x, a.y)); right.append(point(b.x, b.y))
            }
            path.move(to: left[0])
            for vertex in left.dropFirst() { path.addLine(to: vertex) }
            for vertex in right.reversed() { path.addLine(to: vertex) }
            path.closeSubpath()
        }
        for id in AutumnCanopy.shoots.indices {
            let joint = AutumnCanopy.joint(id: id, curves: pose.canopyCurves)
            let start = point(joint.root.x, joint.root.y), end = point(joint.tip.x, joint.tip.y)
            let control = CGPoint(x: (start.x+end.x)*0.5-2*scale, y: (start.y+end.y)*0.5)
            path.move(to: CGPoint(x: start.x-scale, y: start.y))
            path.addQuadCurve(to: end, control: control)
            path.addQuadCurve(to: CGPoint(x: start.x+scale, y: start.y),
                control: CGPoint(x: control.x+scale, y: control.y))
            path.closeSubpath()
        }
        return path
    }

    private var treeBark: some View {
        Canvas { context, _ in
            for (index, curve) in displayFrame.canopyCurves.enumerated() where index < 16 {
                let width = AutumnCanopy.limbs[index].width
                guard width > 7 else { continue }
                for side in [-0.22, 0.18] {
                    var line = Path()
                    for step in 0...20 {
                        let t = Double(step)/20
                        let center = curve.point(t), tangent = curve.tangent(t)
                        let n = SIMD2(-tangent.y, tangent.x)/max(0.001, hypot(tangent.x,tangent.y))
                        let offset = n * width * side * (1-t*0.7)
                        let p = point(center.x+offset.x, center.y+offset.y)
                        if step == 0 { line.move(to: p) } else { line.addLine(to: p) }
                    }
                    context.stroke(line, with: .color(side < 0 ? .black.opacity(0.09) : Color(red: 0.93, green: 0.70, blue: 0.44).opacity(0.12)),
                        style: StrokeStyle(lineWidth: max(0.6, width*0.05)*scale, lineCap: .round))
                }
            }
        }.allowsHitTesting(false)
    }

    private var branch: some View {
        Color(red: 0.27, green: 0.19, blue: 0.23)
            .overlay { Image("NeutralPaperGrainV1").resizable().blendMode(.softLight).opacity(0.6) }
            .mask(treePath.fill(.white))
            .shadow(color: .black.opacity(0.12), radius: 2 * scale, x: -3 * scale, y: 4 * scale)
    }

    func renderLeaf(_ leaf: AutumnBranchLeaf) -> AutumnBranchLeaf {
        guard reduceMotion else { return leaf }
        var result = leaf
        if leaf.phase == .attached {
            let anchor = AutumnBranchSimulation.attachment(id: leaf.id, frame: displayFrame)
            result.x = anchor.x; result.y = anchor.y; result.angle = anchor.angle; result.turn = 0
        } else {
            // A stable resting pose after release: neither falling drift nor later
            // ground gusts should become one-second jumps under Reduce Motion.
            let anchor = AutumnBranchSimulation.attachment(id: leaf.id, frame: displayFrame)
            result.x = anchor.x
            result.y = leaf.groundLevel
            result.angle = anchor.angle
            result.vx = 0; result.vy = 0; result.omega = 0
            result.turn = 0; result.groundTilt = AutumnGroundContact.flatTilt
            result.contactTime = 2
        }
        return result
    }

    /// A bounded paper-bed response, sampled from the same encounter. It does not
    /// feed impulses back into the approved aerodynamic simulation or move leaves
    /// off their ground plane. Both paper and its contact shadow use the result.
    private func deerAdjustedLeaf(_ leaf: AutumnBranchLeaf, pose:AutumnDeerEncounter.Pose?) -> AutumnBranchLeaf {
        guard !reduceMotion, let pose, leaf.phase == .landed || leaf.phase == .settled else { return leaf }
        var result=leaf
        let depth=exp(-pow((leaf.groundLevel-pose.ground)/17,2))
        let nearby=exp(-pow((leaf.x-pose.root)/(65*pose.size),4))
        let direction=leaf.x < pose.root ? -1.0 : 1.0
        let touched=pose.footprints.reduce(0.0) { strongest,footprint in
            let dx=(leaf.x-footprint.point.x)/(15*pose.size)
            let dy=(leaf.groundLevel-pose.ground-footprint.point.z*0.22)/10
            guard abs(dx)<3,abs(dy)<3 else { return strongest }
            return max(strongest,exp(-dx*dx-dy*dy)*AutumnDeerEncounter.smooth(footprint.age/0.35))
        }
        let scatter=(AutumnCanopy.variation(leaf.id+712)-0.5)*9*touched
        result.x += depth*(scatter + direction*8*nearby*pose.settled)
        result.angle += depth*0.045*direction*nearby*pose.settled
        return result
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
            let plan = cache.plan(duration: session?.duration.timeInterval ?? 120,
                seed: session?.randomSeed ?? 42, record: record)
            let frame = cache.frame(plan: plan, time: time)
            VStack(alignment: .leading, spacing: 5) {
                Text("Wind: \(plan.wind(at: 300, seconds: time), specifier: "%.2f") m/s")
                Text("Leaves: \(frame.leaves.filter { $0.phase == .attached }.count) attached · \(frame.leaves.filter { $0.phase == .falling }.count) falling · \(frame.leaves.filter { $0.phase == .settled }.count) settled")
                Text("Breezes: \(plan.gusts.count) · fixed simulation 120 Hz")
                Text("Automatic birds: \(plan.encounters.birds.count) · quiet decisions: \(plan.encounters.decisions.filter { $0.kind == .quiet }.count)")
                Text("Session seed: \(plan.seed)")
                ForEach(Array(plan.encounters.decisions.filter { $0.time >= time }.prefix(4).enumerated()), id: \.offset) { _, decision in
                    Text("\(decision.time, specifier: "%.1f")s · \(decision.kind.rawValue)")
                }
                Text("Guaranteed deer: \(plan.deerEnding.startTime, specifier: "%.1f")s · closing breeze: \(plan.encounters.breezeTimes.last ?? 0, specifier: "%.1f")s")
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
    let onBird: () -> Void
    let onDeer: (Double?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AutumnDeerStudyControls(study:Binding(get:{record.deer ?? AutumnDeerStudy()},
                set:{record.deer=$0}),session:session,onStudy:onDeer)
            Divider()
            AutumnBirdStudyControls(study: Binding(
                get: { record.bird ?? AutumnBirdStudy() },
                set: { record.bird = $0 }), session: session, onFly: onBird)
            Divider()
            Text("Canopy · light · breeze").font(.caption.weight(.semibold))
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
