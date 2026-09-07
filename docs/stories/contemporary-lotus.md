# Contemporary Lotus — opening mechanics

## Decision-level conclusion

The rejected warp experiment used the wrong mechanical model. It treated a
petal as a flat sheet whose upper portion curls backward. A real sacred lotus
(*Nelumbo nucifera*) is better described as a set of broad, cupped blades
whose orientation changes primarily from tissue at and near each petal's
attachment to the receptacle. The petal body is not perfectly rigid, but its
curvature changes are secondary and distributed; a conspicuous hinge or
backward fold in the middle or at the tip is not the opening mechanism.

This motion model should govern the future authored flower rig.

## What is directly observed

### 1. The petal base is a principal actuator

A 2024 controlled-environment study followed the same lotus flowers through
opening and closing and measured epidermal cells at the base, middle, and tip
of petals. The greatest change occurred in basal cells, particularly in inner
petals. Those basal cells expanded during opening and contracted during
closing. Differences between the flower-facing and outward-facing surfaces
are proposed as one of the forces that changes petal orientation.

The strongest practical result for a rig is in the study's sampling method:
the researchers removed the upper half of petals and confirmed that the
remaining lower halves still performed the normal opening and closing motion.
The distal sheet is therefore not the necessary motor of the movement.

Sources: [University of Tokyo research summary and figure captions](https://www.a.u-tokyo.ac.jp/topics/topics_20241107-1.html),
[Ishizuna et al., *American Journal of Botany* (2024)](https://doi.org/10.1002/ajb2.16433).

### 2. Visible separation is not the same as the source of movement

On the first flowering day, an anatomical field study describes only the
distal halves visibly unfolding into a narrow bowl while the basal halves stay
tightly gathered around the reproductive organs. That wording does not imply
a backward tip hinge. It means the unconfined upper portions separate enough
to form the opening while the crowded bases remain close together. On the
second day, the flower opens much more completely into a shallow, broad disk.

Source: [Vogel and Hadacek, *Plant Systematics and Evolution* (2004)](https://doi.org/10.1007/s00606-004-0203-6).

### 3. A real lotus opening is a multi-day cycle

Sacred lotus normally opens in the early morning and closes again later in the
day. The cycle repeats for roughly three days, with a different maximum shape
on each day, before petal drop on the fourth day. Day 1 is a small bowl. Day 2
is the broadest, most complete opening. Day 2 closes less tightly, and Day 3
opens again before senescence and abscission begin.

This sequence is documented independently by the 2024 cell study, the 2004
functional-anatomy study, and a real three-day time-lapse maintained by the
Botanical Garden at Aarhus University.

Sources: [University of Tokyo time series](https://www.a.u-tokyo.ac.jp/wp-content/uploads/topics/2024/topics_20241107-1.jpg),
[Aarhus University botanical-garden time-lapse](https://sciencemuseerne.dk/en/botanisk-have/planternes-hemmelige-liv/the-lotus-plant-blooms),
[Vogel and Hadacek (2004)](https://doi.org/10.1007/s00606-004-0203-6).

### 4. Petals are not synchronized concentric rings

Lotus petals originate in a spiral arrangement rather than as a stack of
perfectly aligned rings. Inner petals also elongate more than outer petals
during the flowering period. A mechanically credible animation therefore
needs individual attachment positions, angles, lengths, and timing offsets.
Several petals can participate in the same broad phase, but they should not
move as one cloned circular array.

Sources: [Hayes, Schneider, and Carlquist, *International Journal of Plant Sciences* (2000)](https://doi.org/10.1086/317577),
[e-Flora of Thailand: Nelumbonaceae](https://botany.dnp.go.th/eflora/florafamily.html?factsheet=Nelumbonaceae),
[Ishizuna et al. (2024)](https://doi.org/10.1002/ajb2.16433).

## What the supplied visual reference shows

Reference 01 is a stylized collage-paper full bloom, not a botanical motion
record. It is still decisive for the finished pose and material language:

- outer petals finish low and wide because their whole base angle has opened;
- middle petals form an upward-facing bowl;
- inner petals remain steeper and frame the seedpod;
- each blade retains a broad convex or cupped body;
- overlap changes from the attachment outward, without a backward kink;
- color and paper texture are independent of the mechanical model.

The reference must not be interpreted as evidence for exact timing, cultivar,
or the number of biological flowering days.

## Motion specification for the next rig

Each petal should own an attachment frame on the receptacle and these channels:

1. **Base flare:** the primary channel. Rotate the whole petal outward around a
   tangential axis near its attachment.
2. **Base azimuth and spiral placement:** give every petal a real angular
   position rather than a copied ring index.
3. **Small base translation/extension:** represent measured basal growth
   without allowing the root to detach or slide visibly.
4. **Preserved cup:** maintain a smooth lengthwise and crosswise curve as the
   petal opens. Any morph is gentle and distributed.
5. **Small axial twist:** use sparingly to prevent mechanical symmetry and to
   reveal the correct front or back surface.
6. **Individual schedule:** group petals into broad outer, middle, and inner
   phases, then add restrained offsets within each phase.
7. **True depth and occlusion:** rear petals pass behind front petals; front and
   back materials remain coherent as the viewing angle changes.

Prohibited motion:

- no mid-petal hinge;
- no tip rolling backward as the main reveal;
- no accordion fold;
- no identical simultaneous ring motion;
- no scale squash standing in for foreshortening;
- no detached or sliding petal roots.

## Technology implication, not yet a technology decision

The biology closes the flat SpriteKit warp approach as the primary mechanism.
The next credible proof needs real three-dimensional petal transforms so base
flare, foreshortening, surface orientation, and occlusion are consequences of
geometry rather than painted guesses. A small amount of smooth mesh
deformation may support the cup, but it should not carry the opening.

RealityKit is available on iOS and iPadOS; it is not limited to visionOS.
Apple documents entity transforms, skeletal animation, blend shapes, meshes,
materials, lighting, and depth-aware rendering. That makes it a plausible
runtime for a petal rig authored in a 3D tool. It does not by itself create a
correct lotus rig: the attachment frames, petal separation, poses, topology,
and animation still have to be designed and likely authored in Blender or a
similar modeling tool, then imported into the app.

Sources: [Apple RealityKit overview](https://developer.apple.com/documentation/realitykit),
[Apple RealityKit models and meshes](https://developer.apple.com/documentation/realitykit/scene-content-models-and-meshes),
[Apple RealityKit animation blending](https://developer.apple.com/documentation/realitykit/blendtreeanimation).

Before choosing RealityKit, SceneKit, rendered image sequences, or another
pipeline, inspect the supplied `.blend` and `.glb` assets for separate petals,
usable topology, texture rights, and attachment geometry. A visually convincing
static mesh is not automatically an animatable flower.

## Suggested authored progression

This is an animation inference from the biological evidence, not a measured
frame-by-frame law:

- **0–15% — enclosed bud:** steep overlapping petals, narrow gaps, intact
  silhouette.
- **15–35% — first bowl:** attachment angles begin to fan outward; free upper
  portions separate visibly while bases remain visually crowded.
- **35–65% — widening cup:** outer petals settle lower, middle petals open into
  a bowl, and depth relationships become legible.
- **65–88% — full presentation:** base flare increases, inner petals lengthen
  subtly and separate enough to frame the center, and the bloom approaches the
  broad Day-2 form.
- **88–100% — completion:** almost no additional gross opening; use tiny
  settling, light, or ambient motion so the completed flower feels alive.

These percentages belong to the story's normalized focus-session progress,
not to literal botanical hours.

## Narrative choice for the animation pass

A real lotus does not perform a single uninterrupted bud-to-full-bloom motion.
The story therefore needs one explicit interpretation:

1. **Recommended: compressed anthesis.** Combine the recognizable Day-1 bowl
   and Day-2 full opening into one quiet, irreversible focus-session arc. This
   is botanically informed but openly stylized.
2. **Literal daily cycle.** Open slightly, close, then open fully. This is more
   faithful to the flower but risks making session progress feel as if it is
   reversing.
3. **One morning only.** Begin at the Day-2 pre-dawn closed state and end at
   that morning's full bloom. This avoids reversal but does not tell the whole
   anthesis story.

No implementation technology can compensate for leaving this narrative choice
undefined.

## Confidence and remaining unknowns

High confidence:

- basal tissue is central to the opening/closing mechanism;
- a backward distal hinge is wrong;
- the body should retain a smooth cup;
- inner and outer petals should not share identical motion;
- the flower opens and closes over multiple days;
- spiral placement matters.

Not established by the available literature:

- exact rotation curves for every petal;
- exact start order among neighboring petals;
- the precise mechanics of the particular cultivar represented by the collage;
- whether the intended paper flower should reproduce Day 1, Day 2, or a
  compressed composite.

Those unknowns should be settled by studying real time-lapse frames and by
human visual judgment, not invented by a procedural rig.
