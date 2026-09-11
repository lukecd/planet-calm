import ActivityKit
import Foundation
import Observation

@MainActor
extension PlanetFocusCountdownDescriptor {
    init(runtime: SessionRuntime, story: Story) {
        sessionID = runtime.id
        storyTitle = story.title
        // The session's authoritative progress is monotonic. Convert its
        // current remaining time to the date-based display contract only when
        // handing work to ActivityKit.
        scheduledEndAt = Date.now.addingTimeInterval(runtime.sample().remainingTime)
    }
}

enum LiveActivityAvailability: Equatable {
    case available
    case disabledBySystem
    case unavailable
}

protocol LiveActivityDriving: Sendable {
    var availability: LiveActivityAvailability { get }
    func startOrUpdate(_ descriptor: PlanetFocusCountdownDescriptor) async throws
    func end(sessionID: UUID) async
    func endAll() async
    func endAll(except sessionID: UUID) async
}

/// Owns ActivityKit side effects only. It mirrors a durable lifecycle outcome but
/// never treats an Activity's expiry, dismissal, or visibility as a session event.
@MainActor
@Observable
final class LiveActivitySessionCoordinator {
    enum Status: Equatable {
        case inactive
        case disabledByPreference
        case pendingForeground
        case unavailable
        case disabledBySystem
        case dismissedByUser
        case active(UUID)
        case failed
    }

    private let driver: any LiveActivityDriving
    private(set) var status: Status = .inactive
    private var didReconcileLaunch = false
    private var foregroundSceneIDs = Set<UUID>()
    private var latestIntent: QueuedIntent?
    private var synchronizationWorker: Task<Void, Never>?
    private var nextIntentID = 0
    private var completedIntentID = 0
    private var completionWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var suppressedSessionIDs = Set<UUID>()
    private var ownCleanupActivityIDs = Set<String>()
    private var currentActivityIDBySessionID: [UUID: String] = [:]
    private var observedActivityIDs = Set<String>()
    private var authorizationObservationTask: Task<Void, Never>?
    private var activityDiscoveryTask: Task<Void, Never>?
    private var activityStateTasks: [String: Task<Void, Never>] = [:]
    private var isObservingSystemState = false

    init(driver: any LiveActivityDriving = ActivityKitLiveActivityDriver()) {
        self.driver = driver
    }

    func synchronize(
        descriptor: PlanetFocusCountdownDescriptor?,
        isEnabled: Bool,
        sceneID: UUID? = nil,
        isForeground: Bool = true
    ) async {
        beginObservingSystemStateIfNeeded()
        let effectiveForeground: Bool
        if let sceneID {
            if isForeground {
                foregroundSceneIDs.insert(sceneID)
            } else {
                foregroundSceneIDs.remove(sceneID)
            }
            effectiveForeground = !foregroundSceneIDs.isEmpty
        } else {
            effectiveForeground = isForeground
        }
        await enqueue(.synchronize(
            descriptor: descriptor,
            isEnabled: isEnabled,
            isForeground: effectiveForeground
        ))
    }

    func sceneDidDisappear(_ sceneID: UUID) {
        foregroundSceneIDs.remove(sceneID)
    }

    /// Activities are display side effects. All requests and cleanup operations
    /// pass through one latest-intent worker so an older suspended request cannot
    /// recreate an Activity after a terminal or preference change has won.
    private func enqueue(_ kind: Intent) async {
        nextIntentID += 1
        let intent = QueuedIntent(id: nextIntentID, kind: kind)
        latestIntent = intent
        if synchronizationWorker == nil {
            synchronizationWorker = Task { [weak self] in
                await self?.drainIntents()
            }
        }
        await waitForCompletion(of: intent.id)
    }

    private func waitForCompletion(of intentID: Int) async {
        guard completedIntentID < intentID else { return }
        await withCheckedContinuation { continuation in
            completionWaiters[intentID, default: []].append(continuation)
        }
    }

