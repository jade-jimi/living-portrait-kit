import LivingPortraitCore
import SwiftUI

/// Native SwiftUI renderer for the platform-neutral scene and motion contract.
public struct LivingPortraitStage<LayerContent: View>: View {
    public typealias LayerResolver = (LivingPortraitScene.Layer, LivingPortraitMotionState) -> LayerContent

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private let scene: LivingPortraitScene
    private let focus: PortraitFocus?
    private let windIntensity: Double
    private let reactionEvents: [LivingPortraitEvent]
    private let framesPerSecond: Double
    private let layerResolver: LayerResolver

    public init(
        scene: LivingPortraitScene,
        focus: PortraitFocus? = nil,
        windIntensity: Double = 1,
        reactionEvents: [LivingPortraitEvent] = [],
        framesPerSecond: Double = 30,
        @ViewBuilder layer: @escaping LayerResolver
    ) {
        self.scene = scene
        self.focus = focus
        self.windIntensity = windIntensity
        self.reactionEvents = reactionEvents
        self.framesPerSecond = min(max(framesPerSecond, 1), 60)
        self.layerResolver = layer
    }

    public var body: some View {
        RunningPortraitStage(
            scene: scene,
            focus: focus,
            windIntensity: windIntensity,
            reactionEvents: reactionEvents,
            framesPerSecond: framesPerSecond,
            reduceMotion: accessibilityReduceMotion,
            layerResolver: layerResolver
        )
    }
}

private struct RunningPortraitStage<LayerContent: View>: View {
    let scene: LivingPortraitScene
    let focus: PortraitFocus?
    let windIntensity: Double
    let reactionEvents: [LivingPortraitEvent]
    let framesPerSecond: Double
    let reduceMotion: Bool
    let layerResolver: LivingPortraitStage<LayerContent>.LayerResolver

    @State private var activationDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / framesPerSecond, paused: reduceMotion)) { timeline in
            let milliseconds = max(0, Int64(timeline.date.timeIntervalSince(activationDate) * 1_000))
            let state = LivingPortraitMotionEngine(scene: scene).state(
                atMilliseconds: milliseconds,
                focus: focus,
                windIntensity: windIntensity,
                reactionEvents: reactionEvents,
                reduceMotion: reduceMotion
            )

            ZStack {
                ForEach(scene.layers.sorted(by: layerOrder)) { layer in
                    rendered(layer, state: state)
                        .zIndex(Double(layer.zIndex))
                }
            }
            .clipped()
        }
    }

    @ViewBuilder
    private func rendered(_ layer: LivingPortraitScene.Layer, state: LivingPortraitMotionState) -> some View {
        let content = layerResolver(layer, state)
        switch layer.role {
        case .background:
            content.offset(x: -state.parallaxX * 0.32, y: -state.parallaxY * 0.32)
        case .character:
            content
                .scaleEffect(state.characterScale, anchor: .bottom)
                .offset(x: state.parallaxX, y: state.parallaxY)
        case .blink:
            content
                .opacity(state.blink)
                .offset(x: state.parallaxX, y: state.parallaxY)
        case .wind:
            content
                .offset(x: state.parallaxX + state.windX, y: state.parallaxY + state.windY)
                .rotationEffect(.degrees(state.windRotationDegrees), anchor: .bottom)
        case .reaction:
            content
                .opacity(state.reaction)
                .offset(x: state.parallaxX, y: state.parallaxY)
        }
    }

    private func layerOrder(_ lhs: LivingPortraitScene.Layer, _ rhs: LivingPortraitScene.Layer) -> Bool {
        if lhs.zIndex == rhs.zIndex { return lhs.id < rhs.id }
        return lhs.zIndex < rhs.zIndex
    }
}
