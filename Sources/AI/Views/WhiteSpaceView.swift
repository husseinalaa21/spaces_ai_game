import SwiftUI

/// One past position of the player, timestamped so the trail can fade and
/// expire samples purely by age instead of counting frames.
private struct TrailSample {
    let position: CGPoint
    let time: Date
}

/// A short burst of little sparkle glyphs flying outward and fading, dropped
/// behind the level-up and form-complete banners (§ new — a milestone should
/// feel like a small celebration, not just a card holding still on screen).
/// Uses the "Sparkle" template image asset so it tints to whatever color the
/// moment calls for (the finished form's own color, or gold for a level-up).
private struct SparkleBurst: View {
    let color: Color
    @State private var progress: CGFloat = 0

    // Fixed, hand-placed angles/distances/sizes/delays rather than true
    // randomness, so the burst looks the same (deliberate, not jittery)
    // every time it plays.
    private let sparkles: [(angle: Double, distance: CGFloat, size: CGFloat, delay: Double)] = [
        (18, 62, 15, 0.00), (63, 76, 10, 0.06), (100, 54, 13, 0.02),
        (146, 70, 9, 0.09), (198, 64, 14, 0.03), (242, 74, 10, 0.07),
        (284, 58, 13, 0.01), (330, 68, 11, 0.08)
    ]

    var body: some View {
        ZStack {
            ForEach(sparkles.indices, id: \.self) { i in
                let s = sparkles[i]
                let local = max(0, min(1, (progress - CGFloat(s.delay)) / (1 - CGFloat(s.delay))))
                let eased = 1 - pow(1 - local, 2)
                Image("Sparkle")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: s.size, height: s.size)
                    .foregroundColor(color)
                    .opacity(Double(1 - local) * 0.95)
                    .scaleEffect(0.3 + 0.9 * local)
                    .rotationEffect(.degrees(Double(local) * 50))
                    .offset(x: cos(s.angle * .pi / 180) * s.distance * eased,
                            y: sin(s.angle * .pi / 180) * s.distance * eased)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                progress = 1
            }
        }
    }
}

/// The main White Space screen: the huge world, the player's dot, collectibles,
/// movement, and the minimal HUD. Fills the entire phone screen edge-to-edge
/// (§41: "avoid huge bars, large opaque panels, clutter").
struct WhiteSpaceView: View {
    @ObservedObject var engine: GameEngine
    @ObservedObject var player: PlayerState
    /// Returns to the main menu — the quit button, and automatically once
    /// the round timer runs out (in `.final` mode) or the player gets eaten.
    let onQuit: () -> Void
    /// Called instead of `onQuit` when a `.practice`-mode round's short timer
    /// runs out (§ new two-phase Play flow) — `RootView` uses this to start
    /// the real `.final` round rather than sending the player back to the menu.
    var onRoundComplete: () -> Void = {}
    @State private var dragStart: CGPoint? = nil
    @State private var lastTick: Date = Date()
    @State private var showingCollection = false
    @State private var showingSettings = false

    // Smoothed squash-and-stretch state for the player dot — updated every
    // frame in lockstep with `engine.tick`, read (unsmoothed math kept out of
    // `draw`) by `DotRenderer.drawPlayer`.
    @State private var stretchAmount: Double = 0
    @State private var stretchVelocity: Double = 0
    @State private var stretchAngleRadians: Double = 0

    // A smoothed, spring-eased look direction (§ user feedback: "let the dot
    // move as connect to the part of the dot so when dot moves somewhere the
    // eye will move with it") — the eyes ease toward wherever the player is
    // currently heading instead of snapping there instantly, the same
    // underdamped-spring feel `updateStretch` already gives the body, so the
    // eyes read as an actually-attached part of the dot reacting to its own
    // motion rather than a separately-driven overlay.
    @State private var smoothedLook: CGVector = .zero
    @State private var lookVelocity: CGVector = .zero

    // A smoothed, slightly underdamped spring toward `player.size` (see
    // `updateGrowth`) — used only for what actually gets drawn, never for
    // gameplay math — so a bite pops the dot with a satisfying little
    // overshoot-then-settle bounce instead of it just snapping instantly to
    // its new size (§ user feedback: "the animation of eating... should be
    // better"). Starts at 0 as a sentinel meaning "not yet initialized",
    // since `player.size` isn't known until the first frame.
    @State private var displaySize: CGFloat = 0
    @State private var growthVelocity: Double = 0

    // A short fading wake of past positions, laid down only while actually
    // moving, so fast travel reads as a liquid streak rather than a dot
    // teleporting frame to frame.
    @State private var trailSamples: [TrailSample] = []
    private static let trailDuration: Double = 0.22

    // Drives the ability button's "ready" pulse — a single continuously
    // looping animation (started once in .onAppear) rather than a per-frame
    // timer, since the button only needs to breathe, not track exact time.
    @State private var abilityPulseOn = false

