import Foundation
import HealthKit
import XCTest
@testable import PlanetCalm

final class HealthSessionCoordinatorTests: XCTestCase {
    @MainActor
    func testWritesOnlyCompletedLocalOptInSessions() async throws {
        let ledger = SessionLedgerStore(persistence: HealthMemoryPersistence())
        let completed = try await makeCompletedAttempt(ledger: ledger, requested: true, offset: 0)
        let noOptIn = try await makeCompletedAttempt(ledger: ledger, requested: false, offset: 1_000)
        let cancelled = SessionAttempt(
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: Date(timeIntervalSince1970: 2_000),
            randomSeed: 3,
            healthWriteRequested: true
        )
        _ = try await ledger.create(cancelled)
        _ = try await ledger.terminalize(id: cancelled.id, event: .cancelled(occurredAt: cancelled.startedAt))
        let distracted = SessionAttempt(
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: Date(timeIntervalSince1970: 3_000),
            randomSeed: 4,
            healthWriteRequested: true
        )
        _ = try await ledger.create(distracted)
        _ = try await ledger.terminalize(
            id: distracted.id,
            event: .distracted(occurredAt: distracted.startedAt, observedAt: distracted.startedAt)
        )
        let interrupted = SessionAttempt(
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: Date(timeIntervalSince1970: 4_000),
            randomSeed: 5,
            healthWriteRequested: true
        )
        _ = try await ledger.create(interrupted)
        _ = try await ledger.terminalize(id: interrupted.id, event: .interrupted(observedAt: interrupted.startedAt))
        let imported = TerminalSessionHistoryRecord(
            id: UUID(), storyID: Story.autumnTree.rawValue, plannedSeconds: 300,
            startedAt: Date(timeIntervalSince1970: 5_000),
            scheduledEndAt: Date(timeIntervalSince1970: 5_300),
            timeZoneIdentifier: "UTC", calendarIdentifier: "gregorian", randomSeed: 6,
            outcome: .completed, terminalAt: Date(timeIntervalSince1970: 5_300),
            observedAt: nil, creditedSeconds: 300
        )
        _ = try await ledger.mergeTerminalHistory(.init(records: [imported], deletedAttemptIDs: []))

        let writer = HealthWriterSpy()
        let coordinator = HealthSessionCoordinator(ledger: ledger, writer: writer, defaults: makeDefaults())
        await coordinator.enable()
        await coordinator.writePendingSessions()

        XCTAssertEqual(writer.savedIDs, [completed.healthSyncID])
        XCTAssertFalse(writer.savedIDs.contains(noOptIn.healthSyncID))
        XCTAssertFalse(writer.savedIDs.contains(cancelled.healthSyncID))
        XCTAssertFalse(writer.savedAttempts.contains(where: { $0.id == imported.id }))
        let completedState = try await healthState(for: completed.id, ledger: ledger)
        XCTAssertEqual(completedState, .succeeded)
    }

    @MainActor
    func testRetryRetainsIdentifierVersionAndOriginalInterval() async throws {
        let ledger = SessionLedgerStore(persistence: HealthMemoryPersistence())
        let attempt = try await makeCompletedAttempt(ledger: ledger, requested: true, offset: 8_000)
        let writer = HealthWriterSpy(failSaves: 1)
        let coordinator = HealthSessionCoordinator(ledger: ledger, writer: writer, defaults: makeDefaults())
        await coordinator.enable()

        await coordinator.writePendingSessions()
        let failedState = try await healthState(for: attempt.id, ledger: ledger)
        XCTAssertEqual(failedState, .failed)
        await coordinator.writePendingSessions()

        XCTAssertEqual(writer.savedAttempts.count, 2)
        XCTAssertEqual(writer.savedAttempts.map(\.healthSyncID), [attempt.healthSyncID, attempt.healthSyncID])
        XCTAssertEqual(writer.savedAttempts.map(\.startedAt), [attempt.startedAt, attempt.startedAt])
        XCTAssertEqual(writer.savedAttempts.map(\.scheduledEndAt), [attempt.scheduledEndAt, attempt.scheduledEndAt])
        let succeededState = try await healthState(for: attempt.id, ledger: ledger)
        XCTAssertEqual(succeededState, .succeeded)
        XCTAssertNil(coordinator.message)
    }

