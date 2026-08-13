import Foundation
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

@Test func zeroWindDisablesWindTransform() {
    let engine = LivingPortraitMotionEngine(scene: fixtureScene())
    for tick in 0...200 {
        let state = engine.state(atMilliseconds: Int64(tick * 100), windIntensity: 0)
        #expect(state.windX == 0)
        #expect(state.windY == 0)
        #expect(state.windRotationDegrees == 0)
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
