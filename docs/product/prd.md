# Planet Focus — mindfulness, settings, and premium features

Status: implementation specification, updated 11 September 2026. Product decisions come from the owner conversation; platform constraints are linked below.

Start with the [code audit](code-audit.md), then use the [ordered implementation briefs](implementation-orders.md). The strict app-switch requirement remains a feasibility gate, not an established iOS capability.

## 1. Product and access

Planet Focus is a mindfulness timer. A chosen duration unfolds one complete, calm paper-cut story. Preserve the existing splash, story selection, duration selection, and shared story runtime. This release does not introduce work/break cycles, tasks, or a meditation course.

| Feature | Free | Paid |
| --- | --- | --- |
| Complete timer experience and one finished story | Yes | Yes |
| App blocking and allowed-app selection | Yes | Yes |
| Optional Apple Health mindful-session writing | Yes | Yes |
| Lock Screen countdown and completion sharing | Yes | Yes |
| Retention of session records on this device | Yes | Yes |
| Optional iCloud session-history sync across the user's devices | Yes | Yes |
| Personal historical analytics and history browsing | No | Yes, including activity recorded before upgrading |
| Additional finished stories | No | Yes; target approximately five or six additional stories |

Offer **subscriptions and a one-time lifetime purchase**, both unlocking the same premium features. Prices, subscription periods, and production product identifiers are owner inputs, not prescribed here. There is no separate paid tier for Health, Screen Time functionality, or allowed apps.

An **allowed app** is an exception to blocking. It is not an app selected for blocking. Use that wording in the UI instead of the ambiguous “whitelist apps to be blocked.”

### Implementation defaults

These fill gaps in the conversation and can be changed without revisiting the agreed access model:

- Autumn Tree is the initial free story because it currently has the developed narrative. Contemporary Lotus requires further story production before being sold as a finished experience.
- Always save locally, with optional free iCloud history sync through the user's Apple Account. No separate app account, custom backend, or third-party telemetry SDK is required. Local retention survives normal relaunches and upgrades; only successfully uploaded records can be recovered from iCloud after device loss or reinstall.
- Analytics, paywall presentation, purchasing, and additional-story merchandising are deferred until owner mockups are approved. Keep local session history for everyone.
- When purchasing is resumed, use RevenueCat as the approved integration direction. This does not authorize dashboard/account setup, product configuration, pricing, or adding the SDK before that implementation brief is reopened.
- Preserve public durations of 5–55 whole minutes. Retain the current initial five-minute selection, then remember the user's last selection.
- Preserve the current no-pause/no-session-restoration rule. A terminated process does not resume a running story after relaunch. Persisting an attempt is separate from restoring playback.
- Health writing is off until the user opts in. Blocking is off until configured and authorized. The Lock Screen feature is enabled by default where available and permitted. No automatic historical Health backfill.

## 2. Session contract

Use one authoritative session identity and clock across the scene, ledger, blocking, and Live Activity. The current `PerformanceSession`/`PerformanceRunner` timing and shared `StoryPlayer` must remain the basis of playback. Do not add an independent decrementing timer for each integration.

| Event | Required result |
| --- | --- |
| Begin | Validate duration, story access, and requested permissions; durably create a running attempt before presenting it as started. |
| Countdown reaches its scheduled end while the session remains valid | Commit completed once, with the scheduled end time; award the full selected duration once. |
| Phone locks | Session continues; the Lock Screen can show remaining time. Locking is not a failure. |
| User switches to an allowed app | Session continues. |
| User switches to a non-allowed app while strict protection is enabled | End as distracted; zero completion credit. This behavior must pass the feasibility gate. |
| User confirms End session before completion | End as cancelled; zero completion credit. |
| Process is terminated before a durable completion is established | On next launch, reconcile the orphaned attempt as interrupted; do not restore playback or infer success just because its deadline is in the past. |
| Normal background suspension with the same live session returning after its deadline | Reconcile against the authoritative clock and any valid interruption evidence; complete at the scheduled end if the session remained valid. |
| View is recreated, completion action repeated, or a callback arrives twice | Preserve the existing terminal result and do not duplicate totals, Health samples, or cleanup. |

These rules intentionally replace the old assumption that every app switch preserves a session. They do **not** authorize failing all background transitions: app switching, screen lock, calls, permission sheets, Control Center, and system interruptions must not be conflated.

