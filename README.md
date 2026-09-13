# Planet Calm

Planet Calm is the native iOS project for **Planet Focus**, a focus timer in
which each completed session unfolds a calm, tactile paper-cut story.

The current flow is:

1. responsive Planet Focus splash screen;
2. story selection;
3. duration selection;
4. timed Autumn Tree playback or the Contemporary Lotus scene checkpoint.

Before a meditation begins, Home runs a quiet, visual-only ten-minute sunrise/sunset
loop that continues while browsing. Beginning a persisted meditation stops it; returning
Home afterward starts a fresh night cycle. Reduce Motion keeps the visual atmosphere
static.

The mindfulness, settings, and premium feature specification is in
[the product PRD](docs/product/prd.md). The accompanying
[code audit](docs/product/code-audit.md) identifies current gaps, and
[implementation briefs](docs/product/implementation-orders.md) define the build order.

## Project

- Xcode project: `PlanetCalm.xcodeproj`
- App target: `PlanetCalm`
- Unit tests: `PlanetCalmTests`
- UI tests: `PlanetCalmUITests`
- Deployment target: iOS 17
- Supported device families: iPhone and iPad

Open `PlanetCalm.xcodeproj` in Xcode and run the `PlanetCalm` scheme. The app
uses bundled fonts and local story artwork; it has no third-party package
dependencies.

## Session history and iCloud

Sessions save locally. Settings → Data & help offers free, optional iCloud sync
between devices using the same Apple Account. It syncs finished attempts, never
active timers, device permissions, or Health-write state. Deletions propagate to
linked devices when syncing resumes; switching sync off keeps existing history.

The app uses native CloudKit with the Luke Cassady-Dorion development team and
`iCloud.com.planetcalm.app`. Debug builds use the development environment;
Release uses production, whose schema must be deployed before distribution.
Foreground sync runs on opening the app, after session completion, and through
“Sync now.” Silent CloudKit notifications also allow background updates when
iOS schedules them; delivery is not immediate or guaranteed. The user's iCloud
sync setting controls both foreground and background syncing.

`CloudKitDeviceTests` is an explicitly selected physical-device test, skipped in
ordinary runs. It uses a separate ledger and a `PlanetFocusValidation…` zone so
test sessions do not enter normal user history. Analytics and purchase screens
remain deferred.

## Apple Health

Settings → Apple Health offers optional, write-only Mindful Minutes permission.
Only completed sessions started locally with the setting and permission enabled
are saved. Earlier sessions and imported iCloud history never create Health
entries. Failed saves retry on foreground or a later session completion using
the original interval and stable HealthKit sync metadata.

Turning the setting off cancels unsent entries, including across relaunches.
An already accepted Health save remains in Health, as do entries whose app
history is deleted. The timer works without Health permission. Simulator-only
`HealthKitIntegrationTests` validates repeated saves against the real HealthKit
API when explicitly enabled; it never writes fixtures on physical devices.

## Architecture

`StoryPlayer` owns authoritative session time and evaluates a deterministic
story plan created by a story-specific `StoryDirector`. Visual and future audio
systems consume the same `StoryMoment` values rather than commanding one
another. See `docs/architecture/generative-performance-system.md`.

For the animation-first Ableton workflow, `scripts/export_story_score` writes a
deterministic MIDI file, semantic cue sheet, and metadata for a selected story,
duration, and seed. Autumn's MIDI remains intentionally empty until its animation
choreography is refined; its current cue sheet is the traceable sound-design map.

The approved outer palette, responsive splash rules, typography, paper
material, and animation boundaries live in `docs/design/colors-and-ui.md`.
Story direction lives in `docs/stories/`.

## Repository policy

Only production source, bundled assets, concise specifications, and the single
approved splash reference belong in the repository. Simulator captures, build
products, prompt archives, generated galleries, and review-run evidence stay
local.
