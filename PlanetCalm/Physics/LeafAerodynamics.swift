import Foundation

struct PassiveFlutterConfiguration: Codable, Equatable, Sendable {
    enum LiftResponse: String, Codable, Sendable {
        case sinTwoAlpha
    }

    /// Dimensionless bound: Cl = maximumLiftCoefficient * sin(2 * alpha).
    let maximumLiftCoefficient: Double
    let liftResponse: LiftResponse
    /// Local chord orientation relative to the sprite's +x axis (radians).
    let chordAngleRadians: Double
    /// Edge-on area / broadside area. A(alpha)/A0 = e + (1-e)*abs(sin(alpha)).
    let edgeOnAreaFraction: Double
    /// Offset from the sprite origin, in fractions of full leaf width and height.
    let centerOfPressure: NormalizedPhysicsPoint
    /// Dimensionless resistance multiplier. Torque opposes omega, never drives it.
    let angularResistanceCoefficient: Double

    func validated() throws -> Self {
        guard maximumLiftCoefficient.isFinite, maximumLiftCoefficient >= 0,
              chordAngleRadians.isFinite,
              edgeOnAreaFraction.isFinite, (0...1).contains(edgeOnAreaFraction),
              (-0.5...0.5).contains(centerOfPressure.x),
              (-0.5...0.5).contains(centerOfPressure.y),
              angularResistanceCoefficient.isFinite, angularResistanceCoefficient >= 0 else {
            throw LeafGravityLabConfigurationError.invalidFlutter
        }
        return self
    }
}

struct LeafAerodynamicSample: Equatable, Sendable {
    let centerOfMass: PhysicsVector
    let centerOfPressure: PhysicsVector
    /// External air minus the rigid body's velocity at the pressure point (pt/s).
    let relativeAirVelocity: PhysicsVector
    let angleOfAttack: Double
    let liftCoefficient: Double
    let projectedAreaFraction: Double
    let dragForceNewtons: PhysicsVector
    let liftForceNewtons: PhysicsVector
    let resistanceTorqueNewtonMeters: Double

    var forceNewtons: PhysicsVector {
        PhysicsVector(x: dragForceNewtons.x + liftForceNewtons.x,
                      y: dragForceNewtons.y + liftForceNewtons.y)
    }
}

struct LeafForceApplication: Equatable, Sendable {
    let forceNewtons: PhysicsVector
    let scenePoint: PhysicsVector
}

struct StillAirDragConfiguration: Codable, Equatable, Sendable {
    /// Air density in kilograms per cubic meter (kg/m^3).
    let airDensityKilogramsPerCubicMeter: Double
    /// Dimensionless bluff-body drag coefficient.
    let dragCoefficient: Double
    /// Broadside leaf area in square meters (m^2).
    let referenceAreaSquareMeters: Double
    /// Fixed Gate 2 fraction of broadside area exposed to the airflow (0...1).
    let projectedAreaFraction: Double
    /// SpriteKit scene points representing one physical meter (pt/m).
    let scenePointsPerMeter: Double
    /// Seconds of velocity represented by the debug velocity vector (s).
    let debugVelocityVectorSeconds: Double
    /// Scene points represented by one Newton in the debug force vector (pt/N).
    let debugForceVectorPointsPerNewton: Double

    func validated() throws -> StillAirDragConfiguration {
        guard airDensityKilogramsPerCubicMeter.isFinite,
              airDensityKilogramsPerCubicMeter > 0,
              dragCoefficient.isFinite,
              dragCoefficient > 0,
              referenceAreaSquareMeters.isFinite,
              referenceAreaSquareMeters > 0,
              projectedAreaFraction.isFinite,
              (0...1).contains(projectedAreaFraction),
              projectedAreaFraction > 0,
              scenePointsPerMeter.isFinite,
              scenePointsPerMeter > 0,
              debugVelocityVectorSeconds.isFinite,
              debugVelocityVectorSeconds > 0,
              debugForceVectorPointsPerNewton.isFinite,
              debugForceVectorPointsPerNewton > 0 else {
            throw LeafGravityLabConfigurationError.invalidDrag
        }
        return self
    }
}

