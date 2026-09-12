import SwiftUI

/// Broad content categories, used for spawn weighting and the Collection screen tabs.
/// Matches MASTER BUILD PROMPT §9 and §48.
enum IconCategory: String, Codable, CaseIterable, Identifiable, Equatable {
    case food, nature, body, technology, space, emotion, animal, objects
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .food: return "Food"
        case .nature: return "Nature"
        case .body: return "Body"
        case .technology: return "Technology"
        case .space: return "Space"
        case .emotion: return "Emotion"
        case .animal: return "Animal"
        case .objects: return "Objects"
        }
    }
}

/// Rarity tiers. Matches §10 — visual treatment stays subtle, rarity mostly
/// affects spawn weight and how much progress a single eat contributes.
enum Rarity: String, Codable, CaseIterable, Comparable {
    case common, uncommon, rare, epic, legendary, mythic

    private var sortOrder: Int {
        switch self {
        case .common: return 0
        case .uncommon: return 1
        case .rare: return 2
        case .epic: return 3
        case .legendary: return 4
        case .mythic: return 5
        }
    }

    static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.sortOrder < rhs.sortOrder }

    /// Relative chance of spawning. Higher rarity = rarer.
    var spawnWeight: Double {
        switch self {
        case .common: return 100
        case .uncommon: return 45
        case .rare: return 18
        case .epic: return 7
        case .legendary: return 2.5
        case .mythic: return 0.6
        }
    }

    /// A single eat of a rarer item contributes more toward its own 100% completion,
    /// so rare forms don't take absurdly long to finish despite spawning less.
    var absorptionPerEat: Double {
        switch self {
        case .common: return 6
        case .uncommon: return 8
        case .rare: return 11
        case .epic: return 16
        case .legendary: return 25
        case .mythic: return 34
        }
    }

    var ringLineWidth: CGFloat {
        switch self {
        case .common: return 0
        case .uncommon: return 1.2
        case .rare: return 1.6
        case .epic: return 2.0
        case .legendary: return 2.4
        case .mythic: return 2.8
        }
    }
}

/// A codable RGB color so collectible definitions can be plain data (§8 data fields).
struct RGBColor: Codable, Equatable {
    let r: Double
    let g: Double
    let b: Double

    var color: Color { Color(red: r, green: g, blue: b) }

    static func hex(_ hex: UInt32) -> RGBColor {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        return RGBColor(r: r, g: g, b: b)
    }
}

/// The identifier for an unlockable active ability. Kept separate from the
/// collectible id so multiple forms could theoretically share an ability later.
enum AbilityID: String, Codable, CaseIterable, Equatable {
    case slipperyDash        // Banana
    case harden               // Rock
    case firePulse            // Fire
    case slowPulse            // Ice
    case speedBoost           // Lightning / Electricity
    case flowEscape           // Water
    case scan                 // Brain
    case viewRange            // Eye
    case magnetPull           // Magnet
    case rocketDash           // Rocket
    case shieldUp             // Shield
    case ghostPhase           // Ghost

    var displayName: String {
        switch self {
        case .slipperyDash: return "Slippery Dash"
        case .harden: return "Harden"
        case .firePulse: return "Fire Pulse"
        case .slowPulse: return "Slow Pulse"
        case .speedBoost: return "Speed Boost"
        case .flowEscape: return "Flow Escape"
        case .scan: return "Scan"
        case .viewRange: return "Eagle Eye"
        case .magnetPull: return "Magnet Pull"
        case .rocketDash: return "Rocket Dash"
        case .shieldUp: return "Shield Up"
        case .ghostPhase: return "Phase"
        }
    }

    /// Seconds before the ability can be used again.
    var cooldown: Double {
        switch self {
        case .slipperyDash, .rocketDash, .ghostPhase: return 6
        case .harden, .shieldUp: return 10
        case .firePulse, .slowPulse: return 8
        case .speedBoost, .flowEscape: return 7
        case .scan, .viewRange: return 12
        case .magnetPull: return 9
        }
    }

    /// How long the effect lasts once triggered.
    var duration: Double {
        switch self {
        case .slipperyDash, .rocketDash: return 0.4
        case .ghostPhase: return 2.5
        case .harden, .shieldUp: return 3.0
        case .firePulse, .slowPulse: return 1.5
        case .speedBoost, .flowEscape: return 4.0
        case .scan, .viewRange: return 5.0
        case .magnetPull: return 4.0
        }
    }
}

/// Static, data-driven definition of a single collectible/form.
/// This is deliberately plain data (§8) so new icons can be added without
/// touching engine logic — see `CollectibleCatalog`.
struct CollectibleDefinition: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let icon: String              // emoji glyph, drawn directly — no art assets required
    let category: IconCategory
    let rarity: Rarity
    let primaryColor: RGBColor
    let activeAbility: AbilityID?
    let passiveDescription: String
    let description: String

    var absorptionPerEat: Double { rarity.absorptionPerEat }
}
