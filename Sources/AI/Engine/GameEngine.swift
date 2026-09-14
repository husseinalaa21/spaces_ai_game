import Foundation
import CoreGraphics
import SwiftUI
import UIKit

/// Drives the whole White Space simulation: movement, spawning, collisions,
/// abilities and Signals. One instance lives for the duration of a play
/// session and is fed frame deltas by `WhiteSpaceView` via a `TimelineView`.
///
/// This is intentionally a single-player / local simulation for now — see
/// the module list in §89 of the spec for where `Multiplayer`/`Networking`
/// would plug in later without changing this file's public surface much:
/// `otherPlayers` below is where synced remote players would appear.
@MainActor
final class GameEngine: ObservableObject {
    // MARK: World configuration
    static let worldSize: CGFloat = 4000
    static let maxCollectibles = 160
    static let maxWanderers = 14
    static let baseSpeed: CGFloat = 130   // points/sec at radius = baseRadius

    /// Length of one White Space play session, started fresh each time the
    /// player taps Play on the main menu.
    static let roundDuration: Double = 15 * 60

    /// The two rooms of the new Play flow (§ new): a short, safe 15-second
    /// "practice" room right after the falling-dot intro where everyone's
    /// just foraging side by side, then the real "final" room where being
    /// the smaller dot next to a rival actually costs you. Both share this
    /// one engine/world so nothing about spawning or eating collectibles has
    /// to be duplicated — only `checkPlayerRivalCollisions` below reads it.
    enum RoundMode { case practice, final }
    @Published var roundMode: RoundMode = .final

    let player: PlayerState

    @Published var collectibles: [SpawnedCollectible] = []
    @Published var wanderers: [AmbientWanderer] = []
    /// Simulated AI "rival" dots (§ new) — stand-ins for other players since
    /// there's no real multiplayer/server yet. They forage for collectibles
    /// the same way the player does in both rooms; only in `.final` mode can
    /// they actually eat (or be eaten by) the player, via
    /// `checkPlayerRivalCollisions`.
    @Published var rivals: [RivalDot] = []
    @Published var activeSignal: SignalEvent? = nil
    @Published var signalBannerText: String? = nil
    @Published var absorbEffects: [AbsorbEffect] = []
    @Published var timeRemaining: Double = GameEngine.roundDuration
    @Published var roundExpired: Bool = false
    /// True the instant a bigger rival touches the player in the final room
    /// — `WhiteSpaceView` shows a distinct "you were eaten" overlay for this
    /// (rather than the plain `roundExpired` "time's up" one) and then quits
    /// back to the menu.
    @Published var playerWasEaten: Bool = false

    /// Rapid consecutive eats build a combo (§ new) that boosts Points and
    /// pops a brief "×N COMBO" banner (`WhiteSpaceView.comboBanner`) —
    /// rewards actively hunting collectibles instead of camping in one
    /// dense cluster. Resets the moment `comboWindow` lapses without a bite.
    @Published var comboCount: Int = 0
    @Published var comboBannerText: String? = nil
    private var lastEatAt: Date? = nil
    private var comboBannerGeneration: Int = 0
    private static let comboWindow: Double = 2.0

    /// Normalized -1...1 drag vector from the on-screen joystick/drag control.
    var moveInput: CGVector = .zero

    private var timeSinceSpawnCheck: Double = 0
    private var timeSinceSignalCheck: Double = 0
    private let saveManager: SaveManager

    init(player: PlayerState, saveManager: SaveManager) {
        self.player = player
        self.saveManager = saveManager
        player.position = CGPoint(x: GameEngine.worldSize / 2, y: GameEngine.worldSize / 2)
        seedInitialWorld()
    }

    private func seedInitialWorld() {
        for _ in 0..<100 {
            spawnCollectible()
        }
        for _ in 0..<GameEngine.maxWanderers {
            wanderers.append(makeWanderer())
        }
    }

