import XCTest
@testable import PlanetCalm

final class SessionHistorySyncPersistenceTests: XCTestCase {
    func testDeletedHistoryKeepsItsAccountOwnershipAfterRestart() async throws {
        let persistence = SyncLedgerTestPersistence()
        let accountA = SessionHistoryAccountKey(userRecordName: "account-A")
        let accountB = SessionHistoryAccountKey(userRecordName: "account-B")
        let first = SessionLedgerStore(persistence: persistence)
        try await first.prepareHistoryAccount(accountA)
        let attempt = SessionAttempt(storyID: "autumn", plannedSeconds: 300, startedAt: .now, randomSeed: 1)
        _ = try await first.create(attempt)
        _ = try await first.terminalize(id: attempt.id, event: .completed)
        try await first.delete(ids: [attempt.id])

        let restarted = SessionLedgerStore(persistence: persistence)
        try await restarted.prepareHistoryAccount(accountB)
        _ = try await restarted.claimUnownedHistory(for: accountB)
        let b = try await restarted.exportTerminalHistory(for: accountB)
        let a = try await restarted.exportTerminalHistory(for: accountA)
        XCTAssertTrue(b.records.isEmpty)
        XCTAssertTrue(b.deletedAttemptIDs.isEmpty)
        XCTAssertEqual(a.deletedAttemptIDs, [attempt.id])

        let stale = TerminalSessionHistoryRecord(
            id: attempt.id, storyID: attempt.storyID, plannedSeconds: attempt.plannedSeconds,
            startedAt: attempt.startedAt, scheduledEndAt: attempt.scheduledEndAt,
            timeZoneIdentifier: attempt.timeZoneIdentifier, calendarIdentifier: attempt.calendarIdentifier,
            randomSeed: attempt.randomSeed, outcome: .completed,
            terminalAt: attempt.scheduledEndAt, observedAt: nil, creditedSeconds: attempt.plannedSeconds
        )
        let rejected = try await restarted.mergeTerminalHistory(.init(records: [stale], deletedAttemptIDs: []), for: accountB)
        XCTAssertEqual(rejected.rejectedOwnershipIDs, [attempt.id])
        let attempts = try await restarted.attempts()
        XCTAssertTrue(attempts.isEmpty)
    }

    func testFailedAccountTransitionDoesNotReassignNewLocalSessions() async throws {
        let persistence = SyncLedgerTestPersistence()
        let accountA = SessionHistoryAccountKey(userRecordName: "account-A")
        let accountB = SessionHistoryAccountKey(userRecordName: "account-B")
        let ledger = SessionLedgerStore(persistence: persistence)
        try await ledger.prepareHistoryAccount(accountA)
        await persistence.failNextSave()
        do {
            try await ledger.prepareHistoryAccount(accountB)
            XCTFail("A failed account save must not be treated as successful.")
        } catch SyncLedgerTestPersistence.SaveFailure.requested {}

        let attempt = SessionAttempt(storyID: "autumn", plannedSeconds: 300, startedAt: .now, randomSeed: 2)
        _ = try await ledger.create(attempt)
        _ = try await ledger.terminalize(id: attempt.id, event: .completed)
        let restarted = SessionLedgerStore(persistence: persistence)
        let a = try await restarted.exportTerminalHistory(for: accountA)
        let b = try await restarted.exportTerminalHistory(for: accountB)
        XCTAssertEqual(a.records.map(\.id), [attempt.id])
        XCTAssertTrue(b.records.isEmpty)
    }
}

private actor SyncLedgerTestPersistence: SessionLedgerPersistence {
    enum SaveFailure: Error { case requested }
    private var data: Data?
    private var shouldFail = false
    func load() -> Data? { data }
    func failNextSave() { shouldFail = true }
    func save(_ data: Data) throws {
        if shouldFail {
            shouldFail = false
            throw SaveFailure.requested
        }
        self.data = data
    }
}
