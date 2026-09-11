import CloudKit
import Foundation
import Observation

enum SessionHistorySyncStatus: Equatable, Sendable {
    case disabled, preparing, ready, syncing, unavailableAccount, failed
}

/// One owner for account selection, CloudKit events and the opt-in setting.
/// UI requests are serialized separately from delegate events: a network request
/// must never hold the local mutation lock while waiting for its own delegate.
@MainActor
@Observable
final class SessionHistorySyncCoordinator: CKSyncEngineDelegate {
    private let ledger: SessionLedgerStore
    private let accountStateStore: SessionHistoryAccountStateStore
    private let container: CKContainer
    let zoneName: String
    private var account: SessionHistoryAccountKey?
    private var accountState: SessionHistoryAccountState?
    private var verifiedAccount: SessionHistoryAccountKey?
    private var engine: CKSyncEngine?
    private var requestTail: Task<Void, Never>?
    private var generation = 0
    private var mutationInFlight = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []
    private var cycleError: (any Error)?

    private(set) var isEnabled = false
    private(set) var isSyncing = false
    private(set) var status: SessionHistorySyncStatus = .disabled
    private(set) var lastSuccessfulSyncAt: Date?
    private(set) var pendingUploadCount = 0
    private(set) var lastErrorDescription: String?

    init(
        ledger: SessionLedgerStore,
        accountStateStore: SessionHistoryAccountStateStore = SessionHistoryAccountStateStore(),
        container: CKContainer = CKContainer(identifier: "iCloud.com.planetcalm.app"),
        zoneName: String = "PlanetFocusHistory"
    ) {
        self.ledger = ledger
        self.accountStateStore = accountStateStore
        self.container = container
        self.zoneName = zoneName
    }

    func prepare() async {
        await enqueue {
            self.status = .preparing
            try await self.resolveAccount()
            if self.isEnabled { try await self.synchronize() }
            else { self.status = .disabled; self.lastErrorDescription = nil }
        }
    }

    func enable() async {
        await enqueue {
            try await self.resolveAccount()
            try await self.withMutation {
                guard let account = self.account, var state = self.accountState else { throw SyncError.noAccount }
                _ = try await self.ledger.claimUnownedHistory(for: account)
                state.isEnabled = true
                try await self.persist(state)
            }
            try await self.synchronize()
        }
    }

    func disable() async {
        // Stop providing records immediately, including during an in-flight sync.
        // Requests queued before this action cannot re-enable the old engine.
        generation += 1
        let oldEngine = engine
        engine = nil
        verifiedAccount = nil
        isEnabled = false
        isSyncing = false
        await enqueue {
            await oldEngine?.cancelOperations()
            try await self.restoreCachedAccountIfNeeded()
            do {
                try await self.withMutation {
                    if var state = self.accountState {
                        state.isEnabled = false
                        try await self.persist(state)
                    }
                }
            } catch {
                self.isEnabled = self.accountState?.isEnabled ?? false
                throw SyncError.settingWriteFailure
            }
            self.status = .disabled
            self.lastErrorDescription = nil
        }
    }

    func syncNow() async {
        await enqueue {
            try await self.resolveAccount()
            if self.isEnabled { try await self.synchronize() }
        }
    }

    func historyDidChange() async {
        guard isEnabled else { return }
        await syncNow()
    }

