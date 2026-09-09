# Generative Performance System

**Status:** live splash integration with temporary synthesized audio · **Updated:** 2026-09-09

One authoritative transport and one seeded score drive narrative motion and sound.
The splash is the first integrated consumer. Autumn and Contemporary Lotus are not
being migrated in this pass.

## Ownership: reuse these components

| Component | Responsibility |
| --- | --- |
| `PerformanceSession` / `PerformanceRunner` | Duration, start date, seed, explicit pause state, accumulated paused time; derive elapsed seconds and progress from a date. |
| `SplashMusicDirector` | Materialize the complete finite score once for a duration and seed. |
| `SplashWaveNoteEvent` | Canonical event ID, tonal slot/wave, start beat, gate, ADSR, role, intensity, and octave offset. |
| `SplashPerformancePlan` | Resolve the semantic sound source at each event's onset; sample atmosphere from the same session. |
| `SplashAtmosphereDirector` | Progress-to-pool weights, semantic palette, and renderer-independent sunrise state. |
| `SplashPerformanceScore` | Shared tempo, note envelopes, scheduled-event queries, and visual sampling. Its old repeating score is a calibration fixture only. |
| `PerformanceSynthesizer` | Temporary native audio consumer of the same event plan. It does not invent note timing or random choices. |
| `SplashScreenView` | Connect transport, plan, renderer, audition, lifecycle, persistence, and the nonblocking performance desk. |
| `StoryPlayer` / `StoryDirector` / `StoryMoment` | Existing focus-story adapters and visual/audio moment contract. Preserve them when adapting other scenes. |

Implementation lives in `PlanetCalm/Directors/`, with existing splash event and visual
types in `PlanetCalm/Views/SplashScreenView.swift`. Do not create another clock,
pool selector, ADSR implementation, or independently randomized audio schedule.

## Transport and lifecycle

A run's selected duration is the complete darkness-to-daylight story length. Debug
offers 1 and 2 minutes as well as the existing 5–50-minute choices. Start begins a
splash run; the runner accordion exposes restart, pause/resume, end, and synth audition.
The bottom Start control can also start or pause/resume the splash.

Elapsed time is clamped to the duration and is calculated as:

```text
sampleDate = pausedAt ?? now
elapsed = clamp(sampleDate - startedAt - accumulatedPause, 0, duration)
progress = elapsed / duration
```

Pause freezes all consumers at the same elapsed time. Resume adds the pause interval
without resetting the seed, envelopes, or note identities. Restart creates a new
session at zero using the selected seed, so repeated auditions are comparable.
Change the seed between runs for another deterministic variation.

The splash stores its transport in the app's local preferences. On relaunch, an
unfinished run regenerates the same score and reconciles to its current time; a paused
run remains paused. Background/inactive audio stops, while an unpaused story keeps
wall-clock progress. Foreground playback resumes current note envelopes, never a
burst of missed attacks. Audio interruptions and headphone disconnection explicitly
pause the run and require resume. Background audio playback is not enabled.

An ended/completed run has no future notes. Completion holds the final sunrise state.
The app does not start another musical cycle automatically. Calibration mode remains
available when no finite run is active.

While running, the speed and light calibration sliders are disabled. The visual Amount
control can still scale wave displacement without changing any musical time or envelope.
Reduce Motion changes visual presentation only, not score timing.

## Musical structure and controlled randomness

Provisional tonal constraint: **F Lydian**, 65 BPM, 4/4.
Eight stable slots map to F2, G2, A2, B2, C3, D3, E3, F3; octave offsets change the
sounding register while retaining the same wave assignment. This is an audition
language, not a final composition or timbre decision.

The director has independent named seeded streams for pads and melody. Randomness is
evaluated when building the plan, never in an animation frame or audio callback.

- **Drone:** root F2, renewed every 28 beats, with a 32-beat gate and 10-beat release.
  The next attack overlaps the previous sustain/release, including bank changes.
- **Pads:** four initial staggered voices, followed by bounded 4.6–5.2-beat onset
  intervals, 16–18-beat gates, and 7-beat releases. Selection favors the current
  harmonic collection and unoccupied wave slots. Dynamics, attack, and occasional
  octave displacement vary within bounds.
- **Melody:** small 2–4-note phrases, neighboring choices in a constrained upper
  register, short gates, and 7–13-beat rests between phrases. The drone/pads continue
  through those melodic rests.
- **Ending:** gates and releases are bounded by session duration; insufficient space
  for a valid attack/decay/release prevents a new late note. The endpoint is silence,
  not abruptly cut active events.

