import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import LivingPortraitCore

@Test func sceneRoundTripsThroughJSON() throws {
    let scene = fixtureScene()
    let data = try JSONEncoder().encode(scene)
    let decoded = try JSONDecoder().decode(LivingPortraitScene.self, from: data)
    #expect(decoded == scene)
}

@Test func bundledContractsAreReadable() throws {
    let schema = try LivingPortraitContract.bundledSchemaData()
    let fixture = try LivingPortraitContract.bundledConformanceFixtureData()
    #expect(schema.count > 1_000)
    #expect(fixture.count > 500)
    #expect(try JSONSerialization.jsonObject(with: schema) is [String: Any])
    #expect(try JSONSerialization.jsonObject(with: fixture) is [String: Any])
}

@Test func bundledConformanceFixtureMatchesEveryExpectedScalar() throws {
    let data = try LivingPortraitContract.bundledConformanceFixtureData()
    let fixture = try JSONDecoder().decode(ConformanceFixture.self, from: data)
    #expect(fixture.contractVersion == 1)
    try fixture.scene.validate()

    for testCase in fixture.cases {
        let state = LivingPortraitMotionEngine(scene: fixture.scene).state(
            atMilliseconds: testCase.milliseconds,
            windIntensity: testCase.windIntensity,
            reactionEvents: testCase.events,
            reduceMotion: testCase.reduceMotion
        )
        expectNear(state.blink, testCase.expected.blink, tolerance: fixture.tolerance, field: "blink", milliseconds: testCase.milliseconds)
        expectNear(state.breath, testCase.expected.breath, tolerance: fixture.tolerance, field: "breath", milliseconds: testCase.milliseconds)
        expectNear(state.gazeX, testCase.expected.gazeX, tolerance: fixture.tolerance, field: "gazeX", milliseconds: testCase.milliseconds)
        expectNear(state.gazeY, testCase.expected.gazeY, tolerance: fixture.tolerance, field: "gazeY", milliseconds: testCase.milliseconds)
        expectNear(state.windX, testCase.expected.windX, tolerance: fixture.tolerance, field: "windX", milliseconds: testCase.milliseconds)
        expectNear(state.reaction, testCase.expected.reaction, tolerance: fixture.tolerance, field: "reaction", milliseconds: testCase.milliseconds)
    }
}

@Test func decodingRejectsSchemaInvalidSceneValues() throws {
    try expectDecodingFailure { $0.schemaVersion = 2 }
    try expectDecodingFailure { $0.id = "" }
    try expectDecodingFailure { $0.seed = "not-decimal" }
    try expectDecodingFailure { $0.seed = String(repeating: "1", count: 21) }
    try expectDecodingFailure { $0.canvas.aspectWidth = 0 }
    try expectDecodingFailure { $0.canvas.aspectHeight = 0 }
    try expectDecodingFailure { $0.layers = [] }
    try expectDecodingFailure { $0.layers[0].id = "" }
    try expectDecodingFailure { $0.layers[0].asset = "" }
    try expectDecodingFailure { $0.motion.blinkSlotMilliseconds = 0 }
    try expectDecodingFailure { $0.motion.blinkDurationMilliseconds = 0 }
    try expectDecodingFailure { $0.motion.blinkProbability = 1.1 }
    try expectDecodingFailure { $0.motion.breathPeriodMilliseconds = 0 }
    try expectDecodingFailure { $0.motion.breathScale = -1 }
    try expectDecodingFailure { $0.motion.gazePeriodMilliseconds = 0 }
    try expectDecodingFailure { $0.motion.parallaxUnits = -1 }
    try expectDecodingFailure { $0.motion.windPeriodMilliseconds = 0 }
    try expectDecodingFailure { $0.motion.windUnits = -1 }
    try expectDecodingFailure { $0.motion.windRotationDegrees = -1 }
    try expectDecodingFailure { $0.motion.reactionScale = -1 }
}

@Test func invalidMutatedPeriodFailsClosedInsteadOfCrashing() {
    var scene = fixtureScene()
    scene.motion.breathPeriodMilliseconds = 0
    #expect(LivingPortraitMotionEngine(scene: scene).state(atMilliseconds: 1_000) == .still)
}

@Test func sameInputsProduceSameState() {
    let engine = LivingPortraitMotionEngine(scene: fixtureScene())
    #expect(engine.state(atMilliseconds: 123_456, windIntensity: 0.8) == engine.state(atMilliseconds: 123_456, windIntensity: 0.8))
}

@Test func reduceMotionIsCompletelyStill() {
    let engine = LivingPortraitMotionEngine(scene: fixtureScene())
    #expect(engine.state(atMilliseconds: 1_000_000, reduceMotion: true) == .still)
}

@Test func focusIsClampedAndDrivesParallax() {
    let engine = LivingPortraitMotionEngine(scene: fixtureScene())
    let state = engine.state(atMilliseconds: 5_000, focus: PortraitFocus(x: 20, y: -20))
    #expect(state.gazeX == 1)
    #expect(state.gazeY == -1)
    #expect(state.parallaxX == 7)
    #expect(state.parallaxY == -7)
}

@Test func envelopesStayInRange() {
    let engine = LivingPortraitMotionEngine(scene: fixtureScene())
    for tick in 0...8_000 {
        let state = engine.state(atMilliseconds: Int64(tick * 25))
        #expect((0...1).contains(state.blink))
        #expect((0...1).contains(state.reaction))
        #expect(state.breath >= 1)
        #expect(state.characterScale >= 1)
    }
}