Completion wins over a cancellation received after a legitimately completed deadline. An evidenced distraction before that deadline must not become a completion just because its callback was processed late. If an integration cannot provide the necessary timing evidence, record that limitation during feasibility testing rather than inventing certainty.

The user can always explicitly end a session. Keep emergency access available; do not claim that the app can trap someone inside itself. When protection is off or unavailable, clearly identify an unprotected session before starting. Never silently replace a requested protected session with an unprotected one.

### Durable records and outcomes

Maintain a versioned local ledger, independent of premium access. A minimal record contains:

- Stable session UUID, story ID, planned seconds, start and scheduled end timestamps, and relevant time-zone/calendar information.
- Outcome: running, completed, cancelled, distracted, or interrupted; terminal timestamp when known; observation timestamp separately when the actual interruption time is unknown.
- Credited seconds: planned seconds for a valid completion, zero for every unfinished outcome. Do not fabricate an exact force-termination time or duration.
- Protection configuration snapshot and Health-write intent, without exposing selected application tokens to analytics.
- Stable Health sync identity and pending/succeeded/failed/not-requested state, kept separate from completion outcome.

Record terminal state atomically before triggering external side effects. A Health failure must not undo local completion. A storage failure must not display a successfully saved result; retain the in-memory result for retry and report the problem. Reject a second simultaneous session, including from another iPad window.

On relaunch reconcile orphaned attempts and stale external state before starting another session. Never resurrect a cancelled or deleted record through delayed callbacks. Development previews, accelerated runs, Controls playback, and UI-test fixtures must not create real history, Health samples, or purchases.

### Optional iCloud history sync