enum LeafAerodynamics {
    /// Two equal/opposite forces: zero net translation, resisting moment only.
    static func resistanceCouple(
        torqueNewtonMeters: Double, center: PhysicsVector,
        radiusScenePoints: Double, rotation: Double, scenePointsPerMeter: Double
    ) -> [LeafForceApplication] {
        guard radiusScenePoints > 0, scenePointsPerMeter > 0 else { return [] }
        let force = torqueNewtonMeters / (2 * radiusScenePoints / scenePointsPerMeter)
        return [-1.0, 1.0].map { sign in
            LeafForceApplication(
                forceNewtons: PhysicsVector(x: -sign * force * sin(rotation), y: sign * force * cos(rotation)),
                scenePoint: PhysicsVector(x: center.x + sign * radiusScenePoints * cos(rotation),
                                          y: center.y + sign * radiusScenePoints * sin(rotation))
            )
        }
    }

    /// Gate 3 is a quasi-steady, two-dimensional plate approximation, not CFD.
    /// All inputs are instantaneous rigid-body state; there is no clock or seed.
    static func stillAirFlutter(
        leafVelocity: PhysicsVector,
        angularVelocity: Double,
        rotation: Double,
        position: PhysicsVector,
        leafSize: PhysicsVector,
        centerOfMass: NormalizedPhysicsPoint,
        drag: StillAirDragConfiguration,
        flutter: PassiveFlutterConfiguration
    ) -> LeafAerodynamicSample {
        sample(airVelocity: .zero, leafVelocity: leafVelocity, angularVelocity: angularVelocity,
               rotation: rotation, position: position, leafSize: leafSize, centerOfMass: centerOfMass,
               drag: drag, flutter: flutter)
    }

    /// Quasi-steady passive response to an external airflow sample (scene pt/s).
    static func sample(
        airVelocity: PhysicsVector, leafVelocity: PhysicsVector, angularVelocity: Double,
        rotation: Double, position: PhysicsVector, leafSize: PhysicsVector,
        centerOfMass: NormalizedPhysicsPoint, drag: StillAirDragConfiguration,
        flutter: PassiveFlutterConfiguration
    ) -> LeafAerodynamicSample {
        let massPoint = scenePoint(local: centerOfMass, size: leafSize,
                                   rotation: rotation, position: position)
        let pressurePoint = scenePoint(local: flutter.centerOfPressure, size: leafSize,
                                       rotation: rotation, position: position)
        let arm = PhysicsVector(x: pressurePoint.x - massPoint.x,
                                y: pressurePoint.y - massPoint.y)
        // v(point) = v(COM) + omega cross r. Drag dissipates relative motion;
        // moving external air can supply energy. Lift is perpendicular to airflow.
        let airflow = PhysicsVector(x: airVelocity.x - leafVelocity.x + angularVelocity * arm.y,
                                    y: airVelocity.y - leafVelocity.y - angularVelocity * arm.x)
        let speed = hypot(airflow.x, airflow.y)
        let alpha = speed > 0 ? atan2(airflow.y, airflow.x) - rotation - flutter.chordAngleRadians : 0
        let coefficient = liftCoefficient(angleOfAttack: alpha, configuration: flutter)
        let areaFraction = flutter.edgeOnAreaFraction
            + (1 - flutter.edgeOnAreaFraction) * abs(sin(alpha))
        let pressureArea = 0.5 * drag.airDensityKilogramsPerCubicMeter
            * pow(speed / drag.scenePointsPerMeter, 2) * drag.referenceAreaSquareMeters
        let direction = speed > 0 ? PhysicsVector(x: airflow.x / speed, y: airflow.y / speed) : .zero
        let dragMagnitude = pressureArea * drag.dragCoefficient * areaFraction
        let liftMagnitude = pressureArea * coefficient
        // Integrating quadratic resistance over a uniform span gives r^3 / 4.
        // This extra broad-span resistance opposes existing rotation only.
        let radiusMeters = leafSize.x / (2 * drag.scenePointsPerMeter)
        let resistance = -0.5 * drag.airDensityKilogramsPerCubicMeter
            * drag.dragCoefficient * drag.referenceAreaSquareMeters
            * flutter.angularResistanceCoefficient * pow(radiusMeters, 3) / 4
            * angularVelocity * abs(angularVelocity)
        return LeafAerodynamicSample(
            centerOfMass: massPoint, centerOfPressure: pressurePoint,
            relativeAirVelocity: airflow, angleOfAttack: alpha,
            liftCoefficient: coefficient, projectedAreaFraction: areaFraction,
            dragForceNewtons: PhysicsVector(x: direction.x * dragMagnitude, y: direction.y * dragMagnitude),
            liftForceNewtons: PhysicsVector(x: -direction.y * liftMagnitude, y: direction.x * liftMagnitude),
            resistanceTorqueNewtonMeters: resistance
        )
    }