    /// Resets the round clock and lets the world start fresh — called both
    /// right after the falling-dot intro (§ new, `mode: .practice`, a fixed
    /// short `duration`) and again the moment that practice room's timer
    /// runs out (`mode: .final`, the normal full-length round).
    func startRound(mode: RoundMode = .final, duration: Double? = nil) {
        roundMode = mode
        timeRemaining = duration ?? GameEngine.roundDuration
        roundExpired = false
        playerWasEaten = false
        comboCount = 0
        comboBannerText = nil
        lastEatAt = nil
        spawnRivals()
    }

    // MARK: - Frame update

    func tick(dt: Double) {
        guard dt > 0, dt < 1 else { return }
        updateMovement(dt: dt)
        updateAbilityTimers(dt: dt)
        updateWanderers(dt: dt)
        updateRivals(dt: dt)
        checkCollisions()
        checkPlayerRivalCollisions()
        handleSpawning(dt: dt)
        handleSignals(dt: dt)
        cleanUpAbsorbEffects()
        checkComboExpiry()
        updateRoundTimer(dt: dt)
    }

    /// Lets a combo lapse quietly (no banner, no haptic) once `comboWindow`
    /// passes without another bite, so the next eat starts a fresh streak
    /// instead of picking up a stale count from long ago.
    private func checkComboExpiry() {
        guard comboCount > 0, let last = lastEatAt else { return }
        if Date().timeIntervalSince(last) > GameEngine.comboWindow {
            comboCount = 0
        }
    }

    private func updateRoundTimer(dt: Double) {
        guard timeRemaining > 0 else { return }
        // Ice's "Slow Pulse" — with no other players to actually slow down in
        // solo White Space, it buys the one thing that's always ticking:
        // the round clock, at 40% of its normal rate while active.
        let rate = (player.abilityEffectRemaining > 0 && player.equippedAbility == .slowPulse) ? 0.4 : 1.0
        timeRemaining = max(0, timeRemaining - dt * rate)
        if timeRemaining == 0 {
            roundExpired = true
        }
    }

    private func cleanUpAbsorbEffects() {
        guard !absorbEffects.isEmpty else { return }
        let now = Date()
        absorbEffects.removeAll { now.timeIntervalSince($0.startedAt) > AbsorbEffect.duration }
    }

    private func updateMovement(dt: Double) {
        let magnitude = min(1, sqrt(moveInput.dx * moveInput.dx + moveInput.dy * moveInput.dy))
        guard magnitude > 0.02 else { return }

        var speed = GameEngine.baseSpeed
        // Rock: slower but sturdier. Rabbit/Lightning: faster. Simple passive tie-ins.
        if player.isCompleted("rock"), player.profile.activeFormID == "rock" { speed *= 0.85 }
        if player.isCompleted("rabbit") { speed *= 1.08 }
        if player.isCompleted("lightning") { speed *= 1.12 }
        if player.abilityEffectRemaining > 0, player.equippedAbility == .speedBoost { speed *= 1.6 }
        // Water's "Flow Escape" — same movement-burst family as Speed Boost
        // (they already share the same HUD icon), just its own form to unlock.
        if player.abilityEffectRemaining > 0, player.equippedAbility == .flowEscape { speed *= 1.6 }
        if player.abilityEffectRemaining > 0, player.equippedAbility == .rocketDash { speed *= 3.2 }
        if player.abilityEffectRemaining > 0, player.equippedAbility == .slipperyDash { speed *= 2.2 }

        let dx = CGFloat(dt) * speed * moveInput.dx
        let dy = CGFloat(dt) * speed * moveInput.dy
        var next = CGPoint(x: player.position.x + dx, y: player.position.y + dy)
        next.x = min(max(next.x, player.size), GameEngine.worldSize - player.size)
        next.y = min(max(next.y, player.size), GameEngine.worldSize - player.size)
        player.position = next
    }

    private func updateAbilityTimers(dt: Double) {
        if player.abilityCooldownRemaining > 0 {
            player.abilityCooldownRemaining = max(0, player.abilityCooldownRemaining - dt)
        }
        if player.abilityEffectRemaining > 0 {
            player.abilityEffectRemaining = max(0, player.abilityEffectRemaining - dt)
        }
    }

