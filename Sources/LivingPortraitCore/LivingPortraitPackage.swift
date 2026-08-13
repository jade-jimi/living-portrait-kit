import CryptoKit
import Foundation

/// A baked, immutable artifact consumed by mobile renderers. Authoring metadata can be richer,
/// but runtime only needs verified files plus the version 1 deterministic scene.
public struct LivingPortraitPackageManifest: Codable, Sendable, Equatable {
    public struct File: Codable, Sendable, Equatable {
        public var path: String
        public var role: String
        public var sha256: String
        public var pixelWidth: Int?
        public var pixelHeight: Int?

        public init(path: String, role: String, sha256: String, pixelWidth: Int? = nil, pixelHeight: Int? = nil) {
            self.path = path
            self.role = role
            self.sha256 = sha256
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }
    }

    public var packageSchemaVersion: Int
    public var packageID: String
    public var revision: Int
    public var coreSceneSchemaVersion: Int
    public var scenePath: String
    public var sourceSHA256: String
    public var files: [File]

    public init(
        packageSchemaVersion: Int = 1,
        packageID: String,
        revision: Int,
        coreSceneSchemaVersion: Int = 1,
        scenePath: String = "scene.json",
        sourceSHA256: String,
        files: [File]
    ) {
        self.packageSchemaVersion = packageSchemaVersion
        self.packageID = packageID
        self.revision = revision
        self.coreSceneSchemaVersion = coreSceneSchemaVersion
        self.scenePath = scenePath
        self.sourceSHA256 = sourceSHA256
        self.files = files
    }
}

public struct LivingPortraitValidationReceipt: Codable, Sendable, Equatable {
    public var validatorProfile: String
    public var validatorVersion: Int
    public var manifestSHA256: String
    public var passedChecks: [String]

    public init(
        validatorProfile: String,
        validatorVersion: Int,
        manifestSHA256: String,
        passedChecks: [String]
    ) {
        self.validatorProfile = validatorProfile
        self.validatorVersion = validatorVersion
        self.manifestSHA256 = manifestSHA256
        self.passedChecks = passedChecks
    }
}

public struct LivingPortraitPackageSignature: Codable, Sendable, Equatable {
    public var algorithm: String
    public var keyID: String
    public var signatureBase64: String

    public init(algorithm: String = "ed25519", keyID: String, signatureBase64: String) {
        self.algorithm = algorithm
        self.keyID = keyID
        self.signatureBase64 = signatureBase64
    }
}

public struct ValidatedLivingPortraitPackage: Sendable {
    public let manifest: LivingPortraitPackageManifest
    public let receipt: LivingPortraitValidationReceipt
    public let scene: LivingPortraitScene
    public let files: [String: Data]
}

public enum LivingPortraitPackageLoadResult: Sendable {
    case validated(ValidatedLivingPortraitPackage)
    /// Hosts render their bundled still when this is returned. Core never attempts repair,
    /// generation, download, or an LLM fallback on a mobile device.
    case staticFallback(reason: String)
}

public enum LivingPortraitPackageLoader {
    public static let requiredChecks: Set<String> = [
        "identity", "silhouette", "alphaBounds", "protectedRegions", "motionBounds",
    ]

    public static func loadOrFallback(
        manifestData: Data,
        receiptData: Data,
        signatureData: Data,
        files: [String: Data],
        trustedPublicKeys: [String: Data]
    ) -> LivingPortraitPackageLoadResult {
        do {
            return .validated(try load(
                manifestData: manifestData,
                receiptData: receiptData,
                signatureData: signatureData,
                files: files,
                trustedPublicKeys: trustedPublicKeys
            ))
        } catch {
            return .staticFallback(reason: String(describing: error))
        }
    }

    public static func load(
        manifestData: Data,
        receiptData: Data,
        signatureData: Data,
        files: [String: Data],
        trustedPublicKeys: [String: Data]
    ) throws -> ValidatedLivingPortraitPackage {
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(LivingPortraitPackageManifest.self, from: manifestData)
        let receipt = try decoder.decode(LivingPortraitValidationReceipt.self, from: receiptData)
        let signature = try decoder.decode(LivingPortraitPackageSignature.self, from: signatureData)

        guard manifest.packageSchemaVersion == 1, manifest.coreSceneSchemaVersion == 1 else {
            throw LivingPortraitPackageError.unsupportedVersion
        }
        guard receipt.validatorProfile == "living-portrait-strict-v1", receipt.validatorVersion == 1 else {
            throw LivingPortraitPackageError.unsupportedValidator
        }
        guard Set(receipt.passedChecks).isSuperset(of: requiredChecks) else {
            throw LivingPortraitPackageError.incompleteValidationReceipt
        }
        guard receipt.manifestSHA256 == sha256Hex(manifestData) else {
            throw LivingPortraitPackageError.manifestDigestMismatch
        }
        guard signature.algorithm == "ed25519",
              let publicKeyData = trustedPublicKeys[signature.keyID],
              let rawSignature = Data(base64Encoded: signature.signatureBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData),
              publicKey.isValidSignature(rawSignature, for: receiptData) else {
            throw LivingPortraitPackageError.invalidSignature
        }

        let declaredPaths = Set(manifest.files.map(\.path))
        guard declaredPaths.count == manifest.files.count,
              declaredPaths == Set(files.keys),
              declaredPaths.allSatisfy(isSafeRelativePath) else {
            throw LivingPortraitPackageError.invalidFileInventory
        }
        for file in manifest.files {
            guard let data = files[file.path], sha256Hex(data) == file.sha256 else {
                throw LivingPortraitPackageError.fileDigestMismatch(file.path)
            }
        }
        guard let sceneData = files[manifest.scenePath] else {
            throw LivingPortraitPackageError.missingScene
        }
        let scene = try decoder.decode(LivingPortraitScene.self, from: sceneData)
        try scene.validate()
        return ValidatedLivingPortraitPackage(
            manifest: manifest,
            receipt: receipt,
            scene: scene,
            files: files
        )
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }
}

public enum LivingPortraitPackageError: Error, Sendable, Equatable {
    case unsupportedVersion
    case unsupportedValidator
    case incompleteValidationReceipt
    case manifestDigestMismatch
    case invalidSignature
    case invalidFileInventory
    case fileDigestMismatch(String)
    case missingScene
}
