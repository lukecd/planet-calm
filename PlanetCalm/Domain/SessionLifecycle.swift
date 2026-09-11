import Foundation
import Observation

/// A durable, app-owned description of a focus attempt. It deliberately stores raw
/// story and duration values so historical records outlive changes to the live catalog.
struct SessionAttempt: Codable, Equatable, Identifiable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case running
        case completed
        case cancelled
        case distracted
        case interrupted
    }

    enum HealthSyncState: String, Codable, Sendable {
        case notRequested
        case pending
        case succeeded
        case failed
        case cancelled
    }

    struct ProtectionSnapshot: Codable, Equatable, Sendable {
        enum Mode: String, Codable, Sendable {
            case unprotected
            case protected
        }

        let mode: Mode

        static let unprotected = Self(mode: .unprotected)
    }

    let id: UUID
    let storyID: String
    let plannedSeconds: Int
    let startedAt: Date
    let scheduledEndAt: Date
    let timeZoneIdentifier: String
    let calendarIdentifier: String
    let randomSeed: UInt64
    let protection: ProtectionSnapshot
    let healthWriteRequested: Bool
    let healthSyncID: UUID
    var healthSyncState: HealthSyncState
    var outcome: Outcome
    var terminalAt: Date?
    var observedAt: Date?
    var creditedSeconds: Int

    init(
        id: UUID = UUID(),
        storyID: String,
        plannedSeconds: Int,
        startedAt: Date,
        randomSeed: UInt64,
        protection: ProtectionSnapshot = .unprotected,
        healthWriteRequested: Bool = false,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        calendarIdentifier: String = String(describing: Calendar.current.identifier)
    ) {
        self.id = id
        self.storyID = storyID
        self.plannedSeconds = plannedSeconds
        self.startedAt = startedAt
        self.scheduledEndAt = startedAt.addingTimeInterval(TimeInterval(plannedSeconds))
        self.timeZoneIdentifier = timeZoneIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.randomSeed = randomSeed
        self.protection = protection
        self.healthWriteRequested = healthWriteRequested
        self.healthSyncID = UUID()
        self.healthSyncState = healthWriteRequested ? .pending : .notRequested
        self.outcome = .running
        self.terminalAt = nil
        self.observedAt = nil
        self.creditedSeconds = 0
    }

    var isTerminal: Bool { outcome != .running }

    /// Imported history deliberately gets a new device-local Health identity. An
    /// imported completion is history only; it must never inherit a pending write
    /// from the device that originally recorded it.
    fileprivate init(importing history: TerminalSessionHistoryRecord) {
        self.id = history.id
        self.storyID = history.storyID
        self.plannedSeconds = history.plannedSeconds
        self.startedAt = history.startedAt
        self.scheduledEndAt = history.scheduledEndAt
        self.timeZoneIdentifier = history.timeZoneIdentifier
        self.calendarIdentifier = history.calendarIdentifier
        self.randomSeed = history.randomSeed
        self.protection = .unprotected
        self.healthWriteRequested = false
        self.healthSyncID = UUID()
        self.healthSyncState = .notRequested
        self.outcome = history.outcome
        self.terminalAt = history.terminalAt
        self.observedAt = history.observedAt
        self.creditedSeconds = history.creditedSeconds
    }
}

