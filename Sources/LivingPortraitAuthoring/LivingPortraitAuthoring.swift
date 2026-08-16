import CryptoKit
import Foundation
import LivingPortraitCore

/// Desktop-only authoring input. Providers may use Vision, a local model, or a cloud model;
/// generated output is always an untrusted candidate until automatic critique and human choice.
public struct LivingPortraitAuthoringSource: Sendable, Equatable {
    public var imageData: Data
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var referenceImageData: [Data]

    public init(imageData: Data, pixelWidth: Int, pixelHeight: Int, referenceImageData: [Data] = []) {
        self.imageData = imageData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.referenceImageData = referenceImageData
    }

    public func validate() throws {
        guard !imageData.isEmpty, pixelWidth > 0, pixelHeight > 0 else {
            throw LivingPortraitAuthoringError.invalidSource
        }
        guard referenceImageData.allSatisfy({ !$0.isEmpty }) else {
            throw LivingPortraitAuthoringError.invalidSource
        }
    }
}

public struct LivingPortraitGeneratedCandidate: Codable, Sendable, Equatable, Identifiable {
    public struct Rect: Codable, Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var isNormalized: Bool {
            x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1 && y + height <= 1
        }

        func intersects(_ other: Rect) -> Bool {
            x < other.x + other.width && x + width > other.x
                && y < other.y + other.height && y + height > other.y
        }
    }

    public enum RegionKind: String, Codable, Sendable, CaseIterable {
        case characterSilhouette
        case face
        case leftHand
        case rightHand
        case teeth
        case eyes
        case hair
        case clothes
        case background
    }

    public enum MotionChannel: String, Codable, Sendable, CaseIterable {
        case rigidParallax
        case breath
        case wind
        case blink
        case reaction
    }

    public struct Region: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var kind: RegionKind
        public var bounds: Rect
        public var maskPath: String
        public var confidence: Double

        public init(id: String, kind: RegionKind, bounds: Rect, maskPath: String, confidence: Double) {
            self.id = id
            self.kind = kind
            self.bounds = bounds
            self.maskPath = maskPath
            self.confidence = confidence
        }
    }

    public struct DepthHint: Codable, Sendable, Equatable {
        public var regionID: String
        public var normalizedDepth: Double

        public init(regionID: String, normalizedDepth: Double) {
            self.regionID = regionID
            self.normalizedDepth = normalizedDepth
        }
    }

    public struct MotionRecipe: Codable, Sendable, Equatable {
        public var regionID: String
        public var channel: MotionChannel
        public var maximumTranslationPixels: Double
        public var maximumRotationDegrees: Double
        public var maximumScaleDelta: Double

        public init(
            regionID: String,
            channel: MotionChannel,
            maximumTranslationPixels: Double,
            maximumRotationDegrees: Double,
            maximumScaleDelta: Double
        ) {
            self.regionID = regionID
            self.channel = channel
            self.maximumTranslationPixels = maximumTranslationPixels
            self.maximumRotationDegrees = maximumRotationDegrees
            self.maximumScaleDelta = maximumScaleDelta
        }
    }

    public var draftSchemaVersion: Int
    public var id: String
    public var briefID: String
    public var scene: LivingPortraitScene
    public var regions: [Region]
    public var depthHints: [DepthHint]
    public var motionRecipes: [MotionRecipe]
    public var assets: [String: Data]

    public init(
        draftSchemaVersion: Int = 1,
        id: String,
        briefID: String,
        scene: LivingPortraitScene,
        regions: [Region],
        depthHints: [DepthHint],
        motionRecipes: [MotionRecipe],
        assets: [String: Data]
    ) {
        self.draftSchemaVersion = draftSchemaVersion
        self.id = id
        self.briefID = briefID
        self.scene = scene
        self.regions = regions
        self.depthHints = depthHints
        self.motionRecipes = motionRecipes
        self.assets = assets
    }
}

/// Measurements produced independently from the drafting provider. A provider confidence of 1.0
/// cannot satisfy any of these gates.
public struct LivingPortraitValidationMeasurements: Codable, Sendable, Equatable {
    public var identitySimilarity: Double
    public var silhouetteIntersectionOverUnion: Double
    public var alphaTouchesCanvasEdge: Bool

