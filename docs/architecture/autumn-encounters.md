# Autumn automatic encounters

`AutumnEncounterSchedule` in `AutumnTreeDirector.swift` is Autumn's creative policy.
It uses the existing `RandomMomentScheduler` for opportunities and the shared seeded
generator for choices. `AutumnBranchPlan` owns this immutable schedule, gust moments,
leaf releases, and the guaranteed deer. Both `AutumnTreeDirector` and the native
renderer consume it. The render cache builds the plan only when session/tuning changes.
There is no second timer, frame-based randomness, saved itinerary, or replay queue.

## Pacing

- Every 22–44 real seconds, evaluate a weighted choice: 50% breeze, 22% bird,
  28% quiet. A blocked choice becomes quiet, never a reroll.
- A breeze reserves at least 18 seconds for its pulse and spatial travel, extended
  when the development gust-duration control requires it. A bird reserves
  its entire approach/perch/departure plus eight quiet seconds.
- After departure, another bird is ineligible for a randomly chosen 90–170 seconds.
- Bird speed varies from 0.92–1.08, wingbeat from 1.4–1.7, depth from 0.9–1.15,
  and perch from 4–9 seconds. Approved geometry, landing and departure paths remain.
- Every bird must finish before both 82% progress and eight seconds before the deer.
  Random activity stops before the deer's approach. Its arrival is never a chance roll.
- One authored soft closing breeze follows the resting transition. One/two-minute
  development previews shorten opportunity spacing, never animal movement; their
  closing breeze may overlap the last resting seconds.

Wind independently chooses source side, source height, angle, breadth, travel speed,
attack, pulse shape, duration, and strength. It is not a strict left/right alternation.
Its shared field moves branches, airborne leaves, and the ground carpet. Late wind
retains the approved 78% intensity treatment.

Across 500 seeds, five-minute sessions average 0.85 birds (range 0–2) and 3.93
breezes. Fifty-five-minute sessions average 9.37 birds (range 5–13) and 46.19 breezes.
These are measured samples, not enforced quotas. A quiet session is valid.

## Ownership and integration

Production Begin already creates a fresh system-random session seed. That seed makes
the chosen performance stable for all consumers during that one session; it does not
offer the user restoration. Background/lock samples the current elapsed time. Expired
birds do not replay on return. Cancellation removes the session and manual events.
Reduce Motion uses the existing stationary perched pose instead of flight.

The Controls monitor shows the seed, counts, upcoming decisions, and guaranteed
ending times. Manual bird controls replace overlapping automatic visits completely
so no partially elapsed visit reappears after the study. Manual gusts do not reseed
or rewrite the automatic schedule. End the run before changing physics parameters.

For later music, consume the same `StoryMoment` identities and timestamps. Gust
audio intents already share their visual moments; animal audio is intentionally
unassigned. Do not invent a separate sound-side encounter schedule. Generic settings,
blocking, history, and preferences belong outside this story policy.

## Verification boundary

Model tests cover every duration from 5–55 minutes over 100 seeds each, plus pacing
over 500 seeds at each endpoint. They check unique IDs, irregular spacing, real-time
movement, cooldowns, full departure before the ending, manual overrides, and director
agreement. Existing physics and animal regression tests protect the approved artwork.
Simulator UI checks exercise an automatic visit without pressing the bird trigger.
Final physical-device validation is explicitly deferred until feature integration.
