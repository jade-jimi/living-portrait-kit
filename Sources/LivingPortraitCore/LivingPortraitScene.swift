import Foundation

public struct LivingPortraitScene: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case seed
        case canvas
        case layers
        case motion
        case fallbackAsset
    }

    public struct Canvas: Codable, Sendable, Equatable {
        public var aspectWidth: Double
        public var aspectHeight: Double

        public init(aspectWidth: Double = 9, aspectHeight: Double = 16) {
            self.aspectWidth = max(0.01, aspectWidth)
            self.aspectHeight = max(0.01, aspectHeight)
        }
    }

    public struct Layer: Codable, Sendable, Equatable, Identifiable {
        public enum Role: String, Codable, Sendable, CaseIterable {
            case background
            case character
            case blink
            case wind
            case reaction
        }

        public var id: String
        public var role: Role
        /// Opaque asset identifier. Each renderer decides how it resolves the value.
        public var asset: String
        public var zIndex: Int

        public init(id: String, role: Role, asset: String, zIndex: Int) {
            self.id = id
            self.role = role
            self.asset = asset
            self.zIndex = zIndex
        }
    }

    public struct Motion: Codable, Sendable, Equatable {
        public var blinkSlotMilliseconds: Int64
        public var blinkDurationMilliseconds: Int64
        public var blinkProbability: Double
        public var breathPeriodMilliseconds: Int64
        public var breathScale: Double
        public var gazePeriodMilliseconds: Int64
        public var parallaxUnits: Double
        public var windPeriodMilliseconds: Int64
        public var windUnits: Double
        public var windRotationDegrees: Double
        public var reactionScale: Double

        public init(
            blinkSlotMilliseconds: Int64 = 3_800,
            blinkDurationMilliseconds: Int64 = 220,
            blinkProbability: Double = 0.72,
            breathPeriodMilliseconds: Int64 = 5_600,
            breathScale: Double = 0.012,
            gazePeriodMilliseconds: Int64 = 4_400,
            parallaxUnits: Double = 7,
            windPeriodMilliseconds: Int64 = 3_100,
            windUnits: Double = 2.4,
            windRotationDegrees: Double = 0.7,
            reactionScale: Double = 0.008
        ) {
            self.blinkSlotMilliseconds = max(500, blinkSlotMilliseconds)
            self.blinkDurationMilliseconds = max(80, min(blinkDurationMilliseconds, self.blinkSlotMilliseconds * 4 / 5))
            self.blinkProbability = blinkProbability.clamped(to: 0...1)
            self.breathPeriodMilliseconds = max(500, breathPeriodMilliseconds)
            self.breathScale = max(0, breathScale)
            self.gazePeriodMilliseconds = max(500, gazePeriodMilliseconds)
            self.parallaxUnits = max(0, parallaxUnits)
            self.windPeriodMilliseconds = max(500, windPeriodMilliseconds)
            self.windUnits = max(0, windUnits)
            self.windRotationDegrees = max(0, windRotationDegrees)
            self.reactionScale = max(0, reactionScale)
        }

        public static let subtle = Motion()
    }

    public var schemaVersion: Int
    public var id: String
    /// Decimal UInt64 text avoids precision loss in JSON implementations that decode numbers as doubles.
    public var seed: String
    public var canvas: Canvas
    public var layers: [Layer]
    public var motion: Motion
    /// Optional signed still used when the layered runtime cannot validate or render the scene.
    /// Declaring it opts the scene into the strict same-canvas layered-package contract.
    public var fallbackAsset: String?

    public init(
        schemaVersion: Int = 1,
        id: String,
        seed: String,
        canvas: Canvas = Canvas(),
        layers: [Layer],
        motion: Motion = .subtle,
        fallbackAsset: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.seed = seed
        self.canvas = canvas
        self.layers = layers
        self.motion = motion
        self.fallbackAsset = fallbackAsset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        seed = try container.decode(String.self, forKey: .seed)
        canvas = try container.decode(Canvas.self, forKey: .canvas)
        layers = try container.decode([Layer].self, forKey: .layers)
        motion = try container.decode(Motion.self, forKey: .motion)
        fallbackAsset = try container.decodeIfPresent(String.self, forKey: .fallbackAsset)
        try validate()
    }

    /// Validates values against the bundled version 1 scene schema.
    /// JSON decoding calls this automatically; hosts should call it after mutating a scene.
    public func validate() throws {
        guard schemaVersion == 1 else {
            throw LivingPortraitValidationError(path: "schemaVersion", reason: "must equal 1")
        }
        guard !id.isEmpty else {
            throw LivingPortraitValidationError(path: "id", reason: "must not be empty")
        }
        guard (1...20).contains(seed.count), seed.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw LivingPortraitValidationError(path: "seed", reason: "must contain 1 to 20 decimal digits")
        }
        guard canvas.aspectWidth.isFinite, canvas.aspectWidth > 0 else {
            throw LivingPortraitValidationError(path: "canvas.aspectWidth", reason: "must be finite and greater than zero")
        }
        guard canvas.aspectHeight.isFinite, canvas.aspectHeight > 0 else {
            throw LivingPortraitValidationError(path: "canvas.aspectHeight", reason: "must be finite and greater than zero")
        }
        guard layers.count >= 2 else {
            throw LivingPortraitValidationError(path: "layers", reason: "must contain at least two layers")
        }
        guard Set(layers.map(\.id)).count == layers.count else {
            throw LivingPortraitValidationError(path: "layers", reason: "layer IDs must be unique")
        }
        for (index, layer) in layers.enumerated() {
            guard !layer.id.isEmpty else {
                throw LivingPortraitValidationError(path: "layers[\(index)].id", reason: "must not be empty")
            }
            guard !layer.asset.isEmpty else {
                throw LivingPortraitValidationError(path: "layers[\(index)].asset", reason: "must not be empty")
            }
            guard isSafeAssetPath(layer.asset) else {
                throw LivingPortraitValidationError(path: "layers[\(index)].asset", reason: "must be a safe relative path")
            }
        }
        if let fallbackAsset {
            guard isSafeAssetPath(fallbackAsset) else {
                throw LivingPortraitValidationError(path: "fallbackAsset", reason: "must be a safe relative path")
            }
        }

        try validateMinimum(motion.blinkSlotMilliseconds, minimum: 500, path: "motion.blinkSlotMilliseconds")
        try validateMinimum(motion.blinkDurationMilliseconds, minimum: 80, path: "motion.blinkDurationMilliseconds")
        try validateUnitInterval(motion.blinkProbability, path: "motion.blinkProbability")
        try validateMinimum(motion.breathPeriodMilliseconds, minimum: 500, path: "motion.breathPeriodMilliseconds")
        try validateNonnegative(motion.breathScale, path: "motion.breathScale")
        try validateMinimum(motion.gazePeriodMilliseconds, minimum: 500, path: "motion.gazePeriodMilliseconds")
        try validateNonnegative(motion.parallaxUnits, path: "motion.parallaxUnits")
        try validateMinimum(motion.windPeriodMilliseconds, minimum: 500, path: "motion.windPeriodMilliseconds")
        try validateNonnegative(motion.windUnits, path: "motion.windUnits")
        try validateNonnegative(motion.windRotationDegrees, path: "motion.windRotationDegrees")
        try validateNonnegative(motion.reactionScale, path: "motion.reactionScale")
    }

    public var numericSeed: UInt64 { UInt64(seed) ?? stableStringSeed(seed) }
}

