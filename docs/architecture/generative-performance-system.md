# Generative Performance System

**Status:** live splash integration with recorded stereo audio · **Updated:** 2026-09-12

One authoritative transport and one seeded score drive narrative motion and sound.
The splash is the first integrated consumer. Autumn now has an integrated branch
checkpoint using the same transport; its full tree and musical direction are not yet
migrated. See [Autumn branch checkpoint](autumn-branch-checkpoint.md).

## Ownership: reuse these components

| Component | Responsibility |
| --- | --- |
| `PerformanceSession` / `PerformanceRunner` | Duration, start date, seed, explicit pause state, accumulated paused time; derive elapsed seconds and progress from a date. |
| `SplashMusicDirector` | Materialize the complete finite score once for a duration and seed. |
| `SplashWaveNoteEvent` | Canonical event ID, tonal slot/wave, start beat, gate, ADSR, role, intensity, and octave offset. |
| `SplashPerformancePlan` | Resolve the semantic sound source at each event's onset; sample atmosphere from the same session. |
| `SplashAtmosphereDirector` | Progress-to-pool weights, semantic palette, and renderer-independent sunrise state. |
| `SplashPerformanceScore` | Shared tempo, note envelopes, scheduled-event queries, and visual sampling. Its old repeating score is a calibration fixture only. |
| `SplashSamplePlan` | Resolve score events to recordings, sustained instrument sections, seeded dynamics, and accents. |
| `PerformanceSampleEngine` | Bounded streaming stereo voices, audio-clock scheduling, and offline validation using the same graph. |
| `PerformanceSynthesizer` | Existing UI facade for recorded playback, output controls, metering, and lifecycle. |
| `SplashScreenView` | Connect transport, plan, renderer, audition, session lifetime, settings persistence, and the nonblocking performance desk. |
| `StoryPlayer` / `StoryDirector` / `StoryMoment` | Existing focus-story adapters and visual/audio moment contract. Preserve them when adapting other scenes. |

Implementation lives in `PlanetCalm/Directors/`, with shared note/envelope/source contracts in
`PlanetCalm/Directors/PerformanceNoteEvent.swift` and splash visual sampling in
`PlanetCalm/Views/SplashScreenView.swift`. Do not create another clock,
pool selector, ADSR implementation, or independently randomized audio schedule.

## Transport and lifecycle

A run's selected duration is the complete darkness-to-daylight story length. Debug
offers 1 and 2 minutes exclusively in development Controls. Scene settings offers every whole
minute from 5 to 55 before starting, using a slider with gentle five-minute detents and no typed entry. The shared
`FocusDuration` value retains its integer-seconds serialization. The splash Start
opens the selected story's setup. A handwritten duration / Tap to begin group at the
top starts a fresh session with a fresh seed, then fades into a large handwritten
countdown in the same position. End session opens the Exit
confirmation. No public pause, replay, or restore exists. The development
runner accordion retains restart, pause/resume, end, and recorded-instrument audition.

The non-blocking Scene settings panel locks duration while a session exists. Volume
and mute stay live and only affect `PerformanceSynthesizer` mixer output; they do not
pause transport, discard scheduled notes, or reset the story. Scene audio settings
are in-memory UI state, not a new persistence service. Autumn currently has cue
intents but no playable soundtrack, so settings explicitly report its silent status.
Only Splash currently invokes recorded playback. Preferred duration and app-wide audio
preferences are deferred.

Elapsed time is clamped to the duration and is calculated as:

```text
sampleDate = pausedAt ?? now
elapsed = clamp(sampleDate - startedAt - accumulatedPause, 0, duration)
progress = elapsed / duration
```

Development pause freezes all consumers at the same elapsed time. Resume adds the pause interval
without resetting the seed, envelopes, or note identities. Restart creates a new
session at zero using the selected seed, so repeated auditions are comparable.
Change the seed between runs for another deterministic variation.

Active sessions are memory-only. Explicit cancellation or process termination
discards them; relaunch does not restore progress, and legacy saved-session keys
are removed. Only tuning settings persist, excluding manually triggered events.
Screen lock, app backgrounding, and audio interruptions leave wall-clock progress
running. Background/inactive audio stops; foreground playback reconciles current
envelopes rather than bursting missed attacks. Headphone disconnection silences
audition without pausing the timer. Background audio playback is not enabled.

An ended/completed run has no future notes. Completion holds the final scene with
Complete / Return to stories returning to the chooser; it never offers replay.
Finite sessions do not start another musical cycle automatically. Browsing ambience is
separate from a focus session: it continues through Home, Settings, Stats, and Stories,
without creating Health or history records. Starting a meditation stops browsing
ambience; returning Home afterward begins a fresh ambient timeline.

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

## Recorded Splash instruments

Production resources live in `PlanetCalm/Assets/Audio/Stories/Splash`, grouped into
Pads, Bass, Melody, Transitions, Atmosphere, and Bookends. All 47 imports are lossless
ALAC in M4A containers, stereo, 48 kHz. Ableton originals stay in the audio project.
Filename octave labels are the original export convention; a prominent harmonic is
not evidence that the MIDI note is wrong. The two bass timbres intentionally retain
the different sounding registers approved by the composer.