    public init(
        identitySimilarity: Double,
        silhouetteIntersectionOverUnion: Double,
        alphaTouchesCanvasEdge: Bool
    ) {
        self.identitySimilarity = identitySimilarity
        self.silhouetteIntersectionOverUnion = silhouetteIntersectionOverUnion
        self.alphaTouchesCanvasEdge = alphaTouchesCanvasEdge
    }
}

/// Provider-neutral visual instructions. Narrative meaning and event semantics stay in the host.
public struct LivingPortraitSceneBrief: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var intent: String
    public var sceneDescription: String
    public var expression: String
    public var pose: String
    public var continuityLocks: [String]
    public var requiredMotionChannels: [LivingPortraitGeneratedCandidate.MotionChannel]

    public init(
        id: String,
        intent: String,
        sceneDescription: String,
        expression: String,
        pose: String,
        continuityLocks: [String],
        requiredMotionChannels: [LivingPortraitGeneratedCandidate.MotionChannel]
    ) {
        self.id = id
        self.intent = intent
        self.sceneDescription = sceneDescription
        self.expression = expression
        self.pose = pose
        self.continuityLocks = continuityLocks
        self.requiredMotionChannels = requiredMotionChannels
    }

    public func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sceneDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !pose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              continuityLocks.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(requiredMotionChannels).count == requiredMotionChannels.count else {
            throw LivingPortraitAuthoringError.invalidSceneBrief
        }
    }
}

public protocol LivingPortraitShotPlanner: Sendable {
    func plan(intent: String, continuityLocks: [String]) async throws -> LivingPortraitSceneBrief
}

public struct LivingPortraitGenerationCritique: Codable, Sendable, Equatable {
    public var issueCodes: [String]
    public var retryInstructions: [String]

    public init(issueCodes: [String], retryInstructions: [String]) {
        self.issueCodes = issueCodes
        self.retryInstructions = retryInstructions
    }
}

public protocol LivingPortraitSceneGenerator: Sendable {
    func generate(
        source: LivingPortraitAuthoringSource,
        brief: LivingPortraitSceneBrief,
        candidateCount: Int,
        previousCritique: LivingPortraitGenerationCritique?
    ) async throws -> [LivingPortraitGeneratedCandidate]
}

public struct LivingPortraitCriticReport: Sendable, Equatable {
    public var measurements: LivingPortraitValidationMeasurements
    public var critique: LivingPortraitGenerationCritique

    public init(
        measurements: LivingPortraitValidationMeasurements,
        critique: LivingPortraitGenerationCritique
    ) {
        self.measurements = measurements
        self.critique = critique
    }
}

public protocol LivingPortraitAutoCritic: Sendable {
    /// Must independently inspect rendered pixels/geometry. It must not trust generator confidence.
    func inspect(
        candidate: LivingPortraitGeneratedCandidate,
        source: LivingPortraitAuthoringSource,
        brief: LivingPortraitSceneBrief
    ) async throws -> LivingPortraitCriticReport
}

/// Provider-neutral process boundary. HTTP and CLI adapters implement this without adding a
/// vendor SDK dependency to LivingPortraitKit.
public struct LivingPortraitProviderConfiguration: Codable, Sendable, Equatable {
    public enum Adapter: String, Codable, Sendable { case http, cli, mock }
    public var id: String
    public var adapter: Adapter
    public var endpointOrExecutable: String
    public var credentialEnvironmentVariable: String?
    public var credentialKeychainReference: String?

    public init(
        id: String,
        adapter: Adapter,
        endpointOrExecutable: String,
        credentialEnvironmentVariable: String? = nil,
        credentialKeychainReference: String? = nil
    ) {
        self.id = id
        self.adapter = adapter
        self.endpointOrExecutable = endpointOrExecutable
        self.credentialEnvironmentVariable = credentialEnvironmentVariable
        self.credentialKeychainReference = credentialKeychainReference
    }

