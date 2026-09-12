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

    let player: PlayerState

    @Published var collectibles: [SpawnedCollectible] = []
    @Published var wanderers: [AmbientWanderer] = []
    @Published var activeSignal: SignalEvent? = nil
    @Published var signalBannerText: String? = nil
    @Published var absorbEffects: [AbsorbEffect] = []
    @Published var timeRemaining: Double = GameEngine.roundDuration
    @Published var roundExpired: Bool = false

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

    /// Resets the round clock and lets the world start fresh — called each
    /// time the player taps Play on the main menu (§ new home screen flow).
    func startRound() {
        timeRemaining = GameEngine.roundDuration
        roundExpired = false
    }

    // MARK: - Frame update

    func tick(dt: Double) {
        guard dt > 0, dt < 1 else { return }
        updateMovement(dt: dt)
        updateAbilityTimers(dt: dt)
        updateWanderers(dt: dt)
        checkCollisions()
        handleSpawning(dt: dt)
        handleSignals(dt: dt)
        cleanUpAbsorbEffects()
        updateRoundTimer(dt: dt)
    }

    private func updateRoundTimer(dt: Double) {
        guard timeRemaining > 0 else { return }
        timeRemaining = max(0, timeRemaining - dt)
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

    // MARK: - Collisions / eating

    private func checkCollisions() {
        guard !collectibles.isEmpty else { return }
        var eatenIndex: Int? = nil
        var pullRadius: CGFloat = 0
        if player.abilityEffectRemaining > 0, player.equippedAbility == .magnetPull {
            pullRadius = 220
        }

        for i in collectibles.indices {
            let c = collectibles[i]
            let dx = c.position.x - player.position.x
            let dy = c.position.y - player.position.y
            let dist = sqrt(dx * dx + dy * dy)
            let eatRadius = player.size + 10

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
        // Kick off the "liquid" travel effect first so it starts exactly at
        // the collectible's last position, then run the actual (instant)
        // progress/completion math — the effect is purely cosmetic and never
        // gates the real absorb logic.
        absorbEffects.append(AbsorbEffect(startPosition: position, color: definition.primaryColor))

        let result = TransformationEngine.absorb(definition, into: player.profile)
        player.profile = result.profile
        player.lastEatenID = definition.id
        // Growth: the dot grows very slightly with every completed form, not every bite,
        // so size stays a meaningful long-term signal rather than jittering constantly.
        if result.didCompleteForm != nil {
            player.size = min(player.size + 3, PlayerState.baseRadius * 3)
            player.formCompleteBanner = definition
        }
        saveManager.scheduleSave(player.profile)
    }

    // MARK: - Abilities

    func triggerAbility() {
        guard player.canUseAbility, let ability = player.equippedAbility else { return }
        player.abilityCooldownRemaining = ability.cooldown
        player.abilityEffectRemaining = ability.duration
        HapticsManager.shared.impact(.medium)
    }

    // MARK: - Spawning

    private func handleSpawning(dt: Double) {
        timeSinceSpawnCheck += dt
        guard timeSinceSpawnCheck > 0.4 else { return }
        timeSinceSpawnCheck = 0
        if collectibles.count < GameEngine.maxCollectibles {
            spawnCollectible()
        }
    }

    private func spawnCollectible(at fixedPosition: CGPoint? = nil, forcedRarity: Rarity? = nil) {
        let definition: CollectibleDefinition
        if let forcedRarity {
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
