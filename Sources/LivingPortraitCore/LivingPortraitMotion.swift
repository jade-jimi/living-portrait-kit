import Foundation

public struct PortraitFocus: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x.clamped(to: -1...1)
        self.y = y.clamped(to: -1...1)
    }

    public static let center = PortraitFocus(x: 0, y: 0)
}

public struct LivingPortraitMotionState: Codable, Sendable, Equatable {
    public var blink: Double
    public var breath: Double
    public var gazeX: Double
    public var gazeY: Double
    public var parallaxX: Double
    public var parallaxY: Double
    public var windX: Double
    public var windY: Double
    public var windRotationDegrees: Double
    public var reaction: Double
    public var characterScale: Double

    public init(
        blink: Double = 0,
        breath: Double = 1,
        gazeX: Double = 0,
        gazeY: Double = 0,
        parallaxX: Double = 0,
        parallaxY: Double = 0,
        windX: Double = 0,
        windY: Double = 0,
        windRotationDegrees: Double = 0,
        reaction: Double = 0,
        characterScale: Double = 1
    ) {
        self.blink = blink
        self.breath = breath
        self.gazeX = gazeX
        self.gazeY = gazeY
        self.parallaxX = parallaxX
        self.parallaxY = parallaxY
        self.windX = windX
        self.windY = windY
        self.windRotationDegrees = windRotationDegrees
        self.reaction = reaction
        self.characterScale = characterScale
    }

    public static let still = LivingPortraitMotionState()
}

/// Deterministic reference evaluator for schema version 1.
/// Other renderers must match the bundled fixtures within `1e-6`.
public struct LivingPortraitMotionEngine: Sendable {
    public var scene: LivingPortraitScene

    public init(scene: LivingPortraitScene) {
        self.scene = scene
    }

    public func state(
        atMilliseconds elapsedMilliseconds: Int64,
        focus: PortraitFocus? = nil,
        windIntensity: Double = 1,
        reactionEvents: [LivingPortraitEvent] = [],
        reduceMotion: Bool = false
    ) -> LivingPortraitMotionState {
        guard !reduceMotion else { return .still }
        let milliseconds = max(0, elapsedMilliseconds)
        let motion = scene.motion
        let resolvedFocus = focus ?? ambientFocus(at: milliseconds)
        let reaction = reactionEvents.reduce(0) { current, event in
            max(current, authoredEventEnvelope(at: milliseconds, event: event))
        }
        let breathPhase = Double(milliseconds % motion.breathPeriodMilliseconds) / Double(motion.breathPeriodMilliseconds)
        let breath = 1 + motion.breathScale * ((sin(breathPhase * .pi * 2 - .pi / 2) + 1) / 2)
        let windPhase = Double(milliseconds % motion.windPeriodMilliseconds) / Double(motion.windPeriodMilliseconds) * .pi * 2
        let windWave = sin(windPhase) * 0.72 + sin(windPhase * 0.47 + 1.3) * 0.28
        let intensity = windIntensity.clamped(to: 0...1.5)

        return LivingPortraitMotionState(
            blink: eventEnvelope(
                at: milliseconds,
                slot: motion.blinkSlotMilliseconds,
                duration: motion.blinkDurationMilliseconds,
                probability: motion.blinkProbability,
                salt: 0xB11C_0001
            ),
            breath: breath,
            gazeX: resolvedFocus.x,
            gazeY: resolvedFocus.y,
            parallaxX: resolvedFocus.x * motion.parallaxUnits,
            parallaxY: resolvedFocus.y * motion.parallaxUnits,
            windX: windWave * motion.windUnits * intensity,
            windY: abs(windWave) * motion.windUnits * 0.18 * intensity,
            windRotationDegrees: windWave * motion.windRotationDegrees * intensity,
            reaction: reaction,
            characterScale: breath + reaction * motion.reactionScale
        )
    }

    private func ambientFocus(at milliseconds: Int64) -> PortraitFocus {
        let period = scene.motion.gazePeriodMilliseconds
        let index = milliseconds / period
        let fraction = Double(milliseconds % period) / Double(period)
        let eased = smoothstep(fraction)
        return PortraitFocus(
            x: lerp(signedRandom(index, 0x6A2E_0001), signedRandom(index + 1, 0x6A2E_0001), eased) * 0.34,
            y: lerp(signedRandom(index, 0x6A2E_0002), signedRandom(index + 1, 0x6A2E_0002), eased) * 0.18
        )
    }

    private func eventEnvelope(
        at milliseconds: Int64,
        slot: Int64,
        duration: Int64,
        probability: Double,
        salt: UInt64
    ) -> Double {
        let index = milliseconds / slot
        guard random(index, salt) < probability else { return 0 }
        let available = max(0, slot - duration)
        let start = Int64(random(index, salt &+ 1) * Double(available))
        let local = milliseconds - index * slot - start
        guard local >= 0, local <= duration else { return 0 }
        let progress = Double(local) / Double(duration)
        if progress < 0.38 { return smoothstep(progress / 0.38) }
        return 1 - smoothstep((progress - 0.38) / 0.62)
    }

    private func authoredEventEnvelope(at milliseconds: Int64, event: LivingPortraitEvent) -> Double {
        let local = milliseconds - event.startMilliseconds
        guard local >= 0, local <= event.durationMilliseconds else { return 0 }
        let progress = Double(local) / Double(event.durationMilliseconds)
        let envelope: Double
        if progress < 0.18 {
            envelope = smoothstep(progress / 0.18)
        } else if progress > 0.65 {
            envelope = 1 - smoothstep((progress - 0.65) / 0.35)
        } else {
            envelope = 1
        }
        return envelope * event.intensity
    }

    private func random(_ index: Int64, _ salt: UInt64) -> Double {
        var value = UInt64(bitPattern: index) &+ scene.numericSeed &+ salt &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }

    private func signedRandom(_ index: Int64, _ salt: UInt64) -> Double {
        random(index, salt) * 2 - 1
    }
}

private func smoothstep(_ value: Double) -> Double {
    let t = value.clamped(to: 0...1)
    return t * t * (3 - 2 * t)
}

private func lerp(_ start: Double, _ end: Double, _ progress: Double) -> Double {
    start + (end - start) * progress
}
