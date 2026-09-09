# Generative Performance System

**Status:** architectural direction · **Updated:** 2026-09-08

Planet Focus uses one canonical time-and-event system for narrative motion and sound.
The goal is not one object that performs every job. The goal is one authoritative
clock, one seeded plan, and one shared performance state consumed independently by
renderers and audio engines.

## Current foundation

## Implemented runner layer

`PerformanceSession` and `PerformanceRunner` are now the reusable transport below
the splash and focus stories. A session persists only duration, start date, and one
seed; the runner derives elapsed time, normalized progress, remaining time, and
completion from any sampled date. It has no frame counter and no mutable playback
position, so a renderer, audio scheduler, and a resumed app all arrive at the same
state independently.

The splash's Debug runner now starts this transport. While it is active, the
transportnot the Light calibration sliderdrives both the visual atmosphere and the
wave-score clock. A `SplashPerformancePlan` deterministically assigns every scheduled
note a semantic sound source at its start: pool, role, tonal slot, and octave. That
choice stays fixed for the event's full envelope even if the visual world moves to the
next pool. The monitor exposes the live pool mix and chosen source key before recorded
assets exist.

`FocusSession` remains the story-facing persistence type for now. When a story is
launched from the shared runner, it is derived from the same `PerformanceSession`,
preserving one start date, duration, and seed for `StoryPlayer`. The next migration is
to have story launch persistence store that transport directly rather than bridge it.

This implements controlled randomness at plan time: event timing variation and source
selection are deterministic functions of the run seed and event identity. No random
choice is evaluated per frame. It does **not** yet play audio: importing recordings and
connecting the existing silent audio dispatcher to these semantic source keys remains a
separate asset-driven step.

The existing story runtime already establishes the core flow:

```text
FocusSession + persisted seed
            ↓
       StoryDirector
            ↓
     immutable StoryPlan
            ↓
        StoryPlayer
       ↙           ↘
visual renderer   audio engine
```

- `StoryDirector` owns story-specific creative decisions and materializes a
  deterministic `StoryPlan`.
- `StoryPlayer` combines the authoritative session clock, selected module, Director,
  and immutable plan.
- `StoryMoment` is the synchronization boundary. One moment may carry visual and audio
  intent, plus identity, start time, duration, intensity, seed, and quantization.
- Renderers and audio engines consume the same moments. They never command one another.
- Normalized progress controls the macro narrative. Elapsed seconds control local
  motion, musical cadence, and event duration.

There are no separate `MusicDirector` and `ActionDirector` implementations in the
current repository. `StoryAudioEngine` is still silent, and musical quantization is
recorded as intent but not yet executed.

## Canonical extension

The reusable layer beneath stories and the splash should eventually provide:

1. An authoritative performance clock derived from a persisted start date. It must
   reconcile after backgrounding or device lock and must never use animation-frame
   count as time.
2. A seeded score that contains continuous beds and discrete moments.
3. Reusable continuous envelopes for visual intensity, audio gain, and other bounded
   parameters.
4. A visual sampler that can evaluate a deterministic performance at any elapsed time.
5. An audio scheduler that schedules ahead against the same clock and deduplicates
   already-issued moments.

`StoryPlayer` remains the focus-story adapter. The splash should use the lower-level
clock and score without pretending to be a `FocusSession`.

## Musical layers

### Continuous beds

Long pad voices, drones, and environmental beds belong to the score rather than being
repeated random moments. Future bed metadata may describe an asset or stem, loop
region, tempo or marker map, gain, and fade envelope.

### Directed moments

Bird passages, gusts, leaf releases, wave pulses, gong notes, sitar notes, and similar
events are bounded `StoryMoment`-style occurrences. A single occurrence carries both
its visual and audio intent. A shared envelope may drive both a visible accent and the
gain of its sound.

Randomness is directed rather than unconstrained. Rules must include progress or time
windows, evaluation cadence, probability, cooldown, duration, intensity, event-count
limits, quiet margins, and cross-family priority. Musical choices must also respect the
current tonal state, register, polyphony, repetition limits, and dynamic range.

### Tonal constraint

The selected scale or mode is the performance's **tonal constraint**. It limits which
recorded notes a generative rule may choose and may later include a root, register,
allowed intervals, chord tones, tension tones, and voice-leading rules. Lydian is a
promising direction for the calm opening scene, but it is not locked until the first
Ableton recordings are auditioned in the app.

Plans are materialized once from stable named random streams. The scheduler never
rolls randomness per frame. Missed or expired moments are not replayed after resume.

## Wave score

The eight splash ribbons are persistent visual instruments. Each owns a stable tonal
slot and deterministic analytic centerline and thickness fields. The generated rest
geometry is never replaced by a second set of authored shapes. A shared outer envelope
constrains only the composition boundary.

