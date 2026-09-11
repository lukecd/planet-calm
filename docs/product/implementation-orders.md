# Planet Focus — implementation briefs for Terra

Use one numbered brief per implementation task. Read the common instructions once in each fresh context, then execute only the selected brief. These are bounded implementation requests, not a new coordinator/runbook system.

## Common prompt

You are implementing Planet Focus's mindfulness product features. Read `AGENTS.md`, `docs/product/prd.md`, `docs/product/code-audit.md`, `docs/design/colors-and-ui.md`, and the relevant architecture/source files before editing. The PRD records the latest owner decisions and supersedes older notes where it explicitly says so.

Work on the owner's designated feature branch; verify the current branch and working tree first. Preserve unrelated work. Do not commit, push, install dependencies, or configure external services without authorization. Do not redesign or retune the story artwork. Use iOS 17, Swift 6, SwiftUI, modern concurrency, and the existing shared performance clock. Do not implement the entire roadmap in one pass.

Free features are timer, one story, app blocking, allowed apps, Health writing, Lock Screen countdown, and sharing. Premium unlocks personal analytics/history and additional ready stories through subscriptions or lifetime ownership. Retain local history for everyone before purchase. Only valid completed sessions earn credit or write to Health.

Implement the selected brief with the smallest appropriate native design. Report what changed, meaningful tests and results, limitations, and any inputs needed for the next brief. Do not treat simulated/fake adapters as proof of OS behavior. Do not add placeholder buttons that appear functional, production secrets, or invented paid content. Keep remaining user questions concise and specific.

## Build sequence

| Brief | Deliverable | Dependencies |
| --- | --- | --- |
| 0 | Physical-device feasibility decision | None; needs signing/device access |
| 1 | Durable session lifecycle and local ledger | Independent of brief 0's unresolved OS behavior |
| 2 | Settings and navigation | 1 |
| 3 | Free protection and Lock Screen integration | 0 accepted for protection; 1–2 |
| 4 | Free Health integration and completion sharing | 1–2; can proceed if protection is blocked |
| 5 | Subscription/lifetime purchases and catalog access | Deferred pending owner-approved mockups; future integration direction is RevenueCat |
| 6 | Premium analytics and integrated acceptance | Deferred pending owner-approved mockups and 5 |

If brief 0 is blocked, report why and continue independent foundations when requested. Never silently substitute block-only behavior for strict failure. Content production for additional stories is outside these briefs.

## Brief 0 — prove the iOS protection contract

**Objective:** determine whether the exact requested behavior can ship with public APIs: locking and allowed-app switching preserve a session; a non-allowed app switch ends it with zero credit.

Review the primary Apple sources in PRD section 3, then build only a minimal isolated native feasibility harness if necessary. Keep experimental code out of the production flow. Verify signing and Family Controls authorization availability first. Do not alter deployment targets to hide an unsupported case.

Distinguish reliable API evidence from inference. Establish whether there is an actual event for the required switch, its timestamp, and its behavior while the app is suspended. Do not treat scene backgrounding, protected-data changes, a shield configuration render, or a shield button press as equivalent events without proving the semantics. Test permission revocation and OS exceptions. Do not use private APIs or EU-only capabilities as a worldwide iOS 17 solution.

Also prove shield expiry for **5, 10, 15, and 55 minutes**, covering the 15-minute Device Activity interval minimum. A foreground task or mock clock does not prove release after the app is suspended. Test both opening a blocked app just before expiry and immediately after expiry while Planet Focus remains backgrounded.

Physical-device matrix: allowed/disallowed app opening, lock/unlock before and after deadline, calls, Control Center, notification interactions, authorization sheets, force-quit, device reboot, revocation, and system time changes. Include iPhone and iPad where supported, with device/OS versions and observed behavior. Mark any unavailable test environment explicitly.

**Acceptance:** a concise evidence-based go/no-go for switch detection, lock preservation, allowed apps, and timely cleanup, plus the API/extension design if viable. Update the PRD feasibility section with the result. If strict behavior is not reliable, present the limitation and a specific alternative for owner decision; do not implement that alternative as though it were approved. The remainder of the product can still be built behind a clear unresolved protection gate.

## Brief 1 — make session completion durable

**Objective:** establish the one source of truth used by every later feature.

Inspect `PerformanceSession`, `PerformanceRunner`, `StoryPlayer`, and the session start/exit/completion paths in `SplashScreenView` and `StoryLibraryView`. Add a stable session identity, a small app-owned observable lifecycle, and versioned local persistence for attempts and terminal results. Choose the simplest appropriate native persistence mechanism and document the choice; do not add a general event bus or duplicate story clock.

