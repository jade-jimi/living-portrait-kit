import CryptoKit
import CoreGraphics
import Foundation
import ImageIO
import LivingPortraitCore
import Testing
@testable import LivingPortraitAuthoring

@Test func approvedDraftBakesAndRuntimeLoadsWithoutAuthoringDependency() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let source = sourceFixture()
    let baked = try LivingPortraitPackageAssembler.bake(
        packageID: "portrait.mono",
        revision: 1,
        source: source,
        draft: validDraft(),
        measurements: validMeasurements(),
        approval: .init(candidateID: "candidate-1", approvedBy: "human-editor", approvedRevision: 1),
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

@Test func sameCanvasLayeredDraftBakesRuntimeMetadataAndSignedFallback() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    var draft = validDraft()
    let image = try png(width: 3, height: 5)
    draft.scene.layers = [
        .init(id: "background", role: .background, asset: "background.png", zIndex: 0),
        .init(id: "character", role: .character, asset: "character.png", zIndex: 10),
        .init(id: "blink", role: .blink, asset: "blink.png", zIndex: 20),
        .init(id: "wind", role: .wind, asset: "wind.png", zIndex: 30),
        .init(id: "reaction", role: .reaction, asset: "reaction.png", zIndex: 40),
    ]
    draft.scene.fallbackAsset = "fallback.png"
    for path in draft.scene.layers.map(\.asset) + ["fallback.png"] {
        draft.assets[path] = image
    }

    let baked = try LivingPortraitPackageAssembler.bake(
        packageID: "portrait.mare",
        revision: 2,
        source: sourceFixture(),
        draft: draft,
        measurements: validMeasurements(),
        approval: .init(candidateID: draft.id, approvedBy: "human-editor", approvedRevision: 2),
        signingKey: privateKey,
        keyID: "test-key"
    )
    let manifest = try JSONDecoder().decode(LivingPortraitPackageManifest.self, from: baked.manifestData)
    let fallback = try #require(manifest.files.first(where: { $0.path == "fallback.png" }))
    #expect(fallback.role == "fallback")
    #expect(fallback.pixelWidth == 3)
    #expect(fallback.pixelHeight == 5)
    #expect(manifest.files.first(where: { $0.path == "blink.png" })?.role == "layer.blink")

    let loaded = try LivingPortraitPackageLoader.load(
        manifestData: baked.manifestData,
        receiptData: baked.receiptData,
        signatureData: baked.signatureData,
        files: baked.files,
        trustedPublicKeys: ["test-key": privateKey.publicKey.rawRepresentation]
    )
    let bundle = try #require(loaded.layerBundle)
    #expect(bundle.canvas == .init(width: 3, height: 5))
    #expect(bundle.reaction?.data == image)
}

@Test func bakeRequiresExplicitHumanApproval() {
    #expect(throws: LivingPortraitAuthoringError.humanApprovalRequired) {
        try LivingPortraitPackageAssembler.bake(
            packageID: "portrait.mono",
            revision: 2,
            source: sourceFixture(),
            draft: validDraft(),
            measurements: validMeasurements(),
            approval: .init(candidateID: "candidate-1", approvedBy: "", approvedRevision: 1),
            signingKey: Curve25519.Signing.PrivateKey(),
            keyID: "test-key"
        )
    }

    #expect(throws: LivingPortraitAuthoringError.humanApprovalRequired) {
        try LivingPortraitPackageAssembler.bake(
            packageID: "portrait.mono",
            revision: 1,
            source: sourceFixture(),
            draft: validDraft(),
            measurements: validMeasurements(),
            approval: .init(candidateID: "different-candidate", approvedBy: "human-editor", approvedRevision: 1),
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

@Test func validatorRejectsInvalidCandidateMetadataAndMeasurements() {
    var missingIdentity = validDraft()
    missingIdentity.id = " "
    #expect(throws: LivingPortraitAuthoringError.invalidCandidateMetadata) {
        try LivingPortraitAuthoringValidator().validate(missingIdentity, measurements: validMeasurements())
    }

    #expect(throws: LivingPortraitAuthoringError.invalidMeasurements) {
        try LivingPortraitAuthoringValidator().validate(
            validDraft(),
            measurements: .init(
                identitySimilarity: .nan,
                silhouetteIntersectionOverUnion: 0.99,
                alphaTouchesCanvasEdge: false
            )
        )
    }

    var invalidConfidence = validDraft()
    invalidConfidence.regions[0].confidence = 1.1
    #expect(throws: LivingPortraitAuthoringError.invalidRegion) {
        try LivingPortraitAuthoringValidator().validate(invalidConfidence, measurements: validMeasurements())
    }
}

