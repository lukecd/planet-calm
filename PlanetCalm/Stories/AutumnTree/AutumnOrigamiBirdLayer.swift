import SwiftUI
import simd

/// Two depth passes let the native tree occlude distant paper faces. Within
/// each pass triangles are painter-sorted in camera space, including both wings.
struct AutumnOrigamiBirdLayer: View {
    let pose: AutumnBirdPose
    let stage: AutumnBirdStage
    let scale: Double
    let offset: Double
    let ground: Double
    let sunlight: Double
    let backlight: Double
    let behindTree: Bool

    var body: some View {
        Canvas { context, _ in
            let mesh = AutumnOrigamiMesh.faces(wing: pose.wingAngle, tipFold: pose.tipFold, legFold: pose.legFold)
            let paper = context.resolve(Image("NeutralPaperGrainV1"))
            var faces: [(AutumnOrigamiMesh.Face, SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)] = []
            for face in mesh {
                faces.append((face, pose.transform(face.a), pose.transform(face.b), pose.transform(face.c)))
            }
            faces.sort { left, right in
                let leftDepth: Double = left.1.z + left.2.z + left.3.z
                let rightDepth: Double = right.1.z + right.2.z + right.3.z
                return leftDepth > rightDepth
            }
            func screen(_ p: SIMD3<Double>) -> CGPoint {
                let q = stage.camera.project(p)
                return CGPoint(x: offset + q.x * scale, y: ground - q.y * scale)
            }
            for (face, a, b, c) in faces {
                let center = (a + b + c) / 3
                let vertices = AutumnOrigamiMesh.clipped([a, b, c], behindTree: behindTree)
                guard vertices.count >= 3 else { continue }
                let pa = screen(a), pb = screen(b), pc = screen(c)
                let area = (pb.x-pa.x)*(pc.y-pa.y) - (pb.y-pa.y)*(pc.x-pa.x)
                guard abs(area) > 0.025 else { continue }
                var path = Path()
                path.move(to: screen(vertices[0]))
                for vertex in vertices.dropFirst() { path.addLine(to: screen(vertex)) }
                path.closeSubpath()
                var normal = simd_normalize(simd_cross(b-a, c-a))
                let eye = SIMD3(stage.camera.center.x, stage.camera.center.y, -AutumnBirdCamera.focalLength)
                if simd_dot(normal, eye-center) < 0 { normal = -normal }
                let light = simd_normalize(SIMD3(stage.sun.x, stage.sun.y, 650)-center)
                let facing = simd_dot(normal, light)
                let value = min(1.08, (0.72 + 0.20*max(0, facing)*sunlight
                    + 0.14*max(0, -facing)*backlight) * face.ink)
                let warm = max(0, facing) * 0.06
                context.fill(path, with: .color(Color(
                    red: min(1, value*1.09 + warm),
                    green: min(1, value*1.02),
                    blue: min(1, value*0.91 - warm))))
                // Affine projection of each rigid triangular panel's local paper.
                // It moves with the fold rather than sliding across the silhouette.
                let edge = face.b-face.a, across = face.c-face.a
                let length = simd_length(edge)
                let u = simd_dot(across, edge/length)
                let v = simd_length(simd_cross(edge, across))/length
                if v > 0.001 {
                    let ax = (pb.x-pa.x)/length, ay = (pb.y-pa.y)/length
                    var grain = context
                    grain.clip(to: path)
                    grain.opacity = 0.20
                    grain.blendMode = .softLight
                    grain.concatenate(CGAffineTransform(a: ax, b: ay,
                        c: (pc.x-pa.x-ax*u)/v, d: (pc.y-pa.y-ay*u)/v, tx: pa.x, ty: pa.y))
                    grain.draw(paper, in: CGRect(x: -128, y: -128, width: 256, height: 256))
                }
                var edges = Path()
                edges.move(to: pa); edges.addLine(to: pb); edges.addLine(to: pc); edges.closeSubpath()
                var edgeContext = context
                edgeContext.clip(to: path)
                edgeContext.stroke(edges, with: .color(Color(red: 0.39, green: 0.28, blue: 0.30).opacity(0.18)),
                    style: StrokeStyle(lineWidth: max(0.25, 0.38*scale), lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if DEBUG
struct AutumnBirdStudyControls: View {
    @Binding var study: AutumnBirdStudy
    let session: PerformanceSession?
    let onFly: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Origami visitor").font(.caption.weight(.semibold))
            Text("Approach · perch · circle the sun").font(.caption2).foregroundStyle(.secondary)
            slider("Flight speed", value: $study.tuning.speed, range: 0.5...1.5)
            slider("Wingbeats / sec", value: $study.tuning.wingbeat, range: 0.8...2.5)
            slider("Flight depth", value: $study.tuning.depth, range: 0...1.5)
            slider("Bird wind response", value: $study.tuning.windResponse, range: 0...2)
            slider("Perch seconds", value: $study.tuning.perchSeconds, range: 3...12)
            Button(action: onFly) {
                Label("Fly origami bird", systemImage: "paperplane")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(PlanetFocusPalette.warmYellow)
            .foregroundStyle(PlanetFocusPalette.canvasInk)
            .accessibilityIdentifier("autumnBirdFly")
            Text("Changes apply to the next flight. Starts/resumes the runner; near the end, starts a fresh run.")
                .font(.caption2).foregroundStyle(.secondary)
            if let flight = study.flight, let session {
                TimelineView(.periodic(from: .now, by: 0.25)) { tick in
                    let elapsed = session.elapsedTime(at: tick.date) - flight.startTime
                    Text(elapsed >= flight.duration ? "Flight complete" :
                        elapsed < flight.approachDuration ? "Approaching branch" :
                        elapsed < flight.approachDuration + flight.perchDuration ? "Perched" : "Returning toward sun")
                        .accessibilityIdentifier("autumnBirdPhase")
                        .font(.caption.monospaced())
                }
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title); Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2))).monospacedDigit()
            }
            Slider(value: value, in: range).tint(PlanetFocusPalette.warmYellow).accessibilityLabel(title)
        }.font(.caption)
    }
}
#endif
