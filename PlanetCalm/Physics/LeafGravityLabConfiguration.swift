import Foundation

struct PhysicsVector: Codable, Equatable, Sendable {
    let x: Double
    let y: Double

    static let zero = PhysicsVector(x: 0, y: 0)
}

struct NormalizedPhysicsPoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
}

struct LeafGravityLabConfiguration: Codable, Equatable, Sendable {
    let gravity: PhysicsVector
    let mass: Double
    let assetID: String
    let leafWidthFraction: Double
    let releasePoint: NormalizedPhysicsPoint
    let collisionHull: [NormalizedPhysicsPoint]
    let offscreenMarginFraction: Double
    let diagnosticsUpdateInterval: TimeInterval
    let stillAirDrag: StillAirDragConfiguration?
    var passiveFlutter: PassiveFlutterConfiguration? = nil
    var wind: WindFieldConfiguration? = nil

    static let gate1Bundled = bundled(resource: "gate-1-gravity")
    static let gate2Bundled = bundled(resource: "gate-2-still-air-drag")
    static let gate3Bundled = bundled(resource: "gate-3-passive-flutter")
    static let gate4Bundled = bundled(resource: "gate-4-external-wind")

    private static func bundled(
        resource: String
    ) -> Result<LeafGravityLabConfiguration, LeafGravityLabConfigurationError> {
        do {
            guard let url = Bundle.main.url(
                forResource: resource,
                withExtension: "json",
                subdirectory: "LeafAerodynamicsV1"
            ) else {
                throw LeafGravityLabConfigurationError.missingResource
            }
            let configuration = try JSONDecoder().decode(
                LeafGravityLabConfiguration.self,
                from: Data(contentsOf: url)
            )
            return .success(try configuration.validated())
        } catch let error as LeafGravityLabConfigurationError {
            return .failure(error)
        } catch {
            return .failure(.invalidResource)
        }
    }

    func validated() throws -> LeafGravityLabConfiguration {
        guard gravity.x == 0, gravity.y < 0 else {
            throw LeafGravityLabConfigurationError.invalidGravity
        }
        guard mass > 0 else {
            throw LeafGravityLabConfigurationError.invalidMass
        }
        guard !assetID.isEmpty else {
            throw LeafGravityLabConfigurationError.invalidAssetID
        }
        guard (0...0.5).contains(leafWidthFraction), leafWidthFraction > 0 else {
            throw LeafGravityLabConfigurationError.invalidLeafSize
        }
        guard Self.isUnitPoint(releasePoint) else {
            throw LeafGravityLabConfigurationError.invalidReleasePoint
        }
        guard collisionHull.count >= 3,
              collisionHull.allSatisfy({ (-0.5...0.5).contains($0.x) && (-0.5...0.5).contains($0.y) }) else {
            throw LeafGravityLabConfigurationError.invalidCollisionHull
        }
        guard offscreenMarginFraction >= 0,
              diagnosticsUpdateInterval > 0 else {
            throw LeafGravityLabConfigurationError.invalidSimulationLimit
        }
        _ = try stillAirDrag?.validated()
        if let passiveFlutter {
            guard stillAirDrag != nil else {
                throw LeafGravityLabConfigurationError.invalidFlutter
            }
            _ = try passiveFlutter.validated()
        }
        if let wind {
            guard passiveFlutter != nil else { throw LeafGravityLabConfigurationError.invalidWind }
            _ = try wind.validated()
        }
        return self
    }

    private static func isUnitPoint(_ point: NormalizedPhysicsPoint) -> Bool {
        (0...1).contains(point.x) && (0...1).contains(point.y)
    }
}

enum LeafGravityLabConfigurationError: LocalizedError, Sendable {
    case missingResource
    case invalidResource
    case invalidGravity
    case invalidMass
    case invalidAssetID
    case invalidLeafSize
    case invalidReleasePoint
    case invalidCollisionHull
    case invalidSimulationLimit
    case invalidDrag
    case invalidFlutter
    case invalidWind

    var errorDescription: String? {
        switch self {
        case .missingResource:
            "Missing a LeafAerodynamicsV1 gate configuration"
        case .invalidResource:
            "Could not decode the leaf aerodynamics gate configuration"
        case .invalidGravity:
            "Gate 1 requires vertical, downward gravity"
        case .invalidMass:
            "Gate 1 leaf mass must be positive"
        case .invalidAssetID:
            "Gate 1 requires a leaf asset identifier"
        case .invalidLeafSize:
            "Gate 1 leaf size is outside its normalized bounds"
        case .invalidReleasePoint:
            "Gate 1 release point must be normalized"
        case .invalidCollisionHull:
            "Gate 1 collision hull must be a normalized polygon"
        case .invalidSimulationLimit:
            "Leaf lab simulation limits are invalid"
        case .invalidDrag:
            "Gate 2 still-air drag assumptions must be positive and finite"
        case .invalidFlutter:
            "Gate 3 requires valid lift, pressure-point, and rotational-resistance assumptions plus drag"
        case .invalidWind:
            "Gate 4 requires passive flutter and finite, ordered wind/gust bounds with positive attack and decay"
        }
    }
}