    private func updateWanderers(dt: Double) {
        for i in wanderers.indices {
            if Double.random(in: 0...1) < 0.01 {
                wanderers[i].heading += CGFloat.random(in: -0.6...0.6)
            }
            let speed: CGFloat = 40
            var pos = wanderers[i].position
            pos.x += cos(wanderers[i].heading) * speed * CGFloat(dt)
            pos.y += sin(wanderers[i].heading) * speed * CGFloat(dt)

            if pos.x < 0 || pos.x > GameEngine.worldSize { wanderers[i].heading = .pi - wanderers[i].heading }
            if pos.y < 0 || pos.y > GameEngine.worldSize { wanderers[i].heading = -wanderers[i].heading }
            pos.x = min(max(pos.x, 0), GameEngine.worldSize)
            pos.y = min(max(pos.y, 0), GameEngine.worldSize)
            wanderers[i].position = pos
        }
    }

    // MARK: - Rivals (§ new two-phase Play flow)

    private static let rivalCount = 6
    private static let rivalMinRadius: CGFloat = 12
    private static let rivalMaxRadius: CGFloat = PlayerState.maxRadius * 1.5
    private static let rivalPalette: [RGBColor] = [
        .hex(0xFF6B6B), .hex(0xFFC94D), .hex(0x6BCB77), .hex(0x4D96FF), .hex(0xC780FA), .hex(0xFF9F45)
    ]

    /// Scatters a fresh batch of rival dots around the player — called from
    /// `startRound` so both the practice room and the final room each open
    /// on a clean set rather than carrying over whatever survived before.
    private func spawnRivals() {
        rivals.removeAll()
        // One fresh batch of unique handles per spawn (§ new — "davi_32"-
        // style names shown under each rival in `WhiteSpaceView`), excluding
        // whatever the player is currently going by so nobody in the same
        // room ever shares a name.
        let names = NameGenerator.uniqueNames(count: GameEngine.rivalCount,
                                               excluding: Set([player.profile.username].compactMap { $0 }))
        for i in 0..<GameEngine.rivalCount {
            let angle = (Double(i) / Double(GameEngine.rivalCount)) * 2 * .pi
            let distance: CGFloat = 260
            let raw = CGPoint(x: player.position.x + CGFloat(cos(angle)) * distance,
                               y: player.position.y + CGFloat(sin(angle)) * distance)
            let position = CGPoint(x: min(max(raw.x, 40), GameEngine.worldSize - 40),
                                    y: min(max(raw.y, 40), GameEngine.worldSize - 40))
            rivals.append(RivalDot(
                position: position,
                heading: CGFloat.random(in: 0...(2 * .pi)),
                radius: CGFloat.random(in: GameEngine.rivalMinRadius...(GameEngine.rivalMinRadius + 8)),
                tint: GameEngine.rivalPalette[i % GameEngine.rivalPalette.count],
                username: names[i]
            ))
        }
    }

    /// Moves every rival and lets each one forage on its own — steering
    /// gently toward the nearest collectible within reach (so they read as
    /// actively hunting, the same as the player), and growing a little every
    /// time one lands a bite. Runs in both rooms; only
    /// `checkPlayerRivalCollisions` below cares which room it is.
    private func updateRivals(dt: Double) {
        guard !rivals.isEmpty else { return }
        let speed: CGFloat = 55
        for i in rivals.indices {
            if let target = nearestCollectiblePosition(to: rivals[i].position, within: 260) {
                let dx = target.x - rivals[i].position.x
                let dy = target.y - rivals[i].position.y
                rivals[i].heading = atan2(dy, dx)
            } else if Double.random(in: 0...1) < 0.02 {
                rivals[i].heading += CGFloat.random(in: -0.7...0.7)
            }

            var pos = rivals[i].position
            pos.x += cos(rivals[i].heading) * speed * CGFloat(dt)
            pos.y += sin(rivals[i].heading) * speed * CGFloat(dt)
            pos.x = min(max(pos.x, 0), GameEngine.worldSize)
            pos.y = min(max(pos.y, 0), GameEngine.worldSize)
            rivals[i].position = pos

            if let idx = collectibleIndex(near: rivals[i].position, eatRadius: rivals[i].radius + 8) {
                let eaten = collectibles.remove(at: idx)
                rivals[i].radius = min(GameEngine.rivalMaxRadius,
                                        rivals[i].radius + CGFloat(eaten.definition.absorptionPerEat) * 0.03)
            }
        }
    }

