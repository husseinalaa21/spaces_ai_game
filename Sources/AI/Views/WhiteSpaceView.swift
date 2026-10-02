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
    @ObservedObject var authState: AuthState
    @ObservedObject var sync: SpacechatSync
    /// Returns to the main menu — the quit button, and automatically once
    /// the round timer runs out (in `.final` mode) or the player gets eaten.
    let onQuit: () -> Void
    /// Called instead of `onQuit` when a `.practice`-mode round's short timer
    /// runs out (§ new two-phase Play flow) — `RootView` uses this to start
    /// the real `.final` round rather than sending the player back to the menu.
    /// The person playing wrote something in the match chat.
    var onChat: (String) -> Void = { _ in }
    var onRoundComplete: () -> Void = {}
    @State private var chatOpen = false
    @State private var chatDraft = ""
    @FocusState private var chatFocused: Bool
    @ObservedObject private var friends = FriendsStore.shared
    /// The player whose card is open after tapping their dot.
    @State private var selectedName: String? = nil
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

    // Arrival animation: the world starts slightly zoomed in, the dot is held
    // small until the window opens, then everything settles.
    @State private var entryZoom: CGFloat = 1.22
    @State private var showEntry = true
    @State private var dotArmed = false

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
                    if dotArmed { engine.tick(dt: dt) }
                    updateStretch(dt: dt)
                    updateLook(dt: dt)
                    updateGrowth(dt: dt)
                    updateTrail()
                }
            }
            .background(currentPalette.background)
            .scaleEffect(entryZoom)
            .contentShape(Rectangle())
            .gesture(dragGesture(screenSize: screenSize))
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
            .overlay(alignment: .topLeading) { chatFeed }
            .overlay(alignment: .bottom) { playerCard }
            .overlay {
                if showEntry {
                    UniverseEntryOverlay(title: entryTitle, caption: engine.roundMode == .final ? "Bigger dots eat smaller ones" : "Eat to grow",
                                         color: entryColor, accent: entryAccent) { showEntry = false }
                        .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingCollection) {
            CollectionView(player: player)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(player: player, authState: authState, sync: sync)
        }
        .onChange(of: engine.roundExpired) { expired in
            if expired && engine.roundMode == .practice { onRoundComplete() }
        }
        .onAppear {
            AudioManager.shared.startMusic("ambient")
            entryZoom = 1.22; showEntry = true; dotArmed = false
            withAnimation(.easeOut(duration: 1.5).delay(UniverseEntryOverlay.holdTime - 0.1)) { entryZoom = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + UniverseEntryOverlay.holdTime + 0.05) { dotArmed = true }
        }
        .onDisappear { AudioManager.shared.stopMusic() }
    }

    /// The final round (§ new two-phase Play flow) always shows its own
    /// distinct look — `WorldBackground.finalUniverse` — instead of whatever
    /// Universe the player has cosmetically picked, so stepping into it after
    /// the practice room actually reads as arriving somewhere new. The
    /// practice room (and this same view when reused elsewhere) still shows
    /// the player's own pick.
    private var currentPalette: WorldBackground.Palette {
        if let custom = player.profile.customUniverses.first(where: { $0.id == player.profile.selectedCustomUniverseID }) {
            return custom.palette
        }
        return engine.roundMode == .final ? WorldBackground.finalUniverse : WorldBackground.palette(for: player.profile.selectedUniverse)
    }

    private var entryTitle: String {
        if engine.roundMode == .final { return "The Arena" }
        if let custom = player.profile.customUniverses.first(where: { $0.id == player.profile.selectedCustomUniverseID }) { return custom.name }
        return player.profile.selectedUniverse.displayName + " Universe"
    }
    private var entryColor: Color {
        engine.roundMode == .final ? Color(red: 0.16, green: 0.12, blue: 0.55) : Color(red: 0.12, green: 0.38, blue: 0.95)
    }
    private var entryAccent: Color {
        engine.roundMode == .final ? Color(red: 0.55, green: 0.32, blue: 0.95) : Color(red: 0.40, green: 0.78, blue: 1.0)
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
                                    dotStyle: .classic)
            drawNameLabel(context, name: rival.username, at: p, belowRadius: rival.radius)
            if let said = rival.lastMessage, let at = rival.lastMessageAt, t - at.timeIntervalSinceReferenceDate < 6 {
                let age = t - at.timeIntervalSinceReferenceDate
                var speech = context
                speech.opacity = min(1, max(0, (6 - age) / 1.2))
                let font = Font.system(size: 12, weight: .heavy, design: .rounded)
                let half = CGFloat(said.count) * 3.7 + 8
                let spot = CGPoint(x: min(max(p.x, half), screenSize.width - half), y: p.y - rival.radius - 16)
                for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
                    speech.draw(Text(said).font(font).foregroundColor(.black.opacity(0.55)), at: CGPoint(x: spot.x + dx, y: spot.y + dy))
                }
                speech.draw(Text(said).font(font).foregroundColor(.white), at: spot)
            }
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
        for dot in engine.growthDots {
            let p = toScreen(dot.position)
            guard isOnScreen(p, size: screenSize, margin: 8) else { continue }
            let hue = abs(sin(Double(dot.position.x) * 0.0173 + Double(dot.position.y) * 0.0291))
            let pellet = Color(hue: 0.02 + hue * 0.86, saturation: 0.82, brightness: 1.0)
            DotRenderer.draw(context, center: p, radius: 5.5, color: pellet)
        }
        for c in engine.collectibles {
            let p = toScreen(c.position)
            guard isOnScreen(p, size: screenSize, margin: 40) else { continue }
            let radius: CGFloat = 13
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

            var textContext = popContext
            textContext.translateBy(x: bobbedP.x, y: bobbedP.y)
            textContext.rotate(by: wiggleAngle)
            textContext.draw(Text(c.definition.icon).font(.system(size: CGFloat(22 * popScale))), at: .zero)

        }

        // Eating: what was eaten is drawn as a gooey blob joined to the dot
        // by a stretching neck, shrinking until the dot swallows it
        // (`MergeEffect`). The dot itself pops through `displaySize`.
        let playerScreenForMerge = toScreen(player.position)
        let playerBaseColor = engine.roundMode == .final
            ? (player.activeForm?.primaryColor.color ?? DotRenderer.defaultColor)
            : DotRenderer.blendedPlayerColor(formColor: player.activeForm?.primaryColor.color, progress: player.activeFormProgress)
        var arrivalFlashAmount: Double = 0
        for effect in engine.absorbEffects {
            let progress = min(1, max(0, Date().timeIntervalSince(effect.startedAt) / AbsorbEffect.duration))
            let from = toScreen(effect.startPosition)
            guard isOnScreen(from, size: screenSize, margin: 120) || isOnScreen(playerScreenForMerge, size: screenSize, margin: 0) else { continue }
            MergeEffect.draw(context, progress: progress, eaten: from, eatenRadius: min(effect.magnitude, 60),
                             eatenColor: effect.color.color, dot: playerScreenForMerge, dotRadius: renderSize, dotColor: playerBaseColor)
            if progress > 0.7 { arrivalFlashAmount = max(arrivalFlashAmount, sin((progress - 0.7) / 0.3 * .pi)) }
        }

        // Player dot, always screen-centered.
        let playerScreenPos = toScreen(player.position)
        let formColor = player.activeForm?.primaryColor.color
        let color = engine.roundMode == .final ? (formColor ?? DotRenderer.blendedPlayerColor(formColor: nil, progress: 0))
            : DotRenderer.blendedPlayerColor(formColor: formColor, progress: player.activeFormProgress)

        // (§ user feedback: "the border around the dot in the universe should
        // be removed" — this used to be a soft pulsing aura circle tinted
        // toward the player's color, filled behind the dot at all times; its
        // flat, low-opacity edge read as a faint ring/border around the
        // player rather than the subtle "alive" glow it was meant to be, so
        // it's gone now. The dot itself still animates plenty via its own
        // squash/stretch and idle motion.)

        DotRenderer.drawPlayer(context, center: playerScreenPos, radius: renderSize, color: color,
                                stretch: CGFloat(stretchAmount), angle: Angle(radians: stretchAngleRadians),
                                lookDirection: smoothedLook, time: t, eyeStyle: .whiteOnly,
                                reduceMotion: player.profile.reduceMotion, eatPulse: arrivalFlashAmount,
                                dotStyle: player.profile.selectedDotStyle,
                                customDot: player.activeCustomDot)
        if engine.roundMode == .final, let form = player.activeForm {
            context.draw(Text(form.icon).font(.system(size: renderSize * 0.9)),
                         at: CGPoint(x: playerScreenPos.x, y: playerScreenPos.y + renderSize * 0.35))
        }
        if let username = player.profile.username {
            drawNameLabel(context, name: username, at: playerScreenPos, belowRadius: renderSize)
        }
        if let said = engine.playerMessage, let at = engine.playerMessageAt, t - at.timeIntervalSinceReferenceDate < 6 {
            var speech = context
            speech.opacity = min(1, max(0, (6 - (t - at.timeIntervalSinceReferenceDate)) / 1.2))
            let font = Font.system(size: 12, weight: .heavy, design: .rounded)
            let half = CGFloat(said.count) * 3.7 + 8
            let spot = CGPoint(x: min(max(playerScreenPos.x, half), screenSize.width - half), y: playerScreenPos.y - renderSize - 16)
            for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
                speech.draw(Text(said).font(font).foregroundColor(.black.opacity(0.55)), at: CGPoint(x: spot.x + dx, y: spot.y + dy))
            }
            speech.draw(Text(said).font(font).foregroundColor(.white), at: spot)
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
        // Plain text with a thin outline (no pill behind it), readable on
        // light and dark universes alike.
        let font = Font.system(size: 11, weight: .heavy, design: .rounded)
        let point = CGPoint(x: center.x, y: center.y + radius + 12)
        let dark = Color.black.opacity(0.55)
        for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
            context.draw(Text(name).font(font).foregroundColor(dark), at: CGPoint(x: point.x + dx, y: point.y + dy))
        }
        context.draw(Text(name).font(font).foregroundColor(.white), at: point)
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
        // Held tiny until the window opens, then released so the spring below
        // pops the dot up to full size as the universe is revealed.
        if !dotArmed { displaySize = 1; growthVelocity = 0; return }
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

    /// Tapping a dot opens its card (add friend).
    private func selectDot(at location: CGPoint, screenSize: CGSize) {
        let camera = CGPoint(x: player.position.x - screenSize.width / 2, y: player.position.y - screenSize.height / 2)
        let world = CGPoint(x: location.x + camera.x, y: location.y + camera.y)
        let hit = engine.rivals
            .filter { hypot($0.position.x - world.x, $0.position.y - world.y) <= $0.radius + 18 }
            .min { hypot($0.position.x - world.x, $0.position.y - world.y) < hypot($1.position.x - world.x, $1.position.y - world.y) }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedName = hit?.username }
    }

    // MARK: - Movement input (drag anywhere, §42 Option A)

    private func dragGesture(screenSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil { dragStart = value.startLocation }
                // A touch that has barely moved is a tap, not steering.
                if hypot(value.translation.width, value.translation.height) < 6 { return }
                guard let start = dragStart else { return }
                let dx = value.location.x - start.x
                let dy = value.location.y - start.y
                let maxRange: CGFloat = 70
                let clampedX = max(-maxRange, min(maxRange, dx)) / maxRange
                let clampedY = max(-maxRange, min(maxRange, dy)) / maxRange
                engine.moveInput = CGVector(dx: clampedX, dy: clampedY)
            }
            .onEnded { value in
                dragStart = nil
                engine.moveInput = .zero
                chatFocused = false
                if hypot(value.translation.width, value.translation.height) < 6 {
                    selectDot(at: value.startLocation, screenSize: screenSize)
                }
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
            .background(HUDChip(shape: Capsule()))

            Spacer()

            Text("Score \(max(0, player.profile.points - engine.gameStartPoints))")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(HUDChip(shape: Capsule()))
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
                            .stroke(DotRenderer.defaultColor.opacity(abilityPulseOn ? 0.0 : 0.5), lineWidth: 3)
                            .frame(width: 64, height: 64)
                            .scaleEffect(abilityPulseOn ? 1.4 : 1.0)
                    }
                    Circle()
                        .fill(player.canUseAbility ? DotRenderer.defaultColor : Color(white: 0.82))
                        .frame(width: 64, height: 64)
                        .overlay(Circle().stroke((player.canUseAbility ? DotRenderer.defaultColor : Color(white: 0.82)).deepened(0.6), lineWidth: 4))
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
            HUDChip(shape: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Canvas { context, size in
                let worldSize = GameEngine.worldSize
                func toMap(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: p.x / worldSize * size.width, y: p.y / worldSize * size.height)
                }
                for dot in engine.growthDots {
                    let p = toMap(dot.position)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)), with: .color(.blue.opacity(0.5)))
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
            .background(HUDChip(shape: Capsule()))
            .padding(.bottom, 106)
    }

    private func timeString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var roundExpiredOverlay: some View {
        Group {
            if engine.roundExpired && engine.roundMode == .final {
                VStack(spacing: 6) {
                    Text("⏱️").font(.system(size: 40))
                    Text("TIME'S UP")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .padding(20)
                .modifier(GameCard(color: Color(red: 0.20, green: 0.50, blue: 1.0)))
                .transition(.scale.combined(with: .opacity))
                .onAppear {
                    HapticsManager.shared.impact(.medium)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        onQuit()
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
                .modifier(GameCard(color: Color(red: 0.95, green: 0.30, blue: 0.38)))
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
                .background(HUDChip(shape: Circle()))
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
                    .modifier(GameCard(color: form.primaryColor.color.deepened(0.85)))
                }
                .offset(y: -190)
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
                    .modifier(GameCard(color: Color(red: 0.98, green: 0.62, blue: 0.10)))
                }
                .offset(y: -190)
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
                    .background(Color(red: 0.98, green: 0.55, blue: 0.10), in: Capsule())
                    .overlay(Capsule().stroke(Color(red: 0.98, green: 0.55, blue: 0.10).deepened(0.6), lineWidth: 3))
                    .transition(.scale.combined(with: .opacity))
                    .padding(.top, 92)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: engine.comboBannerText)
    }

    /// The match chat, small, top-left: the last few lines, a button to open
    /// the box, and (when open) a field with Send and a button that closes the
    /// keyboard. Tapping the universe also closes the keyboard.
    private var chatFeed: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !engine.chatFeed.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(engine.chatFeed.suffix(4)) { line in
                        (Text(line.name + "  ").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(DotRenderer.defaultColor)
                            + Text(line.text).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(.black.opacity(0.8)))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: 230, alignment: .leading)
                .background(HUDChip(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
                .allowsHitTesting(false)
            }
            if chatOpen {
                HStack(spacing: 6) {
                    TextField("Say something", text: $chatDraft)
                        .focused($chatFocused)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .submitLabel(.send)
                        .onSubmit { sendChat() }
                        .padding(.horizontal, 10).frame(height: 34)
                    if chatFocused {
                        Button { chatFocused = false } label: {
                            Image(systemName: "keyboard.chevron.compact.down").font(.system(size: 14, weight: .bold))
                                .foregroundColor(.black.opacity(0.5)).frame(width: 30, height: 34)
                        }.buttonStyle(.plain).accessibilityLabel("Hide keyboard")
                    }
                    Button { sendChat() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .heavy)).foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(chatDraft.trimmingCharacters(in: .whitespaces).isEmpty ? Color(white: 0.8) : DotRenderer.defaultColor, in: Circle())
                    }.buttonStyle(.plain).padding(.trailing, 3).accessibilityLabel("Send")
                }
                .frame(maxWidth: 230)
                .background(HUDChip(shape: Capsule()))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { chatOpen.toggle() }
                if chatOpen { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { chatFocused = true } } else { chatFocused = false }
            } label: {
                Image(systemName: chatOpen ? "xmark" : "bubble.left.fill")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(DotRenderer.defaultColor)
                    .frame(width: 38, height: 34)
                    .background(HUDChip(shape: Capsule()))
            }
            .buttonStyle(.plain).accessibilityLabel(chatOpen ? "Close chat" : "Open chat")
        }
        .padding(.top, 108).padding(.leading, 16)
    }

    private func sendChat() {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { chatFocused = false; return }
        engine.playerSay(String(text.prefix(60)))
        onChat(String(text.prefix(60)))
        chatDraft = ""
        chatFocused = false
        HapticsManager.shared.impact(.light)
    }

    /// Opens after tapping a dot: who it is and a one-tap Add friend.
    private var playerCard: some View {
        Group {
            if let name = selectedName, let rival = engine.rivals.first(where: { $0.username == name }) {
                let isFriend = friends.isFriend(name)
                HStack(spacing: 12) {
                    OrbView(color: rival.tint.color, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 17, weight: .heavy, design: .rounded))
                        Text("\(max(1, Int(rival.radius * rival.radius / 8))) mass")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.black.opacity(0.5))
                    }
                    Spacer(minLength: 8)
                    Button {
                        if isFriend { friends.remove(name) } else { friends.add(name); HapticsManager.shared.impact(.light) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isFriend ? "checkmark" : "person.badge.plus").font(.system(size: 13, weight: .bold))
                            Text(isFriend ? "Friends" : "Add friend").font(.system(size: 14, weight: .heavy, design: .rounded))
                        }
                        .foregroundColor(isFriend ? DotRenderer.defaultColor : .white)
                        .padding(.horizontal, 14).frame(height: 38)
                        .background(isFriend ? DotRenderer.defaultColor.opacity(0.14) : DotRenderer.defaultColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(HUDChip(shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
                .padding(.horizontal, 24).padding(.bottom, 150)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var signalBanner: some View {
        Group {
            if let text = engine.signalBannerText {
                Text(text)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(DotRenderer.defaultColor, in: Capsule())
                    .overlay(Capsule().stroke(DotRenderer.defaultColor.deepened(0.6), lineWidth: 3))
                    .foregroundColor(.white)
                    .padding(.top, 50)
                    .transition(.opacity)
            }
        }
    }
}


/// Flat white chip with a bold outline, used behind HUD readouts in place of
/// translucent material.
struct HUDChip<S: Shape>: View {
    let shape: S
    var body: some View {
        shape.fill(Color.white).overlay(shape.stroke(Color(red: 0.20, green: 0.50, blue: 1.0).opacity(0.28), lineWidth: 2.5))
    }
}

/// A flat, vivid card with a bold darker border for banners ("Time's up",
/// "You were eaten", level and form messages).
struct GameCard: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .foregroundColor(.white)
            .background(color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(color.deepened(0.6), lineWidth: 4))
    }
}
