# Planet Focus

## Purpose

Planet Focus is an iOS focus timer in which a completed session unfolds a calm,
tactile paper-cut story. The timer and story are one experience: a focus duration
is the duration of a complete narrative arc.

The app starts with a splash screen, then story selection, then duration selection.
The initial stories are Autumn Tree and Contemporary Lotus. A future story must be
data-driven and use shared playback services rather than copied application logic.

Preserve a distinctive paper-cut visual language: deliberate layers, generous empty
space, restrained motion, and physical-feeling material. Do not use Liquid Glass,
generic wellness-app cards, or default Apple styling as the visual direction.

## Current splash state

- The approved native composition target is
  `fall-references/planet-focus-ui/splash-screen-v2/planet-focus-blue.png`. It is an
  opaque visual reference, not a production scene plate or layer source.
- The approved outer-UI palette is ink navy `#0A1124`, deep blue `#0D3690`, mid blue
  `#2D50A8`, periwinkle `#516BAF`, lavender `#836FB3`, pale-blue type `#AEC7FB`, and
  warm yellow `#F7A337`. The active design source of truth is
  `docs/design/colors-and-ui.md`.
- A static native splash implementation is authorized. Build every wave, lotus, sun,
  wordmark, and navigation region as an independently addressable layer so entrance
  and exit choreography can be added after the static composition is accepted.
- A wave ribbon has a sinuous top **and** bottom edge and extends beyond both screen
  sides. It is never a landscape fill with a flat lower edge.
- Do not flatten the reference into a production background or implement the deferred
  animation choreography before the user accepts the static native composition.

## Visual iteration

- Work screen by screen. Make one intentional visual change at a time.
- Before generating, state the exact change, retained invariants, target device, and
  what will be judged. After generating, inspect the complete composition critically
  before presenting it.
- Say plainly whether the result meets the requested visual change. Do not present a
  result as complete merely because it matches prompt keywords.
- Inspect accepted compositions in iPhone portrait, iPad portrait, and iPad landscape.
  Treat portrait as a deliberate camera window with protected wordmark and navigation
  safe areas, not a squeezed landscape.
- Independent motion defines asset boundaries. Never flatten elements that enter,
  leave, or move separately into one production scene plate.
- Prefer native, deterministic shapes for responsive geometry such as wave ribbons.
  Use generated art for paper texture and authored organic forms only after the user
  accepts the reference and layer plan.
- Respect Reduce Motion. Motion must be quiet, purposeful, and nonessential to
  understanding the state.

## Swift and SwiftUI

- Match the deployment target and Swift language mode already chosen by the project;
  do not invent a newer minimum platform version.
- Use modern Swift concurrency. Prefer `async`/`await`; do not add new GCD-based
  coordination.
- Prefer `@Observable` shared state. Mark UI-owned observable models `@MainActor`
  unless project-wide actor isolation makes that redundant. Avoid new `ObservableObject`
  code except at unavoidable integration boundaries.
- Use SwiftUI first. Avoid UIKit unless it provides a specific required capability.
- Use `Button` for ordinary interactions, `NavigationStack` for navigation, modern
  `FormatStyle` APIs for user-facing formatting, and `foregroundStyle()` in SwiftUI.
- Do not use `UIScreen.main.bounds`. Choose modern layout APIs first, but use
  `GeometryReader` when custom responsive art geometry genuinely requires it.
- Keep art-direction values in named, typed tokens. Do not scatter magic numbers.
- Do not add dependencies, API keys, or secrets without explicit approval. Secrets
  never enter source control.

## Runtime architecture

- Separate clock, story direction, rendering, audio, persistence, and navigation.
- `StoryPlayer` combines the authoritative session clock, selected module, director,
  and session plan. `StoryDirector` owns only story-specific creative choices.
- Use normalized session progress (`0...1`) from persisted start/end time. Do not use
  animation-frame count as time; relaunch, backgrounding, and device lock must reconcile.
- Represent synchronized visual/audio behavior as shared `StoryMoment` values. Visual
  and audio systems consume moments; they do not command each other directly.
- Build the visual runtime before production audio. Keep audio cues in plans and use a
  silent implementation until original audio is ready.
- Start with SwiftUI `Shape`, `Path`, masks, and texture overlays for the splash.
  Metal shaders are an optional later enhancement, never a prerequisite.

## Assets and quality

- Production-ready movable art must have genuine alpha. Verify RGBA output and real
  transparent pixels before use.
- A paper texture is a restrained layer clipped to its paper shape and moves in that
  shape's local coordinates. It must not behave like a screen-wide digital filter.
- Keep accessibility first: Dynamic Type, contrast, VoiceOver labels, clear targets,
  non-audio-only feedback, and reduced-motion behavior.
- Test timer transitions, normalized timing, persistence, and story-plan behavior.
  Test visual scheduling determinism when seeded randomness is introduced.

## Repository hygiene

- Do not recreate Coordinator Runbook-style contracts, work orders, attempt logs,
  prompt archives, self-evaluation packages, or generated failure galleries.
- Keep active decisions concise and current. Put detailed product specifications in
  normal documentation, not in agent instructions.
- Preserve unrelated user work in a dirty tree. Do not delete, commit, push, or change
  repository-wide configuration beyond the user-approved scope.
- Generated references remain references until accepted. Do not wire them into the app
  or commit them as production assets prematurely.
