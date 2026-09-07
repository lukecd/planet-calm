# Autumn Tree

**Story 01**

## Premise

A person focuses beneath a warm autumn tree. Over the session a soft breeze animates the clearing: leaves drift, a squirrel gathers an acorn, birds cross the canopy, and a deer makes a quiet final appearance. The tree remains rooted and visible at the end—the work happened under its shelter.

**Emotional arc:** stillness → gentle activity → settling → quiet discovery.

## Story contract

The story must complete over any supported focus duration (the Planet Focus product requirement is 5–50 minutes; the current runtime exposes 15, 25, and 50 minutes). Debug-only 1- and 2-minute previews remain separate from production choices. All timing uses normalized progress from `0.0` at session start to `1.0` at completion; the app maps that progress to the chosen duration.

The visual world is ambient, not a reward video. It must remain calm enough that a user can ignore it while working and enjoy it when glancing back.

The final scene direction will include an authored intro that establishes the clearing and an outro that lets it settle before completion. Their exact behavior and progress ranges remain intentionally open until the Autumn scene-design pass.

## Timeline

| Progress | Narrative beat | Visual motion | Ambient audio |
| --- | --- | --- | --- |
| 0–10% | The clearing wakes. | Tree is still; one or two attached maple leaves loosen as a faint breeze begins. Oak leaves remain settled on the ground. | Near-silent bed; very low wind enters gradually. |
| 10–35% | The story gathers. | Leaves drift at varied depths. A squirrel gathers an acorn near the roots and disappears behind them. | Light leaf rustle joins the wind. |
| 35–65% | The clearing is alive. | The breeze reaches its liveliest, still subtle, point. A later Swift implementation may lift a small group of settled oak leaves through the clearing. One flock of 20–30 tiny birds lifts from the canopy, gathers into a loose moving formation, and crosses the distant sky. | Wind and leaf layers are at their warmest level; one distant, restrained flock cue may occur. |
| 65–85% | The world settles. | Wind softens; late-afternoon light warms. One seated rabbit may make a single quiet peek from behind the lower tree, using its approved head-and-ear gesture, then retreat. The squirrel may briefly return as a separate, currently unimplemented cast member. | Leaf rustle eases; wind gently softens. |
| 85–96% | The clearing opens. | Fewer leaves fall. The distant hills feel still, leaving space for the ending. | Sparse wind only. |
| 96–100% | A quiet reveal. | A deer steps out from behind a distant hill, pauses in the clearing, and looks toward the tree. | A final soft breeze; no dramatic sting. |
| Completion | The story rests. | Timer gives way to a quiet completion state. One final leaf settles; the deer remains briefly before the world reaches a calm resting loop. | Ambient layers fade to the user’s selected resting level. |

## Layer plan

Back to front:

1. Handmade-paper sky and background texture.
2. Distant hills and clearing, arranged for slow parallax.
3. Deer, concealed behind a hill at story start.
4. Behind-tree maple instances attached through the reviewed tree-local branch map.
5. Tree trunk and roots.
6. Front-of-tree maple instances from the same deterministic canopy layout.
7. Midground shrubs and squirrel.
8. Settled oak and other approved ground-only leaf instances; later Swift breeze events may temporarily lift selected oak instances.
9. Individual falling maple leaves at background, midground, and foreground depths.
10. Native timer, focus controls, and completion UI.

The deer remains in the background layer and moves more slowly than the leaves. The tree must not fade away or move off-screen for the completion reveal.

The rabbit is an authored settling-phase cameo, provisionally scheduled within 70–84% progress. It remains partly occluded by the lower tree/root layer, never walks or hops, and plays its accepted head-and-ear gesture once. This does not replace the squirrel in the premise or future cast plan.

## Leaf population contract

- The tree canopy uses deterministic instances of `leaf-maple-red`, `leaf-maple-orange`, `leaf-maple-yellow`, and `leaf-maple-olive`. Autumn Tree v1 does not require flattened canopy-cluster assets.
- Attached maple leaves reference a reviewed branch node and a recorded placement seed so the same canonical canopy can be reproduced across devices and story checkpoints.
- Oak leaves begin on the ground and never grow from this tree. They may be designated for later Swift breeze behavior in which small groups lift or blow through the clearing.
- Static assembly shows every oak leaf settled; it does not simulate gusts or airborne oak leaves.
- `leaf-small-orange` and `leaf-small-red` require explicit visual species classification before attachment. Only leaves classified as maple may join the canopy; all others remain ground/drift-only.
- Controlled randomness must create correlated clusters, irregular breathing spaces, branch-informed orientation, and plausible autumn color regions. It must not uniformly scatter leaves or carve a timer-shaped hole in the canopy.

