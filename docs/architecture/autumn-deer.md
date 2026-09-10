# Autumn: the origami deer ending

The deer is an original articulated paper construction, not a sprite sheet, imported
animal model, or a copied commercial origami pattern. The existing tree, leaf physics,
sun and session transport remain the scene's foundation.

## Movement references and interpretation

- [Grand Canyon NPS: Mule Deer Winter Browse, Michael Quinn](https://commons.wikimedia.org/wiki/File:Grand_Canyon_National_Park-_Mule_Deer_Winter_Browse_(b-roll_video)_(8599595030).webm).
  Browser-playback frames at 0, 10, 20, 30 and 40 seconds, then 6–9 seconds, informed
  restrained head/ear movement and the small forefoot adjustment while browsing.
  This is a quiet support/posture reference, not a measured complete walking cycle.
- [Penn State Deer–Forest Study: bedding behaviour](https://www.deer.psu.edu/how-long-do-deer-sleep-and-what-do-bucks-smell/).
  Its [Doe arrives recording](https://www.youtube.com/watch?v=zLrTyHvFe64) was inspected
  at 2, 4, 6 and 8 seconds. The animal pauses upright, directs its attention forward,
  then lowers its head toward the ground. This informed the preparatory pause, not
  the footfall timing; this clip does not show the full lowering transition.
- [Buck kneels, footage by David I., published by Bangor Daily News](https://www.youtube.com/watch?v=gmXTlrSrocw),
  with [publication context](https://www.bangordailynews.com/2020/11/19/outdoors/watch-a-big-buck-bed-down-for-the-night-in-this-trail-camera-video/).
  Frames at 0, 0.5, 1, 1.5, 2 and 3 seconds show a low head, foreleg folding, overlapping
  lowering of the haunches, then the body supported close to the ground. Later frames
  show a resting animal that can still move its head. The relatively quick lowering
  corrected the first implementation's prolonged, stiff bow.
- [Stevens, Ernst & Marty (2022), limb phase and duty factor](https://link.springer.com/article/10.1186/s00015-022-00418-9),
  section 1.3, supplies a formal four-beat gait framework. The implementation uses
  separated lateral-sequence contacts and a 0.68 support fraction. These are authored
  animation parameters, not claimed measurements from this particular deer.
- [Jo Nakashima's paper reindeer](https://jonakashima.com.br/2016/12/19/origami-reindeer/)
  was a material/construction reference. Its [tutorial](https://www.youtube.com/watch?v=pAsNGOvwEC8)
  restricts commercial use without permission. No pattern, model or media from it is
  included. Our broad torso planes, pleated neck, tapered limb panels and lanceolate
  ears are independently authored geometry using the app's existing paper grain.

This is stylized inverse-kinematic paper puppetry, not a biological force simulation
or proof that the complete articulated animal can be folded from one sheet. The
choice retains rigid-looking panels and readable anatomy at phone scale.

## Ownership and timing

`AutumnDeerEncounter` owns the finite performance and produces one `StoryMoment`,
`autumn.deer.ending`. `AutumnBranchPlan.deerEnding`, the generic Autumn director and
catalog snapshots use the same scheduling function. The visible deer remains after
the finite motion ends. Its body and tiny resting motion sample transport time;
completion therefore holds the same final composition.

Defaults are 18 seconds walking, 3.5 standing, and 8 settling. The latter includes
preparation and a resting transition: the main knee/haunch lowering overlaps rather
than occupying the entire eight seconds. A final hold reserves 7% of session length,
bounded to 8–45 real seconds. Supported 1–2-minute development and 5–55-minute user
durations all leave time for the complete performance. Entrance is guaranteed, not
a random encounter. No second clock or session persistence was introduced.

Root travel decelerates smoothly. Each hoof has a world-space touchdown anchor and
a separate swing interval. The terminal footfalls land before the root stops. Leg
panels use two-segment inverse kinematics; during lowering the distal folds tuck
under the body rather than maintaining a walking hoof constraint.

## Rendering and contact

`AutumnOrigamiDeerLayer` painter-sorts original folded polygons in depth, shades them
from the scene's sun, and projects paper grain in panel-local coordinates. The
ground projection is affine so planted hooves do not acquire perspective sliding.
The cast silhouette and tightening belly-contact patch use the same receiving plane.

Ground leaves are split into rear/front passes around the deer. Small, bounded leaf
displacements follow completed foot contacts and final body pressure. Both leaf art
and its shadow consume the adjusted pose. This is a visual paper-bed response, not
a new aerodynamic impulse solver; it does not mutate leaf physics or lift leaves
away from their ground plane. Late scheduled gusts are softened to 78% strength,
which retains the tested, selective movement of grounded leaves.

Reduce Motion omits walking and lowering travel and introduces a fixed resting pose.
It disables the leaf-bed displacement. Session cancellation removes the encounter;
backgrounding follows the existing wall clock; no user pause/restore is added.

## Development and verification

The existing Autumn tuning accordion contains size, walking speed, settling duration,
resting position, Play deer ending, and Walk/Stand/Lower/Rest pose buttons. Play starts
a late-stage two-minute development session and captures the current deer tuning.
Pose buttons pause that same transport. Study encounters are stripped by `settingsOnly`.
Normal runs lock deer tuning to prevent changing an active automatic performance.

Debug launch arguments `--deer-study --autumn-fresh` play the ending;
`--deer-pose=<seconds>` inspects a paused offset within it. They are development-only.

Tests cover ending deadlines across session lengths and tuning limits, planted hoof
invariance, finite geometry, ground clearance, reduced motion, event agreement and
non-persistence. Native snapshot and UI tests inspect phone, tall iPad and landscape
iPad compositions, development controls, and completion.

Deer validation covers the shared model suite and iPad/iPhone ending UI studies.
See [automatic encounters](autumn-encounters.md) for current integration coverage.
Extreme size/speed/resting-position combinations are
checked for fixed limb lengths, not merely finite coordinates. The native iPad
recording was additionally inspected in close-up walking and lowering frame sequences.