    @MainActor
    func testSucceededStateSurvivesRestartAndDoesNotWriteAgain() async throws {
        let persistence = HealthMemoryPersistence()
        let firstLedger = SessionLedgerStore(persistence: persistence)
        let attempt = try await makeCompletedAttempt(ledger: firstLedger, requested: true, offset: 12_000)
        let defaults = makeDefaults()
        let firstWriter = HealthWriterSpy()
        let first = HealthSessionCoordinator(ledger: firstLedger, writer: firstWriter, defaults: defaults)
        await first.enable()
        await first.writePendingSessions()
        let firstState = try await healthState(for: attempt.id, ledger: firstLedger)
        XCTAssertEqual(firstState, .succeeded)

        let restartedWriter = HealthWriterSpy()
        let restarted = HealthSessionCoordinator(
            ledger: SessionLedgerStore(persistence: persistence),
            writer: restartedWriter,
            defaults: defaults
        )
        await restarted.writePendingSessions()
        XCTAssertTrue(restartedWriter.savedAttempts.isEmpty)
    }

    @MainActor
    func testConcurrentWriteRequestsSaveOneLogicalSample() async throws {
        let ledger = SessionLedgerStore(persistence: HealthMemoryPersistence())
        let attempt = try await makeCompletedAttempt(ledger: ledger, requested: true, offset: 14_000)
        let writer = HealthWriterSpy()
        let coordinator = HealthSessionCoordinator(ledger: ledger, writer: writer, defaults: makeDefaults())
        await coordinator.enable()

        async let first: Void = coordinator.writePendingSessions()
        async let second: Void = coordinator.writePendingSessions()
        _ = await (first, second)

        XCTAssertEqual(writer.savedIDs, [attempt.healthSyncID])
        let state = try await healthState(for: attempt.id, ledger: ledger)
        XCTAssertEqual(state, .succeeded)
    }

    @MainActor
    func testDeniedOrRevokedSharingNeverWrites() async throws {
        let ledger = SessionLedgerStore(persistence: HealthMemoryPersistence())
        _ = try await makeCompletedAttempt(ledger: ledger, requested: true, offset: 16_000)
        let writer = HealthWriterSpy(status: .sharingDenied)
        let coordinator = HealthSessionCoordinator(ledger: ledger, writer: writer, defaults: makeDefaults())
        await coordinator.enable()
        XCTAssertFalse(coordinator.isEnabled)
        XCTAssertTrue(writer.savedAttempts.isEmpty)

        writer.setStatus(.sharingAuthorized)
        await coordinator.enable()
        writer.setStatus(.sharingDenied)
        await coordinator.writePendingSessions()
        XCTAssertTrue(writer.savedAttempts.isEmpty)
        XCTAssertNotNil(coordinator.message)
    }

    @MainActor
    func testDisableDuringAuthorizationWinsAndLeavesPreferenceOff() async throws {
        let writer = HealthWriterSpy(status: .sharingAuthorized)
        let authorizationBarrier = HealthBarrier()
        writer.setAuthorizationBarrier(authorizationBarrier)
        let defaults = makeDefaults()
        let coordinator = HealthSessionCoordinator(
            ledger: SessionLedgerStore(persistence: HealthMemoryPersistence()),
            writer: writer,
            defaults: defaults
        )

        let enabling = Task { @MainActor in await coordinator.enable() }
        await authorizationBarrier.waitUntilEntered()
        await coordinator.disable()
        await authorizationBarrier.release()
        await enabling.value

        XCTAssertFalse(coordinator.isEnabled)
        XCTAssertEqual(defaults.object(forKey: "preferences.health-enabled.v1") as? Bool, false)
    }

    @MainActor
    func testEnableWaitsForLaunchCancellationBeforeRequestingAuthorization() async throws {
        let persistence = HealthSuspendedPersistence()
        let ledger = SessionLedgerStore(persistence: persistence)
        _ = try await makeCompletedAttempt(ledger: ledger, requested: true, offset: 18_000)
        await persistence.suspendNextSave()
        let writer = HealthWriterSpy()
        let coordinator = HealthSessionCoordinator(ledger: ledger, writer: writer, defaults: makeDefaults())

        let preparing = Task { @MainActor in await coordinator.prepare() }
        await persistence.waitUntilSaveIsSuspended()
        let enabling = Task { @MainActor in await coordinator.enable() }
        await Task.yield()
        XCTAssertEqual(writer.requestCount, 0)

        await persistence.resumeSave()
        await preparing.value
        await enabling.value
        XCTAssertEqual(writer.requestCount, 1)
        XCTAssertTrue(coordinator.isEnabled)
    }

