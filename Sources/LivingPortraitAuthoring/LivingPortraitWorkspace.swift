import CryptoKit
import Foundation
import LivingPortraitCore

public struct LivingPortraitAuthoringJob: Codable, Sendable, Equatable {
    public struct Source: Codable, Sendable, Equatable {
        public var path: String
        public var pixelWidth: Int
        public var pixelHeight: Int
        public var referencePaths: [String]

        public init(path: String, pixelWidth: Int, pixelHeight: Int, referencePaths: [String] = []) {
            self.path = path
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.referencePaths = referencePaths
        }
    }

    public var jobSchemaVersion: Int
    public var packageID: String
    public var revision: Int
    public var keyID: String
    public var source: Source
    public var candidatePath: String
    public var measurementsPath: String
    public var assetsDirectory: String

    public init(
        jobSchemaVersion: Int = 1,
        packageID: String,
        revision: Int,
        keyID: String,
        source: Source,
        candidatePath: String = "candidate.json",
        measurementsPath: String = "measurements.json",
        assetsDirectory: String = "assets"
    ) {
        self.jobSchemaVersion = jobSchemaVersion
        self.packageID = packageID
        self.revision = revision
        self.keyID = keyID
        self.source = source
        self.candidatePath = candidatePath
        self.measurementsPath = measurementsPath
        self.assetsDirectory = assetsDirectory
    }
}

/// Disk representation of a generated candidate. Asset bytes remain as ordinary files under the
/// workspace asset directory instead of being embedded as base64 in JSON.
public struct LivingPortraitCandidateDocument: Codable, Sendable, Equatable {
    public var draftSchemaVersion: Int
    public var id: String
    public var briefID: String
    public var scene: LivingPortraitScene
    public var regions: [LivingPortraitGeneratedCandidate.Region]
    public var depthHints: [LivingPortraitGeneratedCandidate.DepthHint]
    public var motionRecipes: [LivingPortraitGeneratedCandidate.MotionRecipe]

    public init(
        draftSchemaVersion: Int = 1,
        id: String,
        briefID: String,
        scene: LivingPortraitScene,
        regions: [LivingPortraitGeneratedCandidate.Region],
        depthHints: [LivingPortraitGeneratedCandidate.DepthHint],
        motionRecipes: [LivingPortraitGeneratedCandidate.MotionRecipe]
    ) {
        self.draftSchemaVersion = draftSchemaVersion
        self.id = id
        self.briefID = briefID
        self.scene = scene
        self.regions = regions
        self.depthHints = depthHints
        self.motionRecipes = motionRecipes
    }

    public init(candidate: LivingPortraitGeneratedCandidate) {
        self.init(
            draftSchemaVersion: candidate.draftSchemaVersion,
            id: candidate.id,
            briefID: candidate.briefID,
            scene: candidate.scene,
            regions: candidate.regions,
            depthHints: candidate.depthHints,
            motionRecipes: candidate.motionRecipes
        )
    }
}

public struct LivingPortraitPrivateKeyDocument: Codable, Sendable, Equatable {
    public var keyID: String
    public var privateKeyBase64: String

    public init(keyID: String, privateKeyBase64: String) {
        self.keyID = keyID
        self.privateKeyBase64 = privateKeyBase64
    }
}

public struct LivingPortraitPublicKeyDocument: Codable, Sendable, Equatable {
    public var keyID: String
    public var publicKeyBase64: String

    public init(keyID: String, publicKeyBase64: String) {
        self.keyID = keyID
        self.publicKeyBase64 = publicKeyBase64
    }
}

public struct LoadedLivingPortraitAuthoringWorkspace: Sendable {
    public let job: LivingPortraitAuthoringJob
    public let source: LivingPortraitAuthoringSource
    public let candidate: LivingPortraitGeneratedCandidate
    public let measurements: LivingPortraitValidationMeasurements
}

public enum LivingPortraitAuthoringWorkspace {
    public static let jobFilename = "job.json"
    public static let packageManifestFilename = "manifest.json"
    public static let packageReceiptFilename = "receipt.json"
    public static let packageSignatureFilename = "signature.json"
    public static let packageFilesDirectory = "files"