/// Portable, app-authored terminal history. This is intentionally narrower than
/// `SessionAttempt`: protection and Health fields remain device-local.
struct TerminalSessionHistoryRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let storyID: String
    let plannedSeconds: Int
    let startedAt: Date
    let scheduledEndAt: Date
    let timeZoneIdentifier: String
    let calendarIdentifier: String
    let randomSeed: UInt64
    let outcome: SessionAttempt.Outcome
    let terminalAt: Date?
    let observedAt: Date?
    let creditedSeconds: Int

    init?(_ attempt: SessionAttempt) {
        guard attempt.isTerminal else { return nil }
        self.init(
            id: attempt.id,
            storyID: attempt.storyID,
            plannedSeconds: attempt.plannedSeconds,
            startedAt: attempt.startedAt,
            scheduledEndAt: attempt.scheduledEndAt,
            timeZoneIdentifier: attempt.timeZoneIdentifier,
            calendarIdentifier: attempt.calendarIdentifier,
            randomSeed: attempt.randomSeed,
            outcome: attempt.outcome,
            terminalAt: attempt.terminalAt,
            observedAt: attempt.observedAt,
            creditedSeconds: attempt.creditedSeconds
        )
    }

    init(
        id: UUID,
        storyID: String,
        plannedSeconds: Int,
        startedAt: Date,
        scheduledEndAt: Date,
        timeZoneIdentifier: String,
        calendarIdentifier: String,
        randomSeed: UInt64,
        outcome: SessionAttempt.Outcome,
        terminalAt: Date?,
        observedAt: Date?,
        creditedSeconds: Int
    ) {
        self.id = id
        self.storyID = storyID
        self.plannedSeconds = plannedSeconds
        self.startedAt = startedAt
        self.scheduledEndAt = scheduledEndAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.randomSeed = randomSeed
        self.outcome = outcome
        self.terminalAt = terminalAt
        self.observedAt = observedAt
        self.creditedSeconds = creditedSeconds
    }

    var isTerminal: Bool { outcome != .running }

    /// Imports are untrusted transport input. Preserve only values the local
    /// lifecycle could have produced, so history cannot manufacture credit or a
    /// contradictory timestamp sequence.
    var isWellFormedTerminalRecord: Bool {
        guard isTerminal,
              plannedSeconds > 0,
              scheduledEndAt == startedAt.addingTimeInterval(TimeInterval(plannedSeconds)) else {
            return false
        }

        switch outcome {
        case .running:
            return false
        case .completed:
            return terminalAt == scheduledEndAt
                && observedAt == nil
                && creditedSeconds == plannedSeconds
        case .cancelled:
            return creditedSeconds == 0
                && terminalAt != nil
                && terminalAt == observedAt
        case .distracted:
            return creditedSeconds == 0
                && terminalAt != nil
                && observedAt != nil
        case .interrupted:
            return creditedSeconds == 0
                && terminalAt == nil
                && observedAt != nil
        }
    }
}

/// The local boundary a future CloudKit transport can exchange. It contains no
/// transport state and does not itself enable syncing or change user preferences.
struct TerminalSessionHistoryExport: Codable, Equatable, Sendable {
    let records: [TerminalSessionHistoryRecord]
    let deletedAttemptIDs: Set<UUID>

    init(records: [TerminalSessionHistoryRecord], deletedAttemptIDs: Set<UUID>) {
        self.records = records
        self.deletedAttemptIDs = deletedAttemptIDs
    }
}

/// A future transport can keep a remote deletion pending when it targets an
/// active local attempt, rather than acknowledging and losing that deletion.
struct TerminalSessionHistoryMergeResult: Equatable, Sendable {
    let deferredDeletionIDs: Set<UUID>
    let ignoredRecordIDs: Set<UUID>
    let rejectedOwnershipIDs: Set<UUID>
}

struct SessionHistoryOwnershipReservation: Equatable, Sendable {
    let acceptedIDs: Set<UUID>
    let rejectedIDs: Set<UUID>
}

enum SessionTerminalEvent: Sendable, Equatable {
    case completed
    case cancelled(occurredAt: Date)
    case distracted(occurredAt: Date, observedAt: Date)
    case interrupted(observedAt: Date)
}

enum SessionLedgerError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedSchema(Int)
    case corruptStore
    case activeSessionExists
    case attemptNotFound
    case lifecycleNotReady
    case lifecycleBusy
    case sessionNotDue
    case historyAccountMismatch

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema:
            "This version of Planet Focus can’t read its session history."
        case .corruptStore:
            "Session history couldn’t be read safely."
        case .activeSessionExists:
            "A focus session is already active."
        case .attemptNotFound:
            "That focus session is no longer available."
        case .lifecycleNotReady:
            "Session history is still preparing. Please try again."
        case .lifecycleBusy:
            "A focus session is already being started."
        case .sessionNotDue:
            "This focus session has not reached its scheduled end."
        case .historyAccountMismatch:
            "This history belongs to a different iCloud account."
        }
    }
}