@Test func sourceBriefAndProviderConfigurationFailClosed() async throws {
    #expect(throws: LivingPortraitAuthoringError.invalidSource) {
        try LivingPortraitAuthoringSource(imageData: Data(), pixelWidth: 0, pixelHeight: 0).validate()
    }

    var brief = try await FixturePlanner().plan(intent: "quiet listening", continuityLocks: ["same face"])
    brief.id = " "
    #expect(throws: LivingPortraitAuthoringError.invalidSceneBrief) {
        try brief.validate()
    }

    let safe = LivingPortraitProviderConfiguration(
        id: "generator",
        adapter: .http,
        endpointOrExecutable: "https://example.invalid/generate",
        credentialEnvironmentVariable: "PORTRAIT_PROVIDER_TOKEN"
    )
    try safe.validateNoEmbeddedSecret()

    let embedded = LivingPortraitProviderConfiguration(
        id: "generator",
        adapter: .http,
        endpointOrExecutable: "https://example.invalid/generate?access_token=secret"
    )
    #expect(throws: LivingPortraitAuthoringError.embeddedCredentialForbidden) {
        try embedded.validateNoEmbeddedSecret()
    }

    let blankReference = LivingPortraitProviderConfiguration(
        id: "generator",
        adapter: .http,
        endpointOrExecutable: "https://example.invalid/generate",
        credentialEnvironmentVariable: "  "
    )
    #expect(throws: LivingPortraitAuthoringError.invalidProviderConfiguration) {
        try blankReference.validateNoEmbeddedSecret()
    }
}

@Test func candidateRankerIsDeterministic() {
    var second = validDraft()
    second.id = "candidate-2"
    let ranked = LivingPortraitCandidateRanker.ranked([
        .init(
            candidate: second,
            measurements: .init(identitySimilarity: 0.99, silhouetteIntersectionOverUnion: 0.98, alphaTouchesCanvasEdge: false)
        ),
        .init(candidate: validDraft(), measurements: validMeasurements()),
    ])
    #expect(ranked.map(\.id) == ["candidate-1", "candidate-2"])
}

