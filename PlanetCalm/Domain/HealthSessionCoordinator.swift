import Foundation
import HealthKit
import Observation

protocol HealthSessionWriting: Sendable {
    func isAvailable() -> Bool
    func authorizationStatus() -> HKAuthorizationStatus
    func requestAuthorization() async throws
    func save(_ attempt: SessionAttempt) async throws
}

final class HealthKitSessionWriter: HealthSessionWriting, @unchecked Sendable {
    private let store = HKHealthStore()

    private var mindfulType: HKCategoryType { HKCategoryType(.mindfulSession) }

    func isAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func authorizationStatus() -> HKAuthorizationStatus {
        store.authorizationStatus(for: mindfulType)
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [mindfulType], read: [])
    }

    func save(_ attempt: SessionAttempt) async throws {
        let sample = HKCategorySample(
            type: mindfulType,
            value: HKCategoryValue.notApplicable.rawValue,
            start: attempt.startedAt,
            end: attempt.scheduledEndAt,
            metadata: [
                HKMetadataKeySyncIdentifier: attempt.healthSyncID.uuidString,
                HKMetadataKeySyncVersion: 1
            ]
        )
        try await store.save(sample)
    }
}

/// Coordinates optional, write-only Apple Health exports. The ledger owns every
/// durable state transition; this object only decides whether a send may begin.
@MainActor
@Observable
final class HealthSessionCoordinator {
    private static let preferenceKey = "preferences.health-enabled.v1"
    private static let cancellationPendingKey = "preferences.health-cancellation-pending.v1"

    private let ledger: SessionLedgerStore
    private let writer: any HealthSessionWriting
    private let defaults: UserDefaults
    private var generation = 0
    private var prepared = false
    private var cancellationPending: Bool
    private var isCancelling = false
    private var cancellationWaiters: [CheckedContinuation<Bool, Never>] = []
    private var isWriting = false
    private var needsAnotherWritePass = false

    private(set) var isEnabled: Bool
    private(set) var message: String?

    init(
        ledger: SessionLedgerStore,
        writer: any HealthSessionWriting = HealthKitSessionWriter(),
        defaults: UserDefaults = .standard
    ) {
        self.ledger = ledger
        self.writer = writer
        self.defaults = defaults
        let cancellationPending = defaults.object(forKey: Self.cancellationPendingKey) as? Bool ?? false
        self.cancellationPending = cancellationPending
        if cancellationPending {
            // A prior opt-out is authoritative even if the process ended between
            // writing its cancellation marker and saving the preference itself.
            defaults.set(false, forKey: Self.preferenceKey)
        }
        self.isEnabled = (defaults.object(forKey: Self.preferenceKey) as? Bool ?? false)
            && !cancellationPending
    }

    var isHealthDataAvailable: Bool {
        writer.isAvailable()
    }

    var authorizationStatus: HKAuthorizationStatus {
        guard writer.isAvailable() else { return .notDetermined }
        return writer.authorizationStatus()
    }

    /// Retries a previously interrupted opt-out before any export work can run.
    func prepare() async {
        guard !prepared else { return }
        guard !isEnabled || cancellationPending else {
            prepared = true
            return
        }
        if !cancellationPending {
            // Treat launch-time cleanup exactly like an interactive opt-out so a
            // concurrent enable waits for it instead of reopening old jobs.
            cancellationPending = true
            defaults.set(true, forKey: Self.cancellationPendingKey)
        }
        prepared = await cancelOutstandingWrites(reportFailure: true)
    }

    /// Requests sharing permission only after the user turns on the setting.
    func enable() async {
        let enableGeneration = generation
        guard writer.isAvailable() else {
            message = "Apple Health is not available on this device."
            return
        }

        // An opt-out that could not reach durable storage must finish before a
        // later opt-in. Otherwise a relaunch could resurrect its old jobs.
        if cancellationPending {
            let cancelled = await cancelOutstandingWrites(reportFailure: true)
            guard cancelled else { return }
        }
        guard generation == enableGeneration else { return }

        do {
            try await writer.requestAuthorization()
        } catch {
            guard generation == enableGeneration else { return }
            message = "Apple Health permission could not be requested."
            return
        }

        // The authorization sheet completing is not permission. Check the actual
        // sharing status, and do not let a completed sheet undo a concurrent opt-out.
        guard generation == enableGeneration else { return }
        guard writer.authorizationStatus() == .sharingAuthorized else {
            message = "Allow mindful-session writing in Apple Health to save future sessions."
            return
        }

        isEnabled = true
        defaults.set(true, forKey: Self.preferenceKey)
        message = nil
    }

