import Foundation
import ImageIO

public struct LivingPortraitRasterSize: Codable, Sendable, Equatable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// A verified, same-canvas set of raster assets. The host resolves these bytes into native images
/// and gives the scene to `LivingPortraitStage`; no model, network client, or character semantics
/// are present in this runtime contract.
public struct LivingPortraitRuntimeLayerBundle: Sendable {
    public struct Asset: Sendable {
        public let path: String
        public let data: Data

        public init(path: String, data: Data) {
            self.path = path
            self.data = data
        }
    }

    public let canvas: LivingPortraitRasterSize
    public let background: Asset
    public let character: Asset
    public let blink: Asset?
    public let wind: Asset?
    public let reaction: Asset?
    public let fallback: Asset

    public init(
        canvas: LivingPortraitRasterSize,
        background: Asset,
        character: Asset,
        blink: Asset?,
        wind: Asset?,
        reaction: Asset?,
        fallback: Asset
    ) {
        self.canvas = canvas
        self.background = background
        self.character = character
        self.blink = blink
        self.wind = wind
        self.reaction = reaction
        self.fallback = fallback
    }

    public func assetData(for path: String) -> Data? {
        [background, character, blink, wind, reaction, fallback]
            .compactMap { $0 }
            .first(where: { $0.path == path })?
            .data
    }
}

/// Fail-closed validation shared by desktop authoring and the mobile package loader.
public enum LivingPortraitLayerBundleValidator {
    public static func validate(
        scene: LivingPortraitScene,
        files: [String: Data]
    ) throws -> LivingPortraitRuntimeLayerBundle? {
        guard let fallbackPath = scene.fallbackAsset else { return nil }

        let grouped = Dictionary(grouping: scene.layers, by: \LivingPortraitScene.Layer.role)
        guard grouped[.background]?.count == 1,
              grouped[.character]?.count == 1,
              (grouped[.blink]?.count ?? 0) <= 1,
              (grouped[.wind]?.count ?? 0) <= 1,
              (grouped[.reaction]?.count ?? 0) <= 1 else {
            throw LivingPortraitLayerBundleError.invalidRoleCardinality
        }

        let layerPaths = scene.layers.map(\.asset)
        guard Set(layerPaths).count == layerPaths.count,
              !layerPaths.contains(fallbackPath) else {
            throw LivingPortraitLayerBundleError.duplicateAssetReference
        }

        let referencedPaths = layerPaths + [fallbackPath]
        var sizes: [String: LivingPortraitRasterSize] = [:]
        for path in referencedPaths {
            guard let data = files[path] else {
                throw LivingPortraitLayerBundleError.missingAsset(path)
            }
            sizes[path] = try inspectPNG(data, path: path)
        }
        guard let expectedSize = sizes[referencedPaths[0]],
              sizes.values.allSatisfy({ $0 == expectedSize }) else {
            throw LivingPortraitLayerBundleError.canvasMismatch
        }

        func asset(_ role: LivingPortraitScene.Layer.Role) -> LivingPortraitRuntimeLayerBundle.Asset? {
            guard let layer = grouped[role]?.first, let data = files[layer.asset] else { return nil }
            return .init(path: layer.asset, data: data)
        }
        guard let background = asset(.background),
              let character = asset(.character),
              let fallbackData = files[fallbackPath] else {
            throw LivingPortraitLayerBundleError.invalidRoleCardinality
        }

        return LivingPortraitRuntimeLayerBundle(
            canvas: expectedSize,
            background: background,
            character: character,
            blink: asset(.blink),
            wind: asset(.wind),
            reaction: asset(.reaction),
            fallback: .init(path: fallbackPath, data: fallbackData)
        )
    }

    public static func inspectPNG(_ data: Data, path: String) throws -> LivingPortraitRasterSize {
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0,
              image.height > 0 else {
            throw LivingPortraitLayerBundleError.invalidPNG(path)
        }
        return LivingPortraitRasterSize(width: image.width, height: image.height)
    }
}

public enum LivingPortraitLayerBundleError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidRoleCardinality
    case duplicateAssetReference
    case missingAsset(String)
    case invalidPNG(String)
    case canvasMismatch

    public var description: String {
        switch self {
        case .invalidRoleCardinality:
            "a layered package requires one background, one character, and at most one blink, wind, and reaction layer"
        case .duplicateAssetReference:
            "each layer and fallback must reference a distinct asset"
        case .missingAsset(let path):
            "missing layered portrait asset: \(path)"
        case .invalidPNG(let path):
            "layered portrait asset is not a decodable PNG: \(path)"
        case .canvasMismatch:
            "all layered portrait assets and fallback must use the same pixel canvas"
        }
    }
}