@Test func runtimeRejectsPostValidationMutationAndFallsBackStatic() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let baked = try LivingPortraitPackageAssembler.bake(
        packageID: "portrait.mono",
        revision: 1,
        source: sourceFixture(),
        draft: validDraft(),
        measurements: validMeasurements(),
        approval: .init(candidateID: "candidate-1", approvedBy: "human-editor", approvedRevision: 1),
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
    let baked = try LivingPortraitPackageAssembler.bake(
        packageID: "portrait.mono",
        revision: 1,
        source: sourceFixture(),
        draft: validDraft(),
        measurements: validMeasurements(),
        approval: .init(candidateID: "candidate-1", approvedBy: "human-editor", approvedRevision: 1),
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

@Test func candidateProducerRetriesCritiqueThenReturnsOnlyValidatedCandidates() async throws {
    let generator = RetryGenerator()
    let producer = LivingPortraitCandidateProducer(
        planner: FixturePlanner(),
        generator: generator,
        critic: FixtureCritic()
    )
    let result = try await producer.produce(
        source: sourceFixture(),
        intent: "quiet listening",
        continuityLocks: ["same face", "same headphones"],
        candidateCount: 2,
        maximumAttempts: 2
    )

    #expect(result.count == 1)
    #expect(result[0].candidate.id == "candidate-1")
    #expect(await generator.callCount == 2)
    #expect(await generator.lastCritique?.issueCodes.contains("identityChanged") == true)
}

@Test func candidateProducerRejectsMissingRequiredMotionChannels() async {
    let producer = LivingPortraitCandidateProducer(
        planner: FixturePlanner(),
        generator: MissingMotionGenerator(),
        critic: FixtureCritic()
    )
    await #expect(throws: LivingPortraitAuthoringError.noValidatedCandidate) {
        try await producer.produce(
            source: sourceFixture(),
            intent: "quiet listening",
            continuityLocks: ["same face"],
            maximumAttempts: 1
        )
    }
}

@Test func scaffoldBakeAndVerifyRoundTrip() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("living-portrait-workspace-\(UUID().uuidString)", isDirectory: true)
    let packageDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("living-portrait-package-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? fileManager.removeItem(at: root)
        try? fileManager.removeItem(at: packageDirectory)
    }

    try LivingPortraitAuthoringWorkspace.scaffold(at: root)
    #expect(throws: LivingPortraitWorkspaceError.missingFile("source.png")) {
        try LivingPortraitAuthoringWorkspace.validate(at: root)
    }

    try Data("source".utf8).write(to: root.appendingPathComponent("source.png"), options: .atomic)
    let candidateURL = root.appendingPathComponent("candidate.json")
    var candidate = try JSONDecoder().decode(
        LivingPortraitCandidateDocument.self,
        from: Data(contentsOf: candidateURL)
    )
    for index in candidate.regions.indices { candidate.regions[index].confidence = 0.99 }
    try encodeJSON(candidate).write(to: candidateURL, options: .atomic)
    try encodeJSON(validMeasurements()).write(
        to: root.appendingPathComponent("measurements.json"),
        options: .atomic
    )

    let assetPaths = Set(candidate.regions.map(\.maskPath) + candidate.scene.layers.map(\.asset))
    for path in assetPaths {
        let url = root.appendingPathComponent("assets").appendingPathComponent(path)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(path.utf8).write(to: url, options: .atomic)
    }

    let checks = try LivingPortraitAuthoringWorkspace.validate(at: root)
    #expect(Set(checks) == LivingPortraitPackageLoader.requiredChecks)
    let keys = try LivingPortraitAuthoringWorkspace.generateSigningKeyDocuments(keyID: "portrait-signing-v1")
    let sameKeyURL = root.appendingPathComponent("same-key.json")
    #expect(throws: LivingPortraitWorkspaceError.keyDestinationsMustDiffer) {
        try LivingPortraitAuthoringWorkspace.writeKeyDocuments(
            privateKey: keys.privateKey,
            publicKey: keys.publicKey,
            privateKeyURL: sameKeyURL,
            publicKeyURL: sameKeyURL
        )
    }
    let baked = try LivingPortraitAuthoringWorkspace.bake(
        workspaceAt: root,
        approvedBy: "human-editor",
        privateKeyDocument: keys.privateKey
    )
    try LivingPortraitAuthoringWorkspace.writePackage(baked, to: packageDirectory)
    let verified = try LivingPortraitAuthoringWorkspace.verifyPackage(
        at: packageDirectory,
        publicKeyDocument: keys.publicKey
    )
    #expect(verified.manifest.packageID == "portrait.example")
    #expect(verified.scene.id == "portrait.example")
}

private struct FixturePlanner: LivingPortraitShotPlanner {
    func plan(intent: String, continuityLocks: [String]) async throws -> LivingPortraitSceneBrief {
        .init(
            id: "brief-1",
            intent: intent,
            sceneDescription: "night booth",
            expression: "quiet satisfaction",
            pose: "headphones on",
            continuityLocks: continuityLocks,
            requiredMotionChannels: [.blink, .breath, .wind]
        )
    }
}

private actor RetryGenerator: LivingPortraitSceneGenerator {
    private(set) var callCount = 0
    private(set) var lastCritique: LivingPortraitGenerationCritique?

    func generate(
        source: LivingPortraitAuthoringSource,
        brief: LivingPortraitSceneBrief,
        candidateCount: Int,
        previousCritique: LivingPortraitGenerationCritique?
    ) async throws -> [LivingPortraitGeneratedCandidate] {
        callCount += 1
        lastCritique = previousCritique
        var candidate = validDraft()
        if callCount == 1 { candidate.id = "bad-candidate" }
        return [candidate]
    }
}