    public static func scaffold(at directory: URL) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: directory.path) else {
            throw LivingPortraitWorkspaceError.destinationAlreadyExists(directory.path)
        }
        try fileManager.createDirectory(
            at: directory.appendingPathComponent("assets/masks", isDirectory: true),
            withIntermediateDirectories: true
        )

        let job = LivingPortraitAuthoringJob(
            packageID: "portrait.example",
            revision: 1,
            keyID: "portrait-signing-v1",
            source: .init(path: "source.png", pixelWidth: 900, pixelHeight: 1600)
        )
        let candidate = templateCandidate()
        let measurements = LivingPortraitValidationMeasurements(
            identitySimilarity: 0,
            silhouetteIntersectionOverUnion: 0,
            alphaTouchesCanvasEdge: true
        )
        try writeJSON(job, to: directory.appendingPathComponent(jobFilename))
        try writeJSON(candidate, to: directory.appendingPathComponent(job.candidatePath))
        try writeJSON(measurements, to: directory.appendingPathComponent(job.measurementsPath))
        try workspaceInstructions.write(
            to: directory.appendingPathComponent("WORKSPACE.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    public static func load(at directory: URL) throws -> LoadedLivingPortraitAuthoringWorkspace {
        let root = directory.standardizedFileURL
        let job: LivingPortraitAuthoringJob = try readJSON(
            at: try resolvedRelativePath(jobFilename, under: root)
        )
        guard job.jobSchemaVersion == 1 else { throw LivingPortraitWorkspaceError.unsupportedVersion }
        guard !job.packageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              job.revision > 0,
              !job.keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LivingPortraitWorkspaceError.invalidJobMetadata
        }

        let sourceData = try readRequiredData(
            at: try resolvedRelativePath(job.source.path, under: root),
            relativePath: job.source.path
        )
        let references = try job.source.referencePaths.map { path in
            try readRequiredData(at: try resolvedRelativePath(path, under: root), relativePath: path)
        }
        let source = LivingPortraitAuthoringSource(
            imageData: sourceData,
            pixelWidth: job.source.pixelWidth,
            pixelHeight: job.source.pixelHeight,
            referenceImageData: references
        )
        try source.validate()

        let document: LivingPortraitCandidateDocument = try readJSON(
            at: try resolvedRelativePath(job.candidatePath, under: root)
        )
        let measurements: LivingPortraitValidationMeasurements = try readJSON(
            at: try resolvedRelativePath(job.measurementsPath, under: root)
        )
        let assetsRoot = try resolvedRelativePath(job.assetsDirectory, under: root)
        let assetPaths = Set(document.regions.map(\.maskPath) + document.scene.layers.map(\.asset))
        let assets = try Dictionary(uniqueKeysWithValues: assetPaths.map { path in
            let assetURL = try resolvedRelativePath(path, under: assetsRoot)
            return (path, try readRequiredData(at: assetURL, relativePath: "\(job.assetsDirectory)/\(path)"))
        })
        let candidate = LivingPortraitGeneratedCandidate(
            draftSchemaVersion: document.draftSchemaVersion,
            id: document.id,
            briefID: document.briefID,
            scene: document.scene,
            regions: document.regions,
            depthHints: document.depthHints,
            motionRecipes: document.motionRecipes,
            assets: assets
        )
        return LoadedLivingPortraitAuthoringWorkspace(
            job: job,
            source: source,
            candidate: candidate,
            measurements: measurements
        )
    }

    @discardableResult
    public static func validate(at directory: URL) throws -> [String] {
        let workspace = try load(at: directory)
        return try LivingPortraitAuthoringValidator().validate(
            workspace.candidate,
            measurements: workspace.measurements
        )
    }

    public static func generateSigningKeyDocuments(
        keyID: String
    ) throws -> (privateKey: LivingPortraitPrivateKeyDocument, publicKey: LivingPortraitPublicKeyDocument) {
        guard !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LivingPortraitWorkspaceError.invalidKeyDocument
        }
        let key = Curve25519.Signing.PrivateKey()
        return (
            LivingPortraitPrivateKeyDocument(
                keyID: keyID,
                privateKeyBase64: key.rawRepresentation.base64EncodedString()
            ),
            LivingPortraitPublicKeyDocument(
                keyID: keyID,
                publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()
            )
        )
    }

    public static func bake(
        workspaceAt directory: URL,
        approvedBy: String,
        privateKeyDocument: LivingPortraitPrivateKeyDocument
    ) throws -> BakedLivingPortraitPackage {
        let workspace = try load(at: directory)
        guard privateKeyDocument.keyID == workspace.job.keyID,
              let privateKeyData = Data(base64Encoded: privateKeyDocument.privateKeyBase64),
              let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData) else {
            throw LivingPortraitWorkspaceError.invalidKeyDocument
        }
        return try LivingPortraitPackageAssembler.bake(
            packageID: workspace.job.packageID,
            revision: workspace.job.revision,
            source: workspace.source,
            draft: workspace.candidate,
            measurements: workspace.measurements,
            approval: .init(
                candidateID: workspace.candidate.id,
                approvedBy: approvedBy,
                approvedRevision: workspace.job.revision
            ),
            signingKey: privateKey,
            keyID: workspace.job.keyID
        )
    }

    public static func writePackage(
        _ package: BakedLivingPortraitPackage,
        to directory: URL
    ) throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: directory.path) else {
            throw LivingPortraitWorkspaceError.destinationAlreadyExists(directory.path)
        }
        let filesRoot = directory.appendingPathComponent(packageFilesDirectory, isDirectory: true)
        try fileManager.createDirectory(at: filesRoot, withIntermediateDirectories: true)
        try package.manifestData.write(to: directory.appendingPathComponent(packageManifestFilename), options: .atomic)
        try package.receiptData.write(to: directory.appendingPathComponent(packageReceiptFilename), options: .atomic)
        try package.signatureData.write(to: directory.appendingPathComponent(packageSignatureFilename), options: .atomic)
        for (path, data) in package.files {
            let destination = try resolvedRelativePath(path, under: filesRoot)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
    }

    public static func verifyPackage(
        at directory: URL,
        publicKeyDocument: LivingPortraitPublicKeyDocument
    ) throws -> ValidatedLivingPortraitPackage {
        guard let publicKeyData = Data(base64Encoded: publicKeyDocument.publicKeyBase64),
              (try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)) != nil else {
            throw LivingPortraitWorkspaceError.invalidKeyDocument
        }
        let root = directory.standardizedFileURL
        let manifestData = try readRequiredData(
            at: try resolvedRelativePath(packageManifestFilename, under: root),
            relativePath: packageManifestFilename
        )
        let receiptData = try readRequiredData(
            at: try resolvedRelativePath(packageReceiptFilename, under: root),
            relativePath: packageReceiptFilename
        )
        let signatureData = try readRequiredData(
            at: try resolvedRelativePath(packageSignatureFilename, under: root),
            relativePath: packageSignatureFilename
        )
        let manifest = try JSONDecoder().decode(LivingPortraitPackageManifest.self, from: manifestData)
        let filesRoot = try resolvedRelativePath(packageFilesDirectory, under: root)
        let files = try Dictionary(uniqueKeysWithValues: manifest.files.map { file in
            let fileURL = try resolvedRelativePath(file.path, under: filesRoot)
            return (file.path, try readRequiredData(at: fileURL, relativePath: "\(packageFilesDirectory)/\(file.path)"))
        })
        return try LivingPortraitPackageLoader.load(
            manifestData: manifestData,
            receiptData: receiptData,
            signatureData: signatureData,
            files: files,
            trustedPublicKeys: [publicKeyDocument.keyID: publicKeyData]
        )
    }

    public static func writeKeyDocuments(
        privateKey: LivingPortraitPrivateKeyDocument,
        publicKey: LivingPortraitPublicKeyDocument,
        privateKeyURL: URL,
        publicKeyURL: URL
    ) throws {
        let fileManager = FileManager.default
        guard privateKeyURL.standardizedFileURL != publicKeyURL.standardizedFileURL else {
            throw LivingPortraitWorkspaceError.keyDestinationsMustDiffer
        }
        guard !fileManager.fileExists(atPath: privateKeyURL.path),
              !fileManager.fileExists(atPath: publicKeyURL.path) else {
            throw LivingPortraitWorkspaceError.destinationAlreadyExists(
                fileManager.fileExists(atPath: privateKeyURL.path) ? privateKeyURL.path : publicKeyURL.path
            )
        }
        try fileManager.createDirectory(at: privateKeyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: publicKeyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON(privateKey, to: privateKeyURL)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateKeyURL.path)
        try writeJSON(publicKey, to: publicKeyURL)
    }

    private static func templateCandidate() -> LivingPortraitCandidateDocument {
        let regions: [LivingPortraitGeneratedCandidate.Region] = [
            .init(id: "silhouette", kind: .characterSilhouette, bounds: .init(x: 0.2, y: 0.05, width: 0.6, height: 0.9), maskPath: "masks/silhouette.png", confidence: 0),
            .init(id: "face", kind: .face, bounds: .init(x: 0.4, y: 0.14, width: 0.22, height: 0.18), maskPath: "masks/face.png", confidence: 0),
            .init(id: "left-hand", kind: .leftHand, bounds: .init(x: 0.18, y: 0.62, width: 0.1, height: 0.12), maskPath: "masks/left-hand.png", confidence: 0),
            .init(id: "right-hand", kind: .rightHand, bounds: .init(x: 0.7, y: 0.34, width: 0.1, height: 0.12), maskPath: "masks/right-hand.png", confidence: 0),
            .init(id: "teeth", kind: .teeth, bounds: .init(x: 0.48, y: 0.25, width: 0.06, height: 0.02), maskPath: "masks/teeth.png", confidence: 0),
            .init(id: "eyes", kind: .eyes, bounds: .init(x: 0.44, y: 0.2, width: 0.14, height: 0.035), maskPath: "masks/eyes.png", confidence: 0),
            .init(id: "hair", kind: .hair, bounds: .init(x: 0.63, y: 0.04, width: 0.14, height: 0.08), maskPath: "masks/hair.png", confidence: 0),
        ]
        return LivingPortraitCandidateDocument(
            id: "candidate-1",
            briefID: "brief-1",
            scene: LivingPortraitScene(
                id: "portrait.example",
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
            ]
        )
    }

    private static func resolvedRelativePath(_ path: String, under root: URL) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw LivingPortraitWorkspaceError.unsafePath(path)
        }
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = components.reduce(resolvedRoot) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: false)
        }.resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(resolvedRoot.path + "/") else {
            throw LivingPortraitWorkspaceError.unsafePath(path)
        }
        return candidate
    }

    private static func readRequiredData(at url: URL, relativePath: String) throws -> Data {
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { throw LivingPortraitWorkspaceError.emptyFile(relativePath) }
            return data
        } catch let error as LivingPortraitWorkspaceError {
            throw error
        } catch {
            throw LivingPortraitWorkspaceError.missingFile(relativePath)
        }
    }

    private static func readJSON<Value: Decodable>(at url: URL) throws -> Value {
        try JSONDecoder().decode(Value.self, from: readRequiredData(at: url, relativePath: url.lastPathComponent))
    }

    private static func writeJSON<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static let workspaceInstructions = """
    # LivingPortrait authoring workspace

    1. Put the source portrait at `source.png`, or update `job.json`.
    2. Put every layer and mask referenced by `candidate.json` under `assets/`.
    3. Replace the zero confidence and failing values in `candidate.json` and `measurements.json`
       with outputs from an independent critic. Do not invent passing measurements by hand.
    4. Run `living-portrait-master validate <workspace>`.
    5. Generate a signing key once, then run `bake` with explicit human approval.

    Story meaning, rare-event policy, and reaction triggers stay in the host product.
    """
}

public enum LivingPortraitWorkspaceError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedVersion
    case invalidJobMetadata
    case unsafePath(String)
    case missingFile(String)
    case emptyFile(String)
    case destinationAlreadyExists(String)
    case invalidKeyDocument
    case keyDestinationsMustDiffer

    public var description: String {
        switch self {
        case .unsupportedVersion:
            return "unsupported workspace version"
        case .invalidJobMetadata:
            return "job requires a package ID, positive revision, and signing key ID"
        case .unsafePath(let path):
            return "unsafe relative path: \(path)"
        case .missingFile(let path):
            return "missing required file: \(path)"
        case .emptyFile(let path):
            return "required file is empty: \(path)"
        case .destinationAlreadyExists(let path):
            return "destination already exists: \(path)"
        case .invalidKeyDocument:
            return "invalid or mismatched signing key document"
        case .keyDestinationsMustDiffer:
            return "private and public key destinations must be different files"
        }
    }
}
