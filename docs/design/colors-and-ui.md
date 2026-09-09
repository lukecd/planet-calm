# Planet Focus — Visual Design Foundation

**Version:** 13 · **Updated:** 2026-09-07 · **Status:** Approved palette and current native splash

This is the current design source of truth for Planet Focus outer UI. Story artwork may
use story-specific colors, but navigation, typography, and shared surfaces should use
the semantic roles defined here.

## Identity

Planet Focus uses a calm, tactile paper-cut language throughout the product. The first
screen establishes an ink-navy paper world with broad blue and lavender wave ribbons,
warm-yellow focal details, pale-blue lettering, generous empty space, and restrained
depth.

Avoid Liquid Glass, generic wellness cards, glossy controls, and default Apple styling
as the visual direction. Native controls and navigation behavior should still be used
where they provide accessibility and familiar interaction.

## Approved palette

The palette below replaces the earlier outer-UI direction. The values were sampled from
the approved splash reference and normalized into flat design tokens.

| Token | Name | Hex | Semantic role |
| --- | --- | --- | --- |
| `canvas.ink` | Ink navy | `#0A1124` | App background and deepest paper shadow |
| `wave.deep` | Deep blue | `#0D3690` | Dark wave ribbons and strong blue anchors |
| `wave.mid` | Mid blue | `#2D50A8` | Mid-depth wave ribbons and lotus petals |
| `wave.periwinkle` | Periwinkle | `#516BAF` | Light wave ribbons and supporting petals |
| `wave.lavender` | Lavender | `#836FB3` | Contrasting wave ribbons and lotus petals |
| `type.paleBlue` | Pale blue | `#AEC7FB` | Wordmark and unselected navigation labels |
| `accent.warmYellow` | Warm yellow | `#F7A337` | Sun, lotus centers, and selected navigation state |

Material rendering may derive local tints from these semantic colors without expanding
the app palette. The current sun uses ochre `#D68628` only for its lower-right cut edge;
it is paper thickness, not a standalone accent color.

### Color rules

- Ink navy is the continuous outer-UI field.
- Blue, periwinkle, and lavender create depth through overlapping paper layers; they
  should not be used as equal-width stripes.
- Warm yellow is reserved for focal details and selection. It is not a general button
  fill or a continuous decorative line.
- Selection must also use a dot, underline, shape, or other non-color cue.
- Essential text uses pale blue or warm yellow only when contrast passes on the actual
  textured background.
- Cast shadows use neutral black with opacity; they are material depth, not additional
  palette colors. Using ink navy over the same ink-navy canvas does not create enough
  visible separation.
- Story palettes remain story-owned and do not need to be recolored to match outer UI.

## Typography

| Role | Typeface | Status |
| --- | --- | --- |
| Stories, Stats, and Settings navigation labels | Sue Ellen Francisco Regular | Approved |
| Planet Focus wordmark | Aladin Regular | Trial — evaluate in situ before final approval |
| Start navigation label | Sue Ellen Francisco Regular | Working choice for a coherent navigation row |

Both fonts are bundled under the SIL Open Font License 1.1. Sue Ellen Francisco is
copyright Kimberly Geswein. Aladin is copyright Angel Koziupa and Alejandro Paul and
uses the reserved font name “Aladin.” The bundled files are unmodified.

Custom display lettering must remain readable, and every interactive label must retain
a clear accessibility label independent of its visual font.

## Splash visual target

The implementation target is:

[`planet-focus-blue.png`](../../fall-references/planet-focus-ui/splash-screen-v2/planet-focus-blue.png)

The image is an opaque composition reference, not a production scene plate. The native
screen recreates its hierarchy with independently addressable SwiftUI layers:

1. Ink-navy background.
2. Two-line Planet Focus wordmark.
3. Warm-yellow sun behind the wave field.
4. Individual closed wave ribbons with sinuous top and bottom contours.
5. Three lotus groups, each composed from independent petals and a warm-yellow center.
6. Bottom navigation with Start selected by color, dot, and underline.

## Responsive composition

iPad landscape is the master art direction. Other viewports reframe the same continuous
paper world rather than uniformly squeezing the landscape composition.

- The waves live in one extra-wide, fixed-aspect world sized from the viewport's shortest
  side. Rotation never changes their curvature, thickness, scale, or depth order.
- Each ribbon is generated from two independent continuous functions: an absolute
  centerline and a thickness field. Each function combines low-frequency harmonics with
  its own amplitude, wavelength, and phase. The internal centerlines are not expressed
  as percentages of the outer envelope, so the envelope cannot force every ribbon to
  rise and fall together.
- A smooth analytic boundary constraint keeps the independent ribbons inside the shared
  silhouette only when they approach its edge. It does not otherwise reshape or align
  their phases.
- The renderer samples the analytic functions densely and connects those true samples
  directly. It does not pass a sparse set of points through a second hand-shaped Bézier
  system that can overshoot the equations.
- The accepted landscape camera shows a `3.0 × shortest-side` section of the continuous
  wave world. Narrower devices retain the same intrinsic geometry and reveal a centered
  crop rather than compressing the artwork.
- The combined outer wave envelope is mirror-balanced around the center of that world.
  For every centered camera crop, its top and bottom bounds therefore meet the left and
  right viewport edges at equal total height. This prevents the stack from reading as a
  hill while preserving asymmetric amplitude, thickness, and crossings inside the field.