## Bird-flock direction

The flock is a single authored middle-story moment, not continuous background activity. It uses one reusable small right-facing bird animation instanced 20–30 times with deterministic per-bird wing phase and restrained scale variation. Individual birds remain intentionally tiny at phone scale; the readable subject is the collective formation and how it flexes as it travels.

The route uses elapsed-time motion and a persisted session seed. Local separation, alignment, and weak cohesion combine with a soft moving formation envelope so the group reads as an organized wedge or shallow arc without locking into rigid slots. The flock may breathe and locally avoid crowding, but it must keep a coherent direction, cross the whole visible sky corridor once, and fully exit. It must not wrap, bounce, circle indefinitely, reverse abruptly, or treat the foreground tree as a same-plane obstacle. The tree may occlude birds as they emerge from or pass behind the canopy.

Short focus sessions do not accelerate wingbeats or flight speed. The Director schedules the same complete elapsed-time flock moment within the selected itinerary. A reconstructed active session must produce the same agents, formation, phases, and route from the same seed.

## Audio direction

Audio is optional ambience, not a soundtrack. The initial palette is:

- steady, low-level wind;
- intermittent dry leaf rustle;
- one distant flock moment during the middle of the story.

Each layer needs its own asset, loop behavior, and fade envelope. Audio should be pleasant at low volume, sparse enough for focus, and fully usable with sound off. Do not make successful completion dependent on hearing any cue.

Visual and audio behavior that share a cause use the same scheduled story moment. A gust may move a selected group of leaves and play a matching wind variation; a leaf detachment may later request an original tonal note. Tonal cues may be quantized to the story's musical clock so the visual and note begin together on a beat or subdivision.

Autumn's production audio will be composed after the visual runtime is working. Until then, its Director may produce audio intent that is accepted by a silent audio engine.

The product provides a master ambience control plus three individual levels: Birds, Leaves, and Atmosphere. Atmosphere contains wind and any other non-bird/non-leaf natural ambience. Each level starts from the user’s chosen setting and may only change through a gentle fade.

## Completion and progression

Completing the focus duration records a completed session and adds its full duration to the user’s private focus-minute total. There are no keys, streak-loss penalties, or random rewards.

The completion UI should be small and warm. Everyone receives the complete story ending and a simple completion acknowledgment. Aggregate session counts and focus-minute totals are stats and require paid access under the Planet Focus product policy; the story's Director does not decide that entitlement. Do not use confetti, aggressive celebration, or a forced next action. Whether pre-upgrade history is retained and later revealed remains an app-level product decision.

## Accessibility and interruption behavior

- With Reduce Motion, replace drifting, sway, parallax, the deer walk, and continuous flock flight with minimal fades or static state changes. The flock may appear briefly as a still distant formation and then fade rather than traverse the screen.
- Provide non-audio feedback for every story beat and completion state.
- There is no pause or resume. Choosing to abandon the session ends the current story attempt, grants no completion credit, and starts the narrative from the beginning next time.
- The story never prevents access to calls, emergencies, or system-level needs. Any future Screen Time-based shielding is optional and limited by the user’s system authorization.

## Asset checklist (first pass)

- Paper sky and three to four hill layers.
- Rooted tree trunk and root base.
- Three to five branch groups.
- Four approved maple leaf source cutouts, instanced deterministically to form the attached canopy.
- Two oak leaf source cutouts that begin on the ground and are eligible for later grouped breeze motion.
- Two small leaf source cutouts that remain ground/drift-only unless explicitly classified as maple.
- One settled/completion leaf accent.
- Squirrel idle / gather / exit poses.
- One reusable tiny animated bird component and a deterministic 20–30 bird formation plan.
- Deer hidden, stepping, pause, and resting poses.
- Sprout / completion accent.
- Wind, leaf-rustle, and bird ambience source tracks with confirmed commercial licenses.

## Current implementation boundary

The repository contains deterministic flocking, rabbit playback, leaf
aerodynamics, wind, collision, and terrain primitives. The visible story scene
currently uses the approved layered Autumn artwork and scheduled cast moments.
Full leaf-release choreography, the squirrel, deer motion, production audio,
and final duration mapping remain future work.
