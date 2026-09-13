import Foundation

/// The full set of collectibles available in this build.
///
/// This is the MVP starter set from MASTER BUILD PROMPT §83 (~30 icons).
/// The engine never special-cases an icon by name — everything reads from
/// this data, so growing the catalog later means adding entries here only.
enum CollectibleCatalog {
    static let all: [CollectibleDefinition] = [
        // MARK: Food
        CollectibleDefinition(id: "banana", name: "Banana", icon: "🍌", category: .food, rarity: .common,
                               primaryColor: .hex(0xFFD84D), activeAbility: .slipperyDash,
                               passiveDescription: "Faster direction changes.",
                               description: "Slippery. Hard to pin down.",
                               sizeEffect: -0.7),
        CollectibleDefinition(id: "apple", name: "Apple", icon: "🍎", category: .food, rarity: .common,
                               primaryColor: .hex(0xFF5B4D), activeAbility: nil,
                               passiveDescription: "Small steady health recovery.",
                               description: "Simple and reliable.",
                               sizeEffect: 0.2),
        CollectibleDefinition(id: "pizza", name: "Pizza", icon: "🍕", category: .food, rarity: .uncommon,
                               primaryColor: .hex(0xFFB347), activeAbility: nil,
                               passiveDescription: "Slightly increased growth.",
                               description: "Everyone's favorite.",
                               sizeEffect: 0.9),
        CollectibleDefinition(id: "coffee", name: "Coffee", icon: "☕", category: .food, rarity: .uncommon,
                               primaryColor: .hex(0x6F4E37), activeAbility: nil,
                               passiveDescription: "Temporary speed boost on eat.",
                               description: "A short, sharp jolt.",
                               sizeEffect: -0.7),

        // MARK: Nature / Earth
        CollectibleDefinition(id: "water", name: "Water", icon: "💧", category: .nature, rarity: .common,
                               primaryColor: .hex(0x3FA9F5), activeAbility: .flowEscape,
                               passiveDescription: "Smoother acceleration.",
                               description: "Flows around obstacles.",
                               sizeEffect: -0.7),
        CollectibleDefinition(id: "fire", name: "Fire", icon: "🔥", category: .nature, rarity: .uncommon,
                               primaryColor: .hex(0xFF5722), activeAbility: .firePulse,
                               passiveDescription: "Passive damage aura.",
                               description: "Dangerous up close.",
                               sizeEffect: 0.9),
        CollectibleDefinition(id: "lightning", name: "Lightning", icon: "⚡", category: .nature, rarity: .rare,
                               primaryColor: .hex(0xFFE14D), activeAbility: .speedBoost,
                               passiveDescription: "Increased movement speed.",
                               description: "Fast, unstable energy.",
                               sizeEffect: -0.7),
        CollectibleDefinition(id: "ice", name: "Ice", icon: "🧊", category: .nature, rarity: .uncommon,
                               primaryColor: .hex(0xAEEAFF), activeAbility: .slowPulse,
                               passiveDescription: "Nearby small dots slow slightly.",
                               description: "Cold and deliberate.",
                               sizeEffect: 0.2),
        CollectibleDefinition(id: "leaf", name: "Leaf", icon: "🌿", category: .nature, rarity: .common,
                               primaryColor: .hex(0x4CAF50), activeAbility: nil,
                               passiveDescription: "Slight regeneration.",
                               description: "Quiet and steady.",
                               sizeEffect: -1.3),
        CollectibleDefinition(id: "rock", name: "Rock", icon: "🪨", category: .nature, rarity: .common,
                               primaryColor: .hex(0x8D8478), activeAbility: .harden,
                               passiveDescription: "Increased resistance, slightly slower.",
                               description: "Solid. Hard to move.",
                               sizeEffect: 1.6),
        CollectibleDefinition(id: "cloud", name: "Cloud", icon: "☁️", category: .nature, rarity: .common,
                               primaryColor: .hex(0xE3E8ED), activeAbility: nil,
                               passiveDescription: "Slightly lighter, floatier movement.",
                               description: "Drifts without effort.",
                               sizeEffect: -1.3),
        CollectibleDefinition(id: "star", name: "Star", icon: "⭐", category: .nature, rarity: .rare,
                               primaryColor: .hex(0xFFD700), activeAbility: nil,
                               passiveDescription: "Small passive Intelligence bonus.",
                               description: "Distant and bright.",
                               sizeEffect: 0.9),

        // MARK: Space
        CollectibleDefinition(id: "planet", name: "Planet", icon: "🪐", category: .space, rarity: .epic,
                               primaryColor: .hex(0xB58CFF), activeAbility: nil,
                               passiveDescription: "Slight pull on nearby collectibles.",
                               description: "A small gravity of its own.",
                               sizeEffect: 1.6),
        CollectibleDefinition(id: "rocket", name: "Rocket", icon: "🚀", category: .space, rarity: .rare,
                               primaryColor: .hex(0xFF6B6B), activeAbility: .rocketDash,
                               passiveDescription: "Higher acceleration.",
                               description: "Built for a single burst.",
                               sizeEffect: -0.7),

        // MARK: Technology / AI
        CollectibleDefinition(id: "robot", name: "Robot", icon: "🤖", category: .technology, rarity: .rare,
                               primaryColor: .hex(0x9AA5B1), activeAbility: nil,
                               passiveDescription: "Steady, balanced stats.",
                               description: "Precise and consistent.",
                               sizeEffect: 0.9),
        CollectibleDefinition(id: "gear", name: "Gear", icon: "⚙️", category: .technology, rarity: .uncommon,
                               primaryColor: .hex(0x7C8792), activeAbility: nil,
                               passiveDescription: "Faster ability cooldown recovery.",
                               description: "Everything turns a little smoother.",
                               sizeEffect: -0.7),
        CollectibleDefinition(id: "battery", name: "Battery", icon: "🔋", category: .technology, rarity: .common,
                               primaryColor: .hex(0x66BB6A), activeAbility: nil,
                               passiveDescription: "Larger energy capacity.",
                               description: "Stores a little extra.",
                               sizeEffect: 0.2),
        CollectibleDefinition(id: "brain", name: "Brain", icon: "🧠", category: .body, rarity: .epic,
                               primaryColor: .hex(0xF48FB1), activeAbility: .scan,
                               passiveDescription: "Improved information about nearby objects.",
                               description: "Sees patterns others miss.",
                               sizeEffect: 0.2),
        CollectibleDefinition(id: "eye", name: "Eye", icon: "👁️", category: .body, rarity: .rare,
                               primaryColor: .hex(0x64B5F6), activeAbility: .viewRange,
                               passiveDescription: "Increased vision range.",
                               description: "Notices things from far away.",
                               sizeEffect: -0.7),

        // MARK: Body / Biological
        CollectibleDefinition(id: "blood", name: "Blood", icon: "🩸", category: .body, rarity: .rare,
                               primaryColor: .hex(0xC62828), activeAbility: nil,
                               passiveDescription: "Aggressive growth from consumption.",
                               description: "Intense and reckless.",
                               sizeEffect: 1.6),
        CollectibleDefinition(id: "heart", name: "Heart", icon: "❤️", category: .body, rarity: .common,
                               primaryColor: .hex(0xE53935), activeAbility: nil,
                               passiveDescription: "Slow passive regeneration.",
                               description: "Keeps things going.",
                               sizeEffect: 0.2),
        CollectibleDefinition(id: "skull", name: "Skull", icon: "💀", category: .body, rarity: .epic,
                               primaryColor: .hex(0x424242), activeAbility: nil,
                               passiveDescription: "Higher risk, higher reward encounters.",
                               description: "A dangerous state to be in.",
                               sizeEffect: 0.9),

        // MARK: Objects
        CollectibleDefinition(id: "shield", name: "Shield", icon: "🛡️", category: .objects, rarity: .rare,
                               primaryColor: .hex(0x789AE0), activeAbility: .shieldUp,
                               passiveDescription: "Increased defense.",
                               description: "A moment of safety, on demand.",
                               sizeEffect: 0.9),
        CollectibleDefinition(id: "magnet", name: "Magnet", icon: "🧲", category: .objects, rarity: .uncommon,
                               primaryColor: .hex(0xE0454C), activeAbility: .magnetPull,
                               passiveDescription: "Small collectibles drift toward you.",
                               description: "Things come to it.",
                               sizeEffect: -0.7),
        CollectibleDefinition(id: "diamond", name: "Diamond", icon: "💎", category: .objects, rarity: .legendary,
                               primaryColor: .hex(0x62E3FF), activeAbility: nil,
                               passiveDescription: "High collection value.",
                               description: "Rare, and it shows.",
                               sizeEffect: -1.3),
        CollectibleDefinition(id: "crystalBall", name: "Crystal Ball", icon: "🔮", category: .objects, rarity: .epic,
                               primaryColor: .hex(0xB388FF), activeAbility: nil,
                               passiveDescription: "Occasional glimpse of nearby Signals.",
                               description: "Knows more than it says.",
                               sizeEffect: 0.2),
        CollectibleDefinition(id: "crown", name: "Crown", icon: "👑", category: .objects, rarity: .legendary,
                               primaryColor: .hex(0xFFC107), activeAbility: nil,
                               passiveDescription: "Passive Intelligence bonus.",
                               description: "Status, not strength.",
                               sizeEffect: -0.7),

        // MARK: Animals
        CollectibleDefinition(id: "turtle", name: "Turtle", icon: "🐢", category: .animal, rarity: .common,
                               primaryColor: .hex(0x66BB6A), activeAbility: nil,
                               passiveDescription: "Increased defense, slower movement.",
                               description: "Slow and protected.",
                               sizeEffect: 0.9),
        CollectibleDefinition(id: "rabbit", name: "Rabbit", icon: "🐇", category: .animal, rarity: .uncommon,
                               primaryColor: .hex(0xEFEBE9), activeAbility: nil,
                               passiveDescription: "Increased base speed.",
                               description: "Quick to react.",
                               sizeEffect: -1.3),
        CollectibleDefinition(id: "ghost", name: "Ghost", icon: "👻", category: .emotion, rarity: .epic,
                               primaryColor: .hex(0xE1E8F0), activeAbility: .ghostPhase,
                               passiveDescription: "Slight transparency.",
                               description: "Not fully here.",
                               sizeEffect: -1.3),
    ]

    static func definition(for id: String) -> CollectibleDefinition? {
        byID[id]
    }

    private static let byID: [String: CollectibleDefinition] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    /// Weighted random pick used by the spawner.
    static func randomWeighted() -> CollectibleDefinition {
        let totalWeight = all.reduce(0) { $0 + $1.rarity.spawnWeight }
        var roll = Double.random(in: 0..<totalWeight)
        for def in all {
            roll -= def.rarity.spawnWeight
            if roll <= 0 { return def }
        }
        return all[0]
    }
}