    public func validateNoEmbeddedSecret() throws {
        let endpoint = endpointOrExecutable.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercaseEndpoint = endpoint.lowercased()
        let environmentReferenceIsValid = credentialEnvironmentVariable.map {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? true
        let keychainReferenceIsValid = credentialKeychainReference.map {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? true
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !endpoint.isEmpty,
              environmentReferenceIsValid,
              keychainReferenceIsValid else {
            throw LivingPortraitAuthoringError.invalidProviderConfiguration
        }
        guard !lowercaseEndpoint.contains("api_key="),
              !lowercaseEndpoint.contains("apikey="),
              !lowercaseEndpoint.contains("access_token="),
              !lowercaseEndpoint.contains("authorization:"),
              !lowercaseEndpoint.contains("bearer ") else {
            throw LivingPortraitAuthoringError.embeddedCredentialForbidden
        }
    }
}

public struct LivingPortraitReviewedCandidate: Sendable, Equatable, Identifiable {
    public var id: String { candidate.id }
    public let candidate: LivingPortraitGeneratedCandidate
    public let measurements: LivingPortraitValidationMeasurements

    public init(candidate: LivingPortraitGeneratedCandidate, measurements: LivingPortraitValidationMeasurements) {
        self.candidate = candidate
        self.measurements = measurements
    }
}

public enum LivingPortraitCandidateRanker {
    public static func ranked(_ candidates: [LivingPortraitReviewedCandidate]) -> [LivingPortraitReviewedCandidate] {
        candidates.sorted {
            let lhs = $0.measurements.identitySimilarity * 0.6
                + $0.measurements.silhouetteIntersectionOverUnion * 0.4
            let rhs = $1.measurements.identitySimilarity * 0.6
                + $1.measurements.silhouetteIntersectionOverUnion * 0.4
            if lhs == rhs { return $0.id < $1.id }
            return lhs > rhs
        }
    }
}

/// Desktop candidate factory: plan, generate, independently critique, and retry. It never chooses
/// a winner and never signs output; those remain explicit human and assembler steps.
public struct LivingPortraitCandidateProducer<Planner: LivingPortraitShotPlanner, Generator: LivingPortraitSceneGenerator, Critic: LivingPortraitAutoCritic>: Sendable {
    public let planner: Planner
    public let generator: Generator
    public let critic: Critic
    public let validator: LivingPortraitAuthoringValidator

    public init(planner: Planner, generator: Generator, critic: Critic, validator: LivingPortraitAuthoringValidator = .init()) {
        self.planner = planner
        self.generator = generator
        self.critic = critic
        self.validator = validator
    }

    public func produce(
        source: LivingPortraitAuthoringSource,
        intent: String,
        continuityLocks: [String],
        candidateCount: Int = 3,
        maximumAttempts: Int = 3
    ) async throws -> [LivingPortraitReviewedCandidate] {
        try source.validate()
        let brief = try await planner.plan(intent: intent, continuityLocks: continuityLocks)
        try brief.validate()
        let requestedCandidateCount = max(1, candidateCount)
        var previousCritique: LivingPortraitGenerationCritique?
        for _ in 0..<max(1, maximumAttempts) {
            try Task.checkCancellation()
            let candidates = try await generator.generate(
                source: source,
                brief: brief,
                candidateCount: requestedCandidateCount,
                previousCritique: previousCritique
            )
            var accepted: [LivingPortraitReviewedCandidate] = []
            var issueCodes: [String] = []
            var retryInstructions: [String] = []
            for candidate in candidates.prefix(requestedCandidateCount) {
                try Task.checkCancellation()
                guard candidate.briefID == brief.id else {
                    issueCodes.append("briefMismatch")
                    retryInstructions.append("return candidates for brief \(brief.id)")
                    continue
                }
                let candidateChannels = Set(candidate.motionRecipes.map(\.channel))
                let missingChannels = Set(brief.requiredMotionChannels).subtracting(candidateChannels)
                guard missingChannels.isEmpty else {
                    issueCodes.append("missingMotionChannels")
                    let names = missingChannels.map(\.rawValue).sorted().joined(separator: ",")
                    retryInstructions.append("add required motion channels: \(names)")
                    continue
                }
                let report = try await critic.inspect(candidate: candidate, source: source, brief: brief)
                do {
                    _ = try validator.validate(candidate, measurements: report.measurements)
                    guard report.critique.issueCodes.isEmpty else {
                        issueCodes.append(contentsOf: report.critique.issueCodes)
                        retryInstructions.append(contentsOf: report.critique.retryInstructions)
                        continue
                    }
                    accepted.append(.init(candidate: candidate, measurements: report.measurements))
                } catch {
                    if let authoringError = error as? LivingPortraitAuthoringError {
                        issueCodes.append(authoringError.code)
                    } else {
                        issueCodes.append(String(describing: error))
                    }
                    retryInstructions.append(contentsOf: report.critique.retryInstructions)
                }
            }
            if !accepted.isEmpty { return LivingPortraitCandidateRanker.ranked(accepted) }
            previousCritique = .init(
                issueCodes: Array(Set(issueCodes)).sorted(),
                retryInstructions: Array(Set(retryInstructions)).sorted()
            )
        }
        throw LivingPortraitAuthoringError.noValidatedCandidate
    }
}

public struct LivingPortraitAuthoringValidator: Sendable {
    public struct Policy: Sendable, Equatable {
        public var minimumIdentitySimilarity = 0.98
        public var minimumSilhouetteIntersectionOverUnion = 0.97
        public var maximumLocalTranslationPixels = 12.0
        public var maximumLocalRotationDegrees = 2.0
        public var maximumLocalScaleDelta = 0.025

        public init() {}
        public static let strictV1 = Policy()
    }

    public let policy: Policy

    public init(policy: Policy = .strictV1) {
        self.policy = policy
    }

    public func validate(
        _ draft: LivingPortraitGeneratedCandidate,
        measurements: LivingPortraitValidationMeasurements
    ) throws -> [String] {
        guard draft.draftSchemaVersion == 1 else { throw LivingPortraitAuthoringError.unsupportedVersion }
        guard !draft.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.briefID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LivingPortraitAuthoringError.invalidCandidateMetadata
        }
        try draft.scene.validate()
        guard measurements.identitySimilarity.isFinite,
              (0...1).contains(measurements.identitySimilarity),
              measurements.silhouetteIntersectionOverUnion.isFinite,
              (0...1).contains(measurements.silhouetteIntersectionOverUnion) else {
            throw LivingPortraitAuthoringError.invalidMeasurements
        }
        guard measurements.identitySimilarity >= policy.minimumIdentitySimilarity else {
            throw LivingPortraitAuthoringError.identityChanged
        }
        guard measurements.silhouetteIntersectionOverUnion >= policy.minimumSilhouetteIntersectionOverUnion else {
            throw LivingPortraitAuthoringError.silhouetteChanged
        }
        guard !measurements.alphaTouchesCanvasEdge else { throw LivingPortraitAuthoringError.alphaClipped }

        let regionsByID = Dictionary(uniqueKeysWithValues: draft.regions.map { ($0.id, $0) })
        guard regionsByID.count == draft.regions.count,
              draft.regions.allSatisfy({
                  !$0.id.isEmpty && $0.bounds.isNormalized && !$0.maskPath.isEmpty
                      && $0.confidence.isFinite && (0...1).contains($0.confidence)
              }) else {
            throw LivingPortraitAuthoringError.invalidRegion
        }
        let requiredKinds: Set<LivingPortraitGeneratedCandidate.RegionKind> = [
            .characterSilhouette, .face, .leftHand, .rightHand, .teeth, .eyes,
        ]
        guard Set(draft.regions.map(\.kind)).isSuperset(of: requiredKinds) else {
            throw LivingPortraitAuthoringError.missingProtectedRegion
        }
        guard draft.depthHints.allSatisfy({
            regionsByID[$0.regionID] != nil && (0...1).contains($0.normalizedDepth)
        }) else {
            throw LivingPortraitAuthoringError.invalidDepthHint
        }
        let protected = draft.regions.filter { [.face, .leftHand, .rightHand, .teeth].contains($0.kind) }
        for recipe in draft.motionRecipes {
            guard let region = regionsByID[recipe.regionID],
                  recipe.maximumTranslationPixels >= 0,
                  recipe.maximumTranslationPixels <= policy.maximumLocalTranslationPixels,
                  recipe.maximumRotationDegrees >= 0,
                  recipe.maximumRotationDegrees <= policy.maximumLocalRotationDegrees,
                  recipe.maximumScaleDelta >= 0,
                  recipe.maximumScaleDelta <= policy.maximumLocalScaleDelta else {
                throw LivingPortraitAuthoringError.motionOutOfBounds
            }
            // Whole-character rigid motion is safe. Local deformation and wind may never touch
            // face, hands, or teeth; blink is the only eyes-specific local exception.
            let wholeCharacterMotion = region.kind == .characterSilhouette
                && (recipe.channel == .rigidParallax || recipe.channel == .breath)
            if !wholeCharacterMotion,
               recipe.channel != .blink,
               protected.contains(where: { $0.id == region.id || $0.bounds.intersects(region.bounds) }) {
                throw LivingPortraitAuthoringError.protectedRegionMoved(region.id)
            }
            if recipe.channel == .blink, region.kind != .eyes {
                throw LivingPortraitAuthoringError.invalidBlinkRegion
            }
        }
        guard draft.assets.keys.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("/") && !$0.contains("..") }),
              draft.regions.allSatisfy({ draft.assets[$0.maskPath]?.isEmpty == false }),
              draft.scene.layers.allSatisfy({ draft.assets[$0.asset]?.isEmpty == false }),
              draft.scene.fallbackAsset.map({ draft.assets[$0]?.isEmpty == false }) ?? true else {
            throw LivingPortraitAuthoringError.invalidAssetInventory
        }
        let layerBundle: LivingPortraitRuntimeLayerBundle?
        do {
            layerBundle = try LivingPortraitLayerBundleValidator.validate(scene: draft.scene, files: draft.assets)
        } catch {
            throw LivingPortraitAuthoringError.invalidLayerBundle(String(describing: error))
        }
        var passedChecks = ["identity", "silhouette", "alphaBounds", "protectedRegions", "motionBounds"]
        if layerBundle != nil { passedChecks.append("layerBundle") }
        return passedChecks
    }
}