    var body: some View {
        GeometryReader { geo in
            let screenSize = geo.size
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    draw(context: &context, size: size, screenSize: screenSize)
                }
                .onChange(of: timeline.date) { newDate in
                    let dt = newDate.timeIntervalSince(lastTick)
                    lastTick = newDate
                    engine.tick(dt: dt)
                    updateStretch(dt: dt)
                    updateLook(dt: dt)
                    updateGrowth(dt: dt)
                    updateTrail()
                }
            }
            .background(currentPalette.background)
            .contentShape(Rectangle())
            .gesture(dragGesture(screenSize: screenSize))
            .overlay(alignment: .top) { hud }
            .overlay(alignment: .topLeading) { quitButton }
            .overlay(alignment: .topTrailing) { minimap }
            .overlay(alignment: .bottom) { timerBadge }
            .overlay(alignment: .bottom) { controls }
            .overlay { formCompleteOverlay }
            .overlay { levelUpOverlay }
            .overlay { roundExpiredOverlay }
            .overlay { eliminatedOverlay }
            .overlay(alignment: .top) { signalBanner }
            .overlay(alignment: .top) { comboBanner }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingCollection) {
            CollectionView(player: player)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(player: player)
        }
        .onAppear { AudioManager.shared.startMusic("ambient") }
        .onDisappear { AudioManager.shared.stopMusic() }
    }

    /// The final round (§ new two-phase Play flow) always shows its own
    /// distinct look — `WorldBackground.finalUniverse` — instead of whatever
    /// Universe the player has cosmetically picked, so stepping into it after
    /// the practice room actually reads as arriving somewhere new. The
    /// practice room (and this same view when reused elsewhere) still shows
    /// the player's own pick.
    private var currentPalette: WorldBackground.Palette {
        engine.roundMode == .final ? WorldBackground.finalUniverse : WorldBackground.palette(for: player.profile.selectedUniverse)
    }

    // MARK: - Drawing

    private func draw(context: inout GraphicsContext, size: CGSize, screenSize: CGSize) {
        let camera = CGPoint(x: player.position.x - screenSize.width / 2,
                              y: player.position.y - screenSize.height / 2)
        let t = Date().timeIntervalSinceReferenceDate

        // The player's actually-rendered radius — a smoothed, slightly
        // underdamped spring toward `player.size` (see `updateGrowth`)
        // instead of just drawing `player.size` directly, so growing from a
        // bite pops with a satisfying little overshoot-then-settle bounce
        // rather than snapping instantly to the new size (§ user feedback:
        // "the animation of eating either users or icons should be better").
        // Every visual below that used to read `player.size` reads this
        // instead, so the ripple/flash/trail all stay sized to match what's
        // actually on screen.
        let renderSize = displaySize > 0 ? displaySize : player.size

        func toScreen(_ world: CGPoint) -> CGPoint {
            CGPoint(x: world.x - camera.x, y: world.y - camera.y)
        }

        // Window-pane grid, anchored to world space so it scrolls with the player
        // instead of sitting fixed on screen — same look as the app's dot logo.
        // Which palette depends on the player's chosen Universe (free White,
        // or an AI+ re-skin picked on the main menu) — same grid, same world
        // — except the final room, which always shows its own distinct
        // Nebulous.io-style look (`currentPalette` below) regardless of that
        // cosmetic pick, since it's meant to read as a real place change.
        WorldBackground.draw(context, screenSize: screenSize, cameraOffset: camera,
                              palette: currentPalette,
                              reduceMotion: player.profile.reduceMotion)

        // Ambient wanderers (drawn faint/behind everything else).
        for w in engine.wanderers {
            let p = toScreen(w.position)
            guard isOnScreen(p, size: screenSize, margin: 40) else { continue }
            DotRenderer.draw(context, center: p, radius: w.radius, color: w.tint.color.opacity(0.55))
        }

        // Simulated AI "rival" dots (§ new two-phase Play flow) — read as
        // other players sharing the space, each foraging on its own. Only
        // once `engine.roundMode == .final` does touching one actually risk
        // anything (`GameEngine.checkPlayerRivalCollisions`) — drawn exactly
        // the same way either room, so nothing visually telegraphs that
        // switch besides the size difference that's already grown by then.
        for rival in engine.rivals {
            let p = toScreen(rival.position)
            guard isOnScreen(p, size: screenSize, margin: 60) else { continue }
            let rivalLook = CGVector(dx: 0, dy: sin(t * 0.6 + Double(rival.position.x) * 0.001) * 0.4)
            DotRenderer.drawPlayer(context, center: p, radius: rival.radius, color: rival.tint.color,
                                    stretch: 0, angle: .zero, lookDirection: rivalLook, time: t,
                                    eyeStyle: .whiteOnly, reduceMotion: player.profile.reduceMotion,
                                    dotStyle: .classic, showGroundShadow: false)
            drawNameLabel(context, name: rival.username, at: p, belowRadius: rival.radius)
        }

        // Signal marker.
        if let signal = engine.activeSignal {
            let p = toScreen(signal.position)
            if isOnScreen(p, size: screenSize, margin: 80) {
                let pulse = CGFloat(1.0 + 0.15 * sin(Date().timeIntervalSinceReferenceDate * 3))
                let r: CGFloat = 30 * pulse
                context.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                with: .color(.blue.opacity(0.6)), lineWidth: 2)
            }
        }

        // Collectibles — freshly spawned ones pop in with a small overshoot
        // instead of just appearing instantly, using the spawn timestamp
        // that was already being tracked but never used for anything visual.
        // Every item also gets a gentle idle bob + wiggle (deterministic
        // per-item phase from its world position, so a whole field of them
        // doesn't blink in lockstep) — reads as a scattered little cluster of
        // living things rather than static icons stamped on the grid.
        for c in engine.collectibles {
            let p = toScreen(c.position)
            guard isOnScreen(p, size: screenSize, margin: 40) else { continue }
            // The final universe's plain filler pellets (§ user feedback:
            // "they will eat small blue dots") have no icon glyph to carry
            // their visibility — everything else does, via the emoji drawn
            // on top below, which is why a normal icon's backing circle can
            // get away with being a faint 0.18-opacity tint. An orb needs to
            // actually read as "a small blue dot" on its own: smaller than a
            // full icon and drawn at near-full opacity instead.
            let isOrb = c.definition.icon.isEmpty
            let radius: CGFloat = isOrb ? 7 : 13
            let isRare = c.definition.rarity >= .rare
            let wobble = t * 4 + Double(p.x)
            let pulse: CGFloat = (isRare && !player.profile.reduceMotion) ? CGFloat(1.0 + 0.08 * sin(wobble)) : 1.0

            let popAge = t - c.spawnedAt.timeIntervalSinceReferenceDate
            let popT = min(1, max(0, popAge / 0.28))
            let popScale = max(0, easeOutBack(popT))
            let popOpacity = min(1, popT * 2.5)

            let seed = Double(c.position.x) * 0.013 + Double(c.position.y) * 0.021
            let idleT = t * 1.8 + seed
            let bobOffset: CGFloat = player.profile.reduceMotion ? 0 : CGFloat(sin(idleT) * 2.2)
            let wiggleAngle: Angle = player.profile.reduceMotion ? .zero : Angle(radians: sin(idleT * 0.7 + seed) * 0.12)
            let bobbedP = CGPoint(x: p.x, y: p.y + bobOffset)

            var popContext = context
            popContext.opacity = popOpacity

            // A soft blurred glow behind rare+ items — bigger and breathier
            // than the flat backing circle every collectible gets, so rarity
            // reads as "glowing" rather than just "slightly bigger dot".
            // Still no ring/border/outline anywhere.
            if isRare {
                var glowContext = popContext
                glowContext.opacity = popOpacity * 0.5
                glowContext.addFilter(.blur(radius: radius * 0.9))
                let glowRadius = radius * 2.2 * pulse * CGFloat(popScale)
                glowContext.fill(
                    Path(ellipseIn: CGRect(x: bobbedP.x - glowRadius, y: bobbedP.y - glowRadius,
                                            width: glowRadius * 2, height: glowRadius * 2)),
                    with: .color(c.definition.primaryColor.color)
                )
            }

            // No ring/border — every collectible is a plain dot (rarity still
            // reads through color, glow, and the rare+ pulse, not an outline).
            DotRenderer.draw(popContext, center: bobbedP, radius: radius * pulse * CGFloat(popScale),
                              color: c.definition.primaryColor.color.opacity(isOrb ? 0.92 : 0.18))

            var textContext = popContext
            textContext.translateBy(x: bobbedP.x, y: bobbedP.y)
            textContext.rotate(by: wiggleAngle)
            textContext.draw(Text(c.definition.icon).font(.system(size: CGFloat(16 * popScale))), at: .zero)

            // Epic+ items get a couple of tiny sparkles orbiting the icon —
            // one more visible step up from "rare" (which only gets the
            // glow above), so the top rarity tiers read as distinctly more
            // special the higher they go, still with zero rings/outlines.
            if c.definition.rarity >= .epic, !player.profile.reduceMotion {
                let sparkleCount = c.definition.rarity >= .mythic ? 4 : (c.definition.rarity >= .legendary ? 3 : 2)
                let orbitRadius = radius * 2.0 * CGFloat(popScale)
                var sparkleContext = popContext
                sparkleContext.addFilter(.blur(radius: 0.6))
                for i in 0..<sparkleCount {
                    let orbitAngle = idleT * 1.6 + seed * 3 + (Double(i) / Double(sparkleCount)) * 2 * .pi
                    let sparklePoint = CGPoint(
                        x: bobbedP.x + CGFloat(cos(orbitAngle)) * orbitRadius,
                        y: bobbedP.y + CGFloat(sin(orbitAngle)) * orbitRadius * 0.7
                    )
                    let twinkle = 0.4 + 0.6 * max(0, sin(idleT * 3 + Double(i) * 1.7 + seed))
                    var starContext = sparkleContext
                    starContext.opacity = popOpacity * twinkle
                    let starRadius: CGFloat = 1.6
                    starContext.fill(
                        Path(ellipseIn: CGRect(x: sparklePoint.x - starRadius, y: sparklePoint.y - starRadius,
                                                width: starRadius * 2, height: starRadius * 2)),
                        with: .color(.white)
                    )
                }
            }
        }

        // Absorb "liquid" effects — the eaten collectible's color flows from
        // where it was eaten toward the (moving) player as a stretched
        // droplet with a short trailing stream behind it, rounding out into
        // a plain drop and bursting into a ripple right as it merges in.
        // Drawn before the player/aura so the merge reads as flowing *into*
        // the dot, and feeds a brief color flash onto the player on arrival
        // (below) so eating something visibly "adds" that color and power.
        var arrivalFlashColor: Color? = nil
        var arrivalFlashAmount: Double = 0

        for effect in engine.absorbEffects {
            let elapsed = Date().timeIntervalSince(effect.startedAt)
            let progress = min(1, max(0, elapsed / AbsorbEffect.duration))

            func worldPosition(atProgress p: Double) -> CGPoint {
                let eased = 1 - pow(1 - p, 3)
                return CGPoint(
                    x: effect.startPosition.x + (player.position.x - effect.startPosition.x) * CGFloat(eased),
                    y: effect.startPosition.y + (player.position.y - effect.startPosition.y) * CGFloat(eased)
                )
            }

            let dx = Double(player.position.x - effect.startPosition.x)
            let dy = Double(player.position.y - effect.startPosition.y)
            let travelAngle = Angle(radians: dx == 0 && dy == 0 ? 0 : atan2(dy, dx))
            let fade = 1 - pow(progress, 4)

            // Speed along the ease-out curve — fast at the start, slowing
            // into the merge — drives how drawn-out the droplet's tail looks,
            // so it visibly rounds into a plain drop right as it lands.
            let speed = 3 * pow(1 - progress, 2)
            let elongation = min(1, speed)

            // A short trailing stream of smaller, fainter droplets sampled a
            // touch earlier along the same path — reads as a continuous flow
            // rather than one shape teleporting along a line.
            for step in stride(from: 3, through: 0, by: -1) {
                let stepProgress = max(0, progress - Double(step) * 0.05)
                let p = toScreen(worldPosition(atProgress: stepProgress))
                guard isOnScreen(p, size: screenSize, margin: 60) else { continue }

                let isLead = step == 0
                let stepShrink: CGFloat = isLead ? 1 : CGFloat(1 - Double(step) * 0.22)
                let stepFade = isLead ? fade : fade * (0.5 - Double(step) * 0.13)
                guard stepFade > 0.01 else { continue }

                var dropContext = context
                dropContext.opacity = max(0, min(1, stepFade))
                dropContext.translateBy(x: p.x, y: p.y)
                dropContext.rotate(by: travelAngle)
                let dropRadius: CGFloat = 7 * stepShrink * min(1.7, max(0.8, effect.magnitude / 13))
                let dropElongation = isLead ? CGFloat(elongation) : CGFloat(elongation) * 0.6
                dropContext.fill(DotRenderer.liquidDropletPath(radius: dropRadius, elongation: dropElongation),
                                  with: .color(effect.color.color))
            }

            // Right as it merges in: a quick outward ripple in the eaten
            // item's own color, plus a bump that flashes that color onto the
            // player itself (applied once, after the loop, using whichever
            // effect is peaking hardest right now).
            if progress > 0.7 {
                let arrivalT = min(1, (progress - 0.7) / 0.3)
                let playerScreenPos = toScreen(player.position)
                // Everything below scales with roughly how big whatever got
                // eaten was (`effect.magnitude`) — a plain icon (13) gives
                // the same modest splash as before, but a big rival dot
                // visibly bursts into a much bigger one, so "eating another
                // dot" reads as the bigger event it actually is.
                let splashScale = max(0.8, min(2.4, effect.magnitude / 13))
                let rippleRadius = renderSize + 4 + CGFloat(arrivalT) * 22 * splashScale
                let rippleFade = 1 - arrivalT
                context.stroke(
                    Path(ellipseIn: CGRect(x: playerScreenPos.x - rippleRadius, y: playerScreenPos.y - rippleRadius,
                                            width: rippleRadius * 2, height: rippleRadius * 2)),
                    with: .color(effect.color.color.opacity(0.4 * rippleFade)), lineWidth: 2.5 * min(1.6, splashScale)
                )

                // A handful of tiny droplets scattering outward alongside the
                // ripple — a proper little splash rather than just a ring.
                // The spread angle is derived from the effect's own start
                // position (deterministic, so it doesn't flicker frame to
                // frame) instead of true randomness. A bigger eat also throws
                // a couple more particles, further out, than a small one.
                let baseAngle = atan2(Double(effect.startPosition.y), Double(effect.startPosition.x))
                let particleCount = splashScale > 1.4 ? 8 : 5
                for i in 0..<particleCount {
                    let particleAngle = baseAngle + Double(i) * (2 * Double.pi / Double(particleCount))
                    let particleDistance = CGFloat(arrivalT) * 16 * splashScale
                    let px = playerScreenPos.x + CGFloat(cos(particleAngle)) * particleDistance
                    let py = playerScreenPos.y + CGFloat(sin(particleAngle)) * particleDistance
                    let particleRadius = 2.4 * splashScale * (1 - CGFloat(arrivalT) * 0.5)
                    context.fill(
                        Path(ellipseIn: CGRect(x: px - particleRadius, y: py - particleRadius,
                                                width: particleRadius * 2, height: particleRadius * 2)),
                        with: .color(effect.color.color.opacity(0.55 * rippleFade))
                    )
                }

                let flashBump = max(0, 1 - abs(progress - 1) / 0.3)
                if flashBump > arrivalFlashAmount {
                    arrivalFlashAmount = flashBump
                    arrivalFlashColor = effect.color.color
                }
            }
        }

        // Player dot, always screen-centered.
        let playerScreenPos = toScreen(player.position)
        let formColor = player.activeForm?.primaryColor.color
        let color = DotRenderer.blendedPlayerColor(formColor: formColor, progress: player.activeFormProgress)

        // A short fading wake of small, shrinking blobs at recent positions —
        // reads as a liquid streak trailing the dot while it's moving fast,
        // drawn oldest-first so the newest sample sits closest to the dot.
        // Skipped under Reduce Motion (a trailing afterimage is exactly the
        // sort of thing that setting exists to remove).
        if !player.profile.reduceMotion {
            let now = Date()
            for sample in trailSamples {
                let age = now.timeIntervalSince(sample.time)
                let ageT = min(1, max(0, age / WhiteSpaceView.trailDuration))
                let p = toScreen(sample.position)
                guard isOnScreen(p, size: screenSize, margin: 40) else { continue }
                let trailRadius = renderSize * CGFloat(0.5 - 0.22 * ageT)
                let trailFade = (1 - ageT) * 0.16
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - trailRadius, y: p.y - trailRadius,
                                            width: trailRadius * 2, height: trailRadius * 2)),
                    with: .color(color.opacity(trailFade))
                )
            }
        }

        // (§ user feedback: "the border around the dot in the universe should
        // be removed" — this used to be a soft pulsing aura circle tinted
        // toward the player's color, filled behind the dot at all times; its
        // flat, low-opacity edge read as a faint ring/border around the
        // player rather than the subtle "alive" glow it was meant to be, so
        // it's gone now. The dot itself still animates plenty via its own
        // squash/stretch and idle motion.)

        // Brief color flash right as something finishes merging in (computed
        // in the absorb-effects loop above) — a quick tinted pulse over the
        // dot itself, so eating something visibly "adds" that color and
        // power rather than just a ring appearing around it.
        if let flashColor = arrivalFlashColor, arrivalFlashAmount > 0 {
            let flashRadius = renderSize * 1.08
            context.fill(
                Path(ellipseIn: CGRect(x: playerScreenPos.x - flashRadius, y: playerScreenPos.y - flashRadius,
                                        width: flashRadius * 2, height: flashRadius * 2)),
                with: .color(flashColor.opacity(0.4 * arrivalFlashAmount))
            )
        }

        DotRenderer.drawPlayer(context, center: playerScreenPos, radius: renderSize, color: color,
                                stretch: CGFloat(stretchAmount), angle: Angle(radians: stretchAngleRadians),
                                lookDirection: smoothedLook, time: t, eyeStyle: .whiteOnly,
                                reduceMotion: player.profile.reduceMotion, eatPulse: arrivalFlashAmount,
                                dotStyle: player.profile.selectedDotStyle, showGroundShadow: false)
        if let username = player.profile.username {
            drawNameLabel(context, name: username, at: playerScreenPos, belowRadius: renderSize)
        }

        // Ability effect: a quick expanding shockwave right as it triggers
        // (reads as an actual burst of power instead of a ring just
        // appearing), settling into a gently breathing aura ring for
        // whatever's left of the effect's duration.
        if player.abilityEffectRemaining > 0, let ability = player.equippedAbility {
            let duration = max(0.1, ability.duration)
            let elapsed = duration - player.abilityEffectRemaining
            let tint = formColor ?? .blue

            let shockDuration = 0.35
            if elapsed < shockDuration {
                let shockT = CGFloat(elapsed / shockDuration)
                let shockRadius = renderSize + 6 + shockT * 38
                let shockFade = 1 - shockT
                context.stroke(
                    Path(ellipseIn: CGRect(x: playerScreenPos.x - shockRadius, y: playerScreenPos.y - shockRadius,
                                            width: shockRadius * 2, height: shockRadius * 2)),
                    with: .color(tint.opacity(0.6 * Double(shockFade))), lineWidth: 3
                )
            }

            let r = renderSize + 6
            let auraBreathe = player.profile.reduceMotion ? 0.5 : 0.35 + 0.2 * sin(t * 6)
            context.stroke(Path(ellipseIn: CGRect(x: playerScreenPos.x - r, y: playerScreenPos.y - r, width: r * 2, height: r * 2)),
                            with: .color(tint.opacity(auraBreathe)), lineWidth: 2)
        }

        if let bubble = player.chatBubble {
            context.draw(Text(bubble).font(.system(size: 13, weight: .medium)).foregroundColor(.black),
                         at: CGPoint(x: playerScreenPos.x, y: playerScreenPos.y - renderSize - 18))
        }
    }

    private func isOnScreen(_ p: CGPoint, size: CGSize, margin: CGFloat) -> Bool {
        p.x > -margin && p.x < size.width + margin && p.y > -margin && p.y < size.height + margin
    }

    /// A small "davi_32"-style handle drawn just under a dot (§ new — "add
    /// names under the dots... all unique names"), used for both the
    /// player's own dot and every rival's. A soft dark pill sized to the
    /// actual resolved text (via `context.resolve`, rather than a guessed
    /// fixed width) keeps it legible over every palette this game has —
    /// White Space's light grid just as much as the final room's dark
    /// Nebulous.io-style background.
    private func drawNameLabel(_ context: GraphicsContext, name: String, at center: CGPoint, belowRadius radius: CGFloat) {
        guard !name.isEmpty else { return }
        let text = Text(name)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.92))
        let resolved = context.resolve(text)
        let textSize = resolved.measure(in: CGSize(width: 200, height: 20))
        let paddingX: CGFloat = 6
        let paddingY: CGFloat = 3
        let pillSize = CGSize(width: textSize.width + paddingX * 2, height: textSize.height + paddingY * 2)
        let pillOrigin = CGPoint(x: center.x - pillSize.width / 2, y: center.y + radius + 6)
        context.fill(
            Path(roundedRect: CGRect(origin: pillOrigin, size: pillSize), cornerRadius: pillSize.height / 2),
            with: .color(.black.opacity(0.32))
        )
        context.draw(resolved, at: CGPoint(x: center.x, y: pillOrigin.y + pillSize.height / 2))
    }

    /// Standard "ease-out-back" easing: overshoots past 1 briefly before
    /// settling — used for the collectible spawn-in pop so new items feel
    /// like they spring into place instead of just materializing.
    private func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        let t = x - 1
        return 1 + c3 * t * t * t + c1 * t * t
    }

    /// Smoothly tracks how "stretched" the player dot should look (0 = at
    /// rest, 1 = fully stretched along the direction of travel), so motion
    /// reads as a bit of a liquid squash-and-stretch instead of a rigid
    /// circle snapping to speed. Runs once per frame, right alongside
    /// `engine.tick`.
    private func updateStretch(dt: Double) {
        guard dt > 0, dt < 1 else { return }
        let dx = Double(engine.moveInput.dx)
        let dy = Double(engine.moveInput.dy)
        let magnitude = min(1, sqrt(dx * dx + dy * dy))

        // A lightly underdamped spring instead of a flat ease: starting or
        // stopping overshoots a touch before settling, so the squash/stretch
        // reads as a squishy *reaction* to the change in motion instead of a
        // shape that just snaps straight to whatever the input currently is.
        let stiffness = 260.0
        let damping = 17.0
        let acceleration = stiffness * (magnitude - stretchAmount) - damping * stretchVelocity
        stretchVelocity += acceleration * dt
        stretchAmount += stretchVelocity * dt
        stretchAmount = min(1.2, max(0, stretchAmount))

        guard magnitude > 0.05 else { return }
        let targetAngle = atan2(dy, dx)
        var delta = targetAngle - stretchAngleRadians
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        let angleSmoothing = min(1, dt * 12)
        stretchAngleRadians += delta * angleSmoothing
    }

    /// Eases `smoothedLook` toward wherever the player is currently heading
    /// (or a slow idle glance while still) with the same lightly-underdamped
    /// spring feel as `updateStretch` above (§ user feedback: "let the dot
    /// move as connect to the part of the dot so when dot move somewhere the
    /// eye will move with it") — the eyes visibly ease into a new direction
    /// right alongside the body's own squash/stretch reacting to it, instead
    /// of snapping to `engine.moveInput` a frame before the body catches up.
    private func updateLook(dt: Double) {
        guard dt > 0, dt < 1 else { return }
        let dx = Double(engine.moveInput.dx)
        let dy = Double(engine.moveInput.dy)
        let magnitude = sqrt(dx * dx + dy * dy)

        let target: CGVector
        if magnitude > 0.05 {
            target = engine.moveInput
        } else {
            // Idle: a slow, gentle glance up and down instead of a dead stare.
            let t = Date().timeIntervalSinceReferenceDate
            target = CGVector(dx: 0, dy: CGFloat(sin(t * 0.6) * 0.6))
        }

        let stiffness = 220.0
        let damping = 16.0
        let ax = stiffness * (Double(target.dx) - Double(smoothedLook.dx)) - damping * Double(lookVelocity.dx)
        let ay = stiffness * (Double(target.dy) - Double(smoothedLook.dy)) - damping * Double(lookVelocity.dy)
        lookVelocity.dx += CGFloat(ax * dt)
        lookVelocity.dy += CGFloat(ay * dt)
        smoothedLook.dx += lookVelocity.dx * CGFloat(dt)
        smoothedLook.dy += lookVelocity.dy * CGFloat(dt)
    }

    /// Springs `displaySize` toward the engine's authoritative `player.size`
    /// every frame — deliberately underdamped (like `updateStretch` above),
    /// so it overshoots a little past the new size before settling back,
    /// which is what makes growing from a bite read as a juicy little "pop"
    /// instead of an instant snap. Purely cosmetic: nothing about collision
    /// or eat-radius math ever reads `displaySize`, only `draw`'s `renderSize`.
    private func updateGrowth(dt: Double) {
        guard dt > 0, dt < 1 else { return }
        if displaySize == 0 { displaySize = player.size }
        let stiffness = 210.0
        let damping = 14.0
        let acceleration = stiffness * (Double(player.size) - Double(displaySize)) - damping * growthVelocity
        growthVelocity += acceleration * dt
        displaySize += CGFloat(growthVelocity * dt)
        displaySize = max(1, displaySize)
    }

    /// Lays down a new trail sample only while actually moving with enough
    /// speed (so the wake doesn't linger behind a dot that's just sitting
    /// still), then drops samples older than `trailDuration`. Runs once per
    /// frame, right alongside `updateStretch`.
    private func updateTrail() {
        let dx = Double(engine.moveInput.dx)
        let dy = Double(engine.moveInput.dy)
        let magnitude = min(1, sqrt(dx * dx + dy * dy))
        let now = Date()

        if magnitude > 0.15 {
            trailSamples.append(TrailSample(position: player.position, time: now))
        }
        trailSamples.removeAll { now.timeIntervalSince($0.time) > WhiteSpaceView.trailDuration }
    }

    // MARK: - Movement input (drag anywhere, §42 Option A)

    private func dragGesture(screenSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStart == nil { dragStart = value.startLocation }
                guard let start = dragStart else { return }
                let dx = value.location.x - start.x
                let dy = value.location.y - start.y
                let maxRange: CGFloat = 70
                let clampedX = max(-maxRange, min(maxRange, dx)) / maxRange
                let clampedY = max(-maxRange, min(maxRange, dy)) / maxRange
                engine.moveInput = CGVector(dx: clampedX, dy: clampedY)
            }
            .onEnded { _ in
                dragStart = nil
                engine.moveInput = .zero
            }
    }

    // MARK: - HUD

    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                if let form = player.activeForm {
                    Text("\(form.icon) \(form.name) \(Int(player.activeFormProgress))%")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    // A thin filling bar under the label so progress toward
                    // finishing the current form reads at a glance instead of
                    // only as a number that has to be read and compared.
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.black.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(form.primaryColor.color)
                                    .frame(width: geo.size.width * CGFloat(max(0, min(100, player.activeFormProgress)) / 100))
                            }
                    }
                    .frame(width: 108, height: 4)
                    .animation(.easeOut(duration: 0.3), value: player.activeFormProgress)
                } else {
                    Text("Explore.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Text("Intelligence \(player.profile.intelligenceLevel)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundColor(.black.opacity(0.75))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var controls: some View {
        HStack {
            VStack(spacing: 14) {
                roundIconButton(system: "square.grid.2x2.fill") { showingCollection = true }
                roundIconButton(system: "gearshape.fill") { showingSettings = true }
            }
            .padding(.leading, 20)
            .padding(.bottom, 28)

            Spacer()
            Button(action: { engine.triggerAbility() }) {
                ZStack {
                    // A ring that continuously expands and fades while the
                    // ability is off cooldown — draws the eye to "you can use
                    // this now" instead of the button just sitting there
                    // identical whether it's ready or still recharging.
                    if player.canUseAbility && !player.profile.reduceMotion {
                        Circle()
                            .stroke(Color.black.opacity(abilityPulseOn ? 0.0 : 0.4), lineWidth: 2)
                            .frame(width: 64, height: 64)
                            .scaleEffect(abilityPulseOn ? 1.4 : 1.0)
                    }
                    Circle()
                        .fill(player.canUseAbility ? Color.black.opacity(0.85) : Color.gray.opacity(0.3))
                        .frame(width: 64, height: 64)
                    if player.abilityCooldownRemaining > 0 {
                        Text("\(Int(ceil(player.abilityCooldownRemaining)))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: abilityIconName)
                            .foregroundColor(.white)
                            .font(.system(size: 22, weight: .semibold))
                    }
                }
            }
            .disabled(!player.canUseAbility)
            .padding(.trailing, 20)
            .padding(.bottom, 28)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                    abilityPulseOn = true
                }
            }
        }
    }

    // MARK: - Quit / minimap / timer

    private var quitButton: some View {
        roundIconButton(system: "xmark") { onQuit() }
            .padding(.top, 54)
            .padding(.leading, 16)
    }

    private var minimap: some View {
        let mapSize: CGFloat = 84
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
            Canvas { context, size in
                let worldSize = GameEngine.worldSize
                func toMap(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: p.x / worldSize * size.width, y: p.y / worldSize * size.height)
                }
                for c in engine.collectibles {
                    let p = toMap(c.position)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)),
                                 with: .color(.black.opacity(0.35)))
                }
                let playerDot = toMap(player.position)
                let r: CGFloat = 4
                context.fill(Path(ellipseIn: CGRect(x: playerDot.x - r, y: playerDot.y - r, width: r * 2, height: r * 2)),
                             with: .color(.blue))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        }
        .frame(width: mapSize, height: mapSize)
        .padding(.top, 54)
        .padding(.trailing, 16)
    }

    private var timerBadge: some View {
        Text(timeString(engine.timeRemaining))
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(engine.timeRemaining < 30 ? .red : .black.opacity(0.75))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 106)
    }

    private func timeString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var roundExpiredOverlay: some View {
        Group {
            if engine.roundExpired {
                VStack(spacing: 6) {
                    Text(engine.roundMode == .practice ? "🌌" : "⏱️").font(.system(size: 40))
                    // § user feedback: "remove the phrase that says entering
                    // another universe" — the practice room now hands off
                    // with just the emoji + haptic, no caption; the real
                    // round's "TIME'S UP" text is unrelated and stays.
                    if engine.roundMode != .practice {
                        Text("TIME'S UP")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
                .padding(20)
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
                .foregroundColor(.white)
                .transition(.scale.combined(with: .opacity))
                .onAppear {
                    HapticsManager.shared.impact(.medium)
                    // The 30-second practice room hands straight off
                    // to the real final room instead of quitting to the menu
                    // — only a `.final` round's timer running out actually
                    // ends the session.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        if engine.roundMode == .practice {
                            onRoundComplete()
                        } else {
                            onQuit()
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: engine.roundExpired)
    }

    /// Shown instead of `roundExpiredOverlay` the instant a bigger rival eats
    /// the player in the final room (§ new "big eats small" rule) — a clean,
    /// distinct beat from the plain timer running out, before quitting back
    /// to the menu the same way.
    private var eliminatedOverlay: some View {
        Group {
            if engine.playerWasEaten {
                VStack(spacing: 6) {
                    Text("💥").font(.system(size: 40))
                    Text("YOU WERE EATEN")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .padding(20)
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
                .foregroundColor(.white)
                .transition(.scale.combined(with: .opacity))
                .onAppear {
                    HapticsManager.shared.impact(.medium)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        onQuit()
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: engine.playerWasEaten)
    }

    private func roundIconButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.black.opacity(0.75))
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var abilityIconName: String {
        switch player.equippedAbility {
        case .slipperyDash, .rocketDash, .ghostPhase: return "bolt.fill"
        case .harden, .shieldUp: return "shield.fill"
        case .firePulse: return "flame.fill"
        case .slowPulse: return "snowflake"
        case .speedBoost, .flowEscape: return "wind"
        case .scan, .viewRange: return "eye.fill"
        case .magnetPull: return "circle.hexagongrid.fill"
        case .none: return "questionmark"
        }
    }

    private var formCompleteOverlay: some View {
        Group {
            if let form = player.formCompleteBanner {
                ZStack {
                    SparkleBurst(color: form.primaryColor.color)
                    VStack(spacing: 6) {
                        Text(form.icon).font(.system(size: 40))
                        Text("\(form.name.uppercased()) — FORM COMPLETE")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .padding(20)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18))
                    .foregroundColor(.white)
                }
                .transition(.scale.combined(with: .opacity))
                .onAppear {
                    HapticsManager.shared.success()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation { player.formCompleteBanner = nil }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: player.formCompleteBanner)
    }

    /// A brief "Level N" banner + haptic tap whenever accrued Intelligence
    /// crosses into a new level — previously leveling up had no feedback at
    /// all, so it was easy to not even notice it happened.
    private var levelUpOverlay: some View {
        Group {
            if let level = player.levelUpBanner {
                ZStack {
                    SparkleBurst(color: .yellow)
                    VStack(spacing: 6) {
                        Text("✨").font(.system(size: 36))
                        Text("LEVEL \(level)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .padding(18)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundColor(.white)
                }
                .transition(.scale.combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation { player.levelUpBanner = nil }
                    }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: player.levelUpBanner)
    }

    /// A brief "×N COMBO" pill (§ new) that pops in from `GameEngine.absorb`
    /// whenever consecutive bites land inside the combo window, and fades
    /// itself back out a moment later — purely cosmetic feedback for the
    /// Points multiplier already applied by the time this shows.
    private var comboBanner: some View {
        Group {
            if let text = engine.comboBannerText {
                Text(text)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.orange, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .transition(.scale.combined(with: .opacity))
                    .padding(.top, 92)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: engine.comboBannerText)
    }

    private var signalBanner: some View {
        Group {
            if let text = engine.signalBannerText {
                Text(text)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.black, in: Capsule())
                    .foregroundColor(.white)
                    .padding(.top, 50)
                    .transition(.opacity)
            }
        }
    }
}