private struct SessionLedgerEnvelope: Codable, Sendable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var attempts: [SessionAttempt]
    var deletedAttemptIDs: Set<UUID>
    /// Remote deletes that arrived while the same local ID was still running.
    /// They become ordinary deletion markers as soon as the attempt is terminal.
    var deferredDeletionIDs: Set<UUID>
    /// Bound atomically with ledger mutations. IDs remain owned after deletion,
    /// preventing a different iCloud account from claiming an old tombstone.
    var historyOwnerByAttemptID: [String: SessionHistoryAccountKey]
    var currentHistoryAccount: SessionHistoryAccountKey?

    static let empty = Self(
        schemaVersion: currentSchemaVersion,
        attempts: [],
        deletedAttemptIDs: [],
        deferredDeletionIDs: [],
        historyOwnerByAttemptID: [:],
        currentHistoryAccount: nil
    )

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case attempts
        case deletedAttemptIDs
        case deferredDeletionIDs
        case historyOwnerByAttemptID
        case currentHistoryAccount
    }

    init(
        schemaVersion: Int,
        attempts: [SessionAttempt],
        deletedAttemptIDs: Set<UUID>,
        deferredDeletionIDs: Set<UUID>,
        historyOwnerByAttemptID: [String: SessionHistoryAccountKey],
        currentHistoryAccount: SessionHistoryAccountKey?
    ) {
        self.schemaVersion = schemaVersion
        self.attempts = attempts
        self.deletedAttemptIDs = deletedAttemptIDs
        self.deferredDeletionIDs = deferredDeletionIDs
        self.historyOwnerByAttemptID = historyOwnerByAttemptID
        self.currentHistoryAccount = currentHistoryAccount
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.attempts = try container.decode([SessionAttempt].self, forKey: .attempts)
        self.deletedAttemptIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .deletedAttemptIDs) ?? []
        self.deferredDeletionIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .deferredDeletionIDs) ?? []
        self.historyOwnerByAttemptID = try container.decodeIfPresent(
            [String: SessionHistoryAccountKey].self,
            forKey: .historyOwnerByAttemptID
        ) ?? [:]
        self.currentHistoryAccount = try container.decodeIfPresent(
            SessionHistoryAccountKey.self,
            forKey: .currentHistoryAccount
        )
        self.schemaVersion = (decodedVersion == 1 || decodedVersion == 2)
            ? Self.currentSchemaVersion
            : decodedVersion
    }
}

protocol SessionLedgerPersistence: Sendable {
    func load() async throws -> Data?
    func save(_ data: Data) async throws
}

actor FileSessionLedgerPersistence: SessionLedgerPersistence {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func load() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    func save(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory
            .appending(path: "PlanetFocus", directoryHint: .isDirectory)
            .appending(path: "session-ledger-v1.json", directoryHint: .notDirectory)
    }
}