/// An explicit human gate from the desktop preview. Provider confidence can never mint this.
public struct LivingPortraitHumanApproval: Sendable, Equatable {
    public var candidateID: String
    public var approvedBy: String
    public var approvedRevision: Int

    public init(candidateID: String, approvedBy: String, approvedRevision: Int) {
        self.candidateID = candidateID
        self.approvedBy = approvedBy
        self.approvedRevision = approvedRevision
    }
}

public struct BakedLivingPortraitPackage: Sendable {
    public let manifestData: Data
    public let receiptData: Data
    public let signatureData: Data
    public let files: [String: Data]
}

public enum LivingPortraitPackageAssembler {
    public static func bake(
        packageID: String,
        revision: Int,
        source: LivingPortraitAuthoringSource,
        draft: LivingPortraitGeneratedCandidate,
        measurements: LivingPortraitValidationMeasurements,
        approval: LivingPortraitHumanApproval,
        signingKey: Curve25519.Signing.PrivateKey,
        keyID: String,
        validator: LivingPortraitAuthoringValidator = .init()
    ) throws -> BakedLivingPortraitPackage {
        try source.validate()
        guard !packageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              revision > 0,
              !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LivingPortraitAuthoringError.invalidPackageMetadata
        }
        guard approval.candidateID == draft.id,
              !approval.approvedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              approval.approvedRevision == revision else {
            throw LivingPortraitAuthoringError.humanApprovalRequired
        }
        let passedChecks = try validator.validate(draft, measurements: measurements)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let sceneData = try encoder.encode(draft.scene)
        var files = draft.assets
        files["scene.json"] = sceneData