A note does not create or remove its cardstock ribbon. It creates a localized traveling
packet on that ribbon:

- attack grows the packet smoothly as it enters from the left;
- decay settles its strength;
- sustain carries it through the field;
- release flattens it while it leaves through the right;
- silence evaluates to the exact approved rest geometry.

The packet's compact spatial window and the note ADSR are separate multiplicative
envelopes. The spatial window determines where the ribbon may deform. The ADSR
determines how strongly it deforms. Centerline and thickness oscillators use a shared
directional sign so the visible disturbance reads left to right, while each ribbon
retains its own harmonic geometry.

At rest, the generated geometry must retain the approved reference's silhouette,
varied ribbon thickness, phase counterpoint, and responsive crop. Across time, sampled
frames must stay inside the same visual bounds. The accepted static field is now the
rest pose for the first animated splash pass.

The provisional splash score is 65 BPM in 4/4 and uses F Lydian: `F2, G2, A2, B2,
C3, D3, E3, F3`. Every ribbon has one stable tonal slot, note name, and wave actor.
The current silent audition score exercises all eight slots in a deterministic 32-beat
cycle. Notes begin four beats apart and remain alive for sixteen beats, producing four
continuously overlapping pad envelopes after the initial build. The temporary shared
envelope uses a three-beat attack, two-beat decay, 0.72 sustain level, ten-beat gate,
and six-beat release. Four designated foundation ribbons carry restrained breathing
while the first pad voices accumulate. Each active note then keeps a quiet whole-ribbon
motion bed beneath its stronger traveling packet. Both layers sample the same
continuous per-voice phase clock, so an attack or release can change energy without
restarting the shape. Exactly four ribbon actors remain scheduled after the intro, and
sampled geometry verifies that at least three make perceptible progress throughout the
cycle.

### Canonical performance events and silent-score monitor

`SplashWaveNoteEvent` is the splash's canonical performance event. It carries a stable
event ID, tonal slot, absolute musical start beat, gate length, ADSR envelope, role,
and intensity. A scheduled event is the only source of timing for its corresponding
wave and future audio cue:

```text
one performance event
           wave actor and resonance sampler
           silent-score monitor
           future audio scheduler
```

The renderer samples the event's actual ADSR at the current transport beat. It never
starts a second animation timer. Therefore attack begins at the exact event start,
the ribbon's localized swell follows attack/decay/sustain/release, and the visual ends
when the musical event ends. The future audio scheduler must consume the same event,
not rebuild timing from visual state.

The Debug score monitor makes this inspectable before any recordings exist. It shows
the live bar/beat, active notes and ADSR stages, note-to-wave mapping, a 24-beat score
roll, scheduled event log, and a deterministic ten-minute structural report. Its seed
selects the same event plan consumed by the wave renderer; the default seed preserves
the approved cadence, while other seeds add bounded onset and gate-length variation.
The manual Debug trigger creates one real performance event with a selected F-Lydian
note/wave and gate length; it is immediately visible in the monitor and drives only
that exact wave. Debug review can be frozen or fast-forwarded without altering the
live transport.

Evaluate the silent score in repeated deterministic passes before audio is imported:

1. Generate and inspect ten minutes at a fixed seed.
2. Check active-voice density, silent gaps, event duration, wave coverage, and
   note-to-wave synchronization.
3. Reject any plan with a visual event that has no matching note event, a note that
   has no matching wave actor, out-of-scale pitch choice, prolonged accidental silence,
   or uniformly synchronized waves.
4. Adjust scheduling constraints and compare the next deterministic pass.

This establishes musical structure, not timbre. The recordings will determine final
voicing, articulation, and mix after they arrive.

This is production-shaped placeholder data, not the final composition. The future
audio scheduler should consume the same note identity, tonal slot, beat position,
gate, and ADSR sample used by the visual renderer. The renderer must never infer notes
from audio playback, and the audio engine must never infer timing from animation
frames. The debug speed control scales the living performance clock only; it will be
removed or locked when authored audio establishes canonical note durations.

The approved first-pass choreography is:

- At 0.00 seconds the ink-navy paper canvas is visible and the silent drone/pad score
  begins with the visual intro. There is no post-intro hold or quiet score margin.
- The first ribbon begins unfurling at 0.25 seconds. All eight starts overlap between
  0.25 and 1.51 seconds in 0.18-second increments. Each unfurl lasts 2.00 seconds and
  the field is fully settled by 3.51 seconds.
- Long releases overlap subsequent attacks. The 32-beat loop includes its previous
  cycle when sampling release tails, so it has no silent seam.
