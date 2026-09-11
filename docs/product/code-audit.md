# Settings and mindfulness implementation audit

Audited 10 September 2026 at `250b4923d9b5e950352624b69acf42c9a159e524`, the clean `main` baseline before creating `feat/settings`. Scope: readiness for the [product specification](prd.md), not a redesign or a general animation/physics audit. Application source was not changed.

## Findings in implementation order

### 1. Strict app-switch failure is unproved and conflicts with existing behavior

`PlanetCalm/Views/SplashScreenView.swift:1679` responds to scene-phase changes by synchronizing audio only. `PlanetCalmUITests/PlanetCalmUITests.swift:374` explicitly tests continued countdown after pressing Home and reactivating the app. This is correct for the previous runtime contract, but does not meet the newly requested strict behavior.

Do not patch this by failing every background event: that would also fail legitimate phone locking and system interruptions. First prove the requested distinction and shielding cleanup using public APIs on physical devices. See PRD section 3.

### 2. The clock works; durable outcomes and history do not exist

`PlanetCalm/Directors/PerformanceRunner.swift:8` defines the normalized time-based `PerformanceSession`. `PlanetCalm/Domain/FocusSession.swift:3` also contains timing state. Neither is a durable session ledger with a stable identity and terminal outcome. `SplashScreenView.swift:1290` holds the active session in view state; start at line 1541 constructs it, and exit at line 1545 clears it.

`PlanetCalm/Views/StoryLibraryView.swift:218` derives completion from progress for rendering. Its completion and cancellation paths eventually use the same `onBack` boundary. The task at `SplashScreenView.swift:1696` handles audio fade timing, not a saved completion transaction.

Build a single durable session lifecycle before analytics, Health, or sharing. Otherwise each feature will invent completion and duplicate or lose records. Keep the existing shared clock; do not restore a running story merely because an attempt was persisted.

### 3. Settings and Stats are exposed but do nothing

The menu enum includes both destinations in `SplashScreenView.swift:38`, but `selectMenu` at line 1748 only handles Start and Stories. This is an existing visible navigation gap.

`PlanetCalmUITests/PlanetCalmUITests.swift:736` taps those menu items in a navigation test without asserting a Settings or Stats destination. A passing baseline does not establish that either feature works. Add destination assertions when implementing them.

### 4. All requested system and purchase integrations are new work

No implementation was found for HealthKit, FamilyControls, ManagedSettings, DeviceActivity, ActivityKit, StoreKit purchases, session-history persistence, or completion sharing in the app sources. `PlanetCalm.xcodeproj/project.pbxproj:122` contains the app, unit-test, and UI-test targets, with no relevant extensions. Build settings at lines 152–155 establish Swift 6, iOS 17, iPhone/iPad, and an empty development team.

The project needs focused native services, appropriate capabilities/extensions, and physical-device signing. Family Controls distribution approval is an external dependency. These are planned feature gaps, not claims that previously implemented services are broken.

### 5. Public preferences are transient, and cancellation copy will become wrong

Volume/mute at `SplashScreenView.swift:1273`, selected story at `PlanetCalm/Views/RootView.swift:4`, and setup duration at `StoryLibraryView.swift:143` are view state. Existing persisted art-tuning data is not an app-preferences or session-history store.

Persist public preferences separately from Controls. Update the cancellation message at `StoryLibraryView.swift:300`, “Your progress won’t be saved,” because unfinished attempts will be retained. Explain zero mindful-minute credit without claiming the attempt disappears.

### 6. Premium catalog expansion needs readiness and access metadata

`PlanetCalm/Domain/Story.swift:3` has two stories, and the chooser at `StoryLibraryView.swift:34` offers the enum cases without access gating. `PlanetCalm/Stories/ContemporaryLotus/ContemporaryLotusStageView.swift:7` receives story context but currently presents a static pond/pad composition, not a completed narrative arc.

Retain the shared story module/player structure. Add stable access/readiness metadata and start-time entitlement checks. The settings work must not sell unfinished Lotus content or pretend that five or six additional finished stories already exist.

## What to preserve

- Shared normalized transport, deterministic seeded scheduling, and common visual/audio moments.
- Existing Autumn Tree choreography and layered rendering; this scope does not tune its animation.
- No user-facing pause or automatic restored scene after process termination.
- Current deployment target, Swift language mode, design tokens, and accessibility direction.
- Development Controls isolation. Their accelerated/debug sessions must remain outside real user history.

## Baseline verification

Ran the following existing selected tests on an iPhone 17 simulator, iOS 26.2: **12 passed, zero failures**.

Eight unit tests: whole-minute duration mapping; normalized/clamped progress; stable resumable performance transport; music runner pause/resume/persistence; shared visual/audio events; settings persistence without session events; deterministic seeded moment scheduling; Lotus shared player/Reduce Motion state.

Four UI tests: session cancellation/background/no restoration; completed scene holds its ending; scene settings/start; Start/Stories navigation. The final test's weak Settings/Stats coverage is described above.

The existing Release configuration also built successfully for a generic iOS Simulator destination with code signing disabled. Its only reported warning was skipped App Intents metadata extraction because no AppIntents framework dependency exists.

Local evidence: `/tmp/planet-focus-settings-audit-tests.log`, `/tmp/planet-focus-settings-audit-tests.xcresult`, and `/tmp/planet-focus-settings-audit-release.log`. These are local verification outputs, not committed artifacts. This was a focused baseline, not the full test suite and not device qualification for the proposed integrations.

## Documentation and prior PRD

The checkout contains architecture, design, and story documents, but no current comprehensive PRD. A path-based search of reachable Git history for PRD-named files and `docs/product/` found no matching commits; that does not establish that a PRD never existed under a different name or in unreachable history.

The new PRD is reconstructed from the owner's decisions. It explicitly supersedes the old general app-backgrounding behavior once feasibility is resolved. Older story notes and README milestones are not proof that new product integrations exist.