    private func nearestCollectiblePosition(to point: CGPoint, within range: CGFloat) -> CGPoint? {
        var best: CGPoint? = nil
        var bestDist = range
        for c in collectibles {
            let dx = c.position.x - point.x, dy = c.position.y - point.y
            let d = sqrt(dx * dx + dy * dy)
            if d < bestDist { bestDist = d; best = c.position }
        }
        return best
    }

    private func collectibleIndex(near point: CGPoint, eatRadius: CGFloat) -> Int? {
        for i in collectibles.indices {
            let c = collectibles[i]
            let dx = c.position.x - point.x, dy = c.position.y - point.y
            if sqrt(dx * dx + dy * dy) <= eatRadius { return i }
        }
        return nil
    }

    /// The actual "big eats small" rule (§ user request) — only active once
    /// `roundMode == .final`, so the earlier practice room stays purely
    /// collectible-eating with zero risk. A dot has to be a clear 15% bigger
    /// than the other, not just barely ahead, to actually eat it — keeps two
    /// close-to-even dots from instant-eating each other on first touch.
    private func checkPlayerRivalCollisions() {
        guard roundMode == .final, !playerWasEaten, !rivals.isEmpty else { return }
        let sizeMargin: CGFloat = 1.15
        for i in rivals.indices.reversed() {
            let rival = rivals[i]
            let dx = rival.position.x - player.position.x
            let dy = rival.position.y - player.position.y
            let dist = sqrt(dx * dx + dy * dy)
            let touchDistance = (player.size + rival.radius) * 0.6
            guard dist <= touchDistance else { continue }

            if player.size > rival.radius * sizeMargin {
                rivals.remove(at: i)
                absorbEffects.append(AbsorbEffect(startPosition: rival.position, color: rival.tint, magnitude: rival.radius))
                // A clearly bigger bump than a single collectible bite (§ user
                // feedback: eating a smaller dot should visibly "make you
                // bigger") — eating another dot is the headline move here.
                player.size = min(PlayerState.maxRadius, player.size + rival.radius * 0.35)
                player.profile.points += 5
                HapticsManager.shared.impact(.medium)
                AudioManager.shared.playEat()
            } else if rival.radius > player.size * sizeMargin {
                playerWasEaten = true
                HapticsManager.shared.impact(.medium)
                return
            }
        }
    }

    // MARK: - Collisions / eating

    private func checkCollisions() {
        guard !collectibles.isEmpty else { return }
        var eatenIndex: Int? = nil
        var pullRadius: CGFloat = 0
        if player.abilityEffectRemaining > 0, player.equippedAbility == .magnetPull {
            pullRadius = 220
        }
        // Rock's "Harden" — a temporarily bigger reach instead of a purely
        // defensive stat with nothing to defend against yet in solo White
        // Space (no PvP here — that's Dark Space, per §18–21, not built yet).
        var eatRadiusBonus: CGFloat = 0
        if player.abilityEffectRemaining > 0, player.equippedAbility == .harden {
            eatRadiusBonus = 14
        }

        for i in collectibles.indices {
            let c = collectibles[i]
            let dx = c.position.x - player.position.x
            let dy = c.position.y - player.position.y
            let dist = sqrt(dx * dx + dy * dy)
            let eatRadius = player.size + 10 + eatRadiusBonus

            if pullRadius > 0, dist < pullRadius, dist > eatRadius {
                // Drift the collectible toward the player.
                let pull: CGFloat = 140
                let nx = dx / max(dist, 1), ny = dy / max(dist, 1)
                collectibles[i].position.x -= nx * pull * 0.016
                collectibles[i].position.y -= ny * pull * 0.016
            }

            if dist <= eatRadius {
                eatenIndex = i
                break
            }
        }

        if let idx = eatenIndex {
            let eaten = collectibles.remove(at: idx)
            absorb(eaten.definition, from: eaten.position)
        }
    }