    static func liftCoefficient(angleOfAttack: Double, configuration: PassiveFlutterConfiguration) -> Double {
        switch configuration.liftResponse {
        case .sinTwoAlpha:
            configuration.maximumLiftCoefficient * sin(2 * angleOfAttack)
        }
    }

    static func scenePoint(
        local: NormalizedPhysicsPoint, size: PhysicsVector,
        rotation: Double, position: PhysicsVector
    ) -> PhysicsVector {
        let x = local.x * size.x
        let y = local.y * size.y
        return PhysicsVector(x: position.x + x * cos(rotation) - y * sin(rotation),
                             y: position.y + x * sin(rotation) + y * cos(rotation))
    }

    /// Uniform-density polygon centroid. Works with either winding order.
    static func centerOfMass(hull: [NormalizedPhysicsPoint]) -> NormalizedPhysicsPoint {
        var twiceArea = 0.0
        var xMoment = 0.0
        var yMoment = 0.0
        for index in hull.indices {
            let a = hull[index]
            let b = hull[(index + 1) % hull.count]
            let cross = a.x * b.y - b.x * a.y
            twiceArea += cross
            xMoment += (a.x + b.x) * cross
            yMoment += (a.y + b.y) * cross
        }
        guard abs(twiceArea) > .ulpOfOne else { return NormalizedPhysicsPoint(x: 0, y: 0) }
        return NormalizedPhysicsPoint(x: xMoment / (3 * twiceArea), y: yMoment / (3 * twiceArea))
    }

    /// Calculates quadratic drag in still air. The result is in Newtons.
    ///
    /// `leafVelocity` is in scene points per second. Still air makes the relative
    /// airflow `zero - leafVelocity`; drag follows that airflow, so it opposes the
    /// leaf's motion. Gate 2 uses a fixed projected-area fraction because lift and
    /// orientation-dependent aerodynamics do not begin until Gate 3.
    static func stillAirDrag(
        leafVelocity: PhysicsVector,
        configuration: StillAirDragConfiguration
    ) -> PhysicsVector {
        let relativeAirVelocity = PhysicsVector(
            x: -leafVelocity.x,
            y: -leafVelocity.y
        )
        return drag(
            relativeAirVelocity: relativeAirVelocity,
            configuration: configuration
        )
    }

    private static func drag(
        relativeAirVelocity: PhysicsVector,
        configuration: StillAirDragConfiguration
    ) -> PhysicsVector {
        let speedInScenePoints = hypot(
            relativeAirVelocity.x,
            relativeAirVelocity.y
        )
        guard speedInScenePoints > 0 else { return .zero }

        let speedMetersPerSecond = speedInScenePoints / configuration.scenePointsPerMeter
        let projectedArea = configuration.referenceAreaSquareMeters
            * configuration.projectedAreaFraction
        let forceMagnitude = 0.5
            * configuration.airDensityKilogramsPerCubicMeter
            * configuration.dragCoefficient
            * projectedArea
            * speedMetersPerSecond
            * speedMetersPerSecond
        let inverseSpeed = 1 / speedInScenePoints

        return PhysicsVector(
            x: relativeAirVelocity.x * inverseSpeed * forceMagnitude,
            y: relativeAirVelocity.y * inverseSpeed * forceMagnitude
        )
    }
}