- Four low-amplitude foundation samples cover the initial score build. Each first
  attack hands its foundation to a note-bound global motion bed plus a localized pad
  packet on the same continuous phase. Later loop attacks never reset or inject a
  temporary foundation, preventing both static gaps and onset bumps.
- Selecting Stories responds immediately. Ribbons recede front-to-back with a
  0.05-second stagger and each release lasts 1.15 seconds. At the same time the three
  lotuses close in reverse order: heart out, side petals fold to the shared base, then
  center petal out. Their reverse is time-compressed to 1.12 seconds, and navigation
  occurs when the final ribbon completes at 1.50 seconds.
- On entry, each lotus is assembled without whole-flower scaling or translation:
  center petal first, side-petal fan second, heart during the fan. Left, center, and
  right flowers start 0.16 seconds apart. The first flower waits until 3.56 seconds,
  after all supporting ribbons have completed at 3.51 seconds; the complete entrance
  ends at 4.46 seconds. Navigation becomes interactive at 3.51 seconds and may safely
  interrupt the decorative flower finish without a visual snap.
- Entry and exit vary the sampled domain of the same analytic ribbon used for packets.
  A smooth 0.09-world-width envelope collapses its moving frontier to zero thickness,
  so no mask edge, rigid translation, or opacity fade is exposed.
- Reduce Motion presents the settled composition and routes without unfurling.

## Future audio asset intake

## Atmosphere pools and source selection

The splash has one `SplashAtmosphereDirector`, sampled by the visual scene and later by
the audio scheduler. It is a deterministic state model, not another timer, renderer, or
audio player. Its three named pools are **Night**, **Twilight**, and **Daylight**. It
interpolates the semantic paper palette across Night, Twilight, and Daylight while exposing
the matching source-bank weights. The first automatic proposal is a twelve-minute arc;
the current Debug Light control provides direct visual calibration and deliberately does
not make production time advance yet.

Every future note event receives one `SplashSoundAssetKey` when it starts:

- a pool (`night`, `twilight`, or `daylight`);
- a role (`drone`, `pad`, or `melodicOneShot`);
- a stable tonal slot from zero through seven; and
- an optional octave offset.

The audio engine resolves that semantic key to a recorded asset. It does not use file
names inside the score. At a blended boundary, new events select their source bank with
the current weights; an already-playing event keeps its original asset and tail. This
gives pads the required overlap rather than abruptly switching a held sound between
worlds. The selection function is deterministic from scored event identity, so the
scheduler can prepare it ahead of time and a resumed renderer cannot accidentally choose
a different source.

### Visual light field

`SplashAtmosphereLightField` is the reusable visual counterpart to those weighted sound
pools. It is a deterministic function of atmosphere progress and normalized position.
It expands a warm field from the scene's light origin with a front-loaded
progress^1.8 reach curve, while a
small muted dawn boundary separates clean night and day paper. It does not ask the music
engine for a frame value and it does not linearly average endpoint RGB colors.

Role colors use perceptual OKLCH interpolation. When a role needs to travel from blue to
yellow or coral, its explicitly warm hue route passes through violet, red, and orange,
not cyan, green, olive, or mustard. This math is shared infrastructure: future stories
can provide their own origin, endpoint palettes, and boundary colors without duplicating
the splash implementation.

Chord voicing is intentionally not hard-coded yet. The incoming recordings will decide
the useful native register and articulation. The eventual planner may choose open
voicings, inversions, octave doubles, omissions, and tiny rolled attacks, but it must
only make choices within the tonal constraint and asset keys actually supplied.

The system should accept both individually recorded synth notes and authored stems.
Before production recording, define a small delivery contract covering note and octave,
tuning reference, articulation or variation, sample rate and bit depth, attack and full
release tail, loop points where applicable, tempo and bar markers for phrases, and the
intended audio bus. Preserve raw recordings; normalization and app encoding are derived
steps.

## Non-goals for the current animation pass

- No production audio engine or imported music assets.
- No final harmonic language, scale, instrumentation, or mix decisions; 65 BPM is a
  provisional scheduling tempo.
- No audible note triggering; the current note sequence is a visual audition only.
- No independent subsystem clocks and no renderer-to-audio callbacks.
- No broad rewrite of the working Autumn scheduling and reconciliation behavior.

## Incremental migration

1. Preserve the accepted analytic wave field as the rest pose.
2. Introduce reusable performance-time and deterministic presentation values for the
   first animated splash consumer.
3. Adapt `StoryPlayer` to the shared lower-level clock without changing
   story-owned direction.
4. Add production audio scheduling behind the existing audio protocol.
5. Add authored beds and directed event voices after the recording contract and first
   assets are available.