        let layerRoleByPath = draft.scene.layers.reduce(into: [String: String]()) { result, layer in
            result[layer.asset] = "layer.\(layer.role.rawValue)"
        }
        let runtimePaths = Set(draft.scene.layers.map(\.asset) + [draft.scene.fallbackAsset].compactMap { $0 })
        let manifestFiles = try files.keys.sorted().map { path in
            let data = files[path]!
            let rasterSize: LivingPortraitRasterSize?
            if runtimePaths.contains(path), draft.scene.fallbackAsset != nil {
                rasterSize = try LivingPortraitLayerBundleValidator.inspectPNG(data, path: path)
            } else {
                rasterSize = nil
            }
            let role: String
            if path == "scene.json" {
                role = "scene"
            } else if path == draft.scene.fallbackAsset {
                role = "fallback"
            } else {
                role = layerRoleByPath[path] ?? "auxiliary"
            }
            return LivingPortraitPackageManifest.File(
                path: path,
                role: role,
                sha256: LivingPortraitPackageLoader.sha256Hex(data),
                pixelWidth: rasterSize?.width,
                pixelHeight: rasterSize?.height
            )
        }
        let manifest = LivingPortraitPackageManifest(
            packageID: packageID,
            revision: revision,
            sourceSHA256: LivingPortraitPackageLoader.sha256Hex(source.imageData),
            files: manifestFiles
        )
        let manifestData = try encoder.encode(manifest)
        let receipt = LivingPortraitValidationReceipt(
            validatorProfile: "living-portrait-strict-v1",
            validatorVersion: 1,
            manifestSHA256: LivingPortraitPackageLoader.sha256Hex(manifestData),
            passedChecks: passedChecks.sorted()
        )
        let receiptData = try encoder.encode(receipt)
        let signature = try signingKey.signature(for: receiptData)
        let signatureData = try encoder.encode(
            LivingPortraitPackageSignature(
                keyID: keyID,
                signatureBase64: signature.base64EncodedString()
            )
        )
        return BakedLivingPortraitPackage(
            manifestData: manifestData,
            receiptData: receiptData,
            signatureData: signatureData,
            files: files
        )
    }
}

