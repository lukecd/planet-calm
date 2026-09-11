import SwiftUI
import Observation
import UIKit

struct RootView: View {
    @State private var selectedStory: Story = .autumnTree
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        Group {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--contemporary-lotus-review") {
                ContemporaryLotusReviewView()
            } else {
                SplashScreenView(selectedStory: $selectedStory)
            }
#else
            SplashScreenView(selectedStory: $selectedStory)
#endif
        }
        .onAppear { selectedStory = preferences.selectedStory }
        .onChange(of: selectedStory) { _, story in preferences.selectedStory = story }
    }
}

/// Process-scoped home atmosphere. It intentionally has no session, Health, or
/// history responsibility: it only supplies the wall-clock light state shown
/// while someone is browsing the app before beginning a meditation.
@MainActor
@Observable
final class SplashAmbientPlayback {
    static let halfCycleDuration: TimeInterval = 5 * 60
    static let cycleDuration: TimeInterval = halfCycleDuration * 2

    private(set) var startedAt: Date?
    var isActive: Bool { startedAt != nil }

    init(startedAt: Date? = nil) {
        self.startedAt = startedAt
    }

    func progress(at date: Date = .now) -> Double {
        guard let startedAt else { return 0 }
        let cycleProgress = max(date.timeIntervalSince(startedAt), 0)
            .truncatingRemainder(dividingBy: Self.cycleDuration) / Self.cycleDuration
        return 0.5 - 0.5 * cos(2 * .pi * cycleProgress)
    }

    func elapsed(at date: Date = .now) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(date.timeIntervalSince(startedAt), 0)
    }

    func beginIfNeeded(at date: Date = .now) {
        guard startedAt == nil else { return }
        startedAt = date
    }

    func restart(at date: Date = .now) {
        startedAt = date
    }

    func stop() {
        startedAt = nil
    }

    /// Keeps the browsing atmosphere alive when persistence rejects a start.
    func stopAfterSuccessfulFocusStart<Value>(
        _ start: () async throws -> Value
    ) async rethrows -> Value {
        let value = try await start()
        stop()
        return value
    }
}

enum InterfaceAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String { rawValue.capitalized }
}

@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let selectedStory = "preferences.selected-story.v1"
        static let durationSeconds = "preferences.duration-seconds.v1"
        static let volume = "preferences.volume.v1"
        static let muted = "preferences.muted.v1"
        static let lockScreenEnabled = "preferences.lock-screen-enabled.v1"
        static let keepScreenAwake = "preferences.keep-screen-awake.v1"
        static let interfaceAppearance = "preferences.interface-appearance.v1"
    }

    private let defaults: UserDefaults
    var selectedStory: Story { didSet { defaults.set(selectedStory.rawValue, forKey: Key.selectedStory) } }
    var lastDuration: FocusDuration { didSet { defaults.set(lastDuration.rawValue, forKey: Key.durationSeconds) } }
    var volume: Double { didSet { defaults.set(volume, forKey: Key.volume) } }
    var isMuted: Bool { didSet { defaults.set(isMuted, forKey: Key.muted) } }
    var lockScreenCountdownEnabled: Bool { didSet { defaults.set(lockScreenCountdownEnabled, forKey: Key.lockScreenEnabled) } }
    var keepScreenAwake: Bool { didSet { defaults.set(keepScreenAwake, forKey: Key.keepScreenAwake) } }
    var interfaceAppearance: InterfaceAppearance { didSet { defaults.set(interfaceAppearance.rawValue, forKey: Key.interfaceAppearance) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedStory = defaults.string(forKey: Key.selectedStory).flatMap(Story.init(rawValue:)) ?? .autumnTree
        lastDuration = defaults.object(forKey: Key.durationSeconds).flatMap { ($0 as? Int).flatMap(FocusDuration.init(rawValue:)) } ?? .fiveMinutes
        volume = min(max(defaults.object(forKey: Key.volume) as? Double ?? 0.65, 0), 1)
        isMuted = defaults.object(forKey: Key.muted) as? Bool ?? false
        lockScreenCountdownEnabled = defaults.object(forKey: Key.lockScreenEnabled) as? Bool ?? true
        keepScreenAwake = defaults.object(forKey: Key.keepScreenAwake) as? Bool ?? false
        interfaceAppearance = defaults.string(forKey: Key.interfaceAppearance).flatMap(InterfaceAppearance.init(rawValue:)) ?? .system
    }
}