/// The only mutable owner of the persisted ledger. The mutation gate stays held
/// across persistence awaits so two read-modify-write operations cannot interleave.
actor SessionLedgerStore {
    private let persistence: any SessionLedgerPersistence
    private var envelope: SessionLedgerEnvelope?
    private var preparationTask: Task<SessionLedgerEnvelope, Error>?
    private var mutationInFlight = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    init(persistence: any SessionLedgerPersistence = FileSessionLedgerPersistence()) {
        self.persistence = persistence
    }

    func prepare() async throws -> [SessionAttempt] {
        try await ensureEnvelope().attempts
    }

    func attempts() async throws -> [SessionAttempt] {
        try await ensureEnvelope().attempts
    }

    func currentHistoryAccount() async throws -> SessionHistoryAccountKey? {
        try await ensureEnvelope().currentHistoryAccount
    }

    /// Establishes the account that owns subsequently created local attempts.
    /// Before changing accounts, bind every currently unowned attempt and
    /// tombstone to the prior account in this same durable ledger mutation.
    func prepareHistoryAccount(_ account: SessionHistoryAccountKey) async throws {
        _ = try await mutate { envelope in
            if let previous = envelope.currentHistoryAccount, previous != account {
                let localIDs = Set(envelope.attempts.map(\.id)).union(envelope.deletedAttemptIDs)
                for id in localIDs where envelope.historyOwnerByAttemptID[id.uuidString] == nil {
                    envelope.historyOwnerByAttemptID[id.uuidString] = previous
                }
            }
            envelope.currentHistoryAccount = account
            return ()
        }
    }

    /// Only an explicit opt-in may claim ledger records that have never belonged
    /// to an account. Once assigned, IDs—including deleted IDs—cannot move.
    func claimUnownedHistory(for account: SessionHistoryAccountKey) async throws -> SessionHistoryOwnershipReservation {
        try await mutate { envelope in
            guard envelope.currentHistoryAccount == account else {
                throw SessionLedgerError.historyAccountMismatch
            }
            let localIDs = Set(envelope.attempts.map(\.id)).union(envelope.deletedAttemptIDs)
            var accepted: Set<UUID> = []
            var rejected: Set<UUID> = []
            for id in localIDs {
                switch envelope.historyOwnerByAttemptID[id.uuidString] {
                case nil:
                    envelope.historyOwnerByAttemptID[id.uuidString] = account
                    accepted.insert(id)
                case account:
                    accepted.insert(id)
                default:
                    rejected.insert(id)
                }
            }
            return SessionHistoryOwnershipReservation(acceptedIDs: accepted, rejectedIDs: rejected)
        }
    }

    /// Exports only immutable terminal facts. Running attempts are deliberately
    /// absent so a future transport cannot turn them into restored timers.
    func exportTerminalHistory() async throws -> TerminalSessionHistoryExport {
        let envelope = try await ensureEnvelope()
        let records = envelope.attempts.compactMap(TerminalSessionHistoryRecord.init)
            .filter(\.isWellFormedTerminalRecord)
            .sorted { lhs, rhs in
                lhs.startedAt == rhs.startedAt
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.startedAt < rhs.startedAt
            }
        return TerminalSessionHistoryExport(
            records: records,
            deletedAttemptIDs: envelope.deletedAttemptIDs
        )
    }

    func exportTerminalHistory(for account: SessionHistoryAccountKey) async throws -> TerminalSessionHistoryExport {
        let export = try await exportTerminalHistory()
        let envelope = try await ensureEnvelope()
        return TerminalSessionHistoryExport(
            records: export.records.filter { envelope.historyOwnerByAttemptID[$0.id.uuidString] == account },
            deletedAttemptIDs: Set(export.deletedAttemptIDs.filter {
                envelope.historyOwnerByAttemptID[$0.uuidString] == account
            })
        )
    }

    /// Merges a portable terminal snapshot without invoking lifecycle or Health
    /// work. Deletions win over records, local terminal facts win immutable
    /// conflicts, and an active local attempt is never changed by an import.
    func mergeTerminalHistory(
        _ incoming: TerminalSessionHistoryExport
    ) async throws -> TerminalSessionHistoryMergeResult {
        try await mergeTerminalHistory(incoming, ownedBy: nil)
    }

    /// Claims incoming IDs and merges them in one ledger mutation. A record that
    /// belongs to a different account is ignored before it can affect history.
    func mergeTerminalHistory(
        _ incoming: TerminalSessionHistoryExport,
        for account: SessionHistoryAccountKey
    ) async throws -> TerminalSessionHistoryMergeResult {
        try await mergeTerminalHistory(incoming, ownedBy: account)
    }

    private func mergeTerminalHistory(
        _ incoming: TerminalSessionHistoryExport,
        ownedBy account: SessionHistoryAccountKey?
    ) async throws -> TerminalSessionHistoryMergeResult {
        try await mutate { envelope in
            var rejectedOwnershipIDs: Set<UUID> = []
            if let account {
                guard envelope.currentHistoryAccount == account else {
                    throw SessionLedgerError.historyAccountMismatch
                }
                let incomingIDs = Set(incoming.records.map(\.id)).union(incoming.deletedAttemptIDs)
                for id in incomingIDs {
                    switch envelope.historyOwnerByAttemptID[id.uuidString] {
                    case nil:
                        envelope.historyOwnerByAttemptID[id.uuidString] = account
                    case account:
                        break
                    default:
                        rejectedOwnershipIDs.insert(id)
                    }
                }
            }
            let activeIDs = Set(envelope.attempts.lazy.filter { !$0.isTerminal }.map(\.id))

            // A remote deletion cannot safely be applied to a currently running
            // local attempt. Keep it in the same durable mutation, so a transport
            // has a truthful deferred result and a restart cannot lose it.
            let eligibleDeletionIDs = incoming.deletedAttemptIDs.subtracting(rejectedOwnershipIDs)
            let deferredDeletionIDs = eligibleDeletionIDs.intersection(activeIDs)
            envelope.deferredDeletionIDs.formUnion(deferredDeletionIDs)
            let applicableDeletionIDs = eligibleDeletionIDs.subtracting(activeIDs)
            envelope.deletedAttemptIDs.formUnion(applicableDeletionIDs)
            envelope.attempts.removeAll { envelope.deletedAttemptIDs.contains($0.id) }

            // A malformed transport batch can contain conflicting copies of one
            // ID. Ignore that ID entirely rather than picking an arbitrary winner.
            let groupedRecords = Dictionary(grouping: incoming.records, by: \.id)
            var ignoredRecordIDs: Set<UUID> = []
            for id in groupedRecords.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard !rejectedOwnershipIDs.contains(id),
                      !envelope.deletedAttemptIDs.contains(id),
                      let records = groupedRecords[id],
                      let record = records.first,
                      record.isWellFormedTerminalRecord,
                      records.allSatisfy({ $0 == record }) else {
                    ignoredRecordIDs.insert(id)
                    continue
                }

                if let index = envelope.attempts.firstIndex(where: { $0.id == id }) {
                    // Never overwrite an active timer or device-local Health state.
                    guard envelope.attempts[index].isTerminal,
                          TerminalSessionHistoryRecord(envelope.attempts[index]) == record else {
                        ignoredRecordIDs.insert(id)
                        continue
                    }
                } else {
                    envelope.attempts.append(SessionAttempt(importing: record))
                }
            }
            return TerminalSessionHistoryMergeResult(
                deferredDeletionIDs: deferredDeletionIDs,
                ignoredRecordIDs: ignoredRecordIDs,
                rejectedOwnershipIDs: rejectedOwnershipIDs
            )
        }
    }

    func create(_ attempt: SessionAttempt) async throws -> SessionAttempt {
        try await mutate { envelope in
            guard !envelope.attempts.contains(where: { $0.id == attempt.id }),
                  !envelope.deletedAttemptIDs.contains(attempt.id) else {
                throw SessionLedgerError.attemptNotFound
            }
            guard !envelope.attempts.contains(where: { $0.outcome == .running }) else {
                throw SessionLedgerError.activeSessionExists
            }
            envelope.attempts.append(attempt)
            if let account = envelope.currentHistoryAccount {
                envelope.historyOwnerByAttemptID[attempt.id.uuidString] = account
            }
            return attempt
        }
    }

    /// Records only transitions for an existing attempt. A late callback can never
    /// recreate a deleted record, and a terminal record is immutable.
    func terminalize(
        id: UUID,
        event: SessionTerminalEvent
    ) async throws -> SessionAttempt {
        await acquireMutation()
        defer { releaseMutation() }
        var envelope = try await ensureEnvelope()
        guard let index = envelope.attempts.firstIndex(where: { $0.id == id }),
              !envelope.deletedAttemptIDs.contains(id) else {
            throw SessionLedgerError.attemptNotFound
        }

        var attempt = envelope.attempts[index]
        guard !attempt.isTerminal else { return attempt }

        switch event {
        case .completed:
            attempt.outcome = .completed
            attempt.terminalAt = attempt.scheduledEndAt
            attempt.observedAt = nil
            attempt.creditedSeconds = attempt.plannedSeconds
        case let .cancelled(occurredAt):
            attempt.outcome = .cancelled
            attempt.terminalAt = occurredAt
            attempt.observedAt = occurredAt
            attempt.creditedSeconds = 0
        case let .distracted(occurredAt, observedAt):
            attempt.outcome = .distracted
            attempt.terminalAt = occurredAt
            attempt.observedAt = observedAt
            attempt.creditedSeconds = 0
        case let .interrupted(observedAt):
            attempt.outcome = .interrupted
            attempt.terminalAt = nil
            attempt.observedAt = observedAt
            attempt.creditedSeconds = 0
        }

        envelope.attempts[index] = attempt
        if envelope.deferredDeletionIDs.remove(attempt.id) != nil {
            envelope.deletedAttemptIDs.insert(attempt.id)
            envelope.attempts.removeAll { $0.id == attempt.id }
        }
        let data = try JSONEncoder().encode(envelope)
        try await persistence.save(data)
        self.envelope = envelope
        return attempt
    }

    func reconcileOrphanedAttempts(observedAt: Date) async throws -> [SessionAttempt] {
        try await mutate { envelope in
            for index in envelope.attempts.indices where envelope.attempts[index].outcome == .running {
                envelope.attempts[index].outcome = .interrupted
                envelope.attempts[index].terminalAt = nil
                envelope.attempts[index].observedAt = observedAt
                envelope.attempts[index].creditedSeconds = 0
            }
            let nowTerminalIDs = Set(envelope.attempts.lazy.filter(\.isTerminal).map(\.id))
            let appliedDeletionIDs = envelope.deferredDeletionIDs.intersection(nowTerminalIDs)
            envelope.deferredDeletionIDs.subtract(appliedDeletionIDs)
            envelope.deletedAttemptIDs.formUnion(appliedDeletionIDs)
            envelope.attempts.removeAll { envelope.deletedAttemptIDs.contains($0.id) }
            return envelope.attempts
        }
    }

    func delete(ids: Set<UUID>) async throws {
        _ = try await mutate { envelope in
            envelope.attempts.removeAll { ids.contains($0.id) }
            envelope.deletedAttemptIDs.formUnion(ids)
            envelope.deferredDeletionIDs.subtract(ids)
            if let account = envelope.currentHistoryAccount {
                for id in ids where envelope.historyOwnerByAttemptID[id.uuidString] == nil {
                    envelope.historyOwnerByAttemptID[id.uuidString] = account
                }
            }
            return ()
        }
    }

    func healthWriteCandidates() async throws -> [SessionAttempt] {
        let envelope = try await ensureEnvelope()
        return envelope.attempts.filter {
            $0.isHealthWriteCandidate
        }
    }

    /// Resolves a queued ID against the current durable state immediately before
    /// HealthKit receives it. A previous pass may have completed or cancelled it.
    func healthWriteCandidate(id: UUID) async throws -> SessionAttempt? {
        let envelope = try await ensureEnvelope()
        guard let attempt = envelope.attempts.first(where: { $0.id == id }),
              attempt.isHealthWriteCandidate else { return nil }
        return attempt
    }

    func updateHealthState(id: UUID, state: SessionAttempt.HealthSyncState) async throws {
        _ = try await mutate { envelope in
            guard let index = envelope.attempts.firstIndex(where: { $0.id == id }) else {
                throw SessionLedgerError.attemptNotFound
            }
            let current = envelope.attempts[index].healthSyncState
            guard envelope.attempts[index].outcome == .completed,
                  envelope.attempts[index].healthWriteRequested else { return () }

            switch state {
            case .succeeded:
                // A save can reach HealthKit just before opt-out cancels its
                // unsent state. Preserve that accepted, irreversible result.
                guard current != .succeeded else { return () }
                envelope.attempts[index].healthSyncState = .succeeded
            case .failed:
                // A late failure must never turn a durable cancellation back
                // into a retry candidate.
                guard current == .pending || current == .failed else { return () }
                envelope.attempts[index].healthSyncState = .failed
            case .cancelled:
                guard current == .pending || current == .failed else { return () }
                envelope.attempts[index].healthSyncState = .cancelled
            case .notRequested, .pending:
                return ()
            }
            return ()
        }
    }

    func cancelOutstandingHealthWrites() async throws {
        _ = try await mutate { envelope in
            for index in envelope.attempts.indices where envelope.attempts[index].healthSyncState == .pending || envelope.attempts[index].healthSyncState == .failed {
                envelope.attempts[index].healthSyncState = .cancelled
            }
            return ()
        }
    }

    private func ensureEnvelope() async throws -> SessionLedgerEnvelope {
        if let envelope { return envelope }
        if let preparationTask { return try await preparationTask.value }

        let persistence = persistence
        let task = Task { () throws -> SessionLedgerEnvelope in
            guard let data = try await persistence.load() else {
                return .empty
            }
            do {
                let decoded = try JSONDecoder().decode(SessionLedgerEnvelope.self, from: data)
                guard decoded.schemaVersion == SessionLedgerEnvelope.currentSchemaVersion else {
                    throw SessionLedgerError.unsupportedSchema(decoded.schemaVersion)
                }
                return decoded
            } catch let error as SessionLedgerError {
                throw error
            } catch {
                throw SessionLedgerError.corruptStore
            }
        }
        preparationTask = task

        do {
            let loaded = try await task.value
            envelope = loaded
            preparationTask = nil
            return loaded
        } catch {
            preparationTask = nil
            throw error
        }
    }

    private func mutate<Value: Sendable>(
        _ operation: @Sendable (inout SessionLedgerEnvelope) throws -> Value
    ) async throws -> Value {
        await acquireMutation()
        defer { releaseMutation() }

        var candidate = try await ensureEnvelope()
        let value = try operation(&candidate)
        let data = try JSONEncoder().encode(candidate)
        try await persistence.save(data)
        envelope = candidate
        return value
    }

    private func acquireMutation() async {
        if !mutationInFlight {
            mutationInFlight = true
            return
        }
        await withCheckedContinuation { mutationWaiters.append($0) }
    }

    private func releaseMutation() {
        if mutationWaiters.isEmpty {
            mutationInFlight = false
        } else {
            mutationWaiters.removeFirst().resume()
        }
    }
}

