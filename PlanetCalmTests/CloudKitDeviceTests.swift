import CloudKit
import XCTest
@testable import PlanetCalm

/// Explicit device-only validation. Ordinary test runs skip this test. The
/// selected phase and unique zone are supplied in a temporary .xctestrun file.
/// Fixtures use their own ledger, sync state directory and CloudKit zone.
final class CloudKitDeviceTests: XCTestCase {
    private let phoneSessionID = UUID(uuidString: "E01EFD60-A821-43B6-8763-B60C88F3E001")!
    private let runningSessionID = UUID(uuidString: "E01EFD60-A821-43B6-8763-B60C88F3E002")!
    private let padSessionID = UUID(uuidString: "E01EFD60-A821-43B6-8763-B60C88F3E003")!

    @MainActor
    func testPrivateCloudHistoryRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let phase = environment["PLANET_FOCUS_CLOUD_TEST_PHASE"],
              let zone = environment["PLANET_FOCUS_CLOUD_TEST_ZONE"],
              zone.hasPrefix("PlanetFocusValidation") else {
            throw XCTSkip("Requires an explicitly selected physical-device CloudKit test phase.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("Run CloudKit round-trip validation on the paired physical devices.")
        #else
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "CloudKitValidation/\(zone)", directoryHint: .isDirectory)
        let ledger = SessionLedgerStore(persistence: FileSessionLedgerPersistence(
            fileURL: directory.appending(path: "ledger.json")
        ))
        let stateStore = SessionHistoryAccountStateStore(
            persistence: FileSessionHistoryAccountStatePersistence(directory: directory.appending(path: "sync"))
        )
        let sync = SessionHistorySyncCoordinator(ledger: ledger, accountStateStore: stateStore, zoneName: zone)
        _ = try await ledger.prepare()

        switch phase {
        case "probe-account":
            await sync.prepare()
            XCTAssertNil(sync.lastErrorDescription)
            XCTAssertEqual(sync.status, .disabled)
            XCTAssertFalse(sync.isEnabled)
        case "upload-phone":
            let existing = try await ledger.attempts()
            if !existing.contains(where: { $0.id == phoneSessionID }) {
                let attempt = SessionAttempt(
                    id: phoneSessionID, storyID: Story.autumnTree.rawValue,
                    plannedSeconds: 300, startedAt: Date(timeIntervalSince1970: 1_789_000_000), randomSeed: 123
                )
                _ = try await ledger.create(attempt)
                _ = try await ledger.terminalize(id: attempt.id, event: .completed)
                _ = try await ledger.create(SessionAttempt(
                    id: runningSessionID, storyID: Story.contemporaryLotus.rawValue,
                    plannedSeconds: 300, startedAt: Date(timeIntervalSince1970: 1_789_001_000), randomSeed: 124
                ))
            }
            await sync.prepare()
            await sync.enable()
            await sync.syncNow()
            assertSynced(sync)
            let exported = try await ledger.exportTerminalHistory()
            XCTAssertEqual(exported.records.map(\.id), [phoneSessionID])

        case "receive-automatic-pad":
            let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
            XCTAssertTrue(modes.contains("remote-notification"))
            await sync.prepare()
            await sync.enable()
            assertSynced(sync)
            let initial = try await ledger.attempts()
            XCTAssertFalse(initial.contains { $0.id == phoneSessionID }, "Start this receiver before uploading on the phone.")

            // No manual fetch after setup: the other device uploads while this
            // receiver waits for CKSyncEngine's automatic delivery. This checks
            // automatic reception, not iOS suspension/wake scheduling.
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            var received = false
            while ContinuousClock.now < deadline {
                if try await ledger.attempts().contains(where: { $0.id == phoneSessionID }) {
                    received = true
                    break
                }
                try await Task.sleep(for: .seconds(1))
            }
            XCTAssertTrue(received, "The peer session should arrive without Sync now.")
            let attempts = try await ledger.attempts()
            XCTAssertEqual(attempts.filter { $0.id == phoneSessionID }.count, 1)
            XCTAssertFalse(attempts.contains { $0.id == runningSessionID })
            XCTAssertNil(sync.lastErrorDescription)

        case "receive-delete-pad":
            await sync.prepare()
            await sync.enable()
            await sync.syncNow()
            assertSynced(sync)
            var attempts = try await ledger.attempts()
            let imported = try XCTUnwrap(attempts.first { $0.id == phoneSessionID })
            XCTAssertEqual(imported.outcome, .completed)
            XCTAssertEqual(imported.creditedSeconds, 300)
            XCTAssertFalse(imported.healthWriteRequested)
            XCTAssertEqual(imported.healthSyncState, .notRequested)
            XCTAssertFalse(attempts.contains { $0.id == runningSessionID })

            await sync.syncNow()
            attempts = try await ledger.attempts()
            XCTAssertEqual(attempts.filter { $0.id == phoneSessionID }.count, 1)

            // Opt-out creates an offline-equivalent local change window without
            // changing the owner's device networking or Apple Account.
            await sync.disable()
            XCTAssertFalse(sync.isEnabled)
            let padAttempt = SessionAttempt(
                id: padSessionID, storyID: Story.contemporaryLotus.rawValue,
                plannedSeconds: 600, startedAt: Date(timeIntervalSince1970: 1_789_002_000), randomSeed: 125
            )
            _ = try await ledger.create(padAttempt)
            _ = try await ledger.terminalize(id: padAttempt.id, event: .cancelled(occurredAt: padAttempt.startedAt.addingTimeInterval(20)))
            try await ledger.delete(ids: [phoneSessionID])
            await sync.historyDidChange()
            XCTAssertFalse(sync.isEnabled)
            await sync.enable()
            await sync.syncNow()
            assertSynced(sync)

        case "catch-up-phone", "verify-pad":
            // Phone still has its old local copy from before the iPad deletion.
            await sync.prepare()
            await sync.enable()
            await sync.historyDidChange()
            await sync.syncNow()
            assertSynced(sync)
            let attempts = try await ledger.attempts()
            XCTAssertFalse(attempts.contains { $0.id == phoneSessionID })
            let padAttempt = try XCTUnwrap(attempts.first { $0.id == padSessionID })
            XCTAssertEqual(padAttempt.outcome, .cancelled)
            XCTAssertEqual(padAttempt.creditedSeconds, 0)
            let exported = try await ledger.exportTerminalHistory()
            XCTAssertTrue(exported.deletedAttemptIDs.contains(phoneSessionID))
            XCTAssertEqual(exported.records.map(\.id), [padSessionID])
        default:
            XCTFail("Unknown explicitly selected CloudKit phase: \(phase)")
        }
        await sync.disable()
        #endif
    }

    @MainActor
    private func assertSynced(_ sync: SessionHistorySyncCoordinator, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(sync.isEnabled, file: file, line: line)
        XCTAssertNil(sync.lastErrorDescription, file: file, line: line)
        XCTAssertNotNil(sync.lastSuccessfulSyncAt, file: file, line: line)
        XCTAssertEqual(sync.pendingUploadCount, 0, file: file, line: line)
    }
}
