# Living Portrait authoring and runtime boundary

LivingPortraitKit is deliberately two products connected by one signed package.

## A. Desktop Authoring / Master Builder

The desktop tool accepts one source portrait and optional reference images. A provider can use
Vision, a local model, or a cloud LLM to suggest semantic regions, masks, depth hints, anchors,
occlusion order, and a bounded motion recipe. Provider confidence is advisory only.

The author must preview, correct, and explicitly approve the same revision that is baked.
`LivingPortraitAuthoringValidator` then rejects changed identity or silhouette, clipped alpha,
missing protected regions, unsafe local movement of face/hands/teeth, non-eye blink recipes, and
out-of-policy motion. The master builder emits a versioned manifest, per-file SHA-256 digests, a
strict validation receipt, and an Ed25519 signature.

An authoring provider conforms to `LivingPortraitAuthoringProvider`. The package contains no
provider implementation, API key, prompt, or network client.

## B. Mobile Runtime / Inference

Mobile applications link `LivingPortraitCore`, not `LivingPortraitAuthoring`. Runtime verifies:

1. package, Core scene, and validator profile versions;
2. the trusted signing key and validation receipt signature;
3. exact declared file inventory and every file digest;
4. a decodable, valid deterministic Core scene.

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
