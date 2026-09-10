# Autumn leaf aerodynamics V1

These versioned configurations support the shared leaf-motion model:

- `gate-1-gravity.json`: passive gravity regression baseline.
- `gate-2-still-air-drag.json`: quadratic drag regression baseline.
- `gate-3-passive-flutter.json`: the current Autumn solver's calibrated lift,
  drag, pressure-point torque, and resistance.
- `gate-4-external-wind.json`: seeded wind regression baseline.

The full-tree simulation and its shared transport now own release, gusts, and
ground contact. The old group, terrain, and alpha-collider lab configurations
have been removed along with their separate SpriteKit simulation screens.