/// Coordinates the process-wide idle timer from independent SwiftUI windows.
/// A window can only remove its own request, so backgrounding a second window
/// cannot re-enable screen sleep while another window is actively focusing.
@MainActor
@Observable
final class FocusIdleTimerCoordinator {
    private var eligibleRequests = Set<UUID>()
    private(set) var keepsScreenAwake = false

    func update(requestID: UUID, isEligible: Bool) {
        if isEligible {
            eligibleRequests.insert(requestID)
        } else {
            eligibleRequests.remove(requestID)
        }
        applyCurrentEligibility()
    }

    func remove(requestID: UUID) {
        eligibleRequests.remove(requestID)
        applyCurrentEligibility()
    }

    private func applyCurrentEligibility() {
        keepsScreenAwake = !eligibleRequests.isEmpty
        UIApplication.shared.isIdleTimerDisabled = keepsScreenAwake
    }
}

private enum SettingsPage: Hashable {
    case session
    case soundAndDisplay
    case health
    case membership
    case dataAndHelp
}

struct PreferencesView: View {
    let onBack: () -> Void
    @Environment(AppPreferences.self) private var preferences
    @Environment(SessionLifecycle.self) private var lifecycle
    @Environment(LiveActivitySessionCoordinator.self) private var liveActivity
    @Environment(SessionHistorySyncCoordinator.self) private var historySync
    @Environment(HealthSessionCoordinator.self) private var healthSync
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var settingsTitleSize = SettingsLayout.titleSize
    @State private var path: [SettingsPage] = []
    @State private var confirmsDeletion = false
    @State private var confirmsSync = false
    @State private var isChangingSync = false
    @State private var isChangingHealth = false
    @State private var message: String?

    private var palette: SettingsPalette { SettingsPalette(colorScheme: colorScheme) }

    var body: some View {
        @Bindable var preferences = preferences
        GeometryReader { geometry in
            let isPanel = geometry.size.width >= SettingsLayout.panelBreakpoint
            let panelWidth = dynamicTypeSize.isAccessibilitySize
                ? SettingsLayout.accessiblePanelWidth : SettingsLayout.panelWidth
            VStack(spacing: 0) {
                NavigationStack(path: $path) {
                    settingsHome
                        .navigationDestination(for: SettingsPage.self) { page in
                            detailPage(for: page, preferences: $preferences)
                        }
                }
                .background(palette.background)

                // This belongs to the paper surface, not to the scrolling document.
                palette.background
                    .frame(height: SettingsLayout.footerClearance)
                    .overlay(alignment: .bottomTrailing) {
                        SettingsPaperCorner(palette: palette)
                            .frame(width: SettingsLayout.cornerWidth, height: SettingsLayout.cornerHeight)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
            }
            .frame(
                width: isPanel ? min(panelWidth, geometry.size.width - SettingsLayout.panelMargin * 2) : geometry.size.width,
                height: isPanel ? min(dynamicTypeSize.isAccessibilitySize ? geometry.size.height : SettingsLayout.panelHeight,
                                      geometry.size.height - SettingsLayout.panelMargin * 2) : geometry.size.height
            )
            .background(palette.background)
            .clipShape(RoundedRectangle(cornerRadius: isPanel ? SettingsLayout.panelRadius : 0))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background((isPanel ? palette.surround : palette.background).ignoresSafeArea())
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .tint(palette.control)
        .alert("Delete session history?", isPresented: $confirmsDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteHistory() }
        } message: {
            Text("This cannot be undone. Sessions linked to iCloud will also be deleted from your other devices when syncing resumes. Your preferences and Apple Health records are kept.")
        }
        .alert("Sync sessions with iCloud?", isPresented: $confirmsSync) {
            Button("Cancel", role: .cancel) {}
            Button("Enable sync") { changeSync(enabled: true) }
        } message: {
            Text("Your existing sessions will be added to your private iCloud history and combined with sessions from your other devices. Use the same Apple Account on each device.")
        }
        .alert("Couldn’t delete history", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "Please try again.") }
        .preferredColorScheme(preferences.interfaceAppearance.colorScheme)
        .accessibilityIdentifier("settingsScreen")
    }

