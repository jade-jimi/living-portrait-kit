# LivingPortraitKit maintainer handoff

## Mission

Make layered still character art feel present without turning it into a looping video.
The engine owns deterministic motion and rendering contracts. Host products own character
meaning, art, timing, and the events that deserve a reaction.

## Repository

- Public origin: `https://github.com/jade-jimi/living-portrait-kit`
- Default branch: `main`
- License: MIT
- Swift platforms: iOS 17+, macOS 14+
- Cross-platform boundary: JSON scene schema and deterministic conformance fixture

## Current v0.1 surface

- `LivingPortraitCore`: scene decoding and deterministic blink, breath, gaze, parallax,
  foreground wind, and authored reaction envelopes.
- `LivingPortraitSwiftUI`: the first layered renderer with Reduce Motion support.
- `Examples/macOS/FloatingPortraitPanel.swift`: a non-activating desktop companion panel.
- The repository contains no Awaken character art and no product-specific event semantics.

Run before every release:

```sh
swift test
git diff --check
```

## Ownership boundary

The maintainer owns:

- public API and schema compatibility;
- deterministic behavior across renderers;
- memory, battery, and animation performance;
- macOS companion primitives;
- Android Compose renderer planning and conformance;
- semver tags, changelog, examples, and public issue triage.

The Awaken app PM owns:

- Mono and other grimoire art;
- which product event causes which reaction;
- scene selection, rarity, tap behavior, and narrative meaning;
- physical-device acceptance;
- submitting minimal reproductions and desired engine changes here.

Do not move Awaken-specific characters, assets, product canon, or OTA concepts into this
repository. Do not let the engine invent a rare reaction on a timer.

## Feedback protocol from Awaken

Every request should include:

1. package version and Apple device/OS;
2. smallest scene JSON or API call that reproduces it;
3. Reduce Motion behavior;
4. expected and actual visible result;
5. whether the problem is engine behavior, renderer behavior, or missing authored art.

The maintainer replies with one of: package fix, host-app fix, asset-contract change, or hold.
Avoid adding one-off flags when a host-side event or better layer registration solves it.

## Next gates

1. Awaken Mono consumes tagged `0.1.0` through Swift Package Manager.
2. A second grimoire validates that the API is not Mono-shaped.
3. Add performance instrumentation and long-running macOS companion soak tests.
4. Only then stabilize a Compose renderer against the bundled conformance fixture.

## Product distinction

WidgetKit is for snapshot/timeline states. A continuously blinking and breathing desktop Mono
belongs in a small menu-bar or floating companion app using the macOS panel adapter.
