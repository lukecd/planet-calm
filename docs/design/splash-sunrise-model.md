# Splash sunrise renderer

## Visual contract

The splash tells a sunrise in the established cut-paper composition. The sun starts
with roughly 10% of its diameter above the resting rear-wave horizon, then rises to
the established daytime position. Warm light stays centered on that same sun and
expands across the paper. The current cloud study is one layered paper assembly;
its depth-separated cutouts interrupt the light and make soft rays. The waves, lotus
choreography, score, and navigation keep their existing roles.

The yellow-paper reference is the daytime art target. An entirely yellow sky is not
a physically literal clear daytime sky. The renderer therefore separates a physical
scattering calculation from an explicit paper-pigment treatment. Neither stage should
be described as a full weather simulation or a complete implementation of Hillaire.

## Research and architecture decision

Low-angle sunlight traverses a longer atmospheric path: wavelength-dependent
scattering changes direct sunlight and diffuse sky light differently. This explains
why a list of whole-screen color stops cannot reproduce the spatial relationships
in a sunrise. The National Weather Service describes this distinction in its
[sky-color explanation](https://www.weather.gov/fgz/SkyBlue). The supplied sunrise
references are used for the visual relationship of warm source, cooler surrounding
sky, cloud silhouettes, and rays; they are not treated as calibrated measurements.

Bruneton's [documented atmosphere implementation](https://ebruneton.github.io/precomputed_atmospheric_scattering/)
demonstrates explicit atmosphere density profiles, ozone absorption, transmittance,
and the need to test numerical rendering. Its spectral and multiple-scattering
implementation is more comprehensive than this renderer. Here an RGB single-scattering
solution is sufficient to supply directional radiance to a deliberately abstract
paper composition.

Hillaire's [production atmosphere research](https://sebh.github.io/publications/egsr2020.pdf)
and [published ray-marching implementation](https://github.com/sebh/UnrealEngineSkyAtmosphere/blob/master/Resources/RenderSkyRayMarching.hlsl)
motivate separating relatively stable transmittance from view-dependent integration.
This project implements its own compact transmittance lookup and single-scattering
integrator; it does not implement Hillaire's multiple-scattering LUT, aerial-perspective
volume, or full production architecture. No external rendering dependency or source
code package has been imported.

For rays, [GPU Gems 3, chapter 13](https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows/chapter-13-volumetric-light-scattering-post-process)
provides a useful distinction: screen-space samples toward the source can approximate
volumetric occlusion, but they are not a complete 3D shadow-volume solution. Its warning
about texture streaks informs this implementation: only untextured cloud masks
participate in visibility. Paper grain is excluded.

The native implementation uses [MTKView](https://developer.apple.com/documentation/metalkit/mtkview)
inside the SwiftUI scene. An opaque full-canvas Metal surface owns the sky and rays.
A separate transparent Metal surface draws the paper cloud above the SwiftUI sun and
below the waves. Both receive identical geometry and time. SwiftUI continues to render
the sun, waves, lotuses, type, and controls.
A 3D scene framework is unnecessary for this fixed-view paper scene.

## Ownership and shared time

| Component | Responsibility |
| --- | --- |
| PerformanceSession / PerformanceRunner | Authoritative persisted dates, duration, progress, and performance seed |
| SplashAtmosphereDirector | Sound-bank weights, paper palettes, and SplashSunriseState |
| SplashLayout | Responsive wave horizon and rising solar center |
| SunriseUniforms | The measured scene geometry and sampled physical/art parameters sent to Metal |
| SunriseRenderer / SunriseSky.metal | Transmittance, scattering, cloud occlusion, pigment treatment, and display output |
| SplashSceneView | Layer composition and the existing note-driven actors |

There is no private renderer clock. A runner computes p = clamp(elapsed / duration, 0, 1).
The Light slider samples the same director with a manually chosen p. Cloud poses are
also functions of p, so returning to an earlier Light value reproduces the earlier
sky. Session duration stretches this entire arc without changing its sequence.

The three existing sound pools remain Night, Twilight, and Daylight. Before p = 0.5,
weights are (1 - 2p, 2p, 0); afterward they are (0, 2 - 2p, 2p - 1).
Events select a bank once at onset and retain it through release. The renderer
consumes the same progress but never schedules audio or changes a sounding note.

## Physical calculation

Distances in the shader are kilometers. Earth radius is 6360 km and atmosphere
radius 6460 km. Rayleigh density decreases exponentially with an 8 km scale height;
aerosol density uses 1.2 km. The ozone profile is triangular around 25 km, falling
to zero 15 km above and below that center.

RGB Rayleigh scattering coefficients are (0.005802, 0.013558, 0.033100) km^-1.
Mie scattering is 0.003996 km^-1, with extinction 0.004440 km^-1.
Ozone absorption is (0.000650, 0.001881, 0.000085) km^-1.

A 256-by-64 half-float texture stores transmission to the sun. Its vertical coordinate
uses squared altitude to give more resolution near the ground; its horizontal coordinate
resolves zenith cosine from -0.25 through 1. Each texel integrates 64 quadratically
distributed segments and rejects sunlight paths intersecting the Earth.

The visible scattering integral uses 32 view segments. For each segment:

- Evaluate local molecular, aerosol, and ozone densities.
- Evaluate extinction and Beer-Lambert transmission, T = exp(-extinction * distance).
- Sample transmission toward the sun from the lookup texture.
- Accumulate Rayleigh and forward-peaked Mie contributions with their phase functions.
- Integrate a segment analytically using (1 - T) / extinction.
- Multiply subsequent contributions by accumulated view-path transmission.

The Mie asymmetry parameter is 0.8. The physical calculation is RGB and single-scattering;
it omits multiple scattering, detailed aerosol spectra, refraction, geographic weather,
and volumetric clouds. It is not intended for scientific prediction.

## Responsive paper projection

The resting coverage ribbon supplies a stable horizon at the sun's horizontal position.
Using resting geometry prevents pad attacks from making the sun bob. With diameter D:

- initial solar center y = horizon + 0.4D;
- final solar center = the established responsive layout position;
- interpolate the center linearly with normalized story progress.

The entrance displacement is added to the shared solar center, so the light also follows
the sun during intro/outro. Both are measured inside the same GeometryReader. The full
sky includes safe areas and has no separately colored status-bar or bottom strip.

The paper composition has no photographic ground. It uses radial distance from the
visible sun to sample an atmospheric dome, including below the wave field. The large
paper disc has a symbolic size; angular distance is compressed under it so the source
light remains visible beyond its edge. This radial projection is an artistic mapping,
not a perspective camera model. It is responsible for the desired light emanation around
the sun rather than a literal horizon stretching across the bottom of the screen.

## Tone mapping and paper color

SplashSunriseState maps progress to:

- solar elevation: -0.004 + 0.214p radians (about -0.23 to +12.03 degrees);
- exposure: 0.12 + 1.4p^0.75;
- paper-light spread: 0.12 + 0.70p / max(0.001, 1.001 - p), in short-side units;
- paper-light amount: smoothstep(clamp(p / 0.90));
- cloud time: 180p.

Radiance is exposed in linear light using 1 - exp(-radiance * exposure).
A continuous pigment mapping uses the spectral red/blue relationship to move from
blue through violet and coral to warm gold. This is explicit art direction. Hue is
not recovered from nearly achromatic pixels, avoiding unstable hue jumps and green
seams. Lightness and saturation are controlled separately.

The additional paper illumination has Gaussian falloff centered at the actual sun.
Its spread grows continuously, so the final yellow reaches the edges spatially.
There is no late full-screen color wipe. OKLCH interpolation follows an unwrapped
blue-violet-red-gold path; an unconditional 360-degree wrap must not be reintroduced.

The final target is #FFCE58, with a warmer orange paper sun and deep blue material
anchors. Paper material palettes remain independently addressable. The active
navigation uses a brief neutral ink handoff, avoiding its former green excursion.
Title ink changes from pale blue to deep blue at 48–49%; navigation follows at 54–55%.
These short, smooth transitions keep lettering out of low-contrast intermediate inks
for most of the story. They are independent of decorative material palette timing.
Color interpolation returns exact endpoints rather than round-tripping endpoint
values through floating-point color-space conversions.

## Clouds, rays, and grain

The approved next step is a single-cloud construction study, not the final cloud
arrangement. Three opaque paper sheets overlap at depths 0.13, 0.16, and 0.19
in short-side units (increasing depth approaches the viewer). Each cutout has an
independent center, width, height, and pigment. The broadest sheet is the lit upper
face; two progressively smaller sheets step downward with slight lateral offsets.
Rounded elliptical lobes form each
continuous cut edge. This replaces the previous single-contour strips.

The symbolic solar source uses the existing screen-space sun center and depth -0.60.
For a receiver at depth zr and a blocker at zb, the intersection is
sun.xy + (receiver.xy - sun.xy) * (zb + 0.60) / (zr + 0.60).
Only paper planes between the source and receiver can block it. The visible cutouts
and blockers use the exact same coverage function; no independent ray artwork is used.

Twenty-four samples through a shallow scattering slab (depths 0.22–0.85) average
solar visibility. This modulates aerosol scattering and the paper finish locally.
A sin^2(pi * p) envelope retains quiet endpoints. Unoccluded sky pixels retain the
approved sunrise mapping. This is a 2.5D shadow/scattering approximation, not full
volumetric cloud physics or glass refraction.

Paper faces also query solar visibility against the other layers. Restrained contact
shading supplies a separate studio-fill depth cue; it must not be presented as sunlight.
Pigments move from slate/blue undersides and pale blue faces through lavender/peach
to cream and muted blue. Each layer retains its own pigment and neutral local grain.
The cloud drifts as one assembly using the existing shared progress; it does not
regenerate random shapes or acquire a private clock.

Cloud faces receive the existing NeutralPaperGrainV1 asset in their moving local
coordinates, plus a restrained sun-facing edge. The grayscale source is explicitly
expanded to an RGB texture once because MetalKit's loader does not accept its original
image layout. The grain remains neutral. Background grain is a separate SwiftUI
soft-light layer at a fixed point scale. It never enters the visibility calculation.

## Performance, accessibility, and fallback

The expensive sky pass is capped at 720 pixels on its longest edge. The inexpensive
transparent cloud pass is capped independently at 1440 pixels (up to 2 pixels per point)
so the cut edges remain sharp. It does not build an atmosphere lookup texture.
Other paper artwork and background grain remain native-resolution SwiftUI layers.
The transmittance texture is built once per sky renderer. Identical uniforms skip rendering, and a resize reallocates the
drawable only when its pixel dimensions change.

Reduce Motion freezes decorative cloud drift and keeps existing reduced-motion actor
behavior. A one-second narrative update still advances the session's light state;
accessibility must not stop the transport.

If the renderer or required texture cannot initialize, the existing ink canvas remains
visible. Debug logging reports the failure. This is a safe visual fallback, not an
equivalent sunrise. The screenshot test explicitly rejects an ink-only daylight result.

GPU timings on a development Mac are not device performance measurements. Sustained
frame rate, memory, power, and thermal behavior still require profiling on physical
supported iPhone/iPad hardware before a release performance claim.

## Verification and reuse

The DEBUG-only --sunrise-audit launch mode holds the actor pose and exposes an invisible,
accessible next-state control. UI tests capture 0%, 5%, ..., 100% without repeatedly
launching the app. Portrait and landscape are separate sessions in the same simulator.
The audit asserts actual window dimensions; a requested device orientation is not proof
that the app resized. The landscape audit also requests landscape from its window scene.
Keep screenshot artifacts in temporary output, not production assets.

Inspect all 21 frames for continuous growth, visible early light, sun attachment,
cloud/ray coherence, paper character, readable type, seams, and abrupt changes.
A successful screenshot test is not aesthetic approval: inspect the actual images.
The final screenshot also checks for substantial yellow sky coverage to detect a
silently failed renderer.

The approved sunrise baseline (before the layered-cloud study) was inspected at every
5% on iPhone 17 portrait and
iPad A16 portrait/landscape (63 scene captures). A live one-minute runner capture also
confirmed changing light and wave poses together. These are simulator checks, not
physical-device performance certification. The release build additionally checks that
shared score sampling remains available without DEBUG-only controls.

The layered-cloud study has a separate verification checkpoint. iPhone and iPad portrait
were inspected at every 5%; both portrait UI tests and the release build passed. The stricter landscape window-size assertion currently fails on
the shared simulator despite device/scene rotation requests; do not label those captures
as verified landscape or remove the assertion to obtain a passing test.

Unit coverage checks the 10% initial exposure, rising geometry across four viewport
shapes, agreement between manual and timed samples, exact pool endpoints, deterministic
event source choices, and continuous note phases.

Reuse the transport and parameter data for later stories. Reuse the renderer only when
that story needs this atmosphere. Autumn is not integrated here. Do not copy timing
logic into a future scene or replace its director with this splash-specific art mapping.
