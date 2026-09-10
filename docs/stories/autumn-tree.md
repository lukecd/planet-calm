# Autumn Tree

Story 01: a quiet clearing beneath a warm paper-cut tree.

The approved emotional arc is stillness → gentle activity → settling → quiet rest.
This document describes the current story, not the retired painted-scene proposal.
Implementation details: [tree and physics](../architecture/autumn-branch-checkpoint.md),
[automatic encounters](../architecture/autumn-encounters.md), and
[origami deer ending](../architecture/autumn-deer.md).

## Session contract

- Every whole-minute duration from 5 through 55 is supported. One- and two-minute
  previews are development-only. The shared transport owns all timing.
- Normalized progress controls seasonal evolution and lighting; physical wind,
  leaf flight, bird movement, and deer movement retain real-second durations.
- Begin starts immediately. Duration locks; volume/mute remain adjustable.
- There is no user pause, restart, or restoration. End requires confirmation and
  discards the attempt. Background/lock does not pause the in-memory timer;
  process termination discards the session.
- Completion holds the resting composition with “Complete / Return to stories.”
  Development controls remain separate and are absent from release builds.

## Current choreography

The connected tree carries 182 maple leaves using three retained masks: red,
orange, and yellow. Stem attachment follows the moving branches. Seeded, clustered
release ordering distributes detachment from 8% through at most 80% progress,
leaving real time for every leaf to land before completion. Leaves remain in a
sheltered carpet, with selected exposed leaves responding to later breezes.

Irregular decisions choose wind, a single origami bird visit, or quiet. Each new
session has a fresh seed. Bird visits have variable but restrained travel speed,
wingbeats, depth, and perch time; a full departure and cooldown separate visits.
A short session can have no bird. More time means more opportunities, not slower
wingbeats or a stretched walk. Wind varies its source, direction, pulse, and strength.

Birds finish before the closing act. The guaranteed copper-and-cream origami deer
walks in from the right, pauses, lowers into the leaves, and rests beside the tree.
Its complete movement and an 8–45-second hold are reserved in every duration.
A soft closing breeze is guaranteed too. The tree remains rooted and visible.

## Art and accessibility

Keep independent paper-cut layers, local paper grain, sun-related shading, real
contact shadows, and subtle depth. Do not flatten the scene into a background image.
The bird and deer are native articulated geometry, not sprite sheets. The old
rabbit, flock, painted scene, and leaf-study interfaces are retired; see the
[current asset inventory](../../PlanetCalm/Assets/Stories/AutumnTree/README.md).

Reduce Motion replaces animal travel with still poses and removes continuous sway
and leaf travel. Completion is understandable without sound. Keep readable text,
VoiceOver labels, and generous interaction targets; avoid confetti or forced actions.

## Deferred integration, not missing visual scope

Autumn audio is not connected. The intended direction is a restrained evolving
music bed with sparse melody, wind, leaf rustle, and bird ambience. Shared moments
must align related audio and visuals; no second clock or audio-side random schedule.
All recorded assets need confirmed commercial rights. Master volume/mute are present;
separate Birds, Leaves, and Atmosphere levels remain future audio UI work.

Another app-level workstream owns preferred duration, persistent audio settings,
optional authorized app blocking, session history/stats, and entitlement decisions.
Completion recording is not implemented by the story renderer. The product direction
is private totals without streak-loss penalties or random rewards; aggregate stats
are intended to require paid access. Whether earlier history is retained and later
revealed remains a product decision. Blocking must preserve emergency/system access.

The former squirrel, rabbit, distant flock, and sprout ideas are not required for
this PR and must not be silently reintroduced. Physical-device battery, thermal,
long-session, and background-catch-up validation follows feature integration.
