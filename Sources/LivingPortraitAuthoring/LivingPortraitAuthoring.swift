import CryptoKit
import Foundation
import LivingPortraitCore

/// Desktop-only authoring input. Providers may use Vision, a local model, or a cloud model;
/// provider output is always an untrusted draft until strict validation and human approval.
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
}

public struct LivingPortraitAuthoringDraft: Codable, Sendable, Equatable {
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
    public var scene: LivingPortraitScene
    public var regions: [Region]
    public var depthHints: [DepthHint]
    public var motionRecipes: [MotionRecipe]
    public var assets: [String: Data]

    public init(
        draftSchemaVersion: Int = 1,
        scene: LivingPortraitScene,
        regions: [Region],
        depthHints: [DepthHint],
        motionRecipes: [MotionRecipe],
        assets: [String: Data]
    ) {
        self.draftSchemaVersion = draftSchemaVersion
        self.scene = scene
        self.regions = regions
        self.depthHints = depthHints
        self.motionRecipes = motionRecipes
        self.assets = assets
    }
}

/// Measurements produced independently from the drafting provider. A provider confidence of 1.0
/// cannot satisfy any of these gates.
public struct LivingPortraitValidationMeasurements: Sendable, Equatable {
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

public protocol LivingPortraitAuthoringProvider: Sendable {
    var providerID: String { get }
    var providerVersion: String { get }
    func draft(from source: LivingPortraitAuthoringSource) async throws -> LivingPortraitAuthoringDraft
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
        _ draft: LivingPortraitAuthoringDraft,
        measurements: LivingPortraitValidationMeasurements
    ) throws -> [String] {
        guard draft.draftSchemaVersion == 1 else { throw LivingPortraitAuthoringError.unsupportedVersion }
        try draft.scene.validate()
        guard measurements.identitySimilarity >= policy.minimumIdentitySimilarity else {
            throw LivingPortraitAuthoringError.identityChanged
        }
        guard measurements.silhouetteIntersectionOverUnion >= policy.minimumSilhouetteIntersectionOverUnion else {
            throw LivingPortraitAuthoringError.silhouetteChanged
        }
        guard !measurements.alphaTouchesCanvasEdge else { throw LivingPortraitAuthoringError.alphaClipped }

        let regionsByID = Dictionary(uniqueKeysWithValues: draft.regions.map { ($0.id, $0) })
        guard regionsByID.count == draft.regions.count,
              draft.regions.allSatisfy({ !$0.id.isEmpty && $0.bounds.isNormalized && !$0.maskPath.isEmpty }) else {
            throw LivingPortraitAuthoringError.invalidRegion
        }
        let requiredKinds: Set<LivingPortraitAuthoringDraft.RegionKind> = [
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
              draft.scene.layers.allSatisfy({ draft.assets[$0.asset]?.isEmpty == false }) else {
            throw LivingPortraitAuthoringError.invalidAssetInventory
        }
        return ["identity", "silhouette", "alphaBounds", "protectedRegions", "motionBounds"]
    }
}

/// An explicit human gate from the desktop preview. Provider confidence can never mint this.
public struct LivingPortraitHumanApproval: Sendable, Equatable {
    public var approvedBy: String
    public var approvedRevision: Int

    public init(approvedBy: String, approvedRevision: Int) {
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

public enum LivingPortraitMasterBuilder {
    public static func bake(
        packageID: String,
        revision: Int,
        source: LivingPortraitAuthoringSource,
        draft: LivingPortraitAuthoringDraft,
        measurements: LivingPortraitValidationMeasurements,
        approval: LivingPortraitHumanApproval,
        signingKey: Curve25519.Signing.PrivateKey,
        keyID: String,
        validator: LivingPortraitAuthoringValidator = .init()
    ) throws -> BakedLivingPortraitPackage {
        guard !approval.approvedBy.isEmpty, approval.approvedRevision == revision else {
            throw LivingPortraitAuthoringError.humanApprovalRequired
        }
        let passedChecks = try validator.validate(draft, measurements: measurements)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let sceneData = try encoder.encode(draft.scene)
        var files = draft.assets
        files["scene.json"] = sceneData

        let manifestFiles = files.keys.sorted().map { path in
            let data = files[path]!
            return LivingPortraitPackageManifest.File(
                path: path,
                role: path == "scene.json" ? "scene" : "asset",
                sha256: LivingPortraitPackageLoader.sha256Hex(data)
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

public enum LivingPortraitAuthoringError: Error, Sendable, Equatable {
    case unsupportedVersion
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
    case humanApprovalRequired
}
