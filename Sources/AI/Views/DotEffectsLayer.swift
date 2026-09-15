import SwiftUI
import Vortex

/// Particle bursts for everything that happens to a dot — eating a
/// collectible, absorbing a rival, the level-up pop (§ new — "make the
/// dynamic style effect of eating other dots etc much better").
///
/// Built on Vortex (https://github.com/twostraws/Vortex, MIT), a SwiftUI
/// particle system. It sits as an overlay *above* the game's `Canvas` rather
/// than inside it: Vortex renders real SwiftUI views as particles, which the
/// immediate-mode `GraphicsContext` the rest of the game draws into cannot
/// host.
///
/// The layer is driven entirely by `GameEngine.absorbEffects`. The engine
/// already appends one entry per absorption with the world position, the
/// colour of whatever was eaten and its radius, so nothing new had to be
/// published for this — the burst is a second, richer reading of an event
/// the game was already broadcasting.
struct DotEffectsLayer: View {
    @ObservedObject var engine: GameEngine
    @ObservedObject var player: PlayerState
    let screenSize: CGSize

    @State private var system = DotEffectsLayer.makeBurstSystem()
    /// Guards against re-firing for an absorption already burst: `onChange`
    /// fires on any count change, including the cleanup that removes expired
    /// effects.
    @State private var lastBurstID: UUID?

    var body: some View {
        VortexViewReader { proxy in
            VortexView(system) {
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .blur(radius: 1)
                    .tag("spark")

                Circle()
                    .fill(.white)
                    .frame(width: 6, height: 6)
                    .tag("dust")
            }
            .allowsHitTesting(false)
            .onChange(of: engine.absorbEffects.count) { _ in
                guard let effect = engine.absorbEffects.last,
                      effect.id != lastBurstID,
                      screenSize.width > 0, screenSize.height > 0 else { return }
                lastBurstID = effect.id

                // The camera is simply the player centred on screen (see
                // `WhiteSpaceView.draw`), so world → screen is this subtraction.
                let screenX = effect.startPosition.x - player.position.x + screenSize.width / 2
                let screenY = effect.startPosition.y - player.position.y + screenSize.height / 2
                let unitX = Double(screenX / screenSize.width)
                let unitY = Double(screenY / screenSize.height)

                // Anything well off-screen isn't worth spawning particles for.
                guard (-0.15...1.15).contains(unitX), (-0.15...1.15).contains(unitY) else { return }

                // VortexSystem.ColorMode is Codable, so it carries Vortex's
                // OWN Color struct — not SwiftUI's, which isn't Codable.
                // Handing it a SwiftUI Color does not compile.
                //
                // AbsorbEffect already stores plain r/g/b doubles, so this
                // converts directly with no UIColor round-trip.
                let c = effect.color
                func lighten(_ amount: Double) -> VortexSystem.Color {
                    VortexSystem.Color(red: min(1, c.r + amount),
                                       green: min(1, c.g + amount),
                                       blue: min(1, c.b + amount))
                }
                system.position = [unitX, unitY]
                system.colors = .random(lighten(0), lighten(0.3), lighten(0.65))

                // A rival twice the size of a collectible should visibly read
                // as a bigger event, so count, spread and scale all follow
                // `magnitude` — the radius of whatever was eaten.
                // Explicitly Double: magnitude is a CGFloat, and every Vortex
                // property here is a Double. Swift will bridge the two, but
                // spelling it out keeps the arithmetic unambiguous.
                let scale = min(2.4, max(0.55, Double(effect.magnitude) / 13))
                system.burstCount = Int(14 * scale)
                system.size = 0.35 * scale
                system.speed = 0.6 * scale

                proxy.burst()
            }
        }
    }

    /// Configured for on-demand bursts only: `birthRate` of zero means
    /// nothing emits until `proxy.burst()` is called, so an idle game costs
    /// nothing.
    private static func makeBurstSystem() -> VortexSystem {
        let system = VortexSystem(tags: ["spark", "dust"])
        system.position = [0.5, 0.5]
        system.birthRate = 0
        system.burstCount = 16
        system.lifespan = 0.65
        system.speed = 0.7
        system.speedVariation = 0.5
        system.angle = .degrees(0)
        system.angleRange = .degrees(360)
        system.size = 0.4
        system.sizeVariation = 0.5
        // Fade and shrink out rather than blinking away at end of life.
        system.sizeMultiplierAtDeath = 0.1
        return system
    }
}