    private func enqueue(_ operation: @escaping @MainActor () async throws -> Void) async {
        let previous = requestTail
        let expectedGeneration = generation
        let task = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == expectedGeneration else { return }
            do { try await operation() }
            catch {
                if self.generation == expectedGeneration { self.recordFailure(error) }
            }
        }
        requestTail = task
        await task.value
    }

    private func restoreCachedAccountIfNeeded() async throws {
        guard accountState == nil else { return }
        let expected = generation
        if let known = try await ledger.currentHistoryAccount() {
            let state = try await accountStateStore.load(for: known)
            guard expected == generation else { throw CancellationError() }
            account = known
            apply(state)
        }
    }

    private func resolveAccount() async throws {
        let expected = generation
        try await restoreCachedAccountIfNeeded()
        let resolved: SessionHistoryAccountKey
        do {
            let id = try await container.userRecordID()
            resolved = SessionHistoryAccountKey(userRecordName: id.recordName)
        } catch {
            let old = engine
            engine = nil
            verifiedAccount = nil
            await old?.cancelOperations()
            throw error
        }
        guard expected == generation else { throw CancellationError() }
        if account != resolved || accountState == nil {
            let old = engine
            engine = nil
            await old?.cancelOperations()
            try await withMutation {
                guard expected == self.generation else { throw CancellationError() }
                try await self.ledger.prepareHistoryAccount(resolved)
                let state = try await self.accountStateStore.load(for: resolved)
                guard expected == self.generation else { throw CancellationError() }
                self.account = resolved
                self.apply(state)
            }
        }
        verifiedAccount = resolved
    }

    private var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName) }

    private func makeEngineIfNeeded() throws -> CKSyncEngine {
        if let engine { return engine }
        guard let state = accountState, state.isEnabled, verifiedAccount == account else { throw SyncError.noAccount }
        let serialization = try state.engineStateData.map {
            try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase, stateSerialization: serialization, delegate: self
        )
        // Foreground sync also works in development builds without background
        // delivery. Automatic scheduling is enabled only with the actual capability.
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        configuration.automaticallySync = modes.contains("remote-notification")
        configuration.subscriptionID = "PlanetFocusHistory-\(zoneName)"
        let created = CKSyncEngine(configuration)
        engine = created
        created.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        return created
    }

    private func synchronize() async throws {
        let expected = generation
        guard isEnabled, verifiedAccount == account else { return }
        isSyncing = true
        status = .syncing
        lastErrorDescription = nil
        cycleError = nil
        defer { if expected == generation { isSyncing = false } }
        let engine = try makeEngineIfNeeded()
        try await withMutation { try await self.drainInbox() }
        // Fetch first so an offline device learns about deletion before offering
        // stale local records. Change-tag conflicts enforce the same rule if raced.
        for _ in 0..<3 {
            try check(engine, generation: expected)
            try await engine.fetchChanges()
            try check(engine, generation: expected)
            try await withMutation { try await self.stageLocalChanges(on: engine) }
            try await engine.sendChanges()
            try check(engine, generation: expected)
            try await engine.fetchChanges()
            try check(engine, generation: expected)
            if let cycleError { throw cycleError }
            if pendingUploadCount == 0 { break }
        }
        try await withMutation {
            try self.check(engine, generation: expected)
            guard var state = self.accountState, state.pendingUploadIDs.isEmpty, state.remoteInbox.isEmpty else {
                throw SyncError.pendingChanges
            }
            state.lastSuccessfulSyncAt = .now
            try await self.persist(state)
        }
        try check(engine, generation: expected)
        status = .ready
        lastErrorDescription = nil
    }

    private func check(_ candidate: CKSyncEngine, generation expected: Int) throws {
        guard engine === candidate, isEnabled, generation == expected, verifiedAccount == account else {
            throw CancellationError()
        }
    }

    private func stageLocalChanges(on engine: CKSyncEngine) async throws {
        guard let account, var state = accountState else { throw SyncError.noAccount }
        let history = try await ledger.exportTerminalHistory(for: account)
        let records = Dictionary(uniqueKeysWithValues: history.records.map { ($0.id, $0) })
        let desiredIDs = Set(records.keys).union(history.deletedAttemptIDs)
        for id in desiredIDs {
            let server = try state.serverRecords[id.uuidString].map(Self.unarchive)
            let payload = try records[id].map(Self.encode)
            let deleted = history.deletedAttemptIDs.contains(id)
            if server == nil || !Self.matches(server!, payload: payload, deleted: deleted) {
                state.pendingUploadIDs.insert(id)
            } else { state.pendingUploadIDs.remove(id) }
        }
        // Active local attempts have no portable payload; deferred deletions live
        // durably in the ledger until those attempts terminalize.
        state.pendingUploadIDs.formIntersection(desiredIDs)
        try await persist(state)
        engine.state.add(pendingRecordZoneChanges: state.pendingUploadIDs.map {
            .saveRecord(CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID))
        })
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        do {
            return try await withMutation {
                guard self.engine === syncEngine, self.isEnabled,
                      self.verifiedAccount == self.account, let account = self.account,
                      let state = self.accountState else { return nil }
                let history = try await self.ledger.exportTerminalHistory(for: account)
                let records = Dictionary(uniqueKeysWithValues: history.records.map { ($0.id, $0) })
                let changes = syncEngine.state.pendingRecordZoneChanges.filter {
                    guard case let .saveRecord(id) = $0 else { return false }
                    return id.zoneID == self.zoneID && context.options.scope.contains($0)
                }
                var outgoing: [CKRecord.ID: CKRecord] = [:]
                for change in changes {
                    guard case let .saveRecord(recordID) = change,
                          recordID.zoneID == self.zoneID, let id = UUID(uuidString: recordID.recordName) else { continue }
                    let deleted = history.deletedAttemptIDs.contains(id)
                    guard deleted || records[id] != nil else {
                        syncEngine.state.remove(pendingRecordZoneChanges: [change])
                        continue
                    }
                    let record = try state.serverRecords[id.uuidString].map(Self.unarchive)
                        ?? CKRecord(recordType: Self.recordType, recordID: recordID)
                    record["schemaVersion"] = 1 as Int64
                    record["deleted"] = (deleted ? 1 : 0) as Int64
                    record["payload"] = deleted ? nil : try records[id].map(Self.encode) as CKRecordValue?
                    outgoing[recordID] = record
                }
                let snapshot = outgoing
                return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { snapshot[$0] }
            }
        } catch {
            failEngine(syncEngine, error: error)
            return nil
        }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine, isEnabled else { return }
        if case let .accountChange(change) = event {
            if case let .signIn(currentUser) = change.changeType,
               currentUser.recordName == verifiedAccount?.rawValue { return }
            generation += 1
            engine = nil
            verifiedAccount = nil
            Task.detached { [weak self] in
                await syncEngine.cancelOperations()
                await self?.prepare()
            }
            return
        }
        do {
            try await withMutation {
                guard self.engine === syncEngine, self.isEnabled else { return }
                switch event {
                case let .stateUpdate(update):
                    guard var state = self.accountState else { return }
                    state.engineStateData = try JSONEncoder().encode(update.stateSerialization)
                    try await self.persist(state)
                case let .fetchedRecordZoneChanges(changes):
                    let records = changes.modifications.map(\.record).filter { $0.recordID.zoneID == self.zoneID }
                    let deletions = Set(changes.deletions.compactMap { deletion -> UUID? in
                        guard deletion.recordID.zoneID == self.zoneID else { return nil }
                        return UUID(uuidString: deletion.recordID.recordName)
                    })
                    try await self.receive(records, deletedIDs: deletions)
                case let .sentRecordZoneChanges(changes):
                    try await self.sent(changes, engine: syncEngine)
                case let .sentDatabaseChanges(changes):
                    if let failure = changes.failedZoneSaves.first { self.cycleError = failure.error }
                case let .didFetchRecordZoneChanges(changes):
                    if let error = changes.error { self.cycleError = error }
                case let .fetchedDatabaseChanges(changes):
                    if changes.deletions.contains(where: { $0.zoneID == self.zoneID }) {
                        // Preserve the local copy, but require a new explicit
                        // opt-in before recreating cloud history the user removed.
                        if var state = self.accountState {
                            state.isEnabled = false
                            state.engineStateData = nil
                            state.serverRecords.removeAll()
                            state.pendingUploadIDs.removeAll()
                            state.remoteInbox.removeAll()
                            try await self.persist(state)
                        }
                        throw SyncError.cloudHistoryRemoved
                    }
                default: break
                }
            }
        } catch { failEngine(syncEngine, error: error) }
    }

    /// The inbox and server metadata are durable before any ledger import. A
    /// failed ledger save leaves replayable work, and stops token advancement.
    private func receive(_ records: [CKRecord], deletedIDs: Set<UUID> = []) async throws {
        guard var state = accountState else { throw SyncError.noAccount }
        var history: [TerminalSessionHistoryRecord] = []
        var tombstones = deletedIDs
        for record in records {
            guard record.recordType == Self.recordType,
                  let id = UUID(uuidString: record.recordID.recordName),
                  (record["schemaVersion"] as? NSNumber)?.intValue == 1,
                  let deletionFlag = (record["deleted"] as? NSNumber)?.intValue,
                  deletionFlag == 0 || deletionFlag == 1 else { throw SyncError.invalidRecord }
            if deletionFlag == 1 {
                tombstones.insert(id)
            } else {
                guard let payload = record["payload"] as? Data else { throw SyncError.invalidRecord }
                let value = try JSONDecoder().decode(TerminalSessionHistoryRecord.self, from: payload)
                guard value.id == id, value.isWellFormedTerminalRecord else { throw SyncError.invalidRecord }
                history.append(value)
            }
            state.serverRecords[id.uuidString] = try Self.archive(record)
        }
        for id in deletedIDs { state.serverRecords[id.uuidString] = nil }
        guard !history.isEmpty || !tombstones.isEmpty else { return }
        state.remoteInbox.append(.init(history: .init(records: history, deletedAttemptIDs: tombstones)))
        try await persist(state)
        try await drainInbox()
    }

    private func drainInbox() async throws {
        guard let account else { throw SyncError.noAccount }
        while let entry = accountState?.remoteInbox.first {
            let result = try await ledger.mergeTerminalHistory(entry.history, for: account)
            let current = try await ledger.exportTerminalHistory(for: account)
            // Ignoring a stale live copy of an already deleted record is expected.
            let conflicts = result.ignoredRecordIDs.subtracting(current.deletedAttemptIDs)
            guard conflicts.isEmpty, result.rejectedOwnershipIDs.isEmpty else { throw SyncError.conflictingRecord }
            guard var state = accountState else { throw SyncError.noAccount }
            state.remoteInbox.removeAll { $0.id == entry.id }
            // Deferred deletions were atomically recorded in the ledger itself.
            try await persist(state)
        }
    }

    private func sent(_ changes: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) async throws {
        guard var state = accountState else { throw SyncError.noAccount }
        for record in changes.savedRecords where record.recordID.zoneID == zoneID {
            guard let id = UUID(uuidString: record.recordID.recordName) else { continue }
            state.serverRecords[id.uuidString] = try Self.archive(record)
            state.pendingUploadIDs.remove(id)
        }
        try await persist(state)
        for failure in changes.failedRecordSaves where failure.record.recordID.zoneID == zoneID {
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { throw failure.error }
                try await receive([server])
            case .zoneNotFound:
                guard var state = accountState else { throw SyncError.noAccount }
                state.serverRecords.removeAll()
                try await persist(state)
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            case .unknownItem:
                guard let id = UUID(uuidString: failure.record.recordID.recordName) else { throw SyncError.invalidRecord }
                try await receive([], deletedIDs: [id])
            default:
                cycleError = failure.error
            }
        }
        // Re-evaluate after the send: deletion may have occurred locally while
        // CloudKit was saving an older live record.
        try await stageLocalChanges(on: engine)
    }

    private func failEngine(_ failing: CKSyncEngine, error: any Error) {
        guard engine === failing else { return }
        engine = nil
        cycleError = error
        recordFailure(error)
        // Never wait for the engine from inside its own delegate callback.
        Task.detached { await failing.cancelOperations() }
    }

    private func persist(_ state: SessionHistoryAccountState) async throws {
        let expectedGeneration = generation
        try await accountStateStore.save(state)
        if expectedGeneration == generation {
            apply(state)
        } else if state.accountKey == account {
            // Preserve saved metadata for the queued disable, but never let an
            // older in-flight save visibly turn the user's switch back on.
            accountState = state
            pendingUploadCount = state.pendingUploadIDs.count
            lastSuccessfulSyncAt = state.lastSuccessfulSyncAt
        }
    }

    private func apply(_ state: SessionHistoryAccountState) {
        accountState = state
        isEnabled = state.isEnabled
        pendingUploadCount = state.pendingUploadIDs.count
        lastSuccessfulSyncAt = state.lastSuccessfulSyncAt
    }

    private func withMutation<T>(_ operation: () async throws -> T) async throws -> T {
        if mutationInFlight { await withCheckedContinuation { mutationWaiters.append($0) } }
        else { mutationInFlight = true }
        defer {
            if mutationWaiters.isEmpty { mutationInFlight = false }
            else { mutationWaiters.removeFirst().resume() }
        }
        return try await operation()
    }

    private static let recordType = "FocusSessionHistory"
    private static func encode(_ record: TerminalSessionHistoryRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }
    private static func matches(_ record: CKRecord, payload: Data?, deleted: Bool) -> Bool {
        (record["schemaVersion"] as? NSNumber)?.intValue == 1
            && ((record["deleted"] as? NSNumber)?.intValue == 1) == deleted
            && (deleted ? record["payload"] == nil : record["payload"] as? Data == payload)
    }
    private static func archive(_ record: CKRecord) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)
    }
    private static func unarchive(_ data: Data) throws -> CKRecord {
        guard let record = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: data) else {
            throw SyncError.invalidRecord
        }
        return record
    }

    private func recordFailure(_ error: any Error) {
        isSyncing = false
        if error is CancellationError {
            if lastErrorDescription != nil { return }
            status = isEnabled ? .ready : .disabled
            return
        }
        if let cloud = error as? CKError {
            status = cloud.code == .notAuthenticated ? .unavailableAccount : .failed
            switch cloud.code {
            case .notAuthenticated:
                lastErrorDescription = "Sign in to iCloud in Settings to sync your sessions."
            case .networkFailure, .networkUnavailable:
                lastErrorDescription = "You’re offline. Your sessions are saved on this device. Try syncing again when you’re connected."
            case .quotaExceeded:
                lastErrorDescription = "Your iCloud storage is full. Free up space to resume syncing."
            case .serviceUnavailable, .zoneBusy, .requestRateLimited:
                lastErrorDescription = "iCloud is temporarily unavailable. Your sessions are safe on this device. Try again later."
            default:
                lastErrorDescription = "Couldn’t sync with iCloud. Your sessions are saved on this device. Please try again."
            }
        } else {
            status = .failed
            lastErrorDescription = (error as? SyncError)?.errorDescription
                ?? "Sync couldn’t safely save its changes. Your existing session history is kept. Please try again."
        }
    }

    private enum SyncError: Error, LocalizedError {
        case noAccount, invalidRecord, conflictingRecord, pendingChanges, cloudHistoryRemoved, settingWriteFailure
        var errorDescription: String? {
            switch self {
            case .noAccount: "Sign in to iCloud in Settings to sync your sessions."
            case .invalidRecord, .conflictingRecord: "Some iCloud history could not be read safely. Your existing sessions are kept."
            case .pendingChanges: "Some changes are still waiting to sync. Your sessions are saved on this device."
            case .cloudHistoryRemoved: "Your iCloud history was removed. Sync has stopped to protect your local sessions."
            case .settingWriteFailure: "Couldn’t save the iCloud setting. Sync is stopped for now. Please try turning it off again."
            }
        }
    }
}