    @MainActor
    func testDisableDuringSaveCancelsRemainingJobsAndRecordsAcceptedSave() async throws {
        let ledger = SessionLedgerStore(persistence: HealthMemoryPersistence())
        let first = try await makeCompletedAttempt(ledger: ledger, requested: true, offset: 20_000)
        let second = try await makeCompletedAttempt(ledger: ledger, requested: true, offset: 21_000)
        let writer = HealthWriterSpy()
        let saveBarrier = HealthBarrier()
        writer.setSaveBarrier(saveBarrier)
        let coordinator = HealthSessionCoordinator(ledger: ledger, writer: writer, defaults: makeDefaults())
        await coordinator.enable()

        let writing = Task { @MainActor in await coordinator.writePendingSessions() }
        await saveBarrier.waitUntilEntered()
        await coordinator.disable()
        await saveBarrier.release()
        await writing.value

        XCTAssertEqual(writer.savedIDs, [first.healthSyncID])
        let firstState = try await healthState(for: first.id, ledger: ledger)
        let secondState = try await healthState(for: second.id, ledger: ledger)
        XCTAssertEqual(firstState, .succeeded)
        XCTAssertEqual(secondState, .cancelled)
        await coordinator.enable()
        await coordinator.writePendingSessions()
        XCTAssertEqual(writer.savedIDs, [first.healthSyncID])
    }

    @MainActor
    func testCancellationFailurePersistsBarrierAndRelaunchRetriesIt() async throws {
        let persistence = HealthFailingPersistence()
        let ledger = SessionLedgerStore(persistence: persistence)
        let attempt = try await makeCompletedAttempt(ledger: ledger, requested: true, offset: 24_000)
        let defaults = makeDefaults()
        let coordinator = HealthSessionCoordinator(ledger: ledger, writer: HealthWriterSpy(), defaults: defaults)
        await coordinator.enable()
        await persistence.failWrites()
        await coordinator.disable()

        XCTAssertFalse(coordinator.isEnabled)
        XCTAssertNotNil(coordinator.message)
        XCTAssertEqual(defaults.object(forKey: "preferences.health-cancellation-pending.v1") as? Bool, true)
        let pendingState = try await healthState(for: attempt.id, ledger: ledger)
        XCTAssertEqual(pendingState, .pending)

        await persistence.allowWrites()
        let relaunchedLedger = SessionLedgerStore(persistence: persistence)
        let relaunched = HealthSessionCoordinator(ledger: relaunchedLedger, writer: HealthWriterSpy(), defaults: defaults)
        await relaunched.prepare()

        let cancelledState = try await healthState(for: attempt.id, ledger: relaunchedLedger)
        XCTAssertEqual(cancelledState, .cancelled)
        XCTAssertEqual(defaults.object(forKey: "preferences.health-cancellation-pending.v1") as? Bool, false)
        await relaunched.enable()
        XCTAssertTrue(relaunched.isEnabled)
        let candidates = try await relaunchedLedger.healthWriteCandidates()
        XCTAssertTrue(candidates.isEmpty)
    }

    @MainActor
    func testRestoredCancellationBarrierFailsClosedUntilDurableCleanupSucceeds() async throws {
        let persistence = HealthFailingPersistence()
        let ledger = SessionLedgerStore(persistence: persistence)
        _ = try await makeCompletedAttempt(ledger: ledger, requested: true, offset: 26_000)
        let defaults = makeDefaults()
        defaults.set(true, forKey: "preferences.health-enabled.v1")
        defaults.set(true, forKey: "preferences.health-cancellation-pending.v1")
        await persistence.failWrites()
        let writer = HealthWriterSpy()
        let coordinator = HealthSessionCoordinator(ledger: ledger, writer: writer, defaults: defaults)

        XCTAssertFalse(coordinator.isEnabled)
        XCTAssertFalse(coordinator.shouldRequestWriteForNewSession)
        await coordinator.writePendingSessions()
        XCTAssertTrue(writer.savedAttempts.isEmpty)
        XCTAssertNotNil(coordinator.message)

        await persistence.allowWrites()
        let recoveredLedger = SessionLedgerStore(persistence: persistence)
        let recovered = HealthSessionCoordinator(ledger: recoveredLedger, writer: HealthWriterSpy(), defaults: defaults)
        await recovered.prepare()
        XCTAssertEqual(defaults.object(forKey: "preferences.health-enabled.v1") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "preferences.health-cancellation-pending.v1") as? Bool, false)