private extension SessionAttempt {
    var isHealthWriteCandidate: Bool {
        outcome == .completed && healthWriteRequested
            && (healthSyncState == .pending || healthSyncState == .failed)
    }
}

/// One in-memory clock maps live focus playback to continuous time. It is never
/// persisted or recreated after launch; a persisted running attempt is interrupted.
@MainActor
final class SessionRuntime {
    let session: PerformanceSession
    private let clock = ContinuousClock()
    private let startedInstant: ContinuousClock.Instant

    init(session: PerformanceSession, startedInstant: ContinuousClock.Instant? = nil) {
        self.session = session
        self.startedInstant = startedInstant ?? clock.now
    }

    var id: UUID { session.id }

    func sample(at instant: ContinuousClock.Instant? = nil) -> PerformanceState {
        let current = instant ?? clock.now
        let elapsed = min(max(seconds(from: startedInstant.duration(to: current)), 0), session.duration.timeInterval)
        return PerformanceRunner(session: session).sample(
            at: session.startedAt.addingTimeInterval(elapsed)
        )
    }

    func sample(elapsedTime: TimeInterval) -> PerformanceState {
        let elapsed = min(max(elapsedTime, 0), session.duration.timeInterval)
        return PerformanceRunner(session: session).sample(
            at: session.startedAt.addingTimeInterval(elapsed)
        )
    }

