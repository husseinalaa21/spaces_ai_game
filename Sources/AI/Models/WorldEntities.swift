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

/// A simulated AI "rival" dot (§ new two-phase Play flow) — a stand-in for
/// another player since there's no real multiplayer/server yet. Unlike
/// `AmbientWanderer` above (purely decorative, never interacts with the
/// player), a `RivalDot` actively forages for collectibles and grows from
/// them just like the player does, and — once `GameEngine.roundMode` is
/// `.final` — can eat the player (or be eaten by it) based on which one is
/// bigger. `radius` is mutable, unlike a wanderer's fixed one, since growing
/// from what it eats is the whole point.
struct RivalDot: Identifiable {
    let id: UUID = UUID()
    var position: CGPoint
    var heading: CGFloat        // radians
    var radius: CGFloat
    let tint: RGBColor
    /// A handle like "davi_32" shown under the dot in `WhiteSpaceView`
    /// (§ new — "add names under the dots... all unique names"), generated
    /// once per rival at spawn time via `NameGenerator`.
    let username: String
}

/// Generates short, unique "davi_32"-style handles (§ new — names shown
/// under every dot in the universe, both the player's own and every rival's)
/// — a first-name-like word plus a two-digit number, distinct enough from a
/// plain dictionary word to read as a real handle.
enum NameGenerator {
    private static let firstNames = [
        "davi", "kai", "luna", "zane", "milo", "nova", "ren", "juno", "axel", "mira",
        "theo", "vera", "finn", "ivy", "remy", "sage", "orion", "nyx", "leo", "aria",
        "jax", "wren", "kian", "lyra", "toby", "nia", "enzo", "skye", "cruz", "lior"
    ]

    static func randomName() -> String {
        let first = firstNames.randomElement() ?? "dot"
        let number = Int.random(in: 10...99)
        return "\(first)_\(number)"
    }

    /// `count` distinct handles — collisions are just retried, and since
    /// `count` is always small (a handful of rivals, or a single player),
    /// this never meaningfully loops in practice. `excluding` lets a caller
    /// keep a newly generated batch distinct from names already in use
    /// elsewhere (not currently needed across rivals/player, but cheap
    /// insurance against a coincidental match).
    static func uniqueNames(count: Int, excluding existing: Set<String> = []) -> [String] {
        var used = existing
        var result: [String] = []
        var guardCount = 0
        while result.count < count && guardCount < count * 50 {
            guardCount += 1
            let candidate = randomName()
            guard !used.contains(candidate) else { continue }
            used.insert(candidate)
            result.append(candidate)
        }
        // Effectively unreachable (30 names × 90 numbers = 2700 combos for a
        // handful of dots), but a plain fallback beats ever looping forever.
        while result.count < count {
            result.append("dot_\(Int.random(in: 1000...9999))")
        }
        return result
    }
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

/// A brief "liquid" travel effect from an eaten collectible's last position
/// toward the player, so absorbing something visibly flows its color and
/// power into the player dot instead of just vanishing instantly. Purely
/// cosmetic/local — `WhiteSpaceView` animates and discards these; nothing
/// about the actual absorb logic (`TransformationEngine`) depends on them.
struct AbsorbEffect: Identifiable {
    let id: UUID = UUID()
    let startPosition: CGPoint
    let color: RGBColor
    /// Roughly the radius of whatever got eaten — a plain collectible (the
    /// default, 13, matches the fixed radius they're drawn at in
    /// `WhiteSpaceView`) or a rival dot's own (much larger, and variable)
    /// radius. Scales the whole splash — ripple, particle count/spread, the
    /// traveling droplet itself — so eating a big rival visibly reads as a
    /// bigger event than eating one small icon (§ user feedback: "the
    /// animation of eating either users or icons should be better").
    var magnitude: CGFloat = 13
    let startedAt: Date = Date()

    static let duration: Double = 0.5
}

/// Neutral food in the second universe; never changes the player's form.
struct GrowthDot: Identifiable {
    let id = UUID()
    var position: CGPoint
}
