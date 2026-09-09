# Autumn branch checkpoint

Status: integrated branch study, not the completed Autumn tree or its final sunset.
The actual Autumn route hosts this checkpoint; no new lab navigation is introduced.
Existing landscape and maple alpha artwork are reused. The full-tree resources and
the older laboratory physics fixtures remain available for later migration.

## Shared contracts

PerformanceSession and PerformanceRunner remain the authoritative transport.
StoryPlayer now accepts explicit elapsed time, so the story renderer need not
reconstruct a clock from a FocusSession that has lost its pause state.

PerformanceNoteEvent.swift owns the reusable event, role, ADSR, sound asset key and
three-pool blend contracts. Existing Splash-prefixed names are compatibility aliases,
not duplicate implementations. Splash keeps its approved score and atmosphere.
Autumn uses Warm / Amber / Dusk as its provisional bank labels; only the weights and
breeze audio intents are exposed in this checkpoint. No Autumn music plays yet.

SplashScreenView still owns navigation and the contextual performance desk. It passes
the actual PerformanceSession and AutumnBranchRecord into StorySceneLaunchView.
The active story identity and branch record are saved alongside the session.
A release build has Begin and Pause/Resume controls; tuning remains DEBUG-only.

## Direction and simulation

AutumnBranchPlan places three gusts at 8%, 40%, and 72% of the selected duration.
Manual gusts are appended to the same event list at the shared elapsed time.
A gust keeps its duration in seconds regardless of the total meditation length.

The spatial field delays gust arrival along the branch. Its attack and decay use the
existing smooth GustPlan envelope. Two damped torsion springs provide the branch's
small-angle response; twig attachment points come from the same quadratic centerline
used to draw the main branch. Three of the six leaves are eligible to release.

AutumnBranchSimulation samples in fixed 1/120-second steps, independent of redraw rate.
It reuses LeafAerodynamics lift, drag, pressure-point torque, and resistance with the
existing calibrated Gate 3 configuration. These are quasi-steady 2D plate dynamics,
not CFD. A limited visual fold follows rotation smoothly; it is not full flexible
sheet mechanics. Ground contact uses a simple receiving plane, damped sliding and
settling rather than the full old terrain/contact solver.

An eligible leaf retains its identity, position, angle and velocities at release.
Landed leaves remain visible. Three attached leaves remain to show branch response
after the demonstration releases.

Pause freezes the sampled time. Restoration and backward inspection replay the same
fixed steps from the initial state. The in-memory cache avoids replay during ordinary
forward display. This checkpoint does not promise cross-version/platform bitwise
physics determinism. Before full-tree expansion, profile long-run reconstruction and
add versioned sparse checkpoints if required; do not add a competing clock.

Physics controls are locked while a run exists. End the run, tune, and restart to
avoid retroactively rewriting motion. The same seed repeats a run. Manual gusts and
tuning persist with it. Light-position inspection is available only outside a run;
during playback progress is the sole owner. Sun intensity, shadow softness and
backlight remain live-adjustable without invalidating the physics cache.

## Rendering and limits

Autumn's Metal sky fragment reuses the existing atmospheric integral. Its fixed-view
projection, paper treatment and sun path are its own; it does not reverse the splash
timeline. The approved splash fragment is unchanged.

Maple silhouettes mask independently colored paper and neutral local grain.
Grayscale detail from the existing assets supplies restrained veins/material detail;
the original baked color is not the animated pigment.

Leaf orientation and the shared visible sun position determine diffuse illumination.
Warm transmission, ambient fill, shallow projected alpha shadows, and contact
shading are artistic approximations. There is no global illumination, mutual
leaf-to-leaf shadow map, full 3D terrain receiver, or full-tree canopy-ray system yet.
Do not describe this checkpoint as providing those effects.

Reduce Motion keeps the branch and attached leaves still and presents released
leaves at ground level. The session and lighting still evolve.

## Validation

Model tests cover cadence-independent replay, release continuity, finite poses,
settling, pause/restoration, gust durations and manual-event serialization.
Splash score, pool selection and envelope regressions protect the shared extraction.

UI tests capture light at every 5%, exercise playback controls, and capture successive
live-motion states. Inspect the images and motion recordings, not merely test status.
Landscape is accepted only when the actual app window is wider than it is tall.
Simulator checks do not establish physical-device thermal, battery or frame-rate
performance.

The current targeted physics/transport/pool regression checks and playback UI checks
pass. Debug and Release builds pass. All 21 light states were inspected on iPhone
portrait and iPad portrait, and a recorded iPad release/fall/landing sequence was
inspected. The iPad landscape check remains failed: the existing simulator retains an
820-by-1180 portrait app window despite device and scene rotation requests. No
landscape approval or physical-device performance claim is made.

Stop at this checkpoint for visual evaluation. Full-tree articulation, richer terrain,
canopy light shafts, animal choreography, and the complete musical direction follow
only after that approval.