Pad banks advance in thirds of the selected duration. A note holds its bank through
release, so notes from both banks overlap around a boundary. Visual pad source labels
use the same boundary calculation. Melody instruments use a seeded shuffled bag,
remaining for 48–72 seconds and changing only between phrases. Handpan phrases have
3–5 neighboring notes, spaced 1.5 beats apart, with alternating gentle left/right
balance. Chimes retain their sparse authored strikes and cyber chords retain their
baked texture. The shared handpan effects are a quiet tempo-related delay and hall
reverb; the other recordings receive no additional reverb or delay.

Bass alternates its two recordings, with a seeded 20% chance of an octave-down
pitch shift on each event. TimePitch preserves playback duration. Note dynamics
vary by approximately −1.5…+1 dB. This varies amplitude, not the timbre of a
velocity-sensitive instrument: only one rendered velocity layer was supplied.

The catalog records the Ableton faders. The runtime additionally trims pad banks by
−3/+7/+6 dB to reduce the measured level drop between banks. Rainstick 1 has an
18 dB catalog correction for its unusually quiet source; both rainsticks receive a
further gentle −6…−4 dB trim in the mix. These are reversible playback settings,
not normalization of the source files. Intro/outro frame a finite run; one rainstick
plays at each pad transition; occasional koshi accents leave space around those
transitions. A planned finite ending fades the complete output, including effects, over ten seconds.

## Playback and verification

The same finite score event IDs and absolute start beats drive waves and recorded
notes. Accents/bookends are audio-only texture, not extra wave triggers. Recorded
melodies preserve their natural tails beyond the short visual note envelope. Pads
and drones follow their scheduled gate/release lengths using gradual gain envelopes.
Overlapping notes keep independent traveling wave packets. Their local strengths
combine within a fixed motion budget; a new attack cannot move an existing packet.
Percussive notes begin their visual response at the shared onset, but the paper
builds over up to 0.9 seconds at the note's intensity instead of snapping to the
instrument's short attack. Gate/release endpoints stay shared. Only waves with an
existing ambient foundation hand it off when their first note arrives.
Generated melody notes also drive the paper-edge highlight and localized lift.
Each note keeps its own contribution through overlaps, using the same gentle
visual attack and shared score onset. Travel stays in the central portion of
the wave world visible in portrait. Reduce Motion suppresses these accents.

`AVAudioPlayerNode` streams segments instead of loading the full sample bank into
RAM. A bounded pool is sized to the score's maximum simultaneous voices, including
lookahead. A dedicated audio actor prepares the graph, opens files, and runs the
10 ms control task off the UI actor. It queues 250 ms ahead; note onsets are
scheduled with `AVAudioTime`, not fired by that task's tick. Playback projects the
same session elapsed time onto the host audio clock, accounting for engine startup.
Background audio remains disabled. Returning seeks held pads/drones into their
current source positions and skips missed melodic attacks and accents. Mute/volume
only affect output and never regenerate the score.

Offline tests use this same engine graph and scheduling path. They render three
complete five-minute seeds at full output, verify finite samples, stereo energy,
headroom, absence of unintended silence, and complete event scheduling. Plan tests
cover shared visual/audio onsets, seed determinism and variation, instrument dwell,
bank overlap, and the bass transposition distribution. Existing score-continuity
and live-output tests also run. Musical balance still needs the composer's live
listening judgment; numerical tests cannot establish whether a piece feels calming.

A Debug-only `--splash-audio-review` launch opens a finite five-minute run with animations
and recordings for comparison. `--splash-ambient-review` opens the continuous browsing
composition. The existing Controls runner can still start a reproducible finite seed.


## Continuous browsing composition

Home ambience uses the existing five-minute rise and five-minute return to night.
Music advances forward throughout; it never reverses with the sun. The shared light
progress controls a restrained night-to-day gain change and a pad-only low-pass filter.
Night is quieter with more space between musical phrases; daylight is fuller and the
pads gently brighten. Filtering preserves stereo and leaves the source files intact.

Musical passages use repeatable seeded variation. Harmonic variety stays inside the
existing F-centered natural-note pool, with the recorded F bass as an anchor. Changes
must preserve the sparse onset rate and five-voice pad ceiling; adding compatible
chords must not add extra musical activity. Shared pitches bridge changes through
existing overlapping recordings, whose baked releases cannot sustain indefinitely.
Five close voicings retain F and C; upper C enters last in each block and rings
across the next boundary before being retriggered. Harmonic sections last about
89 seconds, with a seeded chance to hold for a second section. Night favors open
colors, while daylight also admits major-seventh colors. Independent pad octave
jumps are removed. Melody notes follow the current chord’s pitch classes within
the five recorded melody notes, using semitone distance for nearby choices.
Short motifs recur with small changes rather than replacing every note independently.
Melody instruments stay for sustained passages. Drone timbres alternate, retaining the approved
occasional octave-down variation. Rainsticks mark pad changes and koshi accents leave
space around them. The intro plays only at the beginning; cycle boundaries have no
outro, restart, or global fade. Existing notes and effects finish naturally across them.

The rolling score must be independent of query size: requesting one passage in several
small batches must produce exactly the same events, timbres, and full lifetimes as one
larger request. Retention and audio voice counts remain bounded during long playback.
The first entrance fades in gradually; mute and headphone loss remain responsive.