@Test func reactionOnlyOccursForAnAuthoredEvent() {
    let scene = fixtureScene()
    let engine = LivingPortraitMotionEngine(scene: scene)
    #expect(engine.state(atMilliseconds: 1_000).reaction == 0)
    let event = LivingPortraitEvent(
        id: "tap-1",
        type: "host.tap",
        startMilliseconds: 800,
        durationMilliseconds: 1_000,
        intensity: 0.7
    )
    let active = engine.state(atMilliseconds: 1_100, reactionEvents: [event])
    #expect(active.reaction > 0)
    #expect(active.reaction <= 0.7)
    #expect(engine.state(atMilliseconds: 2_000, reactionEvents: [event]).reaction == 0)
}

@Test func sharedClockTriggersEventAtTheHostEpoch() {
    let clock = LivingPortraitClock(epoch: Date(timeIntervalSinceReferenceDate: 1_000))
    let triggeredAt = Date(timeIntervalSinceReferenceDate: 1_017.5)
    let event = clock.event(
        id: "host-1",
        type: "host.cue",
        triggeredAt: triggeredAt,
        durationMilliseconds: 1_000,
        intensity: 0.8
    )

    #expect(event.startMilliseconds == 17_500)
    let activeMilliseconds = clock.milliseconds(at: Date(timeIntervalSinceReferenceDate: 1_018))
    let active = LivingPortraitMotionEngine(scene: fixtureScene()).state(
        atMilliseconds: activeMilliseconds,
        reactionEvents: [event]
    )
    #expect(abs(active.reaction - 0.8) <= 0.000_001)
}

@Test func zeroWindDisablesWindTransform() {
    let engine = LivingPortraitMotionEngine(scene: fixtureScene())
    for tick in 0...200 {
        let state = engine.state(atMilliseconds: Int64(tick * 100), windIntensity: 0)
        #expect(state.windX == 0)
        #expect(state.windY == 0)
        #expect(state.windRotationDegrees == 0)
    }
}

@Test func strictLayerBundleRequiresDecodableSameCanvasImagesAndProvidesFallback() throws {
    let onePixel = try png(width: 1, height: 1)
    let scene = LivingPortraitScene(
        id: "mare.current",
        seed: "20260816",
        layers: [
            .init(id: "background", role: .background, asset: "background.png", zIndex: 0),
            .init(id: "character", role: .character, asset: "character.png", zIndex: 10),
            .init(id: "blink", role: .blink, asset: "blink.png", zIndex: 20),
            .init(id: "wind", role: .wind, asset: "wind.png", zIndex: 30),
            .init(id: "reaction", role: .reaction, asset: "reaction.png", zIndex: 40),
        ],
        fallbackAsset: "fallback.png"
    )
    var files = Dictionary(uniqueKeysWithValues: (scene.layers.map(\.asset) + ["fallback.png"]).map {
        ($0, onePixel)
    })

    let validated = try LivingPortraitLayerBundleValidator.validate(scene: scene, files: files)
    let bundle = try #require(validated)
    #expect(bundle.canvas == .init(width: 1, height: 1))
    #expect(bundle.fallback.path == "fallback.png")
    #expect(bundle.blink?.path == "blink.png")

    files["reaction.png"] = try png(width: 2, height: 1)
    #expect(throws: LivingPortraitLayerBundleError.canvasMismatch) {
        try LivingPortraitLayerBundleValidator.validate(scene: scene, files: files)
    }
}

@Test func strictLayerBundleRejectsDuplicateOrMissingAssets() throws {
    let image = try png(width: 1, height: 1)
    var scene = LivingPortraitScene(
        id: "mono.current",
        seed: "7",
        layers: [
            .init(id: "background", role: .background, asset: "background.png", zIndex: 0),
            .init(id: "character", role: .character, asset: "character.png", zIndex: 10),
        ],
        fallbackAsset: "fallback.png"
    )
    #expect(throws: LivingPortraitLayerBundleError.missingAsset("fallback.png")) {
        try LivingPortraitLayerBundleValidator.validate(
            scene: scene,
            files: ["background.png": image, "character.png": image]
        )
    }

    scene.fallbackAsset = "character.png"
    #expect(throws: LivingPortraitLayerBundleError.duplicateAssetReference) {
        try LivingPortraitLayerBundleValidator.validate(
            scene: scene,
            files: ["background.png": image, "character.png": image]
        )
    }
}

private func fixtureScene() -> LivingPortraitScene {
    LivingPortraitScene(
        id: "test",
        seed: "424242",
        layers: [
            .init(id: "bg", role: .background, asset: "background", zIndex: 0),
            .init(id: "body", role: .character, asset: "character", zIndex: 10),
        ]
    )
}

private struct ConformanceFixture: Decodable {
    struct TestCase: Decodable {
        struct Expected: Decodable {
            let blink: Double
            let breath: Double
            let gazeX: Double
            let gazeY: Double
            let windX: Double
            let reaction: Double
        }

        let milliseconds: Int64
        let windIntensity: Double
        let events: [LivingPortraitEvent]
        let reduceMotion: Bool
        let expected: Expected
    }

    let contractVersion: Int
    let tolerance: Double
    let scene: LivingPortraitScene
    let cases: [TestCase]
}

private func expectNear(
    _ actual: Double,
    _ expected: Double,
    tolerance: Double,
    field: String,
    milliseconds: Int64
) {
    #expect(
        abs(actual - expected) <= tolerance,
        "\(field) at \(milliseconds) ms: expected \(expected), got \(actual)"
    )
}

private func expectDecodingFailure(_ mutate: (inout LivingPortraitScene) -> Void) throws {
    var scene = fixtureScene()
    mutate(&scene)
    let data = try JSONEncoder().encode(scene)
    #expect(throws: LivingPortraitValidationError.self) {
        try JSONDecoder().decode(LivingPortraitScene.self, from: data)
    }
}

private func png(width: Int, height: Int) throws -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = width * 4
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}
