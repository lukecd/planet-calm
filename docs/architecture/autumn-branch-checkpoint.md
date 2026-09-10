# Autumn tree composition checkpoint

Status: Autumn includes the full tree, automatic encounters, session UI, and guaranteed
origami deer ending. Music and physical-device validation remain deferred.
Existing landscape and maple alpha artwork are reused.
The six-leaf branch remains a model regression fixture, not an extra user-facing lab.

## Asset and code cleanup

The [origami deer ending](autumn-deer.md) now supplies the guaranteed final arrival,
grounded walk and folded resting pose. It shares the session clock and leaves a
real-time resting hold before completion; its study controls stay inside Controls.

The retired painted scene, SpriteKit leaf-study screens, cast-review screen,
old composition/terrain data, and their unused artwork have been removed.
The active scene, catalog thumbnail, and legacy timer catalog path now share
AutumnBranchCanvas. Catalog snapshots consume caller-provided elapsed time,
duration, and seed; they do not create a second transport.
AutumnArtwork owns the five retained paper masks. Their pixels and the approved
full-tree wind/light/ground calculations are unchanged. Shared aerodynamics and
its small baseline configurations remain. Obsolete rabbit/flock frames, loaders,
scheduling, and the flock solver are removed. Old screen-only tests
are retired; current physics, attachment, ground, and playback regressions remain.
The bundle inventory test prevents deleted scene plates/layouts from shipping again.

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
Only tuning persists, never sessions or manual events. Release builds have Begin,
countdown/end confirmation, and Scene settings. Pause/restart remain DEBUG-only.

## Direction and simulation

AutumnBranchPlan consumes the [automatic encounter policy](autumn-encounters.md).
Irregular opportunities choose a breeze, a bird, or quiet, with real-time cooldowns.
Manual gusts are appended to the same event list at the shared elapsed time.
A gust keeps its duration in seconds regardless of the total meditation length.
AutumnWindPassage derives a stable source position, oblique direction, travel speed,
spatial breadth, attack shape and single/two-pulse character from the seed and event
index. Scheduled events independently choose upwind sides with seeded source heights and
angles. Their durations and strengths vary around the tuning controls' base values;
the actual values are carried by the shared StoryMoment. Appending a manual gust
does not alter earlier passages. Quiet air has no persistent rightward bias.

The spatial field delays gust arrival across the tree, falling leaves, and ground
leaves. All three sample the same passages at their own x/y position and the same
transport time; ground motion is not a second animation clock. Projected distance
from the source controls arrival; transverse distance controls exposure. Branch
loading uses the force across each limb. Seasonal release events loosen every leaf
regardless of wind strength; either wind direction then affects its flight.
Canopy shelter reduces airborne transport while
preserving direction and timing. Its attack and decay use the existing smooth
GustPlan envelope. AutumnCanopy defines 42 parent-connected limbs
and 182 leaf-bearing shoots. Its asymmetric scaffold has tapered limbs, smaller
lateral branches, clustered foliage, and correlated amber/gold/russet regions.

