# Autumn leaf aerodynamics V1

These JSON files define the deterministic leaf-motion model used by the native
Autumn simulation:

- `gate-1-gravity.json` establishes the passive gravity baseline.
- `gate-2-still-air-drag.json` adds quadratic drag.
- `gate-3-passive-flutter.json` adds bounded, angle-dependent lift and a
  physically resisting force couple.
- `gate-4-external-wind.json` adds the shared seeded wind field.
- `early-group.json` defines the six-leaf population and release bounds.
- `gate-5-terrain.json` defines terrain contact and settling.
- `gate-5-leaf-colliders-v2.json` stores alpha-derived convex collision hulls
  and the measured scene-space contact inset.

Randomness is materialized from the persisted session seed. The runtime does
not add per-frame random forces. Reduce Motion uses deterministic static states.
The source leaf bitmaps and these versioned configurations should be changed
together and covered by the existing physics and asset-hash tests.