    private func seconds(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

/// App-scoped lifecycle used by every production session. The story renderer samples
/// its `SessionRuntime`; the ledger records outcomes but never restores playback.
@MainActor
@Observable
final class SessionLifecycle {
    private let ledger: SessionLedgerStore
    private var preparationTask: Task<Void, Error>?
    private var isFinishing = false
    private var finishWaiters: [CheckedContinuation<SessionAttempt, Error>] = []
    private var completionTask: Task<Void, Never>?
    private var isStarting = false
    private var isDeleting = false
    private var activePresentationIsTerminal = false
    private var pendingTerminalEvent: SessionTerminalEvent?

    private(set) var isReady = false
    private(set) var activeRuntime: SessionRuntime?
    private(set) var activeStoryID: String?
    private(set) var activeOutcome: SessionAttempt.Outcome?
    private(set) var lastError: SessionLedgerError?
    var hasPendingTerminalEvent: Bool { pendingTerminalEvent != nil || isFinishing }

    init(ledger: SessionLedgerStore = SessionLedgerStore()) {
        self.ledger = ledger
    }

    func prepareForLaunch(observedAt: Date = .now) async {
        guard !isReady else { return }
        if let preparationTask {
            _ = try? await preparationTask.value
            return
        }

        let ledger = ledger
        let task = Task {
            _ = try await ledger.prepare()
            _ = try await ledger.reconcileOrphanedAttempts(observedAt: observedAt)
        }
        preparationTask = task

        do {
            try await task.value
            isReady = true
            lastError = nil
        } catch let error as SessionLedgerError {
            lastError = error
        } catch {
            lastError = .corruptStore
        }
        preparationTask = nil
    }

    func begin(story: Story, duration: FocusDuration, healthWriteRequested: Bool = false, startedAt: Date? = nil) async throws -> SessionRuntime {
        if !isReady {
            await prepareForLaunch()
        }
        guard isReady else { throw lastError ?? SessionLedgerError.lifecycleNotReady }
        guard activeRuntime == nil, !isStarting, !isFinishing, !isDeleting else {
            throw SessionLedgerError.activeSessionExists
        }

        isStarting = true
        defer { isStarting = false }

        // Capture the wall date beside the continuous runtime start only after
        // preparation has completed, so a delayed load cannot shorten a session.
        let resolvedStart = startedAt ?? .now
        let session = PerformanceSession(duration: duration, startedAt: resolvedStart)
        let runtime = SessionRuntime(session: session)
        let attempt = SessionAttempt(
            id: session.id,
            storyID: story.rawValue,
            plannedSeconds: duration.rawValue,
            startedAt: resolvedStart,
            randomSeed: session.randomSeed,
            healthWriteRequested: healthWriteRequested
        )

        do {
            _ = try await ledger.create(attempt)
            activeRuntime = runtime
            activeStoryID = story.rawValue
            activeOutcome = nil
            activePresentationIsTerminal = false
            startCompletionSupervision(for: runtime)
            lastError = nil
            return runtime
        } catch let error as SessionLedgerError {
            lastError = error
            throw error
        } catch {
            lastError = .corruptStore
            throw error
        }
    }

    func completeIfDue(id expectedID: UUID) async throws -> SessionAttempt {
        guard let runtime = activeRuntime else { throw SessionLedgerError.attemptNotFound }
        guard runtime.id == expectedID else { throw SessionLedgerError.attemptNotFound }
        if let pendingTerminalEvent { return try await finish(runtime: runtime, event: pendingTerminalEvent) }
        guard runtime.sample().isComplete else { throw SessionLedgerError.sessionNotDue }
        return try await finish(runtime: runtime, event: .completed)
    }

    func cancel(id expectedID: UUID, at occurredAt: Date = .now) async throws -> SessionAttempt {
        guard let runtime = activeRuntime else { throw SessionLedgerError.attemptNotFound }
        guard runtime.id == expectedID else { throw SessionLedgerError.attemptNotFound }
        if let pendingTerminalEvent { return try await finish(runtime: runtime, event: pendingTerminalEvent) }
        return try await finish(
            runtime: runtime,
            event: runtime.sample().isComplete ? .completed : .cancelled(occurredAt: occurredAt)
        )
    }

    /// Reserved for a future, proven protection integration. The supplied occurrence
    /// time is retained so a pre-deadline event is not confused with late delivery.
    func recordDistraction(
        id expectedID: UUID,
        occurredAt: Date,
        observedAt: Date = .now
    ) async throws -> SessionAttempt {
        guard let runtime = activeRuntime else { throw SessionLedgerError.attemptNotFound }
        guard runtime.id == expectedID else { throw SessionLedgerError.attemptNotFound }
        let event: SessionTerminalEvent = occurredAt < runtime.session.endDate
            ? .distracted(occurredAt: occurredAt, observedAt: observedAt)
            : (runtime.sample().isComplete
                ? .completed
                : .distracted(occurredAt: occurredAt, observedAt: observedAt))
        return try await finish(runtime: runtime, event: event)
    }

    func attempts() async throws -> [SessionAttempt] {
        try await ledger.attempts()
    }

    func deleteHistory() async throws {
        guard isReady, activeRuntime == nil, !isStarting, !isFinishing, !isDeleting else {
            throw SessionLedgerError.activeSessionExists
        }
        isDeleting = true
        defer { isDeleting = false }
        let ids = Set(try await ledger.attempts().map(\.id))
        try await ledger.delete(ids: ids)
    }

    /// The scene may continue showing its completed ending after the terminal write.
    /// It explicitly releases that in-memory presentation only when the user leaves.
    func dismissActivePresentation(id expectedID: UUID) {
        guard activePresentationIsTerminal,
              activeRuntime?.id == expectedID else { return }
        activeRuntime = nil
        activeStoryID = nil
        activeOutcome = nil
        activePresentationIsTerminal = false
        completionTask?.cancel()
        completionTask = nil
    }

    private func finish(
        runtime: SessionRuntime,
        event: SessionTerminalEvent
    ) async throws -> SessionAttempt {
        if isFinishing {
            return try await withCheckedThrowingContinuation { continuation in
                finishWaiters.append(continuation)
            }
        }
        isFinishing = true
        pendingTerminalEvent = event

        do {
            let attempt = try await ledger.terminalize(id: runtime.id, event: event)
            activePresentationIsTerminal = true
            activeOutcome = attempt.outcome
            pendingTerminalEvent = nil
            completionTask?.cancel()
            completionTask = nil
            lastError = nil
            resumeFinishWaiters(with: .success(attempt))
            return attempt
        } catch let error as SessionLedgerError {
            lastError = error
            resumeFinishWaiters(with: .failure(error))
            throw error
        } catch {
            lastError = .corruptStore
            resumeFinishWaiters(with: .failure(error))
            throw error
        }
    }

    private func resumeFinishWaiters(with result: Result<SessionAttempt, Error>) {
        isFinishing = false
        let waiters = finishWaiters
        finishWaiters = []
        for waiter in waiters {
            switch result {
            case let .success(attempt): waiter.resume(returning: attempt)
            case let .failure(error): waiter.resume(throwing: error)
            }
        }
    }

    private func startCompletionSupervision(for runtime: SessionRuntime) {
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            let remaining = runtime.sample().remainingTime
            guard remaining > 0 else {
                _ = try? await self?.completeIfDue(id: runtime.id)
                return
            }
            do {
                try await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
                _ = try await self?.completeIfDue(id: runtime.id)
            } catch is CancellationError {
                return
            } catch {
                // `completeIfDue` records the durable error for the presentation to retry.
            }
        }
    }
}