- Landscape reveals a wider section of the wave world and portrait reveals a narrower
  centered section. The viewport crops the world; it never reshapes it.
- Wave ribbons extend beyond both horizontal edges in every orientation.
- Wordmark and navigation occupy protected safe areas and never depend on cropping.
- The sun and three undistorted lotus groups are independent actors with deliberate
  orientation-specific anchors so they remain visible and attached to the wave field.
- iPad portrait and iPhone portrait use a taller camera window with deliberate lotus and
  sun placement.
- iPhone landscape uses a compact wide composition with reduced type and navigation
  spacing while retaining the full interaction row.
- Geometry is driven by the current container and safe-area insets, never by
  `UIScreen.main.bounds` or device-name checks.

## Animation boundaries

The accepted static composition is the rest pose for animation. The same independently
addressable layers now support entrance, living motion, and exit choreography without
rebuilding or flattening the screen.

- Every wave ribbon is a separate actor with a stable identity and an independent
  entry edge. Its visible domain grows and recedes along the analytic centerline
  rather than translating a finished shape.
- Every lotus is a separate actor. Within each lotus, the upright center petal, paired
  side petals, outer petals, base petals, and warm-yellow heart remain independently
  addressable.
- Lotus entry is built from the existing petals rather than scaling or translating a
  completed flower. The upright center petal appears first, the side families fan
  outward from their shared base, and the warm-yellow heart appears during that fan.
  Flowers do not begin until the supporting ribbon field has finished unfurling, then
  left, center, and right overlap in a 0.16-second cascade. Exit samples the same path
  backward on a shorter 1.12-second clock.
- Wordmark, sun, navigation, and the full scene remain separate actors.
- A future navigation transition can animate the scene to an exit state before routing
  to Start, Stories, Stats, or Settings.
- Reduce Motion presents the settled composition and uses immediate state changes.
  Motion is never required to understand the screen.

### Approved first-pass splash score

The provisional performance tempo is 65 BPM in 4/4. It schedules future musical
moments; the continuous wave field remains fluid and derives from elapsed time.

In the current living-motion study, the eight ribbons keep stable tonal slots but do
not yet have assigned pitches. Four quiet foundation voices cover the initial score
build, then hand off to long, overlapping pad envelopes on those same ribbon actors.
Every note supplies a restrained whole-ribbon motion bed plus a stronger traveling
packet. Both use one uninterrupted phase clock per ribbon; note onset never resets the
wave. After the intro exactly four actors remain scheduled and at least three produce
measurable visible movement throughout the cycle. This prevents full staticness and
onset jerks without making every ribbon crest and fall together. The same
performance-clock samples are the future synchronization seam for music.

- At 0.00 seconds only the ink-navy paper canvas is visible. The provisional drone and
  note score begin with the visual performance rather than waiting after the intro.
- Ribbon starts overlap from 0.25 through 1.51 seconds at 0.18-second intervals. Each
  unfurls for 2.00 seconds, so the complete field is settled at 3.51 seconds.
- The menu becomes usable when the ribbon field completes at 3.51 seconds. The lotus
  sequence begins at 3.56 seconds and finishes at 4.46 seconds, but it never blocks a
  returning user from navigating. An interrupted flower sequence reverses from its
  exact current petal state.
- The audition score is a 32-beat cycle. A new pad voice begins every four beats and
  remains active for sixteen beats: three-beat attack, two-beat decay, 0.72 sustain,
  ten-beat gate, and six-beat release. Four pad envelopes therefore overlap once the
  first cycle has filled, with no quiet interval at the loop boundary.
- Selecting Stories immediately starts a front-to-back ribbon release and a
  time-compressed reverse lotus cascade. The lotuses finish in 1.12 seconds and routing
  completes with the last ribbon at 1.50 seconds.
- The advancing or receding frontier is part of the generated geometry: the sampled
  domain changes over time and a smooth 0.09-world-width envelope tapers thickness to
  zero at the tip. The final frame is the exact approved rest geometry.
- Ribbons never use a moving rectangular mask, rigid translation, or opacity to enter
  or leave.
- Wordmark, sun, and navigation remain independently addressable alongside the authored
  lotus petal choreography.

## Generative atmosphere direction

The splash is a story driven by the shared performance transport. Its current sunrise
implementation is specified in [Splash sunrise renderer](splash-sunrise-model.md).
That document supersedes the earlier full-canvas palette fades and expanding opaque masks.

The sun begins approximately 10% exposed above the rear wave, rises, and carries a
spatial light field. Native Metal evaluates atmospheric scattering; an explicit paper
color treatment brings the result to the yellow reference. Three abstract paper cloud
strips share their visible silhouettes with the ray-occlusion calculation. Texture
stays neutral and separate from light.

The approved yellow-paper reference is
[planet-focus-yellow.png](../../fall-references/planet-focus-ui/splash-screen-v2/planet-focus-yellow.png).
It is a visual target, never a flattened production scene plate.

Waves retain their stable tonal slots and note envelopes. The existing abstract wave
resonance remains the melodic study; no visiting animal is introduced by the sunrise work.
Night, Twilight, and Daylight sound banks overlap according to normalized transport
progress. A note chooses its bank at onset and keeps it through its release.

The Light slider and Splash runner sample the same director. The configured session
duration controls the arc. Every 5% state must be visually inspected in phone and tablet
layouts, including both tablet orientations. Keep the established individual paper
actors and their entrances/exits; future music refinement should use this shared system.
