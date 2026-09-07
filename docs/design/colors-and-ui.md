# Planet Focus — Visual Design Foundation

**Version:** 12 · **Updated:** 2026-09-07 · **Status:** Approved palette and current native splash

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

The first milestone is static, but the layer structure must support later entrance and
exit choreography without rebuilding the screen.

- Every wave ribbon is a separate actor with a stable identity and an independent
  horizontal travel direction.
- Every lotus is a separate actor. Within each lotus, the upright center petal, paired
  side petals, outer petals, base petals, and warm-yellow heart remain independently
  addressable.
- The settled lotus geometry is compatible with a later sequence in which the upright
  center petal fades in first and the side petals fan outward from the base.
- Wordmark, sun, navigation, and the full scene remain separate actors.
- A future navigation transition can animate the scene to an exit state before routing
  to Start, Stories, Stats, or Settings.
- Reduce Motion will replace travel and petal fanning with calm fades or immediate state
  changes. Motion will never be required to understand the screen.

## Material and accessibility

- The canvas uses `CanvasPaperTextureV3`, an original cardstock material field calibrated
  directly around `canvas.ink`. Its Autumn-derived fibers remain visible at normal iPad
  scale, with restrained contrast so the surface reads as clean cardstock rather than felt
  or compressed pulp. It introduces no new semantic color and does not use a blend mode that
  shifts the approved navy.
- The canvas material is aspect-filled as one continuous crop rather than tiled, so its
  fiber scale remains stable and it cannot expose repeating seams during rotation.
- The sun uses its own locally clipped `SunPaperTexture`, calibrated around `sun.warm`.
  A thin derived ochre backing disc is offset down and right to expose only the paper's cut
  edge; a restrained pale highlight stays on the face. A tight contact shadow and softer
  secondary cast shadow provide separation without changing the approved circle geometry.
  These shadows use neutral black rather than `canvas.ink`; reusing the canvas color over
  itself does not create enough luminance separation on the dark navy surface.
- Each wave uses the neutral `WavePaperTexture` as a local tiled material field. The
  grayscale fibers are soft-light composited inside an isolated face group, then clipped
  by that ribbon's native path. This keeps the approved semantic color in control and
  prevents the material from bleaching adjacent waves, the canvas, or the sun.
- Every wave actor contains its own face, locally clipped fibers, thin darker derived-color
  cut edge, tight contact shadow, and restrained cast shadow. The complete paper stack
  travels as one actor during future entrance or exit motion.
- Wave cut-edge colors are material tints derived from the approved ribbon colors; they
  do not expand the semantic palette. Wave shadows use neutral black so layer separation
  remains visible over both the navy canvas and neighboring colored paper.
- Paper texture is subtle, clipped to each paper shape, and moves with that shape.
- Shallow shadows may explain layer order; heavy floating-card shadows are inappropriate.
- Navigation labels keep clear tap targets and VoiceOver labels.
- Dynamic Type and compact layouts must avoid clipped navigation or an obscured wordmark.
- Contrast is verified against rendered textured surfaces, not flat swatches alone.

## Deferred decisions

- Final approval or replacement of Aladin after it is reviewed in the native screen.
- Exact grain treatment for the approved lotus construction.
- Entrance timing, easing, stagger, wave phase, lotus bloom timing, idle behavior, and
  exit choreography.
- Navigation destinations beyond the minimal Stories path used to demonstrate the splash.