    private func absorb(_ definition: CollectibleDefinition, from position: CGPoint) {
        if definition.id == CollectibleCatalog.plainOrb.id {
            absorbPlainOrb(definition, from: position)
            return
        }
        // Kick off the "liquid" travel effect first so it starts exactly at
        // the collectible's last position, then run the actual (instant)
        // progress/completion math — the effect is purely cosmetic and never
        // gates the real absorb logic.
        absorbEffects.append(AbsorbEffect(startPosition: position, color: definition.primaryColor))

        // Combo bookkeeping: another bite within `comboWindow` of the last
        // one extends the streak; otherwise it starts a fresh one. Feeds the
        // Points multiplier below and, from ×2 up, a brief HUD banner.
        let now = Date()
        if let last = lastEatAt, now.timeIntervalSince(last) <= GameEngine.comboWindow {
            comboCount += 1
        } else {
            comboCount = 1
        }
        lastEatAt = now
        // +10% Points per combo step, capped at ×2.0 so a very long streak
        // stays a nice bonus rather than snowballing the currency.
        let comboMultiplier = 1.0 + Double(min(comboCount - 1, 10)) * 0.1
        if comboCount >= 2 {
            comboBannerGeneration += 1
            let generation = comboBannerGeneration
            comboBannerText = "×\(comboCount) COMBO"
            HapticsManager.shared.impact(.light)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self, self.comboBannerGeneration == generation else { return }
                self.comboBannerText = nil
            }
        }

        // A light tap and a soft sound on every single bite (§53: "light
        // haptics for eating, form completion, abilities" / §52 sound) —
        // both were documented but never actually wired up, so eating had
        // zero feedback until now.
        HapticsManager.shared.impact(.light)
        if definition.rarity >= .rare {
            AudioManager.shared.playRareEat()
        } else {
            AudioManager.shared.playEat()
        }

        let levelBefore = player.profile.intelligenceLevel
        let result = TransformationEngine.absorb(definition, into: player.profile)
        player.profile = result.profile
        player.lastEatenID = definition.id
        let didCompleteForm = result.didCompleteForm != nil

        // Every bite earns a few Points (§ new store currency) — more for
        // rarer finds — so there's always a steady, passive way to build up
        // toward AI+ Premium besides the direct/mock-purchase path in the
        // Store. Bonuses for the bigger milestones are added further below,
        // once we know whether this bite also completed a form or leveled up.
        player.profile.points += Int((Double(Self.pointsAward(for: definition.rarity)) * comboMultiplier).rounded())

        // What you eat nudges your size, not just your form (§ user feedback:
        // "the dot should get bigger when eat") — every single bite grows
        // you now, a "big/heavy" icon (rock, planet, blood...) just grows you
        // more than a "small/light" one (leaf, diamond, ghost...) per
        // `CollectibleDefinition.sizeEffect`, instead of that catalog's more
        // negative values actually shrinking the dot like before. Clamped so
        // it never grows past a sane, still-a-dot maximum.
        let growth = max(0.5, CGFloat(definition.sizeEffect))
        player.size = min(PlayerState.maxRadius, player.size + growth)

