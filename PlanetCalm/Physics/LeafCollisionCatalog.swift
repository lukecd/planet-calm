import Foundation

/// Artwork-derived, counterclockwise convex polygons in centered texture coordinates.
/// Gate 5 only: approved single-leaf and open-sky baselines retain their original hull.
struct LeafCollisionCatalog: Codable, Equatable, Sendable {
    let alphaThreshold: Int
    /// Native SpriteKit contact separation measured in scene points, not texture pixels.
    /// Inset the collision core so its effective contact envelope meets visible pixels.
    let contactInsetPoints: Double
    let shapes: [LeafCollisionShape]

    static let bundled: Result<Self, Error> = Result {
        guard let url = Bundle.main.url(forResource: "gate-5-leaf-colliders-v2", withExtension: "json",
                                        subdirectory: "LeafAerodynamicsV1") else {
            throw LeafGravityLabConfigurationError.missingResource
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)).validated()
    }

    func validated() throws -> Self {
        guard (1...255).contains(alphaThreshold), contactInsetPoints.isFinite,
              (0...3).contains(contactInsetPoints), !shapes.isEmpty,
              Set(shapes.map(\.assetID)).count == shapes.count else {
            throw LeafGravityLabConfigurationError.invalidResource
        }
        for shape in shapes { try shape.validate() }
        return self
    }

    func shape(for assetID: String) throws -> LeafCollisionShape {
        guard let shape = shapes.first(where: { $0.assetID == assetID }) else {
            throw LeafGravityLabConfigurationError.missingResource
        }
        return shape
    }
}

struct LeafCollisionShape: Codable, Equatable, Sendable {
    let assetID: String
    let sourceSHA256: String
    let sourcePixelWidth: Int
    let sourcePixelHeight: Int
    let hull: [NormalizedPhysicsPoint]

    /// Clip against inward-offset edge lines in scene space. Unlike scaling a hull,
    /// this compensates a fixed contact margin equally for every edge/leaf size.
    func collisionHull(width: Double, height: Double, inset: Double) throws -> [NormalizedPhysicsPoint] {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              inset.isFinite, inset >= 0 else { throw LeafGravityLabConfigurationError.invalidResource }
        try validate()
        let points = hull.map { PhysicsVector(x: $0.x * width, y: $0.y * height) }
        struct Edge { let p: PhysicsVector; let d: PhysicsVector }
        let edges = points.indices.map { i -> Edge in
            let p = points[i], q = points[(i + 1) % points.count]
            let d = PhysicsVector(x: q.x - p.x, y: q.y - p.y)
            let length = hypot(d.x, d.y)
            return Edge(p: .init(x: p.x - d.y / length * inset, y: p.y + d.x / length * inset), d: d)
        }
        var clipped = points
        for edge in edges {
            func distance(_ p: PhysicsVector) -> Double {
                (edge.d.x * (p.y - edge.p.y) - edge.d.y * (p.x - edge.p.x)) / hypot(edge.d.x, edge.d.y)
            }
            let input = clipped
            clipped = []
            guard var previous = input.last else { throw LeafGravityLabConfigurationError.invalidResource }
            for current in input {
                let a = distance(previous), b = distance(current)
                if (a >= 0) != (b >= 0) {
                    let t = a / (a - b)
                    clipped.append(.init(x: previous.x + t * (current.x - previous.x),
                                         y: previous.y + t * (current.y - previous.y)))
                }
                if b >= 0 { clipped.append(current) }
                previous = current
            }
        }
        guard clipped.count >= 3 else { throw LeafGravityLabConfigurationError.invalidResource }
        return clipped.map { .init(x: $0.x / width, y: $0.y / height) }
    }

    func validate() throws {
        guard !assetID.isEmpty, sourceSHA256.count == 64,
              sourceSHA256.allSatisfy(\.isHexDigit), sourcePixelWidth > 1, sourcePixelHeight > 1,
              (3...32).contains(hull.count), Set(hull.map { "\($0.x),\($0.y)" }).count == hull.count,
              hull.allSatisfy({ $0.x.isFinite && $0.y.isFinite
                  && (-0.5...0.5).contains($0.x) && (-0.5...0.5).contains($0.y) }) else {
            throw LeafGravityLabConfigurationError.invalidResource
        }
        // Every non-edge vertex must be strictly left of every directed edge.
        // This rejects clockwise, concave, degenerate, and self-intersecting inputs.
        for i in hull.indices {
            let a = hull[i], b = hull[(i + 1) % hull.count]
            for j in hull.indices where j != i && j != (i + 1) % hull.count {
                let c = hull[j]
                guard (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) > 0 else {
                    throw LeafGravityLabConfigurationError.invalidResource
                }
            }
        }
    }
}
