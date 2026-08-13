import CryptoKit
import Foundation
import LivingPortraitCore
import Testing
@testable import LivingPortraitAuthoring

@Test func approvedDraftBakesAndRuntimeLoadsWithoutAuthoringDependency() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let source = sourceFixture()
    let baked = try LivingPortraitMasterBuilder.bake(
        packageID: "portrait.mono",
        revision: 1,
        source: source,
        draft: validDraft(),
        measurements: validMeasurements(),
        approval: .init(approvedBy: "human-editor", approvedRevision: 1),
        signingKey: privateKey,
        keyID: "test-key"
    )

    let loaded = try LivingPortraitPackageLoader.load(
        manifestData: baked.manifestData,
        receiptData: baked.receiptData,
        signatureData: baked.signatureData,
        files: baked.files,
        trustedPublicKeys: ["test-key": privateKey.publicKey.rawRepresentation]
    )
    #expect(loaded.manifest.packageID == "portrait.mono")
    #expect(loaded.scene.id == "mono.single-source")
}

@Test func bakeRequiresExplicitHumanApproval() {
    #expect(throws: LivingPortraitAuthoringError.humanApprovalRequired) {
        try LivingPortraitMasterBuilder.bake(
            packageID: "portrait.mono",
            revision: 2,
            source: sourceFixture(),
            draft: validDraft(),
            measurements: validMeasurements(),
            approval: .init(approvedBy: "", approvedRevision: 1),
            signingKey: Curve25519.Signing.PrivateKey(),
            keyID: "test-key"
        )
    }
}

@Test func validatorRejectsWindTouchingFaceEvenWithPerfectProviderConfidence() {
    var draft = validDraft()
    draft.regions.append(.init(
        id: "hair-on-face",
        kind: .hair,
        bounds: .init(x: 0.43, y: 0.16, width: 0.2, height: 0.2),
        maskPath: "masks/hair.png",
        confidence: 1
    ))
    draft.assets["masks/hair.png"] = Data([1])
    draft.motionRecipes.append(.init(
        regionID: "hair-on-face",
        channel: .wind,
        maximumTranslationPixels: 4,
        maximumRotationDegrees: 0.5,
        maximumScaleDelta: 0
    ))
    #expect(throws: LivingPortraitAuthoringError.protectedRegionMoved("hair-on-face")) {
        try LivingPortraitAuthoringValidator().validate(draft, measurements: validMeasurements())
    }
}

@Test func validatorRejectsIdentitySilhouetteAlphaAndBadBlink() {
    #expect(throws: LivingPortraitAuthoringError.identityChanged) {
        try LivingPortraitAuthoringValidator().validate(
            validDraft(),
            measurements: .init(identitySimilarity: 0.5, silhouetteIntersectionOverUnion: 0.99, alphaTouchesCanvasEdge: false)
        )
    }

    #expect(throws: LivingPortraitAuthoringError.silhouetteChanged) {
        try LivingPortraitAuthoringValidator().validate(
            validDraft(),
            measurements: .init(identitySimilarity: 0.995, silhouetteIntersectionOverUnion: 0.5, alphaTouchesCanvasEdge: false)
        )
    }

    #expect(throws: LivingPortraitAuthoringError.alphaClipped) {
        try LivingPortraitAuthoringValidator().validate(
            validDraft(),
            measurements: .init(identitySimilarity: 0.995, silhouetteIntersectionOverUnion: 0.99, alphaTouchesCanvasEdge: true)
        )
    }

    var blink = validDraft()
    blink.motionRecipes.append(.init(
        regionID: "face",
        channel: .blink,
        maximumTranslationPixels: 0,
        maximumRotationDegrees: 0,
        maximumScaleDelta: 0
    ))
    #expect(throws: LivingPortraitAuthoringError.invalidBlinkRegion) {
        try LivingPortraitAuthoringValidator().validate(blink, measurements: validMeasurements())
    }
}

@Test func runtimeRejectsPostValidationMutationAndFallsBackStatic() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let baked = try LivingPortraitMasterBuilder.bake(
        packageID: "portrait.mono",
        revision: 1,
        source: sourceFixture(),
        draft: validDraft(),
        measurements: validMeasurements(),
        approval: .init(approvedBy: "human-editor", approvedRevision: 1),
        signingKey: privateKey,
        keyID: "test-key"
    )
    var changedFiles = baked.files
    changedFiles["masks/face.png"]?.append(0xff)

    let result = LivingPortraitPackageLoader.loadOrFallback(
        manifestData: baked.manifestData,
        receiptData: baked.receiptData,
        signatureData: baked.signatureData,
        files: changedFiles,
        trustedPublicKeys: ["test-key": privateKey.publicKey.rawRepresentation]
    )
    guard case .staticFallback = result else {
        Issue.record("Mutated package must fail closed to host static art")
        return
    }
}

