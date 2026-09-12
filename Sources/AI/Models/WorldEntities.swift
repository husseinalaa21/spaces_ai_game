import Foundation
import CoreGraphics

/// A collectible that currently exists somewhere in the White Space world.
struct SpawnedCollectible: Identifiable {
    let id: UUID = UUID()
    let definition: CollectibleDefinition
    var position: CGPoint
    /// Rare spawns get a slow pulse animation (§10 — "light animation" for Rare+).
    var spawnedAt: Date = Date()
}

/// A purely cosmetic, locally-simulated dot that makes the world feel populated
/// (§23 AI-controlled dots) until real multiplayer is wired up. It wanders
/// gently and never interacts with the player in this build.
struct AmbientWanderer: Identifiable {
    let id: UUID = UUID()
    var position: CGPoint
    var heading: CGFloat        // radians
    let tint: RGBColor
    let radius: CGFloat
}

/// A lightweight local "Signal" event (§15). In this offline build it simply
/// marks a point of interest in the world with a bonus, rarer-weighted spawn
/// and a banner the player can navigate toward.
struct SignalEvent: Identifiable {
    let id: UUID = UUID()
    var position: CGPoint
    var expiresAt: Date
    var claimed: Bool = false
}