    private func drainIntents() async {
        while let intent = latestIntent, intent.id > completedIntentID {
            await apply(intent)
            completedIntentID = intent.id
            let completedWaiters = completionWaiters.keys.filter { $0 <= intent.id }
            for waiterID in completedWaiters {
                completionWaiters.removeValue(forKey: waiterID)?.forEach { $0.resume() }
            }
        }
        synchronizationWorker = nil
    }

    private func apply(_ intent: QueuedIntent) async {
        switch intent.kind {
        case let .synchronize(descriptor, isEnabled, isForeground):
            await applySynchronization(
                descriptor: descriptor,
                isEnabled: isEnabled,
                isForeground: isForeground,
                intent: intent
            )
        }
    }

    private func applySynchronization(
        descriptor: PlanetFocusCountdownDescriptor?,
        isEnabled: Bool,
        isForeground: Bool,
        intent: QueuedIntent
    ) async {
        guard isEnabled else {
            markExistingActivitiesForOwnCleanup()
            await driver.endAll()
            setStatus(.disabledByPreference, for: intent)
            return
        }
        guard let descriptor else {
            markExistingActivitiesForOwnCleanup()
            await driver.endAll()
            setStatus(.inactive, for: intent)
            return
        }
        guard !suppressedSessionIDs.contains(descriptor.sessionID) else {
            setStatus(.dismissedByUser, for: intent)
            return
        }
        // Activity requests belong to an active foreground scene. Keep the
        // current display intact while backgrounded, then reconcile the latest
        // monotonic remaining time on the next foreground transition.
        guard isForeground else {
            setStatus(.pendingForeground, for: intent)
            return
        }

        switch driver.availability {
        case .unavailable:
            setStatus(.unavailable, for: intent)
        case .disabledBySystem:
            setStatus(.disabledBySystem, for: intent)
        case .available:
            do {
                markExistingActivitiesForOwnCleanup(except: descriptor.sessionID)
                await driver.endAll(except: descriptor.sessionID)
                // `endAll` can suspend. A later terminal or preference intent
                // must win before this operation is allowed to request an
                // Activity for the now-stale session.
                guard isCurrent(intent), !suppressedSessionIDs.contains(descriptor.sessionID) else { return }
                try await driver.startOrUpdate(descriptor)
                guard isCurrent(intent), !suppressedSessionIDs.contains(descriptor.sessionID) else { return }
                status = .active(descriptor.sessionID)
                observeExistingActivities()
            } catch {
                setStatus(.failed, for: intent)
            }
        }
    }

    /// Called after launch reconciliation. Activities for an orphaned, terminal,
    /// dismissed, or disabled session are cleaned up without altering the ledger.
    func reconcile(activeDescriptor: PlanetFocusCountdownDescriptor?, isEnabled: Bool) async {
        guard !didReconcileLaunch else { return }
        didReconcileLaunch = true
        await synchronize(descriptor: activeDescriptor, isEnabled: isEnabled)
    }

    private func setStatus(_ newStatus: Status, for intent: QueuedIntent) {
        guard isCurrent(intent) else { return }
        status = newStatus
    }

    private func isCurrent(_ intent: QueuedIntent) -> Bool {
        latestIntent?.id == intent.id
    }

    private func markExistingActivitiesForOwnCleanup(except preservedSessionID: UUID? = nil) {
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<PlanetFocusCountdownAttributes>.activities
        where activity.attributes.sessionID != preservedSessionID {
            ownCleanupActivityIDs.insert(activity.id)
        }
    }

    /// ActivityKit observations are display-only signals. A dismissal never
    /// changes the session ledger, but it does suppress recreating that same
    /// session's Activity until a distinct session is started.
    private func beginObservingSystemStateIfNeeded() {
        guard !isObservingSystemState, #available(iOS 16.1, *) else { return }
        isObservingSystemState = true

        authorizationObservationTask = Task { [weak self] in
            let authorization = ActivityAuthorizationInfo()
            for await enabled in authorization.activityEnablementUpdates {
                guard !Task.isCancelled, let self else { return }
                if !enabled {
                    self.status = .disabledBySystem
                }
            }
        }
        activityDiscoveryTask = Task { [weak self] in
            for await activity in Activity<PlanetFocusCountdownAttributes>.activityUpdates {
                guard !Task.isCancelled, let self else { return }
                self.observe(activity)
            }
        }
        observeExistingActivities()
    }