@Test func runtimeRejectsWrongSigningKeyAndPathTraversal() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let baked = try LivingPortraitMasterBuilder.bake(
        packageID: "portrait.mono",
        revision: 1,
        source: sourceFixture(),
        draft: validDraft(),
        measurements: validMeasurements(),
        approval: .init(approvedBy: "human-editor", approvedRevision: 1),
        signingKey: privateKey,
        keyID: "test-key"
    )
    #expect(throws: LivingPortraitPackageError.invalidSignature) {
        try LivingPortraitPackageLoader.load(
            manifestData: baked.manifestData,
            receiptData: baked.receiptData,
            signatureData: baked.signatureData,
            files: baked.files,
            trustedPublicKeys: ["test-key": Curve25519.Signing.PrivateKey().publicKey.rawRepresentation]
        )
    }

    var manifest = try JSONDecoder().decode(LivingPortraitPackageManifest.self, from: baked.manifestData)
    manifest.files[0].path = "../escape"
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let manifestData = try encoder.encode(manifest)
    var receipt = try JSONDecoder().decode(LivingPortraitValidationReceipt.self, from: baked.receiptData)
    receipt.manifestSHA256 = LivingPortraitPackageLoader.sha256Hex(manifestData)
    let receiptData = try encoder.encode(receipt)
    let signatureData = try encoder.encode(LivingPortraitPackageSignature(
        keyID: "test-key",
        signatureBase64: try privateKey.signature(for: receiptData).base64EncodedString()
    ))
    #expect(throws: LivingPortraitPackageError.invalidFileInventory) {
        try LivingPortraitPackageLoader.load(
            manifestData: manifestData,
            receiptData: receiptData,
            signatureData: signatureData,
            files: baked.files,
            trustedPublicKeys: ["test-key": privateKey.publicKey.rawRepresentation]
        )
    }
}

private func sourceFixture() -> LivingPortraitAuthoringSource {
    LivingPortraitAuthoringSource(
        imageData: Data("source-image".utf8),
        pixelWidth: 900,
        pixelHeight: 1600
    )
}

private func validDraft() -> LivingPortraitAuthoringDraft {
    let regions: [LivingPortraitAuthoringDraft.Region] = [
        .init(id: "silhouette", kind: .characterSilhouette, bounds: .init(x: 0.2, y: 0.05, width: 0.6, height: 0.9), maskPath: "masks/silhouette.png", confidence: 0.99),
        .init(id: "face", kind: .face, bounds: .init(x: 0.4, y: 0.14, width: 0.22, height: 0.18), maskPath: "masks/face.png", confidence: 0.99),
        .init(id: "left-hand", kind: .leftHand, bounds: .init(x: 0.18, y: 0.62, width: 0.1, height: 0.12), maskPath: "masks/left-hand.png", confidence: 0.99),
        .init(id: "right-hand", kind: .rightHand, bounds: .init(x: 0.7, y: 0.34, width: 0.1, height: 0.12), maskPath: "masks/right-hand.png", confidence: 0.99),
        .init(id: "teeth", kind: .teeth, bounds: .init(x: 0.48, y: 0.25, width: 0.06, height: 0.02), maskPath: "masks/teeth.png", confidence: 0.99),
        .init(id: "eyes", kind: .eyes, bounds: .init(x: 0.44, y: 0.2, width: 0.14, height: 0.035), maskPath: "masks/eyes.png", confidence: 0.99),
    ]
    var assets = Dictionary(uniqueKeysWithValues: regions.map { ($0.maskPath, Data([1, 2, 3])) })
    assets["background.png"] = Data([4, 5, 6])
    assets["character.png"] = Data([7, 8, 9])
    return LivingPortraitAuthoringDraft(
        scene: LivingPortraitScene(
            id: "mono.single-source",
            seed: "42",
            layers: [
                .init(id: "background", role: .background, asset: "background.png", zIndex: 0),
                .init(id: "character", role: .character, asset: "character.png", zIndex: 10),
            ]
        ),
        regions: regions,
        depthHints: [.init(regionID: "face", normalizedDepth: 0.8)],
        motionRecipes: [
            .init(regionID: "silhouette", channel: .rigidParallax, maximumTranslationPixels: 5, maximumRotationDegrees: 0, maximumScaleDelta: 0.01),
            .init(regionID: "eyes", channel: .blink, maximumTranslationPixels: 0, maximumRotationDegrees: 0, maximumScaleDelta: 0),
        ],
        assets: assets
    )
}

private func validMeasurements() -> LivingPortraitValidationMeasurements {
    .init(
        identitySimilarity: 0.995,
        silhouetteIntersectionOverUnion: 0.99,
        alphaTouchesCanvasEdge: false
    )
}