The retained repeating 32-beat score is used only for visual calibration outside a
run. Finite events set `isRepeating = false`, and the shared query/sampler must never
duplicate them into subsequent cycles.

## Event-to-wave synchronization

Every event's source of truth is its absolute start beat plus gate and release.
Both audio and visuals sample the same `SplashADSREnvelope`. A note's lifetime is
`gateBeats + releaseBeats`; no separate UI animation timer is started.

The eight paper ribbons remain in the scene. Notes create traveling deformations,
not new cardstock bands. Attack enters smoothly; sustain carries the packet; release
returns to the resting ribbon. Existing continuous phase is never reset at onset.
If several notes share a wave, their envelope-weighted packet positions combine
continuously; they do not steal or restart each other's phase. The manual tuning
trigger is also an event: during a run it is heard and shown at the same transport beat.

The nonblocking monitor shows active notes, role, ADSR, source bank, actual octave,
wave assignment, and scheduled starts/lengths. Its frozen/fast-review view is inspection
only; it does not seek playback. Structural diagnostics are cached per plan rather
than recomputed for every animation frame.

## Sound pools and visual evolution

Night, Twilight, and Daylight are the three semantic pools. For progress p:

- 0…0.5: weights are Night = 1−2p, Twilight = 2p, Daylight = 0.
- 0.5…1: weights are Night = 0, Twilight = 2−2p, Daylight = 2p−1.

Each event deterministically selects its pool from its onset progress, run seed, and
event identity. It holds that source through its release. Long overlaps therefore
blend banks naturally; a held note is never replaced at a pool boundary.

The same progress drives the approved native Metal sunrise: sun rise, cloud lighting,
atmospheric scattering, and paper-color treatment. Do not replace it with an even
whole-screen RGB fade. See [Splash sunrise model](../design/splash-sunrise-model.md).
Cloud artwork and its ray-blocking shapes share geometry and depth.

## Temporary audio implementation

The audition uses native AVAudioEngine and AVAudioSourceNode, not JavaScript, MIDI
sent to another app, bundled samples, or a second transport. Immutable prepared voices
retain the canonical score event and selected semantic source key.

The source callback maps the audio host timestamp to session elapsed seconds using
one start anchor; it samples only voices intersecting the requested audio block.
Audio callbacks are explicitly sendable and do not inherit main-actor isolation.
They perform no file I/O, random selection, or score mutation. A mixer tap reports
actual output level to the debug desk, so a successful engine start is not mistaken
for nonzero output.

The drone and pads use quiet harmonic synthesis with a slow spectral-tilt modulation;
the melodic voice has decaying bell-like partials. Pool choices alter harmonic
brightness. Gain is conservative and output is soft-limited. Resume/unmute has a
short click-prevention ramp; pause/end fades output briefly. These are audition
instruments, not an assertion that the final music is approved.

The app uses an ambient, mixing audio session and respects silent mode. Existing
focus-story `StoryAudioEngine` remains silent; it has not been silently switched to
this splash audition.

Relevant Apple API contracts:
[Source render callback](https://developer.apple.com/documentation/avfaudio/avaudiosourcenoderenderblock)
and [host-time conversion](https://developer.apple.com/documentation/avfaudio/avaudiotime/seconds(forhosttime:)).

## Recording intake and future scenes

Retain `SplashSoundAssetKey` as the source lookup contract: pool, role, tonal slot,
octave offset. Original recordings can replace the audition voice without changing
score timing, wave envelopes, or bank selection. Provide long pad/drone notes and
short melodic articulations separately, with note/octave, tuning, sample format,
full release tail, loop metadata where applicable, and tempo markers for phrases.
Do not discard originals or normalize them destructively.

The Autumn adapter should consume the same transport progress for leaf evolution and
shared moments for synchronized cues, while retaining its own director and geometry.
Do that as a separate scoped integration after the splash checkpoint is accepted.

## Verification and limits

Automated checks cover pause/resume persistence, deterministic seeds, finite endings,
drone continuity, active-wave density, event/audio envelope identity, source-key
stability, offline PCM output, live mixer output, and nonblocking playback controls.
Use the one-minute rendered audition to evaluate musical structure, then audition
longer sessions before accepting final harmony or mix.

Existing intro/exit choreography and the approved sun/cloud scene are preserved.
The desktop simulator is a functional check, not physical-device latency, battery,
or audio-route qualification. Production recordings, full background playback, and
final musical taste approval remain outstanding.
