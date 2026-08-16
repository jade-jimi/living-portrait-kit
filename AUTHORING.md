# Living Portrait authoring and runtime boundary

LivingPortraitKit is deliberately two products connected by one signed package.

## A. Desktop Authoring / Master Builder

The desktop tool accepts one source portrait and optional reference images. Its primary flow is:

```text
provider-backed ShotPlanner (host visual intent + continuity locks -> scene brief)
  -> image/edit SceneGenerator (complete backgrounds, identity-locked character, pose/expression,
                                transparent layers, multiple candidates)
  -> independent vision/geometry AutoCritic
  -> automatic retry with structured critique
  -> playable validated candidates
  -> human choose or reject
  -> PackageAssembler signed bake
```

The human does not repair masks, depth, hair, or wind in the product path. Manual mask tools may
exist only as debug/fallback diagnostics for generator development. The reviewer plays complete
candidates and explicitly chooses or rejects one; approval is bound to its candidate ID and the
same revision that is baked.

`LivingPortraitAuthoringValidator` rejects changed identity or silhouette, clipped alpha,
missing protected regions, unsafe local movement of face/hands/teeth, non-eye blink recipes, and
out-of-policy motion. The master builder emits a versioned manifest, per-file SHA-256 digests, a
strict validation receipt, and an Ed25519 signature.

Real models live behind `LivingPortraitShotPlanner`, `LivingPortraitSceneGenerator`, and
`LivingPortraitAutoCritic` provider adapters. The package contains no provider implementation,
API key, prompt, or network client.

The visual brief contains composition, expression, pose, continuity locks, and requested motion
channels. Story beats, hidden intent, rare-event meaning, and the decision to trigger a reaction
remain host-product data and are not part of the LivingPortraitKit contract.

## Local workspace workflow

The bundled command-line tool turns prepared local assets into a signed directory package:

```sh
swift run living-portrait-master init MyPortrait

# Add source.png and the layers/masks named by MyPortrait/candidate.json.
# Replace the fail-closed zero values with independent critic measurements.
swift run living-portrait-master validate MyPortrait

swift run living-portrait-master keygen portrait-signing-v1 \
  .living-portrait-keys/private-key.json \
  .living-portrait-keys/public-key.json \
  --acknowledge-private-key

swift run living-portrait-master bake MyPortrait \
  --approved-by jade \
  --private-key .living-portrait-keys/private-key.json \
  --output MyPortrait.lpk

swift run living-portrait-master verify MyPortrait.lpk \
  --public-key .living-portrait-keys/public-key.json
```

`init` deliberately creates a workspace that fails validation until source art, all referenced
assets, candidate confidence, and independent measurements are present. `bake` records the named
human approval for the exact candidate and revision, then writes `manifest.json`, `receipt.json`,
`signature.json`, and the verified file inventory. Existing workspaces, keys, and packages are
never overwritten. Keep the private key outside source control; `keygen` writes it with mode 0600,
and this repository ignores `.living-portrait-keys/` by default.

The CLI does not call a model or choose a candidate. Provider adapters remain responsible for
planning, generation, and independent critique; a human remains responsible for selection.

### Downloadable same-canvas package

For an OTA portrait, the approved candidate scene declares `fallbackAsset` and supplies:

```text
background.png   required, environment only
character.png    required, stable transparent character
blink.png        optional, closed-eye overlay
wind.png         optional, separated hair or fabric
reaction.png     optional, host-triggered accent
fallback.png     required, fully composited still
```

Every file is a decodable PNG with identical pixel dimensions and registration. Each path is
distinct. `validate` and `bake` reject mismatched or missing assets; `bake` writes their semantic
roles and dimensions into the signed manifest. AI may create these files on Mac/Jimi through a
provider adapter, but neither its credentials nor its model enter the package. Mare, Mono, and
future characters therefore share one renderer contract while retaining host-owned art and
reaction meaning.

## B. Mobile Runtime / Inference

Mobile applications link `LivingPortraitCore`, not `LivingPortraitAuthoring`. Runtime verifies:

1. package, Core scene, and validator profile versions;
2. the trusted signing key and validation receipt signature;
3. exact declared file inventory and every file digest;
4. a decodable, valid deterministic Core scene.
5. for scenes declaring `fallbackAsset`, the complete PNG layer bundle, manifest roles, and one
   shared pixel canvas.

Any failure returns `.staticFallback`. Runtime never repairs a package, invokes Vision or an LLM,
generates an image, or uses a network. A validated package drives deterministic blink, breath,
gaze, wind, and host-triggered state transitions from the existing Core engine.

## Protection rule

Face, hands, and teeth cannot receive local wind/reaction/deformation. Whole-character rigid
parallax and bottom-anchored breathing remain allowed because they preserve registration and
silhouette. Blink is the single local exception and must target the authored eyes region.

This first vertical slice validates rectangular semantic bounds and signed file integrity. A
production desktop application should add pixel-mask occupancy, boundary-distance, recomposition,
and independent identity measurements before publishing packages; it must not weaken the runtime
receipt and signature contract while those checks evolve.