Implement the PRD outcome table and complete-only credit. Save the attempt before start; make terminal transitions atomic/idempotent. Separate completion, cancellation, distraction evidence, and unexpected interruption. Reconcile a returning live session from its dates. On cold launch, retain orphaned attempts as interrupted without restoring playback or crediting elapsed wall time as success. Preserve unknown interruption timestamps honestly.

Make cancellation wording match retained attempts. Prevent concurrent sessions across windows. Keep end-state scene presentation intact. Provide narrow boundaries for Health, protection, and Live Activity side effects without implementing those integrations yet. Exclude development previews and accelerated Controls runs from production persistence.

**Acceptance tests:** repeated completion commits once; cancellation/distraction before deadline earns zero; deadline/cancel ordering follows the PRD; returning after lock/background uses correct time; cold launch reconciles but never resumes; storage errors do not pretend success; deleting a record cannot be undone by a late callback; persistence reload/migration preserves all outcomes; a second scene cannot create overlapping sessions. Preserve the existing transport and story scheduling tests. Include wall-clock-change handling evidence rather than allowing manual time changes to silently manufacture mindfulness credit.

**Handoff:** state the concrete lifecycle/persistence interfaces, schema version, and which integration boundaries remain unavailable. Do not claim strict switching is implemented by accepting a synthetic distraction event in a unit test.

## Brief 2 — ship real Settings and Stats navigation

**Objective:** make the existing menu useful and persist public preferences.

Wire Settings and Stats destinations using the established navigation and design tokens. Read PRD section 4 for the launch rows and defaults. Keep current duration selection in session setup; remember selected duration/story and volume/mute. Separate public preferences from the existing art-tuning store. Apply keep-screen-awake only during active foreground sessions and restore normal idle behavior on all exits.

Build only honest integration states: not configured, denied, unavailable, ready, or pending implementation where appropriate in development. Do not ship controls claiming to block apps, silence notifications, or save to Health before the relevant integration exists. Add the Focus setup guide without pretending to set system Do Not Disturb.

Implement free confirmed local-history deletion, blocking deletion during an active session and cancelling queued work for deleted records. The approved Settings home is Paper Chapters: Session, Sound & display, and Apple Health under Your sessions; Membership and Data & help under Your app. Persist System/Light/Dark appearance (default System) and use paired warm-ivory/ink-navy functional surfaces while leaving authored story/splash colors intact. Membership is a truthful deferred state: analytics, paywall, and purchasing wait for owner mockups. Terms/privacy/support links require real configuration before release.

**Acceptance:** Settings and Stats taps assert actual destination content in UI tests; preferences survive relaunch; deletion preserves preferences and purchase ownership; unavailable integrations explain their state; VoiceOver, large Dynamic Type, and Reduce Motion work. Inspect iPhone portrait, iPad portrait, and landscape against the existing paper-cut direction. Do not change the splash/story art to make room for a generic settings design.

## Brief 3 — integrate free protection and Lock Screen countdown

**Objective:** implement the proven protection policy and a Live Activity using the shared session identity and clock.

Protection depends on an accepted brief 0 result. Add only the capabilities and extensions justified by that result. Use individual authorization, Apple's private app picker tokens, a free allowed-app list, a dedicated managed settings store, and a frozen per-session configuration. Handle denial/revocation explicitly. A requested protected start must either establish protection or explain failure before offering a clearly unprotected start.

Keep all system/OS exceptions visible in capability descriptions. Implement the validated distraction event and zero-credit result. Cancellation must clear the app's own restrictions. Recovery must remove stale restrictions without modifying unrelated system settings. Test the exact short-session strategy; do not leave users blocked until a longer schedule expires.

Add the free ActivityKit countdown with minimal shared data and accessible supported layouts. Use date-driven text, not continual app background ticks. Respect feature availability, user dismissal, and disabled Live Activities. Reconcile lifecycle cleanup independently of whether the activity is visible. Do not let its stale date or disappearance complete/cancel a session.

**Acceptance:** repeat brief 0's physical-device cases against the real ledger; prove exactly one appropriate outcome and cleanup in each. Verify native Lock Screen countdown while suspended, zero remaining time, early cancellation, stale activity recovery, and disabled/dismissed activity. Include denied/revoked entitlements, app force-quit, reboot, and five-minute sessions. Simulator unit tests cover adapter idempotency; device evidence covers actual OS behavior. Any unresolved strict requirement remains a release blocker.

