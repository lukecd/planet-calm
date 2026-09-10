import SwiftUI
import simd

struct AutumnOrigamiDeerLayer: View {
  let pose: AutumnDeerEncounter.Pose
  let scale: Double
  let offset: Double
  let ground: Double
  let sun: SIMD2<Double>
  let tuning: AutumnBranchTuning

  var body: some View {
    Canvas { context, _ in
      func world(_ vertex: SIMD3<Double>) -> SIMD3<Double> {
        let p = vertex * pose.size
        return p + SIMD3(pose.root, pose.ground, 0)
      }
      func screen(_ p: SIMD3<Double>) -> CGPoint {
        CGPoint(x: offset + (p.x + p.z * 0.16) * scale, y: ground - (p.y + p.z * 0.22) * scale)
      }
      func path(_ vertices: [SIMD3<Double>]) -> Path {
        var p = Path()
        guard let first = vertices.first else { return p }
        p.move(to: screen(first))
        for v in vertices.dropFirst() { p.addLine(to: screen(v)) }
        p.closeSubpath()
        return p
      }
      var faces: [(AutumnDeerMesh.Face, [SIMD3<Double>])] = []
      for face in AutumnDeerMesh.faces(pose) {
        faces.append((face, face.vertices.map(world)))
      }
      func depth(_ vertices: [SIMD3<Double>]) -> Double {
        vertices.reduce(0.0) { $0 + $1.z } / Double(vertices.count)
      }
      faces.sort { depth($0.1) > depth($1.1) }
      context.opacity = pose.opacity
      var shadow = Path()
      for (_, vertices) in faces {
        shadow.addPath(
          path(
            vertices.map { p in
              let height = max(0, p.y - pose.ground)
              let direction = min(0.8, max(-0.8, (p.x - sun.x) / 600))
              return SIMD3(p.x + height * direction, pose.ground, p.z - height * 0.35)
            }))
      }
      var cast = context
      cast.addFilter(.blur(radius: (2 + 3 * (1 - pose.settled)) * scale))
      cast.fill(shadow, with: .color(Color(red: 0.20, green: 0.15, blue: 0.20).opacity(0.20)))
      // The broad contact patch grows as the chest and haunches take weight.
      let contact = screen(SIMD3(pose.root, pose.ground - 1, 0))
      var shade = context
      shade.addFilter(.blur(radius: 1.5 * scale))
      shade.fill(
        Path(
          ellipseIn: CGRect(
            x: contact.x - 55 * scale * pose.size,
            y: contact.y - 4 * scale, width: 110 * scale * pose.size, height: 10 * scale)),
        with: .color(.black.opacity(0.19 * pose.settled)))
      let paper = context.resolve(Image("NeutralPaperGrainV1"))
      for (face, vertices) in faces {
        let shape = path(vertices)
        let a = vertices[0]
        let b = vertices[1]
        let c = vertices[2]
        let cross = simd_cross(b - a, c - a)
        guard simd_length(cross) > 0.001 else { continue }
        var normal = simd_normalize(cross)
        if normal.z > 0 { normal = -normal }
        let center = vertices.reduce(SIMD3<Double>.zero, +) / Double(vertices.count)
        let light = simd_normalize(SIMD3(sun.x, sun.y, -280) - center)
        let facing = simd_dot(normal, light)
        let diffuse = max(0, facing)
        let brightness =
          0.80 + 0.25 * diffuse * tuning.sunIntensity + 0.08 * max(0, -facing) * tuning.backlight
        let rgb = face.pigment * brightness + SIMD3(0.09, 0.035, 0.005) * diffuse
        context.fill(
          shape, with: .color(Color(red: min(1, rgb.x), green: min(1, rgb.y), blue: min(1, rgb.z))))
        if face.grain {
          // Material coordinates follow the panel, not the screen.
          let localA = face.vertices[0]
          let edge = face.vertices[1] - localA
          let across = face.vertices[2] - localA
          let length = simd_length(edge)
          let u = simd_dot(across, edge) / length
          let v = simd_length(simd_cross(edge, across)) / length
          let pa = screen(a)
          let pb = screen(b)
          let pc = screen(c)
          if v > 0.001 {
            let ax = (pb.x - pa.x) / length
            let ay = (pb.y - pa.y) / length
            var grain = context
            grain.clip(to: shape)
            grain.opacity *= 0.23
            grain.blendMode = .softLight
            grain.concatenate(
              CGAffineTransform(
                a: ax, b: ay, c: (pc.x - pa.x - ax * u) / v,
                d: (pc.y - pa.y - ay * u) / v, tx: pa.x, ty: pa.y))
            grain.draw(paper, in: CGRect(x: -192, y: -192, width: 384, height: 384))
          }
          context.stroke(
            shape, with: .color(Color(red: 0.98, green: 0.83, blue: 0.64).opacity(0.15)),
            style: StrokeStyle(lineWidth: max(0.2, 0.45 * scale), lineJoin: .round))
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

#if DEBUG
  struct AutumnDeerStudyControls: View {
    @Binding var study: AutumnDeerStudy
    let session: PerformanceSession?
    let onStudy: (Double?) -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text("Deer · a sheltered ending").font(.caption.weight(.semibold))
        Group {
          slider("Deer size", value: $study.tuning.size, range: 0.75...1.2)
          slider("Walking speed", value: $study.tuning.speed, range: 0.7...1.3)
          slider("Settling seconds", value: $study.tuning.settlingSeconds, range: 6...12)
          slider("Resting position", value: $study.tuning.restingPosition, range: 0.56...0.76)
        }.disabled(session != nil && study.encounter == nil)
        Button("Play deer ending") { onStudy(nil) }
          .buttonStyle(.borderedProminent).tint(PlanetFocusPalette.warmYellow)
          .foregroundStyle(PlanetFocusPalette.canvasInk)
          .accessibilityIdentifier("autumnDeerPlay")
        HStack {
          Button("Walk") { onStudy(8) }.accessibilityIdentifier("autumnDeerWalk")
          Button("Stand") { onStudy(prototype.walkDuration + 1) }
          Button("Lower") { onStudy(prototype.walkDuration + prototype.standingDuration + 3) }
          Button("Rest") { onStudy(prototype.duration + 2) }.accessibilityIdentifier(
            "autumnDeerRest")
        }.buttonStyle(.bordered)
        Text(
          "Pose buttons pause the shared development runner. Play captures these values for a fresh ending study."
        )
        .font(.caption2).foregroundStyle(.secondary)
      }
    }
    private var prototype: AutumnDeerEncounter { .init(startTime: 0, tuning: study.tuning) }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>)
      -> some View
    {
      VStack {
        HStack {
          Text(title)
          Spacer()
          Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
        }
        Slider(value: value, in: range).accessibilityLabel(title)
      }.font(.caption)
    }
  }
#endif
