# Generative Performance System

**Status:** architectural direction · **Updated:** 2026-09-06

Planet Focus uses one canonical time-and-event system for narrative motion and sound.
The goal is not one object that performs every job. The goal is one authoritative
clock, one seeded plan, and one shared performance state consumed independently by
renderers and audio engines.

## Current foundation

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

The splash wave field is a continuous generative performance. Each ribbon has a stable
identity and a deterministic oscillator configuration containing an absolute spatial
centerline, independent phase, temporal rate, amplitude modulation, wavelength
modulation, thickness field, and future musical voice assignment. A shared outer
envelope constrains only the composition boundary; it does not transport the internal
ribbons up and down.

The field has two behaviors:

- continuous, slow analytic motion sampled from elapsed time;
- sparse directed accents represented as shared visual/audio moments.

At rest, the generated geometry must retain the approved reference's silhouette,
varied ribbon thickness, phase counterpoint, and responsive crop. Across time, sampled
frames must stay inside the same visual bounds. Animation remains deferred until the
static field is accepted.

## Future audio asset intake

The system should accept both individually recorded synth notes and authored stems.
Before production recording, define a small delivery contract covering note and octave,
tuning reference, articulation or variation, sample rate and bit depth, attack and full
release tail, loop points where applicable, tempo and bar markers for phrases, and the
intended audio bus. Preserve raw recordings; normalization and app encoding are derived
steps.

## Non-goals for the current wave pass

- No production audio engine or imported music assets.
- No final harmonic language, scale, tempo, instrumentation, or mix decisions.
- No visible idle animation, note triggering, or entrance/exit choreography.
- No independent subsystem clocks and no renderer-to-audio callbacks.
- No broad rewrite of the working Autumn scheduling and reconciliation behavior.

## Incremental migration

1. Accept the static analytic wave field and its reference-derived scoring.
2. Introduce reusable envelope and performance-time value types when the first real
   motion/audio consumer requires them.
3. Adapt `StoryPlayer` and the splash to the shared lower-level clock without changing
   story-owned direction.
4. Add production audio scheduling behind the existing audio protocol.
5. Add authored beds and directed event voices after the recording contract and first
   assets are available.