**Independent portion:** the Live Activity can be implemented if protection is awaiting an owner decision. State that partial status plainly rather than marking the whole brief complete.

## Brief 4 — save mindfulness to Health and share completion

**Objective:** deliver the two free completion benefits without duplicating the completion logic.

Add a write-only HealthKit integration following PRD section 6, permission purpose strings, availability checks, optional opt-in, and clear denied/error states. No Health reads, automatic backfill, or purchase gate. Use stable sync identity/version and a durable write queue associated with completed session records. Keep retries independent from credit; turning the feature off or deleting a pending record must prevent unwanted later writes.

Add a native completion share sheet with readable artwork and duration. Verify that the export actually includes the intended scene, especially Metal-backed content; use approved share artwork if necessary. No social account, invitation economy, publishing endpoint, or tracking SDK. Sharing cancellation has no effect on the completed record.

**Acceptance:** completed opted-in record writes one logical mindful session with correct bounds; duplicate delivery/relaunch does not duplicate samples; failed/cancelled/interrupted/debug sessions never write; denied/unavailable Health leaves the timer working; transient retry does not change credit; prior successful writes do not get recreated merely because the user deleted a sample in Health; no historical export on first opt-in. Verify real-device Health behavior and inspect the actual exported image on iPhone/iPad. Include cancelled share and unavailable snapshot cases.

## Brief 5 — sell premium through subscriptions and lifetime

**Objective:** implement verified access to analytics and ready additional stories, while all core integrations remain free.

**Deferred pending owner mockups.** When reopened, use RevenueCat as the approved purchase integration direction and one shared premium-access model. This decision does not authorize installing the SDK, creating/configuring a RevenueCat account, products, offerings, pricing, or external services. List the exact owner inputs needed before any integration begins.

Load localized product information; implement purchase, pending/cancelled/error states, transaction verification and updates, restore purchases, and subscription management. Reconcile subscription expiration/grace/revocation and lifetime ownership according to verified store state. Test offline behavior with cached verified state and do not convert a temporary store error into a fabricated purchase or permanent unlock.

Add stable story IDs with separate readiness and access metadata. Keep Autumn Tree free by the PRD default. Guard premium starts as well as chooser taps. Do not sell unfinished stories as available. Honor a validly started session if access changes while running; apply the new access state to subsequent starts. Do not erase session history on downgrade or refresh.

**Acceptance when reopened:** exercise purchase/restore, pending approval, cancellation, verification failure, renewal/grace/expiry, refunds/revocation, interrupted transaction handling, and offline startup through the approved integration. Test lifetime plus expired subscription together: lifetime still grants access. A free user cannot bypass premium starts through saved selection/navigation, and upgrading reveals pre-purchase records without migration loss. Sandbox validation and production legal/product configuration remain separate release gates.

## Brief 6 — reveal premium history and validate the complete flow

**Deferred pending owner mockups.** When reopened, build paid personal statistics directly from the existing ledger and verify that monetization does not change session integrity.

Implement PRD section 7's summaries, daily/week/month views, all-time totals, story breakdown, and historical outcomes. Include every retained qualifying record, even before purchase. Distinguish zero-credit unfinished attempts from completed mindfulness. Use stable date buckets, aggregate seconds before rounding, and accessible chart summaries. Empty states must be real; no fabricated history in release.

Free users retain completion sharing and receive a concise upgrade explanation in Stats. Premium access reveals history immediately; downgrade hides premium presentation and preserves the underlying data. Make deletion recalculate analytics without restoring deleted data through pending integration callbacks. Do not add third-party product telemetry under the name of personal analytics.

**Acceptance tests:** datasets with mixed outcomes; no completions; a completion across midnight/DST; travel between time zones; week-start locale differences; deletion; upgrading after months of free history; expiration and lifetime restore. Charts and text must agree numerically. Verify selection boundaries and display rounding.

Finish with end-to-end free and paid flows, repeated launches, cancellation, completion, lock, allowed/disallowed switching where proven, Health retries, sharing, purchases, and cleanup. Re-run relevant existing story/runtime tests and a Release build. Inspect iPhone/iPad layouts and accessibility. Separate automated test results from real-device system-integration evidence and remaining store/capability/content inputs.

**Handoff for audit:** provide a short change summary, relevant file locations, executed test commands/results, physical-device observations, and remaining release blockers. Do not ask the reviewer to infer missing behavior from a successful build. Do not declare the paid content bundle ready before its additional narratives actually exist.
