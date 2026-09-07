# Planet Calm

Planet Calm is the native iOS project for **Planet Focus**, a focus timer in
which each completed session unfolds a calm, tactile paper-cut story.

The current flow is:

1. responsive Planet Focus splash screen;
2. story selection;
3. Autumn Tree or Contemporary Lotus scene;
4. duration and production playback work to follow.

## Project

- Xcode project: `PlanetCalm.xcodeproj`
- App target: `PlanetCalm`
- Unit tests: `PlanetCalmTests`
- UI tests: `PlanetCalmUITests`
- Deployment target: iOS 17
- Supported device families: iPhone and iPad

Open `PlanetCalm.xcodeproj` in Xcode and run the `PlanetCalm` scheme. The app
uses bundled fonts and local story artwork; it has no third-party package
dependencies.

## Architecture

`StoryPlayer` owns authoritative session time and evaluates a deterministic
story plan created by a story-specific `StoryDirector`. Visual and future audio
systems consume the same `StoryMoment` values rather than commanding one
another. See `docs/architecture/generative-performance-system.md`.

The approved outer palette, responsive splash rules, typography, paper
material, and animation boundaries live in `docs/design/colors-and-ui.md`.
Story direction lives in `docs/stories/`.

## Repository policy

Only production source, bundled assets, concise specifications, and the single
approved splash reference belong in the repository. Simulator captures, build
products, prompt archives, generated galleries, and review-run evidence stay
local.