    private var settingsHome: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Settings")
                    .font(.custom("SueEllenFrancisco", fixedSize: min(settingsTitleSize, SettingsLayout.maximumTitleSize)))
                    .foregroundStyle(palette.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onBack) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.control)
                .accessibilityLabel("Back")
            }
            .padding(.horizontal, SettingsLayout.contentInset)
            .padding(.top, SettingsLayout.headerTop)
            .padding(.bottom, SettingsLayout.headerBottom)

            settingsSurface {
                VStack(alignment: .leading, spacing: SettingsLayout.chapterSpacing) {
                    SettingsChapter(title: "Your sessions", palette: palette) {
                        SettingsHomeRow(title: "Session", subtitle: "Blocking • Lock Screen", page: .session, palette: palette)
                        SettingsHomeRow(title: "Sound & display", subtitle: "Audio • Appearance", page: .soundAndDisplay, palette: palette)
                        SettingsHomeRow(title: "Apple Health", subtitle: "Mindful sessions", page: .health, palette: palette, showsDivider: false)
                    }

                    SettingsChapter(title: "Your app", palette: palette) {
                        SettingsHomeRow(title: "Membership", subtitle: "Analytics • More stories", page: .membership, palette: palette)
                        SettingsHomeRow(title: "Data & help", subtitle: "History • Support", page: .dataAndHelp, palette: palette, showsDivider: false)
                    }
                }
            }
        }
        .background(palette.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func detailPage(
        for page: SettingsPage,
        preferences: Bindable<AppPreferences>
    ) -> some View {
        settingsSurface {
            VStack(alignment: .leading, spacing: 28) {
                Text(detailTitle(for: page))
                    .font(PlanetFocusTypography.interface(.title, weight: .semibold))
                    .foregroundStyle(palette.title)
                    .accessibilityAddTraits(.isHeader)

                switch page {
                case .session:
                    settingsSection("Focus session") {
                        unavailable("App protection", "Not available in this build.")
                        unavailable("Allowed apps", "Available when app protection is available.")
                        Toggle("Lock Screen countdown", isOn: preferences.lockScreenCountdownEnabled)
                        detailText(lockScreenCountdownDetail)
                        Divider().overlay(palette.divider)
                        detailText("On your iPhone or iPad, open Settings > Focus. Choose or create a Focus, select allowed people and apps, then turn it on from Control Center. Planet Focus cannot turn it on for you.")
                    }
                case .soundAndDisplay:
                    settingsSection("Appearance") {
                        Picker("Appearance", selection: preferences.interfaceAppearance) {
                            ForEach(InterfaceAppearance.allCases) { appearance in
                                Text(appearance.title).tag(appearance)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    settingsSection("Audio") {
                        Toggle("Mute audio", isOn: preferences.isMuted)
                        HStack {
                            Text("Volume")
                            Spacer()
                            Text("\(Int((preferences.volume.wrappedValue * 100).rounded()))%")
                                .monospacedDigit()
                                .foregroundStyle(palette.secondary)
                        }
                        Slider(value: preferences.volume, in: 0...1)
                            .accessibilityLabel("Volume")
                            .accessibilityValue("\(Int((preferences.volume.wrappedValue * 100).rounded())) percent")
                    }
                    settingsSection("Screen") {
                        Toggle("Keep screen awake during a session", isOn: preferences.keepScreenAwake)
                        detailText("Applies only while a foreground focus session is running.")
                    }
                case .health:
                    settingsSection("Apple Health") {
                        Toggle("Save completed mindful sessions", isOn: Binding(
                            get: { healthSync.isEnabled },
                            set: { enabled in changeHealth(enabled: enabled) }
                        ))
                        .disabled(isChangingHealth || !healthSync.isHealthDataAvailable)
                        .accessibilityIdentifier("appleHealthToggle")

                        if !healthSync.isHealthDataAvailable {
                            detailText("Apple Health is not available on this device. Focus sessions still work.")
                        } else if healthSync.isEnabled {
                            detailText("Only completed sessions that begin while this setting is on are saved. Earlier sessions are not added.")
                        } else {
                            detailText("Turn this on to ask Apple Health for permission to save future completed sessions.")
                        }

                        if let message = healthSync.message {
                            detailText(message)
                                .accessibilityIdentifier("appleHealthStatus")
                        }

                        Divider().overlay(palette.divider)
                        detailText("To manage permission later, open the Health app, tap your profile, then Apps and Services > Planet Focus. Turning this off cancels unsent sessions; anything Apple Health already accepted remains in Health.")
                    }
                case .membership:
                    settingsSection("Membership") {
                        detailText("Membership options, analytics, and additional stories are not available in this build. Your session history is kept for when analytics arrive.")
                    }
                case .dataAndHelp:
                    iCloudSection
                    settingsSection("Session history") {
                        Button(role: .destructive) { confirmsDeletion = true } label: {
                            Text("Delete session history")
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                            .foregroundStyle(palette.destructive)
                            .disabled(lifecycle.activeRuntime != nil)
                        detailText(lifecycle.activeRuntime == nil
                                   ? "Your preferences and any sessions already saved in Apple Health are kept."
                                   : "Finish or end the active session before deleting history.")
                        Divider().overlay(palette.divider)
                        HStack {
                            Text("App version")
                            Spacer()
                            Text(appVersion).monospacedDigit().foregroundStyle(palette.secondary)
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func settingsSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SettingsLayout.contentInset)
                .padding(.top, SettingsLayout.contentTop)
                .padding(.bottom, SettingsLayout.contentBottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            palette.background.ignoresSafeArea()
        }
        .foregroundStyle(palette.primary)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(PlanetFocusTypography.interface(.title3, weight: .semibold))
                .foregroundStyle(palette.section)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .font(PlanetFocusTypography.interface(.body))
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(PlanetFocusTypography.interface(.footnote))
            .foregroundStyle(palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func unavailable(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(PlanetFocusTypography.interface(.body, weight: .medium))
            detailText(detail)
        }
    }

    private func detailTitle(for page: SettingsPage) -> String {
        switch page {
        case .session: "Session"
        case .soundAndDisplay: "Sound & display"
        case .health: "Apple Health"
        case .membership: "Membership"
        case .dataAndHelp: "Data & help"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unavailable"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var lockScreenCountdownDetail: String {
        switch liveActivity.status {
        case .unavailable: "Live Activities are not available on this device. Focus sessions still work."
        case .disabledBySystem: "Live Activities are disabled in system settings. Focus sessions still work."
        case .dismissedByUser: "The Lock Screen countdown was dismissed. This focus session still works."
        case .failed: "The Lock Screen countdown could not start. Focus sessions still work."
        case .active: "The Lock Screen countdown is active for this focus session."
        case .pendingForeground: "The Lock Screen countdown will update when Planet Focus returns to the foreground."
        case .inactive, .disabledByPreference: "Shows a remaining-time countdown when Live Activities are available."
        }
    }

    private func deleteHistory() {
        Task {
            do {
                try await lifecycle.deleteHistory()
                await historySync.historyDidChange()
            }
            catch { message = error.localizedDescription }
        }
    }

    private var iCloudSection: some View {
        settingsSection("iCloud") {
            Toggle("Sync session history", isOn: Binding(
                get: { historySync.isEnabled },
                set: { enabled in
                    if enabled { confirmsSync = true }
                    else { changeSync(enabled: false) }
                }
            ))
            .disabled(isChangingSync)
            .accessibilityIdentifier("iCloudSyncToggle")

            detailText("Keep your session history together on iPhone and iPad. Sessions always save on this device, even when you’re offline.")

            if let error = historySync.lastErrorDescription {
                detailText(error)
                    .accessibilityIdentifier("iCloudSyncStatus")
            } else if historySync.isSyncing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Syncing sessions…")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("iCloudSyncStatus")
            } else if historySync.isEnabled {
                if historySync.pendingUploadCount > 0 {
                    detailText("Changes are waiting to sync. Your sessions are saved on this device.")
                }
                if let date = historySync.lastSuccessfulSyncAt {
                    detailText("Last synced \(date.formatted(date: .abbreviated, time: .shortened)).")
                        .accessibilityIdentifier("iCloudSyncStatus")
                } else {
                    detailText("Waiting to sync. Your sessions are saved on this device.")
                        .accessibilityIdentifier("iCloudSyncStatus")
                }
            } else {
                detailText("iCloud sync is off. Existing sessions stay on each device and in iCloud.")
                    .accessibilityIdentifier("iCloudSyncStatus")
            }

            if historySync.isEnabled {
                Button {
                    Task { await historySync.syncNow() }
                } label: {
                    Text("Sync now")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(isChangingSync || historySync.isSyncing)
            }
        }
    }

    private func changeSync(enabled: Bool) {
        isChangingSync = true
        Task {
            if enabled { await historySync.enable() }
            else { await historySync.disable() }
            isChangingSync = false
        }
    }

    private func changeHealth(enabled: Bool) {
        isChangingHealth = true
        Task {
            if enabled { await healthSync.enable() }
            else { await healthSync.disable() }
            isChangingHealth = false
        }
    }
}

private enum SettingsLayout {
    static let titleSize: CGFloat = 44
    static let maximumTitleSize: CGFloat = 64
    static let panelBreakpoint: CGFloat = 700
    static let panelWidth: CGFloat = 640
    static let accessiblePanelWidth: CGFloat = 840
    static let panelHeight: CGFloat = 880
    static let panelMargin: CGFloat = 32
    static let panelRadius: CGFloat = 24
    static let contentInset: CGFloat = 28
    static let headerTop: CGFloat = 20
    static let headerBottom: CGFloat = 22
    static let contentTop: CGFloat = 8
    static let contentBottom: CGFloat = 24
    static let chapterSpacing: CGFloat = 26
    static let footerClearance: CGFloat = 76
    static let cornerWidth: CGFloat = 210
    static let cornerHeight: CGFloat = 76
}

private struct SettingsChapter<Content: View>: View {
    let title: String
    let palette: SettingsPalette
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(PlanetFocusTypography.interface(.headline, weight: .semibold))
                .foregroundStyle(palette.section)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(palette.divider).frame(height: 1)
            content
        }
    }
}

private struct SettingsHomeRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let subtitle: String
    let page: SettingsPage
    let palette: SettingsPalette
    var showsDivider = true

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(value: page) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(PlanetFocusTypography.interface(.title3, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(PlanetFocusTypography.interface(.body))
                            .foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.control)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 16)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.primary)
            .accessibilityIdentifier("settings-\(title)")
            if showsDivider {
                Rectangle().fill(palette.divider).frame(height: 1)
            }
        }
    }
}

private struct SettingsPalette {
    var destructive: Color { isDark ? Color(red: 1, green: 0.68, blue: 0.65) : Color(red: 0.65, green: 0.12, blue: 0.12) }
    let colorScheme: ColorScheme

    private var isDark: Bool { colorScheme == .dark }
    var background: Color { isDark ? PlanetFocusPalette.canvasInk : Color(red: 249 / 255, green: 245 / 255, blue: 237 / 255) }
    var surround: Color { isDark ? Color(red: 5 / 255, green: 10 / 255, blue: 23 / 255) : Color(red: 235 / 255, green: 230 / 255, blue: 220 / 255) }
    var primary: Color { isDark ? Color(red: 247 / 255, green: 245 / 255, blue: 240 / 255) : PlanetFocusPalette.canvasInk }
    var secondary: Color { isDark ? PlanetFocusPalette.typePaleBlue : Color(red: 43 / 255, green: 75 / 255, blue: 123 / 255) }
    var section: Color { isDark ? PlanetFocusPalette.typePaleBlue : PlanetFocusPalette.waveDeep }
    var title: Color { isDark ? PlanetFocusPalette.warmYellow : PlanetFocusPalette.canvasInk }
    var control: Color { isDark ? PlanetFocusPalette.typePaleBlue : PlanetFocusPalette.waveDeep }
    var divider: Color { isDark ? PlanetFocusPalette.waveMid.opacity(0.82) : PlanetFocusPalette.wavePeriwinkle.opacity(0.54) }
}

private struct SettingsPaperCorner: View {
    let palette: SettingsPalette

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SettingsCornerWave(isFold: false).fill(PlanetFocusPalette.waveMid)
            SettingsCornerWave(isFold: true).fill(PlanetFocusPalette.wavePeriwinkle)
            SettingsCornerWarmSlip().fill(PlanetFocusPalette.warmYellow)
        }
        .opacity(palette.colorScheme == .dark ? 0.92 : 0.9)
    }
}

private struct SettingsCornerWarmSlip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.68, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.48),
            control1: CGPoint(x: rect.width * 0.80, y: rect.height * 0.76),
            control2: CGPoint(x: rect.width * 0.9, y: rect.height * 0.58)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SettingsCornerWave: Shape {
    let isFold: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * (isFold ? 0.43 : 0), y: rect.maxY))
        if isFold {
            path.addCurve(to: CGPoint(x: rect.maxX, y: 0),
                          control1: CGPoint(x: rect.width * 0.75, y: rect.height * 0.72),
                          control2: CGPoint(x: rect.width * 0.68, y: rect.height * 0.20))
        } else {
            path.addCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.28),
                          control1: CGPoint(x: rect.width * 0.35, y: rect.height * 0.45),
                          control2: CGPoint(x: rect.width * 0.62, y: rect.height * 0.72))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct StatsDestinationView: View {
    let onBack: () -> Void
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.colorScheme) private var colorScheme

    private var palette: SettingsPalette { SettingsPalette(colorScheme: colorScheme) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Stats")
                    .font(PlanetFocusTypography.interface(.largeTitle, weight: .semibold))
                    .foregroundStyle(palette.title)
                Text("Your session history stays on this device. This build does not yet include history browsing or analytics.")
                    .font(PlanetFocusTypography.interface(.body))
                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.background.ignoresSafeArea())
            .foregroundStyle(palette.primary)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Back", action: onBack) } }
        }
        .preferredColorScheme(preferences.interfaceAppearance.colorScheme)
        .accessibilityIdentifier("statsScreen")
    }
}