Each limb has a damped small-angle spring; smaller branches receive a larger
angular response than the trunk. Parent rotation propagates to every child joint.
The root position is fixed. This is an art-directed reduced-order model, not an
elasticity solver or a botanically exact species reconstruction. Structure and
taper are informed by [UF/IFAS's discussion of distributed canopy loading](https://hos.ifas.ufl.edu/woody/distribution-loading.shtml)
and [research on wind and tree architecture](https://www.nature.com/articles/s41467-017-00995-6).

Every full-tree leaf now has a stable, seeded release StoryMoment. Stratified ranks
blend branch-related and per-leaf variation; a smooth timing curve distributes
releases from 8% to at most 80%, reserving at least 16 physical seconds at the end.
Release sensitivity gently biases that distribution rather than disabling completion.
The exact scheduled onset changes the leaf to falling without resetting its pose or
velocity. Flight, flutter, and settling retain their physical-second timescale.
All 182 leaves reach the ground before completion, including in 1–2-minute previews.
Late passages act on a bare tree and its leaf carpet. The automatic bird and
guaranteed deer share this timeline. Full musical direction remains deferred.

AutumnBranchSimulation samples in fixed 1/120-second steps, independent of redraw rate.
It reuses LeafAerodynamics lift, drag, pressure-point torque, and resistance with the
existing calibrated Gate 3 configuration. These are quasi-steady 2D plate dynamics,
not CFD. A limited visual fold follows rotation smoothly; it is not full flexible
sheet mechanics. Ground contact uses a simple receiving plane, damped sliding and
settling rather than the full old terrain/contact solver. The receiving plane is
stored per leaf as groundLevel for both leaf centers and projected shadows; the
full tree varies that depth across the ground rather than placing every leaf in a
single row. The branch fixture retains y = 0. As a leaf settles flat, its
shadow converges to the same transformed alpha footprint, with only half a point
of paper-thickness offset. Airborne drop shading fades out at contact; it must
not introduce a second, detached shadow beneath resting paper.

Each maple asset has a measured stem-tip anchor. A shared branch-space twig tip
and orthographic leaf transform keep that anchor fixed while the leaf flutters;
the center position and its velocity are derived from that constraint. The same
joint supplies the drawn twig endpoint. Bare twigs retain their branch-space tip.
An eligible leaf retains its identity, position, angle and velocities at release.
Landed leaves remain visible; the canopy is empty at the end of the full-tree story.
The six-leaf branch regression fixture retains its original wind-threshold releases.

AutumnGroundContact gives full-tree leaves static/kinetic friction, quadratic drag
against relative air velocity, and off-centre pressure that pivots a sliding sheet.
The shared gust can reawaken a settled leaf. Stable per-leaf curl and friction plus
direction-aware shelter behind the trunk mean not every sheet moves. Nearby grounded
leaves increase friction and reduce exposure using a smooth distance-weighted field.
Overlap shelter saturates so exposed sheets in a full carpet can still move.
Ground exposure gently increases as the canopy opens. Neighbour weights update at
a fixed 10 Hz and are reused while positions remain unchanged; contact stays 120 Hz.
Velocity-dependent surface resistance dissipates a shuffle before it becomes a long
slide. There is no viewport clamp, edge wall, teleport, or attraction toward the tree;
retention comes from shelter, resistance, shorter airborne drift and changing wind.
Quiet background air
is below the static threshold; it must not produce permanent crawling. This pass
keeps sliding/pivoting paper on the receiving plane, rather than introducing airborne
tumbling or a separate bounce animation. The six-leaf contact fixture is unchanged.
The force form follows [NASA's drag equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/drag-equation/);
its coefficients and the shelter field are art-directed scene-unit approximations,
not measured leaf friction or a resolved fluid simulation.

Development pause freezes sampled time. Backward inspection replays the same
fixed steps from the initial state. The in-memory cache avoids replay during ordinary
forward display. This checkpoint does not promise cross-version/platform bitwise
physics determinism. Conservative propagation bounds skip gusts that cannot reach
any simulation point at the sampled time; they do not change the wind field.
Full 50-minute reconstruction was measured at roughly 11 seconds on the simulator,
down from roughly 95 seconds before culling. This is not instant-resume performance:
background catch-up optimization remains a device-validation concern, not a
promise of saved sessions or user-facing restoration.
Forward playback is incremental; there is still only one transport.

Physics controls are locked while a run exists. End the run, tune, and restart to
avoid retroactively rewriting motion. The same development seed repeats a run. Only tuning persists;
manual events do not. Light-position inspection is available only outside a run;
during playback progress is the sole owner. Sun intensity, shadow softness and
backlight remain live-adjustable without invalidating the physics cache.

## Rendering and limits

Autumn's Metal sky fragment reuses the existing atmospheric integral. Its fixed-view
projection, paper treatment and sun path are its own; it does not reverse the splash
timeline. The approved splash fragment is unchanged.

Maple silhouettes mask independently colored paper and neutral local grain.
Grayscale detail from the existing assets supplies restrained veins/material detail;
the original baked color is not the animated pigment. The full tree uses three
reusable Canvas paper symbols rather than 182 independent SwiftUI texture stacks.
Leaves are rendered in rear/front depth groups around the articulated branch mask.
Their own orientation still drives lighting, and their measured stem anchors stay
attached until the simulation releases them. Root flare and restrained bark lines
maintain the paper silhouette without flat sprite joints or plastic highlights.

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

Full-tree model tests cover parent/child joint coincidence, root anchoring, taper,
all attached stem constraints during wind, release continuity, replay, and ground
shadow convergence at varied depths. The previous six-leaf grounding and attachment
tests remain intact.

Connected-wind tests cover sub-threshold static contact, selective reactivation by a
later gust, frictional stopping, ground-shadow coincidence, spatial gust delay,
strong overlapping gusts, and paused/restored ground motion. Live UI captures now
span multiple gusts so later passages act on already-settled leaves; portrait
captures cover all three scheduled sources. Spatial-wind tests also check opposite
arrival directions, unchanged earlier events when a manual breeze is appended,
duration-independent gust profiles, neighbouring-leaf shelter, and at least 85% retention
within the narrow camera's visible ground across three representative seeds. This is a
validation criterion, not a viewport constraint in the simulation. Inspect both
canopy response and ground movement in the same sequence.

Three visual passes corrected canopy framing, hard limb/root junctions, and the
straight-row landing artifact. All 21 light states were inspected on iPhone and
iPad portrait, along with successive recorded release/settling frames. Targeted
model and playback tests pass.

Native snapshots cover the wide tree geometry; offscreen ImageRenderer cannot
capture the Metal sky. Simulator UI captures cover iPhone portrait, iPad portrait,
and iPad landscape including the atmosphere and ending. On windowed iPadOS the
test expands the app through its system window controls after rotation and checks
the actual aspect ratio. Use full-display screenshots to avoid XCTest window-origin
cropping. Physical-device frame rate, thermal behavior, and long-session background
catch-up remain deferred until feature integration.

Complete-story tests check every scheduled leaf onset, natural landing before
completion, selective late-carpet movement, and deterministic plans at 1, 2, 15,
and 50 minutes. Live one-minute UI captures cover the full-to-bare progression.
The Stories thumbnail uses this same current tree renderer, not a saved old plate.

## Origami visitor study

### Session UI and lifetime

Setup shows handwritten duration / Tap to begin at the top. The single button starts
the clock immediately and fades into the countdown in the same position; the entire
countdown is the End session confirmation trigger. Duration selection is hidden in
Scene settings: a fine cream slider and round paper thumb for every whole minute
from 5 through 55, with gentle five-minute detents and no typed entry. Duration locks
after starting, while volume/mute remain adjustable. The non-blocking panel never
pauses transport. Autumn remains silent until its soundtrack is connected, and the
panel explains that limitation. Shared synth output volume/mute are wired separately
from transport; muting does not stop or restart the score. App-wide preferred duration
and persistent audio preferences are deferred. Other functional session UI uses standard San Francisco
through `PlanetFocusTypography.interface`, with Dynamic Type text styles and stable-width
digits for duration selection. Reduce Motion removes interface fades. Completion holds the ending with
Complete / return to stories; cancellation returns to the chooser
and discards the session and manual events. There is no public pause, replay, or
restoration. Start on the splash opens setup for the selected story. Screen locking,
backgrounding, and audio interruptions do not pause the in-memory wall-clock timer.
Process termination discards it; legacy saved-session keys are removed on launch.
Only tuning settings persist. Debug pause/restart, short durations, bird triggers,
and monitors remain inside the separate Dev controls menu at bottom right, closed by
default and absent from release builds.
`FocusDuration` is a validated value type rather than a preset-only enum. Its
single-integer Codable representation remains seconds for compatibility. Slider
touch mapping and VoiceOver adjustment use whole minutes; event motion still uses
real seconds and the existing session transport.

The Autumn tuning accordion now contains **Fly origami bird** and controls for
speed, wingbeat frequency, depth, wind response, and perch duration. This is a
development study alongside automatically scheduled visits.
It starts or resumes the shared runner; if too little time remains for the whole
flight, it starts a fresh run. Each trigger captures tuning for that flight.

`AutumnOrigamiFlight` describes one finite `StoryMoment`: eight seconds approaching,
six perched, and thirteen departing at default settings. Speed changes the travel
durations, not the perch duration or the tree's physics. Its onset is transport
elapsed time, so development pause/resume uses the existing clock. No flight is
restored across app launches; seeded reproducibility is only a development aid.
New runs clear the old flight. An optional bird record preserves compatibility
with previously saved Autumn settings. There is no second timer or sprite sheet.

The camera is at z = -1100, with the tree at z = 0. For each vertex, perspective
magnification is `1100 / (1100 + z)`; positive z recedes. Routes are authored in
the same responsive tree coordinates and unprojected where a screen-space target
is useful. The branch perch samples limb 7 at 64% along its current curve, offset
by its tapered half-width. Both landing and departure reach zero velocity at the
perch. Approach uses three Hermite segments with shared time-scaled tangents:
far glide (z = 650), banking correction (z = 280), near approach (z = -105), then
the branch (z = 0). These depths are scaled by the captured depth control. Joins
occur at 45% and 76% of the approach; there is no initial ease-in. A finite-window
curvature estimate drives bank, while the final approach spreads the wings, pitches
up, and unfolds rigid paper supports. After foot contact, wings close over 1.1
seconds with a small foot-anchored settling rotation. The approved departure
continues to use its original cubic Hermite arc toward the sun, protected by
pre-refinement golden-pose tests. This is authored choreography,
not a claim of a full aerodynamic bird simulation.

`AutumnOrigamiMesh` contains folded triangular paper panels, a reverse-folded
neck/beak, tail, body, and supports. Quaternion wing-root and outer-crease rotations
preserve panel edge lengths. The renderer projects every vertex, depth-sorts faces,
and clips crossing panels at z = 0 for front/back passes around the tree layers.
This avoids whole-wing depth pops. This is a 2.5D tree with a 3D
bird, not a fully volumetric forest. Per-panel diffuse light and backlight use the
scene sun; local paper texture follows the panels. A branch-clipped contact shadow
supports the perch. The sun remains an atmospheric backdrop, never a nearby sphere
that the bird flies behind.

Wind is sampled from `AutumnBranchPlan.air` at the bird's current route position.
It adds bounded drift and bank during flight, fading to zero at the perch. Reduce
Motion hides travel and presents a stationary perched pose during the rest only.
The earlier flock solver and cast assets are removed. Current visits use this
single articulated mesh.

Tests cover camera projection, finite event boundaries, receding size, moving-branch
attachment, transition continuity, wind response, pause/persistence, Reduce Motion,
rigid panel dimensions, and phone/tall-iPad/wide-iPad snapshots. UI tests trigger the
same control and capture the complete flight. Physical-device performance remains a separate check after feature integration.

Projection reference: [MIT, Imaging](https://visionbook.mit.edu/imaging.html).
Native rendering uses [SwiftUI Canvas](https://developer.apple.com/documentation/swiftui/canvas).

Music and physical-device validation remain deferred. Richer terrain and canopy
light shafts are optional future artwork, not missing PR scope. There is no
user-facing session restoration.
