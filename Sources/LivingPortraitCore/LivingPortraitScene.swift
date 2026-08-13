import Foundation

public struct LivingPortraitScene: Codable, Sendable, Equatable {
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

    public init(
        schemaVersion: Int = 1,
        id: String,
        seed: String,
        canvas: Canvas = Canvas(),
        layers: [Layer],
        motion: Motion = .subtle
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.seed = seed
        self.canvas = canvas
        self.layers = layers
        self.motion = motion
    }

    public var numericSeed: UInt64 { UInt64(seed) ?? stableStringSeed(seed) }
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

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
