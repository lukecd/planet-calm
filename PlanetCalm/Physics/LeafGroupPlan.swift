import Foundation

struct LeafGroupConfiguration: Codable, Equatable, Sendable {
    let count: Int
    let assetIDs: [String]
    let linearScale: WindParameterRange
    let arealDensityScale: WindParameterRange
    let pressureX: WindParameterRange
    let pressureY: WindParameterRange
    let releaseX: WindParameterRange
    let releaseY: WindParameterRange
    let releaseSeconds: WindParameterRange
    let initialTiltRadians: WindParameterRange
    let initialVelocityX: WindParameterRange
    let initialVelocityY: WindParameterRange

    static let bundled: Result<Self, Error> = Result {
        guard let url = Bundle.main.url(forResource: "early-group", withExtension: "json",
                                        subdirectory: "LeafAerodynamicsV1") else {
            throw LeafGravityLabConfigurationError.missingResource
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)).validated()
    }

    func validated() throws -> Self {
        let ranges = [linearScale, arealDensityScale, pressureX, pressureY, releaseX, releaseY,
                      releaseSeconds, initialTiltRadians, initialVelocityX, initialVelocityY]
        guard count == 6, !assetIDs.isEmpty, assetIDs.allSatisfy({ !$0.isEmpty }),
              ranges.allSatisfy(\.isValid), linearScale.minimum > 0,
              arealDensityScale.minimum > 0, releaseSeconds.minimum >= 0,
              releaseX.minimum >= 0, releaseX.maximum <= 1,
              releaseY.minimum >= 0, releaseY.maximum <= 1,
              pressureX.minimum >= -0.5, pressureX.maximum <= 0.5,
              pressureY.minimum >= -0.5, pressureY.maximum <= 0.5 else {
            throw LeafGravityLabConfigurationError.invalidResource
        }
        return self
    }
}

struct LeafGroupMember: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let assetID: String
    let linearScale: Double
    let arealDensityScale: Double
    let massKilograms: Double
    let areaSquareMeters: Double
    let centerOfPressure: NormalizedPhysicsPoint
    let releasePoint: NormalizedPhysicsPoint
    let releaseSeconds: Double
    let initialTiltRadians: Double
    let initialVelocityMetersPerSecond: PhysicsVector
    /// No identity-based spin: rotation must emerge from forces after release.
    var initialAngularVelocity: Double { 0 }

    func drag(from reference: StillAirDragConfiguration) -> StillAirDragConfiguration {
        StillAirDragConfiguration(airDensityKilogramsPerCubicMeter: reference.airDensityKilogramsPerCubicMeter,
            dragCoefficient: reference.dragCoefficient, referenceAreaSquareMeters: areaSquareMeters,
            projectedAreaFraction: reference.projectedAreaFraction, scenePointsPerMeter: reference.scenePointsPerMeter,
            debugVelocityVectorSeconds: reference.debugVelocityVectorSeconds,
            debugForceVectorPointsPerNewton: reference.debugForceVectorPointsPerNewton)
    }

    func flutter(from reference: PassiveFlutterConfiguration) -> PassiveFlutterConfiguration {
        PassiveFlutterConfiguration(maximumLiftCoefficient: reference.maximumLiftCoefficient,
            liftResponse: reference.liftResponse, chordAngleRadians: reference.chordAngleRadians,
            edgeOnAreaFraction: reference.edgeOnAreaFraction, centerOfPressure: centerOfPressure,
            angularResistanceCoefficient: reference.angularResistanceCoefficient)
    }
}

/// Immutable replay plan; no frame-time RNG and no per-leaf wind or flight path.
struct LeafGroupPlan: Codable, Equatable, Sendable {
    let seed: UInt64
    let members: [LeafGroupMember]

    init(configuration: LeafGroupConfiguration, reference: LeafGravityLabConfiguration, seed: UInt64) throws {
        _ = try configuration.validated()
        _ = try reference.validated()
        guard let drag = reference.stillAirDrag, reference.passiveFlutter != nil, reference.wind != nil else {
            throw LeafGravityLabConfigurationError.invalidWind
        }
        self.seed = seed
        // Separate deterministic streams: changing the population never changes the air.
        var random = SeededRandomNumberGenerator(seed: seed ^ StableSeed.hash("leaf-group-properties-v1"))
        var strata = Array(0..<configuration.count)
        for index in stride(from: strata.count - 1, through: 1, by: -1) {
            strata.swapAt(index, random.integer(in: 0...index))
        }
        members = (0..<configuration.count).map { index in
            let quantile = (Double(strata[index]) + random.unitInterval()) / Double(configuration.count)
            let scale = configuration.linearScale.minimum
                + quantile * (configuration.linearScale.maximum - configuration.linearScale.minimum)
            let density = configuration.arealDensityScale.draw(using: &random)
            let xQuantile = (Double(index) + random.value(in: 0.2...0.8)) / Double(configuration.count)
            return LeafGroupMember(id: index + 1,
                assetID: configuration.assetIDs[random.integer(in: 0...(configuration.assetIDs.count - 1))],
                linearScale: scale, arealDensityScale: density,
                massKilograms: reference.mass * scale * scale * density,
                areaSquareMeters: drag.referenceAreaSquareMeters * scale * scale,
                centerOfPressure: NormalizedPhysicsPoint(x: configuration.pressureX.draw(using: &random),
                                                        y: configuration.pressureY.draw(using: &random)),
                releasePoint: NormalizedPhysicsPoint(
                    x: configuration.releaseX.minimum + xQuantile * (configuration.releaseX.maximum - configuration.releaseX.minimum),
                    y: configuration.releaseY.draw(using: &random)),
                releaseSeconds: configuration.releaseSeconds.draw(using: &random),
                initialTiltRadians: configuration.initialTiltRadians.draw(using: &random),
                initialVelocityMetersPerSecond: PhysicsVector(x: configuration.initialVelocityX.draw(using: &random),
                                                             y: configuration.initialVelocityY.draw(using: &random)))
        }
    }

    func wind(reference: WindFieldConfiguration) -> WindField {
        WindField(configuration: reference, seed: seed, mode: .gust)
    }
}