        // Completing a form still adds its own small permanent bump on top —
        // a milestone reward layered over the per-bite nudge above, not a
        // replacement for it.
        if didCompleteForm {
            player.size = min(player.size + 3, PlayerState.maxRadius)
            player.formCompleteBanner = definition
            player.profile.points += 30
            AudioManager.shared.playFormComplete()
            // (haptic success already fires from `formCompleteOverlay.onAppear`)
        }
        if player.profile.intelligenceLevel > levelBefore {
            let newLevel = player.profile.intelligenceLevel
            player.profile.points += 15
            HapticsManager.shared.impact(.medium)
            if didCompleteForm {
                // Completing a form often crosses a level threshold in the same
                // bite — stagger the two banners (and their sounds) instead of
                // stacking them.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { [weak player] in
                    player?.levelUpBanner = newLevel
                    AudioManager.shared.playLevelUp()
                }
            } else {
                player.levelUpBanner = newLevel
                AudioManager.shared.playLevelUp()
            }
        }
        saveManager.scheduleSave(player.profile)
    }

    /// A stripped-down absorb for `CollectibleCatalog.plainOrb` — the small
    /// blue filler pellets seeded in the final universe instead of icons.
    /// Deliberately skips `TransformationEngine`/`activeFormID`/progress/
    /// Intelligence entirely (unlike the full `absorb` above): an orb only
    /// nudges size and Points, so the player keeps showing up as whatever
    /// form they actually earned back in the first universe instead of a
    /// plain orb overwriting it (§ user feedback: "make the user as what he
    /// ate in the next universe"). Still gets the same combo streak, haptic,
    /// sound, and "liquid" absorb-effect visuals as a real bite, so it never
    /// reads as a different, lesser interaction.
    private func absorbPlainOrb(_ definition: CollectibleDefinition, from position: CGPoint) {
        absorbEffects.append(AbsorbEffect(startPosition: position, color: definition.primaryColor))

        let now = Date()
        if let last = lastEatAt, now.timeIntervalSince(last) <= GameEngine.comboWindow {
            comboCount += 1
        } else {
            comboCount = 1
        }
        lastEatAt = now
        let comboMultiplier = 1.0 + Double(min(comboCount - 1, 10)) * 0.1
        if comboCount >= 2 {
            comboBannerGeneration += 1
            let generation = comboBannerGeneration
            comboBannerText = "×\(comboCount) COMBO"
            HapticsManager.shared.impact(.light)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self, self.comboBannerGeneration == generation else { return }
                self.comboBannerText = nil
            }
        }

        HapticsManager.shared.impact(.light)
        AudioManager.shared.playEat()
        player.lastEatenID = definition.id
        player.profile.points += Int((Double(Self.pointsAward(for: definition.rarity)) * comboMultiplier).rounded())
        player.size = min(PlayerState.maxRadius, player.size + max(0.3, CGFloat(definition.sizeEffect)))
        saveManager.scheduleSave(player.profile)
    }

    /// Points awarded per single eat, scaled with rarity — deliberately
    /// modest (this is meant to accrue over a whole session, not hand out
    /// the Store's membership redemption cost in a few bites).
    static func pointsAward(for rarity: Rarity) -> Int {
        switch rarity {
        case .common: return 1
        case .uncommon: return 2
        case .rare: return 4
        case .epic: return 8
        case .legendary: return 15
        case .mythic: return 30
        }
    }

    // MARK: - Abilities

    func triggerAbility() {
        guard player.canUseAbility, let ability = player.equippedAbility else { return }
        player.abilityCooldownRemaining = ability.cooldown
        player.abilityEffectRemaining = ability.duration
        HapticsManager.shared.impact(.medium)
        AudioManager.shared.playAbility()

        // Fire's "Fire Pulse" — an instant burst that eats everything close
        // by right now, rather than a lingering timed effect like the others.
        if ability == .firePulse {
            firePulseBurst()
        }
        // NOTE: `.scan` and `.viewRange` still have no gameplay effect here —
        // their natural payoff (revealing nearby players/threats) needs real
        // opponents, which only exist once Dark Space/multiplayer (§88 Phase
        // 3–4) is built. Every other ability above has a real local effect.
    }

    private func firePulseBurst() {
        let burstRadius: CGFloat = 90
        let caught = collectibles.filter { c in
            let dx = c.position.x - player.position.x
            let dy = c.position.y - player.position.y
            return dx * dx + dy * dy <= burstRadius * burstRadius
        }
        guard !caught.isEmpty else { return }
        let caughtIDs = Set(caught.map(\.id))
        collectibles.removeAll { caughtIDs.contains($0.id) }
        for item in caught {
            absorb(item.definition, from: item.position)
        }
    }

    // MARK: - Spawning

    /// Only the `.practice` room (the first universe) spawns the actual
    /// icon catalog now — by the time the player reaches `.final` (the
    /// second universe) they've already eaten from that variety, so it
    /// reseeds plain blue filler orbs instead (§ user feedback: "they
    /// already ate in the first universe so the second universe... they
    /// will eat small blue dots"). Everything else about spawning —
    /// the cadence, the cap — stays identical between the two.
    private func handleSpawning(dt: Double) {
        timeSinceSpawnCheck += dt
        guard timeSinceSpawnCheck > 0.4 else { return }
        timeSinceSpawnCheck = 0
        guard collectibles.count < GameEngine.maxCollectibles else { return }
        if roundMode == .practice {
            spawnCollectible()
        } else {
            spawnCollectible(forcedDefinition: CollectibleCatalog.plainOrb)
        }
    }

    private func spawnCollectible(at fixedPosition: CGPoint? = nil, forcedRarity: Rarity? = nil, forcedDefinition: CollectibleDefinition? = nil) {
        let definition: CollectibleDefinition
        if let forcedDefinition {
            definition = forcedDefinition
        } else if let forcedRarity {
            definition = CollectibleCatalog.all.filter { $0.rarity == forcedRarity }.randomElement()
                ?? CollectibleCatalog.randomWeighted()
        } else {
            definition = CollectibleCatalog.randomWeighted()
        }
        let position = fixedPosition ?? CGPoint(
            x: CGFloat.random(in: 40...(GameEngine.worldSize - 40)),
            y: CGFloat.random(in: 40...(GameEngine.worldSize - 40))
        )
        collectibles.append(SpawnedCollectible(definition: definition, position: position))
    }

    private func makeWanderer() -> AmbientWanderer {
        AmbientWanderer(
            position: CGPoint(x: CGFloat.random(in: 0...GameEngine.worldSize),
                               y: CGFloat.random(in: 0...GameEngine.worldSize)),
            heading: CGFloat.random(in: 0...(2 * .pi)),
            tint: RGBColor(r: 0.25, g: 0.25, b: 0.27),
            radius: CGFloat.random(in: 10...20)
        )
    }

    // MARK: - Signals (§15, simplified for offline MVP)

    private func handleSignals(dt: Double) {
        // Signals hand out a bonus legendary icon — the same "no icons in
        // the final universe" rule above applies here too, so this whole
        // system stays a `.practice`-room-only bonus.
        guard roundMode == .practice else { return }
        if let signal = activeSignal {
            if Date() > signal.expiresAt {
                activeSignal = nil
                signalBannerText = nil
                return
            }
            let dx = signal.position.x - player.position.x
            let dy = signal.position.y - player.position.y
            if sqrt(dx * dx + dy * dy) < player.size + 26 {
                activeSignal?.claimed = true
                spawnCollectible(at: signal.position, forcedRarity: .legendary)
                player.profile.intelligence += 50
                activeSignal = nil
                signalBannerText = nil
            }
            return
        }

        timeSinceSignalCheck += dt
        guard timeSinceSignalCheck > 45 else { return }
        timeSinceSignalCheck = 0
        guard Double.random(in: 0...1) < 0.5 else { return }

        let position = CGPoint(x: CGFloat.random(in: 100...(GameEngine.worldSize - 100)),
                                y: CGFloat.random(in: 100...(GameEngine.worldSize - 100)))
        activeSignal = SignalEvent(position: position, expiresAt: Date().addingTimeInterval(40))
        signalBannerText = "SIGNAL DETECTED"
        HapticsManager.shared.impact(.light)
    }
}
