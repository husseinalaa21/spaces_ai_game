import Foundation

/// Turns "the player ate collectible X" into updated percentages, a new active
/// form, Intelligence gain, and (when a form crosses 100%) a completion event.
///
/// Deterministic and side-effect free on its own — it reads/writes only the
/// `PlayerProfile` it's handed, per §90's "make the logic deterministic and
/// testable" requirement. `GameEngine` is what wires it to the live UI.
enum TransformationEngine {

    struct AbsorptionResult {
        var profile: PlayerProfile
        var intelligenceGained: Int
        var didCompleteForm: CollectibleDefinition?
        var isNewDiscovery: Bool
    }

    /// Independent-completion-progress model recommended for MVP by §91:
    /// each form tracks its own 0...100 progress, and the "active" transformation
    /// is simply whatever the player most recently pursued.
    static func absorb(_ definition: CollectibleDefinition, into profile: PlayerProfile) -> AbsorptionResult {
        var profile = profile
        let isNewDiscovery = profile.progress[definition.id] == nil

        let current = profile.progress[definition.id] ?? 0
        let already100 = current >= 100
        let updated = min(100, current + definition.absorptionPerEat)
        profile.progress[definition.id] = updated

        // Eating something you haven't maxed becomes your active pursuit.
        if !already100 {
            profile.activeFormID = definition.id
        }

        var intelligenceGained = isNewDiscovery ? 5 : 1
        var completed: CollectibleDefinition? = nil

        if updated >= 100 && !already100 {
            profile.completedForms.insert(definition.id)
            intelligenceGained += 20 + Int(definition.rarity.spawnWeight > 10 ? 0 : 15) // rarer forms pay out a bit more
            completed = definition
        }

        profile.intelligence += intelligenceGained
        profile.intelligenceLevel = levelForIntelligence(profile.intelligence)

        return AbsorptionResult(profile: profile,
                                 intelligenceGained: intelligenceGained,
                                 didCompleteForm: completed,
                                 isNewDiscovery: isNewDiscovery)
    }

    static func levelForIntelligence(_ intelligence: Int) -> Int {
        // Simple curve: level N requires N*(N+1)/2 * 25 cumulative Intelligence.
        var level = 1
        while intelligence >= requiredIntelligence(forLevel: level + 1) {
            level += 1
        }
        return level
    }

    static func requiredIntelligence(forLevel level: Int) -> Int {
        let n = level - 1
        return (n * (n + 1) / 2) * 25
    }

    static func progressToNextLevel(_ profile: PlayerProfile) -> Double {
        let currentFloor = requiredIntelligence(forLevel: profile.intelligenceLevel)
        let nextFloor = requiredIntelligence(forLevel: profile.intelligenceLevel + 1)
        guard nextFloor > currentFloor else { return 1 }
        let into = Double(profile.intelligence - currentFloor)
        let span = Double(nextFloor - currentFloor)
        return max(0, min(1, into / span))
    }

    /// Dark Space unlock requirements from §17's example numbers.
    static func isDarkSpaceUnlocked(_ profile: PlayerProfile) -> Bool {
        profile.completedForms.count >= 5 && profile.intelligenceLevel >= 10
    }
}