        let secondRelaunch = HealthSessionCoordinator(
            ledger: SessionLedgerStore(persistence: persistence), writer: HealthWriterSpy(), defaults: defaults
        )
        XCTAssertFalse(secondRelaunch.isEnabled)
        XCTAssertFalse(secondRelaunch.shouldRequestWriteForNewSession)
    }

    @MainActor
    func testLifecycleCapturesWritePreferenceAtBegin() async throws {
        let persistence = HealthMemoryPersistence()
        let lifecycle = SessionLifecycle(ledger: SessionLedgerStore(persistence: persistence))
        let start = Date(timeIntervalSince1970: 28_000)
        await lifecycle.prepareForLaunch(observedAt: start)
        let runtime = try await lifecycle.begin(
            story: .autumnTree,
            duration: .fiveMinutes,
            healthWriteRequested: true,
            startedAt: start
        )
        let attempts = try await lifecycle.attempts()
        let stored = try XCTUnwrap(attempts.first)
        XCTAssertTrue(stored.healthWriteRequested)
        XCTAssertEqual(stored.healthSyncState, .pending)
        _ = try await lifecycle.cancel(id: runtime.id, at: start)
    }

    @MainActor
    private func makeCompletedAttempt(
        ledger: SessionLedgerStore,
        requested: Bool,
        offset: TimeInterval
    ) async throws -> SessionAttempt {
        let attempt = SessionAttempt(
            storyID: Story.autumnTree.rawValue,
            plannedSeconds: 300,
            startedAt: Date(timeIntervalSince1970: offset),
            randomSeed: UInt64(offset),
            healthWriteRequested: requested
        )
        _ = try await ledger.create(attempt)
        _ = try await ledger.terminalize(id: attempt.id, event: .completed)
        return attempt
    }

    @MainActor
    private func healthState(
        for id: UUID,
        ledger: SessionLedgerStore
    ) async throws -> SessionAttempt.HealthSyncState? {
        (try await ledger.attempts()).first(where: { $0.id == id })?.healthSyncState
    }

    @MainActor
    private func makeDefaults() -> UserDefaults {
        let name = "PlanetCalmTests.health.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }
}

private final class HealthWriterSpy: HealthSessionWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var remainingFailures: Int
    private var recordedAttempts: [SessionAttempt] = []
    private var recordedAuthorizationRequests = 0
    private var available = true
    private var storedStatus: HKAuthorizationStatus
    private var authorizationBarrier: HealthBarrier?
    private var saveBarrier: HealthBarrier?

    init(status: HKAuthorizationStatus = .sharingAuthorized, failSaves: Int = 0) {
        self.storedStatus = status
        self.remainingFailures = failSaves
    }

    var savedAttempts: [SessionAttempt] { lock.withLock { recordedAttempts } }
    var savedIDs: [UUID] { savedAttempts.map(\.healthSyncID) }
    var requestCount: Int { lock.withLock { recordedAuthorizationRequests } }

    func isAvailable() -> Bool { lock.withLock { available } }
    func authorizationStatus() -> HKAuthorizationStatus { lock.withLock { storedStatus } }

    func setStatus(_ status: HKAuthorizationStatus) { lock.withLock { storedStatus = status } }
    func setAuthorizationBarrier(_ barrier: HealthBarrier?) { lock.withLock { authorizationBarrier = barrier } }
    func setSaveBarrier(_ barrier: HealthBarrier?) { lock.withLock { saveBarrier = barrier } }

    func requestAuthorization() async throws {
        let barrier = lock.withLock { authorizationBarrier }
        if let barrier { await barrier.enterAndWait() }
        lock.withLock { recordedAuthorizationRequests += 1 }
    }

    func save(_ attempt: SessionAttempt) async throws {
        let barrier = lock.withLock { saveBarrier }
        if let barrier { await barrier.enterAndWait() }
        let shouldFail = lock.withLock { () -> Bool in
            recordedAttempts.append(attempt)
            guard remainingFailures > 0 else { return false }
            remainingFailures -= 1
            return true
        }
        if shouldFail { throw CocoaError(.fileWriteUnknown) }
    }
}

private actor HealthBarrier {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func enterAndWait() async {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters = []
        waiters.forEach { $0.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters = []
        waiters.forEach { $0.resume() }
    }
}

private actor HealthMemoryPersistence: SessionLedgerPersistence {
    private var data: Data?

    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
}

private actor HealthFailingPersistence: SessionLedgerPersistence {
    private var data: Data?
    private var shouldFail = false

    func load() -> Data? { data }

    func save(_ data: Data) throws {
        guard !shouldFail else { throw CocoaError(.fileWriteOutOfSpace) }
        self.data = data
    }

    func failWrites() { shouldFail = true }
    func allowWrites() { shouldFail = false }
}

private actor HealthSuspendedPersistence: SessionLedgerPersistence {
    private var data: Data?
    private var shouldSuspend = false
    private var saveWaiter: CheckedContinuation<Void, Never>?
    private var enteredWaiter: CheckedContinuation<Void, Never>?

    func load() -> Data? { data }

    func save(_ data: Data) async {
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { continuation in
                saveWaiter = continuation
                enteredWaiter?.resume()
                enteredWaiter = nil
            }
        }
        self.data = data
    }

    func suspendNextSave() { shouldSuspend = true }

    func waitUntilSaveIsSuspended() async {
        guard saveWaiter == nil else { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func resumeSave() {
        saveWaiter?.resume()
        saveWaiter = nil
    }
}