Added by the owner on 11 September 2026, before Health implementation. Use CloudKit's private database with `CKSyncEngine`, retaining app-owned local storage and offline operation. Sync individual records rather than placing the entire mutable ledger file in iCloud Drive. Apple's engine supports custom local persistence; the app remains responsible for local merges and account-change handling. [Apple: CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-4b4w9), [Apple: sync integration](https://developer.apple.com/videos/play/wwdc2023/10188/).

- Implementation default: opt-in, initially off, under Data & help. Explain that enabling uploads existing eligible history and merges history from devices using the same Apple Account. No paid gate; browsing analytics remains deferred and paid.
- Sync terminal attempts, including zero-credit unfinished attempts, with their existing stable IDs and original dates/outcomes. Keep active timers, playback, device permissions, blocking selections, and preferences local in this first version. There is no cross-device session handoff or global active-session lock.
- Preserve the existing local ledger through any migration. Imports must be idempotent, must not become local orphaned running sessions, and must not create new completion credit or trigger Health writes. Keep Health permission, write intent, and retry state device-local; only the device that recorded a session may originate its Health write.
- Persist pending uploads, deletion markers, and sync-engine state so offline changes survive restart. A deletion must not be undone by an older device reconnecting. “Delete session history” deletes local records and queues deletion of linked iCloud records; the confirmation must explain that other devices update when sync resumes. Do not label this action “Delete local history.” Removing only a downloaded copy is not offered in this version.
- Keep each iCloud account's cached history and pending work isolated. Signing out or switching accounts must never upload the previous account's history into the new account. Enabling sync for existing local-only records is an explicit user action. Disabling sync stops new transfers and keeps local history; it does not silently delete cloud records.
- The app must work offline and without an iCloud account. Surface unavailable account, syncing, last successful sync, and actionable failure states truthfully. Do not promise instantaneous synchronization or treat sync as a substitute for an independent backup.
- Background iCloud updates are owner-approved. Enable silent remote notifications and initialize sync at process launch, independently of screen appearance. The same opt-in controls automatic and manual transfers; iOS controls background scheduling. Physical-device validation covers automatic reception without manual refresh; suspended-device wake delivery still needs separate validation.
- Apple setup uses the owner-approved Luke Cassady-Dorion team (`V88J4N5A7U`), app ID `com.planetcalm.app`, and private container `iCloud.com.planetcalm.app`. The container is configured for development device testing; App Store release still requires the tested CloudKit schema to be deployed to production.
- Acceptance requires an actual iPhone/iPad round trip on the same account, offline catch-up, duplicate delivery, deletion after offline use, migration, account isolation, opt-out, and proof that importing a session does not write a second Health sample. Local merge tests alone do not mean iCloud sync is implemented.

## 3. iOS feasibility: prove before promising

### Strict switching and allowed apps

Investigate public `FamilyControls`, `ManagedSettings`, and `DeviceActivity` APIs with individual authorization. They support system shielding and app selection, but that is not proof of a reliable, immediate “user switched to app X” event. Device Activity events concern usage thresholds; shield configuration requests concern presentation, and shield button callbacks concern button actions. None should be assumed to be an exhaustive app-opening notification. [Apple: DeviceActivityEvent](https://developer.apple.com/documentation/deviceactivity/deviceactivityevent), [shield configuration](https://developer.apple.com/documentation/managedsettingsui/shieldconfigurationdatasource).

Test all-app shielding with allowed application exceptions using Apple's picker and opaque tokens. Apple's category policy supports up to 50 application exceptions. Treat system exceptions and revocable authorization honestly; this is user-authorized protection, not device management. [Apple: all(except:)](https://developer.apple.com/documentation/managedsettings/shieldsettings/activitycategorypolicy/all%28except%3A%29), [individual authorization](https://developer.apple.com/videos/play/wwdc2022/110336/).

An app becoming inactive/backgrounded does not establish why. Protected-data availability is also not a universal lock detector: protection configuration affects its meaning. Do not use undocumented lock notifications, private APIs, or infer another app's identity from timing. [Apple: protected-data availability](https://developer.apple.com/documentation/uikit/uiapplication/isprotecteddataavailable), [Apple DTS discussion](https://developer.apple.com/forums/thread/69333).

**Go/no-go:** demonstrate on physical devices that disallowed switching fails the session, allowed switching preserves it, and locking preserves it without false failures during system interactions. Document OS/device coverage and unresolved cases. A block-only timer that continues behind a shield does not satisfy the owner's strict-failure requirement. If the combination cannot be delivered reliably, return a concise product decision before shipping that behavior. Independent ledger/settings/Health/purchase work can continue.

#### Feasibility status — 10 September 2026

**Unverified; blocked pending physical proof.** The checkout has no configured
development team, Family Controls capability, entitlement file, or Device Activity
extension, so it cannot currently install a protection harness. A valid development
signing identity and a connected iPhone 17 Pro are available on the host; a paired
iPad Pro 11-inch (M4) is also available. That establishes a potential test
environment, not that the app is signed, authorized, or approved for distribution.

The reviewed public API material documents individual authorization, app/category
shielding, Device Activity timing windows, and usage thresholds. It does not document
an exhaustive, timestamped callback for every app opening, so no implementation may
infer the required distraction event from scene backgrounding, locking, a shield
render, or a shield button action. No physical tests have yet established the required
allowed/disallowed distinction, lock preservation, authorization/revocation behavior,
or shield cleanup at 5, 10, 15, and 55 minutes. No block-only or background-failure
substitute is authorized. Family Controls distribution approval remains a separate
release dependency.

### Shield lifetime and short sessions

The public timer includes five-minute sessions, while Device Activity monitoring intervals have a 15-minute minimum. Its interval-end callback is tied to device use outside the interval, not a guarantee of code executing at the deadline while locked. Prove timely release when an app is opened after completion, and recovery after cancellation, process termination, reboot, and authorization revocation. Do not extend a five-minute block to 15 minutes or depend on an in-app sleep to remove shields while suspended. [Apple: intervalTooShort](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort), [intervalDidEnd](https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor/intervaldidend%28for%3A%29).

Family Controls distribution approval is required for the relevant app and extensions. Signing and approval are release dependencies; a simulator demonstration cannot establish readiness. [Apple: entitlement request](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement).

### Notifications and Screen Time accounting

Provide concise instructions for enabling an iOS Focus/Do Not Disturb and choosing allowed notifications. A Focus status API reports communication availability; it is not a general setter for system-wide notification suppression. Do not offer a toggle that falsely claims to silence other apps. A preferences row may open an in-app setup guide and optionally remind the user before a session. [Apple: INFocusStatus](https://developer.apple.com/documentation/intents/infocusstatus), [Focus setup](https://support.apple.com/en-ie/guide/iphone/iphd6288a67f/ios).

No documented public exemption was found that removes Planet Focus usage from Screen Time because it writes mindfulness data. Health and Screen Time are separate systems. Support locking the phone and test the observed accounting, but make no “doesn't count as screen time” claim. This is a research conclusion, not an explicit Apple guarantee about every accounting case. [Apple: Screen Time](https://support.apple.com/guide/iphone/get-started-with-screen-time-iphbfa595995/ios).

## 4. Settings and navigation

Wire the existing Settings and Stats menu items to real destinations. Settings uses the approved Paper Chapters home: **Your sessions** contains Session, Sound & display, and Apple Health; **Your app** contains Membership and Data & help. Its focused detail pages retain actual controls and honest unavailable states. Preserve story/splash artwork colors.

Use a warm-ivory light theme and ink-navy dark theme for functional Settings/Stats surfaces. Appearance defaults to System and persists System, Light, or Dark. Use clear system type for functional UI; the main Settings title alone may use handwriting. Keep the short rows/dividers, a bounded iPad column, and a reserved non-overlapping paper corner footer. Large Dynamic Type may scroll; it must not overlap controls.

| Group | Launch scope |
| --- | --- |
| Session | App protection status/setup; allowed apps; Lock Screen countdown preference; Focus notification setup guide. |
| Sound and display | Persist System/Light/Dark appearance, volume/mute, and keep-screen-awake (default off; only during an active foreground session). Do not imply production audio exists before it is ready. |
| Apple Health | Save completed mindfulness sessions; authorization/error explanation; instructions for managing permission. |
| Membership | Truthful deferred state for analytics, additional stories, and purchasing until approved mockups and the later purchase brief. |
| Data and help | Delete local history with confirmation, privacy policy, terms, support, app version, share app when a real App Store URL exists. |

Keep duration selection in the existing session setup. Keep Controls and art tuning separate from public settings. No paywall blocks permissions, allowed-app selection, deletion, purchase restoration, or completed-session sharing.

Request permissions only in response to relevant user actions, not all at first launch. Explain denial/revocation without repeated prompting. Permission failure must leave ordinary free timer functionality available through an explicit unprotected start. Freeze the running session's protection configuration; changes apply next session, and disabling active protection requires ending the session first.

Deleting session history is free, requires confirmation, replaces pending uploads with deletion markers, and cannot run midway through an active session. Linked iCloud records are deleted across synced devices when syncing resumes. Explain that samples already saved in Apple Health remain there; do not claim history deletion also deletes Apple's records. Preferences and purchase ownership survive history deletion.

## 5. Lock Screen countdown

Use an ActivityKit Live Activity, not a replacement for the system Lock Screen. Show the story name, remaining countdown, and a compact app identity in supported Lock Screen/Dynamic Island layouts. Use the session's dates with system-driven countdown rendering so displaying seconds does not require continual background execution. Clamp at zero. [Apple: Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).

Starting/updating/ending an activity is idempotent by session ID. Clear it on a known terminal result; reconcile leftovers when the app next runs. Dismissing a Live Activity does not cancel the session. Disabled Live Activities must not block the timer. A stale date only describes content freshness; it does not commit a session or guarantee that the system ends the activity at that instant. Test locked expiry explicitly and do not show an unverified completion claim merely because the countdown reaches zero. [Apple: staleDate](https://developer.apple.com/documentation/activitykit/activitycontent/staledate).

## 6. Apple Health

Write completed sessions as `HKCategoryTypeIdentifier.mindfulSession`, using the supported category value and actual session interval. Request **write permission only**; no health-reading feature is required. Check Health availability and sharing authorization independently of whether the authorization sheet completed successfully. The user can decline without losing timer functionality. [Apple: mindfulSession](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/mindfulsession), [authorization](https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization%28toshare%3Aread%3A%29).

Write only when the user opted in for the session, permission allows it, and its durable outcome is completed. Failed/cancelled/interrupted sessions never write a partial mindful interval. Opting in later does not silently export historical sessions. Turning the preference off cancels outstanding unsent jobs.

Use a stable per-session Health sync identifier with its paired sync version. Test repeat saves and crash recovery to establish one logical sample per session; do not use a new UUID or increment the sync version for every retry. Preserve successful-write state so deleting a sample in Health does not cause routine relaunches to recreate it. Retry transient failures without changing local credit, and surface persistent failure without blocking the next session. [Apple: sync identifiers](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier).

Do not send Health data or opaque app-selection tokens to advertising or product telemetry. Include accurate permission purpose strings and privacy disclosures. [Apple: review guidelines, 5.1.3](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research).

## 7. Personal analytics and sharing

**Deferred:** analytics/history presentation and its paywall remain out of the current implementation scope until owner mockups are approved. The ledger still retains local records; do not add analytics screens or upgrade flows in the meantime.

Store the ledger for everyone; gate the historical presentation and computations exposed to the user, not recording. Free users see their current completion result and a truthful explanation that upgrading reveals activity retained on this device. Never display fabricated personal trends as a teaser.

Premium MVP includes:

- Total mindful time and completed-session count for a selected period.
- Daily totals with week/month views, average completed-session length, and completed-time breakdown by story.
- History rows with date, story, planned duration, and outcome, including unfinished attempts clearly marked as zero credit.
- All-time totals and a usable empty state. No leaderboards or punitive broken streaks.

Compute total time as the sum of credited seconds, count only completed records, and average only across completed records. Round for display after aggregation. Capture the local completion date/time zone so historical daily buckets do not move when the user travels; use the current locale's week-start convention to group those stable dates. Test midnight, DST, time-zone changes, zero completions, deletion, and legacy/migrated records. Additional screens should not invent a separate analytics database or event pipeline.

Sharing is free after a valid completion: story artwork, the completed duration, and restrained Planet Focus branding through the native share sheet. It requires no profile or friend graph and does not publish automatically. Use a verified rendering/snapshot path: a SwiftUI snapshot alone may not capture a Metal-backed scene correctly. If necessary, use approved story-specific share artwork without flattening production scene layers. Verify the exported image, readability, and cancelled share behavior. Do not include app selections, Health permissions, or private historical details by default.

Developer product analytics are a separate future decision. This scope does not authorize installing a tracking SDK, creating a backend, or exporting the session ledger. Local diagnostic logs should avoid sensitive payloads.

## 8. Purchases and story access

**Deferred:** do not implement a paywall or purchasing until owner mockups are approved. The future purchase integration direction is RevenueCat, replacing the earlier native StoreKit-only instruction. No RevenueCat account, products, offerings, pricing, SDK dependency, or external configuration is authorized by this decision alone.

One premium entitlement is satisfied by either a verified active subscription or a verified lifetime non-consumable. Handle purchase cancellation, pending approval, verification failure, refund/revocation, renewal, grace period, expiration, offline cached access, and restored ownership. Never grant lifetime access from an unverified flag. Observe transaction updates and persist only what is needed to recover processing. [Apple: currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements).

Use localized product information returned by the store. Show recurring period and price for subscriptions, a clear one-time label for lifetime, restore access, terms/privacy links, and the correct subscription-management action. An unavailable store produces a retryable state while leaving free features usable. Production products and legal URLs must be supplied before release; test fixtures are not production configuration.

Downgrading or a refund hides premium analytics and prevents the next premium-story start, but preserves the ledger. Allow a session validly started with premium access to finish. Never restart or fail a running session due to an entitlement refresh. Recheck access at the actual start boundary, not only in the chooser. If the selected premium story becomes inaccessible, offer the free story for the next session.

Give stories stable identifiers and separate content readiness from free/premium access. Retain shared modules/directors; do not add per-story copies of the application runtime. A locked ready story can open the paywall; unfinished story content must not be represented as playable or as an already delivered paid benefit. Producing the additional five or six narratives is a separate art/content project.

## 9. Scope and release gates

Excluded: Pomodoro cycles, to-do lists, bedtime schedules, referral currencies, voice interaction, picture-in-picture, home-screen widgets, wallpaper export, Calendar/Reminders sync, separate app accounts, social feeds, independent cloud-backup/version-history features, and production of new stories/audio. Optional iCloud session-history sync is in scope. Competitor screenshots are reference material, not a requirement to clone these features.

Release requires:

1. A demonstrated strict-switch/lock/allowed-app policy or an explicit owner-approved replacement; reliable shield release across supported durations.
2. Correct durable outcomes, no duplicate credit or Health samples, no debug records, and no loss of prior history when purchasing or downgrading.
3. Signed device validation of Family Controls, Health, and ActivityKit, including iOS 17 support and currently supported OS versions. Any untestable platform case is reported.
4. StoreKit tests plus store sandbox validation for subscription and lifetime ownership; valid prices, product IDs, signing/team configuration, entitlement approvals, privacy/support/terms URLs, and finished paid content.
5. Accessible UI reviewed in iPhone portrait, iPad portrait and landscape, large Dynamic Type, VoiceOver, and Reduce Motion. Preserve existing scene and timing tests.

The implementation briefs define testable milestones. A successful simulator build alone does not clear the system-integration release gates.