    /// Stops future sends immediately, then durably cancels every unsent job.
    /// A save that was already handed to HealthKit can still finish; HealthKit
    /// samples cannot be withdrawn by this app after acceptance.
    func disable() async {
        generation &+= 1
        isEnabled = false
        defaults.set(false, forKey: Self.preferenceKey)
        cancellationPending = true
        defaults.set(true, forKey: Self.cancellationPendingKey)
        _ = await cancelOutstandingWrites(reportFailure: true)
    }

    /// Captured at the local begin boundary so changing the preference later never
    /// retroactively exports an earlier session.
    var shouldRequestWriteForNewSession: Bool {
        isEnabled && !cancellationPending && writer.isAvailable()
            && writer.authorizationStatus() == .sharingAuthorized
    }

    /// Performs at most one serial pass. Rechecking the generation after each
    /// suspension prevents an old candidate snapshot from continuing after opt-out.
    func writePendingSessions() async {
        await prepare()
        guard prepared, isEnabled, !cancellationPending, writer.isAvailable() else { return }
        guard writer.authorizationStatus() == .sharingAuthorized else {
            message = "Apple Health permission is off. Turn on mindful-session writing in Apple Health to save future sessions."
            return
        }

        guard !isWriting else {
            needsAnotherWritePass = true
            return
        }

        isWriting = true
        defer { isWriting = false }

        repeat {
            needsAnotherWritePass = false
            await writeOnePendingPass()
        } while needsAnotherWritePass && isEnabled
    }

    private func writeOnePendingPass() async {
        let passGeneration = generation
        let candidates: [SessionAttempt]
        do {
            candidates = try await ledger.healthWriteCandidates()
        } catch {
            message = "Mindful sessions could not be prepared for Apple Health. Please try again."
            return
        }

        var encounteredFailure = false
        for attempt in candidates {
            guard isEnabled, generation == passGeneration,
                  writer.authorizationStatus() == .sharingAuthorized else { return }

            // A candidate list is only a snapshot. Avoid saving an item another
            // pass already completed, cancelled, or deleted while we were away.
            let currentAttempt: SessionAttempt?
            do {
                currentAttempt = try await ledger.healthWriteCandidate(id: attempt.id)
            } catch {
                message = "Mindful sessions could not be prepared for Apple Health. Please try again."
                return
            }
            guard let currentAttempt else { continue }
            guard isEnabled, generation == passGeneration,
                  writer.authorizationStatus() == .sharingAuthorized else { return }

            do {
                // This is the last check before the external side effect. If it
                // passes, a later opt-out may only race an already-sent save.
                try await writer.save(currentAttempt)
                try await ledger.updateHealthState(id: currentAttempt.id, state: .succeeded)
            } catch {
                encounteredFailure = true
                do {
                    // The ledger refuses to replace a durable cancellation with a
                    // late failure, so a disabled job can never be resurrected.
                    try await ledger.updateHealthState(id: currentAttempt.id, state: .failed)
                } catch {
                    message = "Apple Health could not record this session state. Please try again."
                    return
                }
                if isEnabled, generation == passGeneration {
                    message = "A mindful session could not be saved. It will retry while Apple Health is on."
                }
            }
        }
        if !encounteredFailure, isEnabled, generation == passGeneration {
            message = nil
        }
    }

    private func cancelOutstandingWrites(reportFailure: Bool) async -> Bool {
        if isCancelling {
            return await withCheckedContinuation { cancellationWaiters.append($0) }
        }
        isCancelling = true
        let completed: Bool
        do {
            try await ledger.cancelOutstandingHealthWrites()
            cancellationPending = false
            defaults.set(false, forKey: Self.cancellationPendingKey)
            if !isEnabled { message = nil }
            completed = true
        } catch {
            prepared = false
            if reportFailure {
                message = "Apple Health is off for new sessions, but earlier unsent sessions could not be cancelled yet. Keep this setting off and try again."
            }
            completed = false
        }
        isCancelling = false
        let waiters = cancellationWaiters
        cancellationWaiters = []
        waiters.forEach { $0.resume(returning: completed) }
        return completed
    }
}
