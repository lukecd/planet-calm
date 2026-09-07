import Foundation

struct LeafTerrainConfiguration: Codable, Equatable, Sendable {
    let assetID: String
    let sourceSHA256: String
    let sourcePixelWidth: Int
    let sourcePixelHeight: Int
    let alphaThreshold: Int
    let renderedHeightFraction: Double
    /// Source-texture coordinates, x rightward and y upward from its bottom edge.
    let surface: [NormalizedPhysicsPoint]
    let friction: Double
    let restitution: Double
    let quietLinearSpeedMetersPerSecond: Double
    let quietAngularSpeedRadiansPerSecond: Double
    let quietContactSeconds: Double
    let maximumTrialSeconds: Double

    static let bundled: Result<Self, Error> = Result {
        guard let url = Bundle.main.url(forResource: "gate-5-terrain", withExtension: "json",
                                        subdirectory: "LeafAerodynamicsV1") else {
            throw LeafGravityLabConfigurationError.missingResource
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)).validated()
    }

    func validated() throws -> Self {
        let positive = [renderedHeightFraction, quietLinearSpeedMetersPerSecond,
                        quietAngularSpeedRadiansPerSecond, quietContactSeconds, maximumTrialSeconds]
        guard !assetID.isEmpty, sourceSHA256.count == 64, sourcePixelWidth > 1, sourcePixelHeight > 1,
              (1...255).contains(alphaThreshold), positive.allSatisfy({ $0.isFinite && $0 > 0 }),
              renderedHeightFraction < 0.5, (0...1).contains(friction), (0...0.1).contains(restitution),
              maximumTrialSeconds > quietContactSeconds, surface.count >= 2,
              surface.first?.x == 0, surface.last?.x == 1,
              surface.allSatisfy({ (0...1).contains($0.x) && (0...1).contains($0.y) }),
              zip(surface, surface.dropFirst()).allSatisfy({ $0.x < $1.x }) else {
            throw LeafGravityLabConfigurationError.invalidResource
        }
        return self
    }

    func surfaceHeight(at normalizedX: Double) -> Double {
        guard let first = surface.first, let last = surface.last else { return 0 }
        if normalizedX <= first.x { return first.y }
        for (a, b) in zip(surface, surface.dropFirst()) where normalizedX <= b.x {
            return a.y + (b.y - a.y) * (normalizedX - a.x) / (b.x - a.x)
        }
        return last.y
    }
}

/// A supported, quiet dwell is required. Elapsed trial time alone never settles a leaf.
struct LeafSettlingTracker: Equatable, Sendable {
    private(set) var quietSeconds = 0.0
    private(set) var hasTouchedGround = false
    private(set) var isSettled = false

    mutating func update(touchingGround: Bool, linearSpeed: Double, angularSpeed: Double,
                         deltaTime: Double, configuration: LeafTerrainConfiguration) -> Bool {
        guard !isSettled else { return false }
        hasTouchedGround = hasTouchedGround || touchingGround
        guard touchingGround, linearSpeed.isFinite, angularSpeed.isFinite, deltaTime.isFinite,
              linearSpeed >= 0, linearSpeed <= configuration.quietLinearSpeedMetersPerSecond,
              abs(angularSpeed) <= configuration.quietAngularSpeedRadiansPerSecond, deltaTime >= 0 else {
            quietSeconds = 0
            return false
        }
        quietSeconds += deltaTime
        isSettled = quietSeconds >= configuration.quietContactSeconds
        return isSettled
    }
}