private func isSafeAssetPath(_ path: String) -> Bool {
    !path.isEmpty
        && !path.hasPrefix("/")
        && path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
}

/// A stable, field-addressable failure returned by `LivingPortraitScene.validate()`.
public struct LivingPortraitValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    public let path: String
    public let reason: String

    public var description: String { "Invalid \(path): \(reason)" }

    init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

/// A product event authored by the host app, not ambient behavior invented by the engine.
public struct LivingPortraitEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var type: String
    public var startMilliseconds: Int64
    public var durationMilliseconds: Int64
    public var intensity: Double

    public init(
        id: String,
        type: String,
        startMilliseconds: Int64,
        durationMilliseconds: Int64,
        intensity: Double = 1
    ) {
        self.id = id
        self.type = type
        self.startMilliseconds = max(0, startMilliseconds)
        self.durationMilliseconds = max(1, durationMilliseconds)
        self.intensity = intensity.clamped(to: 0...1)
    }
}

public enum LivingPortraitContract {
    public static func bundledSchemaData() throws -> Data {
        try bundledResourceData(named: "living-portrait.schema", extension: "json")
    }

    public static func bundledConformanceFixtureData() throws -> Data {
        try bundledResourceData(named: "deterministic-conformance", extension: "json")
    }

    private static func bundledResourceData(named name: String, extension fileExtension: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources")
            ?? Bundle.module.url(forResource: name, withExtension: fileExtension) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}

private func stableStringSeed(_ string: String) -> UInt64 {
    string.utf8.reduce(14_695_981_039_346_656_037) { value, byte in
        (value ^ UInt64(byte)) &* 1_099_511_628_211
    }
}

private func validateMinimum(_ value: Int64, minimum: Int64, path: String) throws {
    guard value >= minimum else {
        throw LivingPortraitValidationError(path: path, reason: "must be at least \(minimum)")
    }
}

private func validateNonnegative(_ value: Double, path: String) throws {
    guard value.isFinite, value >= 0 else {
        throw LivingPortraitValidationError(path: path, reason: "must be finite and nonnegative")
    }
}

private func validateUnitInterval(_ value: Double, path: String) throws {
    guard value.isFinite, (0...1).contains(value) else {
        throw LivingPortraitValidationError(path: path, reason: "must be finite and between zero and one")
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
