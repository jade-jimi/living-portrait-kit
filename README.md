# LivingPortraitKit

LivingPortraitKit is a small, dependency-free engine for making layered still portraits
feel present. It provides deterministic blinking, breathing, gaze/parallax, foreground-hair
wind transforms, and host-triggered reaction envelopes. It does not warp faces, generate frames,
play GIFs, use a network, or include private art.

The public contract is platform-neutral JSON, not Swift. `LivingPortraitCore` is the Swift
reference decoder/evaluator and `LivingPortraitSwiftUI` is the first renderer.

## Requirements

- iOS 17+
- macOS 14+
- Swift 6

## Architecture

```text
living-portrait.schema.json
          + deterministic-conformance.json
                         |
             LivingPortraitCore
                         |
             LivingPortraitSwiftUI
```

Every future renderer must decode the same schema and match the deterministic conformance
fixture within its declared tolerance. An Android Jetpack Compose renderer should implement
the same seed, integer-millisecond clock, SplitMix64 random function, smoothstep envelopes,
and scalar outputs. Android code is intentionally not duplicated in this package yet.

## Layer contract

All art uses one shared canvas and registration point:

- `background`: environment without the character baked in
- `character`: stable base pose
- `blink`: authored closed-eye overlay; opacity is the `blink` scalar
- `wind`: separated foreground hair or fabric, transformed by wind scalars
- `reaction`: a rare authored accent, faded by the `reaction` scalar

Asset strings are opaque. `Image(layer.asset)` is only one possible resolver. Apps may use
asset catalogs, downloaded files, Compose resources, Metal textures, or another store.

## SwiftUI usage

```swift
import LivingPortraitCore
import LivingPortraitSwiftUI

LivingPortraitStage(scene: scene) { layer, _ in
    Image(layer.asset)
        .resizable()
        .scaledToFit()
}
```

Decoding a `LivingPortraitScene` validates the version 1 schema values automatically. Call
`try scene.validate()` after mutating a scene in memory. Invalid periods are rejected during
decoding, and the evaluator fails closed to a still state if an invalid period is introduced
later.

For a host-triggered reaction, create one clock and share its epoch with the event and stage:

```swift
let clock = LivingPortraitClock()
let event = clock.event(
    id: "cue-17",
    type: "host.cue",
    durationMilliseconds: 1_000,
    intensity: 0.8
)

LivingPortraitStage(scene: scene, reactionEvents: [event], clock: clock) { layer, _ in
    Image(layer.asset)
}
```

Omit `clock` to retain the renderer-owned epoch used by earlier releases.

The renderer automatically respects Reduce Motion and becomes still.

## macOS companion versus widget

**Widget = static state. Companion panel = continuous presence.** WidgetKit should show a
snapshot or timeline-selected expression because it does not provide a continuously running
animation surface. A macOS 14+ menu-bar or desktop-companion app can instead host the same
`LivingPortraitStage` in a small floating `NSPanel`, where blinking, breathing, and wind keep
running while the panel is visible.

`Examples/macOS/FloatingPortraitPanel.swift` demonstrates a borderless, non-activating panel
that floats across Spaces, can be dragged by its background, and can be toggled by a menu-bar
coordinator. It has no WidgetKit dependency and does not prescribe app lifecycle, persistence,
click-through behavior, or private character assets.

## Why not GIF?

A GIF repeats the same timing, cannot respond to focus or wind, wastes frames, and does not
naturally obey Reduce Motion. Authored transparent layers plus deterministic transforms are
smaller, composable, and controllable. Reaction layers only animate for explicit host events;
the engine never invents a character reaction on a random timer.

## Test

```sh
swift test
```

## License

MIT. See `LICENSE`.