    private func observeExistingActivities() {
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<PlanetFocusCountdownAttributes>.activities {
            observe(activity)
        }
    }

    private func observe(_ activity: Activity<PlanetFocusCountdownAttributes>) {
        let sessionID = activity.attributes.sessionID
        let currentState = activity.activityState
        if currentState == .dismissed || currentState == .ended {
            handle(activityState: currentState, sessionID: sessionID, activityID: activity.id)
            return
        }
        guard observedActivityIDs.insert(activity.id).inserted else { return }
        currentActivityIDBySessionID[sessionID] = activity.id

        activityStateTasks[activity.id] = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled, let self else { return }
                self.handle(activityState: state, sessionID: sessionID, activityID: activity.id)
            }
        }
    }

    private func handle(activityState: ActivityState, sessionID: UUID, activityID: String) {
        if activityState == .dismissed {
            let wasOwnCleanup = ownCleanupActivityIDs.remove(activityID) != nil
            guard currentActivityIDBySessionID[sessionID] == activityID else { return }
            if !wasOwnCleanup { suppressedSessionIDs.insert(sessionID) }
            if !wasOwnCleanup, case .active(sessionID) = status {
                status = .dismissedByUser
            }
        } else if activityState == .ended {
            let wasOwnCleanup = ownCleanupActivityIDs.remove(activityID) != nil
            guard currentActivityIDBySessionID[sessionID] == activityID else { return }
            if !wasOwnCleanup {
                suppressedSessionIDs.insert(sessionID)
                if case .active(sessionID) = status {
                    status = .inactive
                }
            }
        }
        if activityState == .dismissed || activityState == .ended {
            if currentActivityIDBySessionID[sessionID] == activityID {
                currentActivityIDBySessionID[sessionID] = nil
            }
            activityStateTasks[activityID]?.cancel()
            activityStateTasks[activityID] = nil
            observedActivityIDs.remove(activityID)
        }
    }

    private enum Intent {
        case synchronize(
            descriptor: PlanetFocusCountdownDescriptor?,
            isEnabled: Bool,
            isForeground: Bool
        )
    }

    private struct QueuedIntent {
        let id: Int
        let kind: Intent
    }
}

private final class ActivityKitLiveActivityDriver: LiveActivityDriving, @unchecked Sendable {
    var availability: LiveActivityAvailability {
        guard #available(iOS 16.1, *) else { return .unavailable }
        return ActivityAuthorizationInfo().areActivitiesEnabled ? .available : .disabledBySystem
    }

    func startOrUpdate(_ descriptor: PlanetFocusCountdownDescriptor) async throws {
        guard #available(iOS 16.1, *) else { return }
        let content = ActivityContent(
            state: PlanetFocusCountdownAttributes.ContentState(
                scheduledEndAt: descriptor.scheduledEndAt
            ),
            staleDate: descriptor.scheduledEndAt
        )
        if let activity = matchingActivity(for: descriptor.sessionID) {
            await activity.update(content)
        } else {
            _ = try Activity.request(
                attributes: PlanetFocusCountdownAttributes(
                    sessionID: descriptor.sessionID,
                    storyTitle: descriptor.storyTitle
                ),
                content: content,
                pushType: nil
            )
        }
    }

    func end(sessionID: UUID) async {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = matchingActivity(for: sessionID) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    func endAll() async {
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<PlanetFocusCountdownAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func endAll(except sessionID: UUID) async {
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<PlanetFocusCountdownAttributes>.activities
        where activity.attributes.sessionID != sessionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func matchingActivity(for sessionID: UUID) -> Activity<PlanetFocusCountdownAttributes>? {
        Activity<PlanetFocusCountdownAttributes>.activities.first {
            $0.attributes.sessionID == sessionID
        }
    }
}