private struct MissingMotionGenerator: LivingPortraitSceneGenerator {
    func generate(
        source: LivingPortraitAuthoringSource,
        brief: LivingPortraitSceneBrief,
        candidateCount: Int,
        previousCritique: LivingPortraitGenerationCritique?
    ) async throws -> [LivingPortraitGeneratedCandidate] {
        var candidate = validDraft()
        candidate.motionRecipes.removeAll { $0.channel == .wind }
        return [candidate]
    }
}

private struct FixtureCritic: LivingPortraitAutoCritic {
    func inspect(
        candidate: LivingPortraitGeneratedCandidate,
        source: LivingPortraitAuthoringSource,
        brief: LivingPortraitSceneBrief
    ) async throws -> LivingPortraitCriticReport {
        if candidate.id == "bad-candidate" {
            return .init(
                measurements: .init(identitySimilarity: 0.5, silhouetteIntersectionOverUnion: 0.99, alphaTouchesCanvasEdge: false),
                critique: .init(issueCodes: ["identityChanged"], retryInstructions: ["lock face to source"])
            )
        }
        return .init(measurements: validMeasurements(), critique: .init(issueCodes: [], retryInstructions: []))
    }
}

private func sourceFixture() -> LivingPortraitAuthoringSource {
    LivingPortraitAuthoringSource(
        imageData: Data("source-image".utf8),
        pixelWidth: 900,
        pixelHeight: 1600
    )
}

private func validDraft() -> LivingPortraitGeneratedCandidate {
    let regions: [LivingPortraitGeneratedCandidate.Region] = [
        .init(id: "silhouette", kind: .characterSilhouette, bounds: .init(x: 0.2, y: 0.05, width: 0.6, height: 0.9), maskPath: "masks/silhouette.png", confidence: 0.99),
        .init(id: "face", kind: .face, bounds: .init(x: 0.4, y: 0.14, width: 0.22, height: 0.18), maskPath: "masks/face.png", confidence: 0.99),
        .init(id: "left-hand", kind: .leftHand, bounds: .init(x: 0.18, y: 0.62, width: 0.1, height: 0.12), maskPath: "masks/left-hand.png", confidence: 0.99),
        .init(id: "right-hand", kind: .rightHand, bounds: .init(x: 0.7, y: 0.34, width: 0.1, height: 0.12), maskPath: "masks/right-hand.png", confidence: 0.99),
        .init(id: "teeth", kind: .teeth, bounds: .init(x: 0.48, y: 0.25, width: 0.06, height: 0.02), maskPath: "masks/teeth.png", confidence: 0.99),
        .init(id: "eyes", kind: .eyes, bounds: .init(x: 0.44, y: 0.2, width: 0.14, height: 0.035), maskPath: "masks/eyes.png", confidence: 0.99),
        .init(id: "hair", kind: .hair, bounds: .init(x: 0.63, y: 0.04, width: 0.14, height: 0.08), maskPath: "masks/hair.png", confidence: 0.99),
    ]
    var assets = Dictionary(uniqueKeysWithValues: regions.map { ($0.maskPath, Data([1, 2, 3])) })
    assets["background.png"] = Data([4, 5, 6])
    assets["character.png"] = Data([7, 8, 9])
    return LivingPortraitGeneratedCandidate(
        id: "candidate-1",
        briefID: "brief-1",
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
            .init(regionID: "silhouette", channel: .breath, maximumTranslationPixels: 0, maximumRotationDegrees: 0, maximumScaleDelta: 0.01),
            .init(regionID: "eyes", channel: .blink, maximumTranslationPixels: 0, maximumRotationDegrees: 0, maximumScaleDelta: 0),
            .init(regionID: "hair", channel: .wind, maximumTranslationPixels: 4, maximumRotationDegrees: 0.5, maximumScaleDelta: 0),
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

private func encodeJSON<Value: Encodable>(_ value: Value) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}

private func png(width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}
