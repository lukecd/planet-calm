import SwiftUI

@main
struct PlanetCalmApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var sessionLifecycle: SessionLifecycle
    @State private var historySync: SessionHistorySyncCoordinator
    @State private var healthSync: HealthSessionCoordinator
    @State private var preferences = AppPreferences()
    @State private var idleTimer = FocusIdleTimerCoordinator()
    @State private var liveActivity = LiveActivitySessionCoordinator()
    @State private var splashAmbient = SplashAmbientPlayback()

    init() {
        let ledger = SessionLedgerStore()
        _sessionLifecycle = State(initialValue: SessionLifecycle(ledger: ledger))
        let sync = SessionHistorySyncCoordinator(ledger: ledger)
        _historySync = State(initialValue: sync)
        _healthSync = State(initialValue: HealthSessionCoordinator(ledger: ledger))
        PlanetFocusTypography.registerBundledFonts()
        // Silent iCloud notifications can launch the process without presenting
        // a view. Start the opted-in sync engine independently of view appearance.
        Task { await sync.prepare() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sessionLifecycle)
                .environment(preferences)
                .environment(idleTimer)
                .environment(liveActivity)
                .environment(historySync)
                .environment(healthSync)
                .environment(splashAmbient)
                .task {
                    await sessionLifecycle.prepareForLaunch()
                    let activeDescriptor: PlanetFocusCountdownDescriptor?
                    if let runtime = sessionLifecycle.activeRuntime,
                       let storyID = sessionLifecycle.activeStoryID,
                       let story = Story(rawValue: storyID) {
                        activeDescriptor = PlanetFocusCountdownDescriptor(runtime: runtime, story: story)
                    } else {
                        activeDescriptor = nil
                    }
                    await liveActivity.reconcile(
                        activeDescriptor: activeDescriptor,
                        isEnabled: preferences.lockScreenCountdownEnabled
                    )
                    await healthSync.prepare()
                    await healthSync.writePendingSessions()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await historySync.prepare() }
                        Task { await healthSync.writePendingSessions() }
                    }
                }
                .onChange(of: sessionLifecycle.activeOutcome) { _, outcome in
                    if outcome != nil {
                        Task { await historySync.historyDidChange() }
                        Task { await healthSync.writePendingSessions() }
                    }
                }
        }
    }
}
