import HealthKit
import XCTest
@testable import PlanetCalm

/// Opt-in verification against a simulator's real HealthKit store. Never writes
/// fixtures to a physical device or the app's session ledger.
final class HealthKitIntegrationTests: XCTestCase {
    @MainActor
    func testRepeatSaveCreatesOneMindfulSample() async throws {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["PLANET_FOCUS_HEALTH_INTEGRATION_TEST"] == "1" else {
            throw XCTSkip("Explicit simulator HealthKit validation only.")
        }
        let writer = HealthKitSessionWriter()
        try XCTSkipUnless(writer.isAvailable(), "HealthKit is unavailable in this simulator.")
        try await writer.requestAuthorization()
        XCTAssertEqual(writer.authorizationStatus(), .sharingAuthorized)
        guard writer.authorizationStatus() == .sharingAuthorized else { return }

        var attempt = SessionAttempt(
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: Date.now.addingTimeInterval(-600),
            randomSeed: 1,
            healthWriteRequested: true
        )
        attempt.outcome = .completed
        attempt.terminalAt = attempt.scheduledEndAt
        attempt.creditedSeconds = attempt.plannedSeconds

        // A fresh writer models a process restarting after Health accepted the
        // sample but before the local success marker was committed.
        try await writer.save(attempt)
        try await HealthKitSessionWriter().save(attempt)

        let store = HKHealthStore()
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: [attempt.healthSyncID.uuidString]
        )
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.mindfulSession), predicate: predicate)],
            sortDescriptors: []
        )
        let samples = try await query.result(for: store)
        XCTAssertEqual(samples.count, 1)
        if let sample = samples.first {
            XCTAssertEqual(sample.startDate.timeIntervalSince1970, attempt.startedAt.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(sample.endDate.timeIntervalSince1970, attempt.scheduledEndAt.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(sample.value, HKCategoryValue.notApplicable.rawValue)
            XCTAssertEqual(sample.metadata?[HKMetadataKeySyncVersion] as? Int, 1)
        }
        // Remove only this test's unique sample from the simulator store.
        if !samples.isEmpty { try await store.delete(samples) }
        #else
        throw XCTSkip("Never writes synthetic Health data on a physical device.")
        #endif
    }
}
