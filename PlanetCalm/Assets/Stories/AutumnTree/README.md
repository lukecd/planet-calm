# Autumn Tree assets

The current renderer is `AutumnBranchSceneView`; its thumbnail uses the same
`AutumnBranchCanvas`. See [the implementation boundary](../../../../docs/architecture/autumn-branch-checkpoint.md).

## SceneV1

Only five reusable RGBA masks remain: `hill-far-left`, `hill-mid-right`,
`leaf-maple-yellow`, `leaf-maple-orange`, and `leaf-maple-red`.
`AutumnArtwork` owns their inventory and loading. The approved source pixels
are unchanged. Branches and ground are native shapes; the sky is Metal-backed.
Local neutral paper grain is shared through the asset catalog.

The retired painted tree, sky/ground plates, extra terrain and leaf variants,
baked focus button, old placement/checkpoint JSON, and SceneV2 adjustments are
removed. Do not restore that renderer for previews or introduce another clock.

## LeafAerodynamicsV1

The current solver uses the calibrated Gate 3 configuration. Gates 1, 2, and 4
remain small regression baselines for gravity, drag, flutter, and seeded wind.
The old SpriteKit labs and their separate group/terrain/collider data are retired.

## Origami animals

The bird and deer use original articulated geometry and the shared paper grain,
not image frames. The unused CastV1 rabbit/flock sprites, loaders, scheduler,
and flock solver are retired. Do not reintroduce them for automatic encounters.