public enum LivingPortraitAuthoringError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedVersion
    case invalidSource
    case invalidSceneBrief
    case invalidCandidateMetadata
    case invalidMeasurements
    case identityChanged
    case silhouetteChanged
    case alphaClipped
    case invalidRegion
    case missingProtectedRegion
    case invalidDepthHint
    case motionOutOfBounds
    case protectedRegionMoved(String)
    case invalidBlinkRegion
    case invalidAssetInventory
    case invalidLayerBundle(String)
    case humanApprovalRequired
    case invalidPackageMetadata
    case noValidatedCandidate
    case embeddedCredentialForbidden
    case invalidProviderConfiguration

    public var code: String {
        switch self {
        case .unsupportedVersion: "unsupportedVersion"
        case .invalidSource: "invalidSource"
        case .invalidSceneBrief: "invalidSceneBrief"
        case .invalidCandidateMetadata: "invalidCandidateMetadata"
        case .invalidMeasurements: "invalidMeasurements"
        case .identityChanged: "identityChanged"
        case .silhouetteChanged: "silhouetteChanged"
        case .alphaClipped: "alphaClipped"
        case .invalidRegion: "invalidRegion"
        case .missingProtectedRegion: "missingProtectedRegion"
        case .invalidDepthHint: "invalidDepthHint"
        case .motionOutOfBounds: "motionOutOfBounds"
        case .protectedRegionMoved: "protectedRegionMoved"
        case .invalidBlinkRegion: "invalidBlinkRegion"
        case .invalidAssetInventory: "invalidAssetInventory"
        case .invalidLayerBundle: "invalidLayerBundle"
        case .humanApprovalRequired: "humanApprovalRequired"
        case .invalidPackageMetadata: "invalidPackageMetadata"
        case .noValidatedCandidate: "noValidatedCandidate"
        case .embeddedCredentialForbidden: "embeddedCredentialForbidden"
        case .invalidProviderConfiguration: "invalidProviderConfiguration"
        }
    }

    public var description: String {
        switch self {
        case .unsupportedVersion:
            "unsupported authoring schema version"
        case .invalidSource:
            "source image data and positive pixel dimensions are required"
        case .invalidSceneBrief:
            "scene brief contains blank or duplicate required fields"
        case .invalidCandidateMetadata:
            "candidate ID and brief ID are required"
        case .invalidMeasurements:
            "identity and silhouette measurements must be finite values from zero through one"
        case .identityChanged:
            "identity similarity is below the validator threshold"
        case .silhouetteChanged:
            "silhouette similarity is below the validator threshold"
        case .alphaClipped:
            "candidate alpha touches the canvas edge"
        case .invalidRegion:
            "region IDs, bounds, mask paths, or confidence values are invalid"
        case .missingProtectedRegion:
            "candidate is missing a required protected region"
        case .invalidDepthHint:
            "depth hint references an unknown region or is outside zero through one"
        case .motionOutOfBounds:
            "motion recipe references an unknown region or exceeds the strict motion policy"
        case .protectedRegionMoved(let regionID):
            "local motion intersects a protected region: \(regionID)"
        case .invalidBlinkRegion:
            "blink motion must target the eyes region"
        case .invalidAssetInventory:
            "every scene layer and region mask must reference a safe, nonempty asset"
        case .invalidLayerBundle(let reason):
            "layered runtime bundle is invalid: \(reason)"
        case .humanApprovalRequired:
            "approval must name a human and match the exact candidate and revision"
        case .invalidPackageMetadata:
            "package ID, positive revision, and signing key ID are required"
        case .noValidatedCandidate:
            "no candidate passed independent critique and strict validation"
        case .embeddedCredentialForbidden:
            "provider endpoint contains an embedded credential"
        case .invalidProviderConfiguration:
            "provider ID, endpoint, and credential references must be nonblank"
        }
    }
}

@available(*, deprecated, renamed: "LivingPortraitPackageAssembler")
public typealias LivingPortraitMasterBuilder = LivingPortraitPackageAssembler
