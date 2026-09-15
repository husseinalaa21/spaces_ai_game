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
    /// How much this item nudges the player's size on the SAME bite it's
    /// eaten on — positive grows, negative shrinks. Roughly themed to how
    /// "big/heavy" vs. "small/light" each icon reads (a rock or planet
    /// grows you; a leaf or diamond shrinks you), decoded once from data
    /// here so the engine never special-cases an icon by name (§8).
    var sizeEffect: Double = 0

    var absorptionPerEat: Double { rarity.absorptionPerEat }
}

// MARK: - Cosmetics (§27-29's AI+ premium store, MVP'd locally per §87)
//
// Kept in this already-tracked file rather than a new one: this project's
// Xcode project is generated by XcodeGen from `project.yml`'s folder-level
// `sources: Sources/AI`, which only picks up new files the next time
// `xcodegen generate` is run (see README) — an edit to an existing file
// needs no regeneration, so new cosmetic types land here instead.

/// Shared shape for the two cosmetic picker rows on the main menu
/// (`MainMenuView`) — one free option plus a few AI+ premium ones, each with
/// just enough to draw as a small swatch. Keeping this generic means the
/// picker UI is written once and works for both `UniverseTheme` and `DotStyle`.
protocol CosmeticOption: Identifiable, CaseIterable, Equatable {
    var displayName: String { get }
    var isPremium: Bool { get }
    var swatchColor: Color { get }
    /// Points cost to buy this one item individually (§ new — "add more to
    /// buy... set price for them"), independent of the AI+ subscription,
    /// which still unlocks everything at once regardless of this value. 0
    /// for every free option.
    var price: Int { get }
}

/// A selectable background look for White Space — the free "White" universe
/// plus a growing set of AI+ palette swaps, each individually purchasable
/// with Points too (§ new — "add more universes to buy"), not just via the
/// AI+ subscription. Purely cosmetic: the grid, spawns, and gameplay all
/// behave identically no matter which one is active, per §38's "cosmetics
/// only, never pay-to-win" monetization rule. The actual in-game colors live
/// in `WorldBackground.palette(for:)`; `swatchColor` here is just a quick
/// accent used for tiny preview details.
enum UniverseTheme: String, Codable, CaseIterable, Identifiable, CosmeticOption {
    case white, sunset, midnight, ocean, forest, bubblegum, volcano, aurora, cosmic
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .white: return "White"
        case .sunset: return "Sunset"
        case .midnight: return "Midnight"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .bubblegum: return "Bubblegum"
        case .volcano: return "Volcano"
        case .aurora: return "Aurora"
        case .cosmic: return "Cosmic"
        }
    }

    /// "White" is the one every player already has; the rest are the AI+
    /// perk the user asked for (their "Prepaid" section) — or buyable
    /// individually below.
    var isPremium: Bool { self != .white }

    var price: Int {
        switch self {
        case .white: return 0
        case .sunset: return 300
        case .midnight: return 450
        case .ocean: return 350
        case .forest: return 350
        case .bubblegum: return 400
        case .volcano: return 600
        case .aurora: return 900
        case .cosmic: return 1500
        }
    }

    var swatchColor: Color {
        switch self {
        case .white: return .white
        case .sunset: return Color(red: 1.0, green: 0.72, blue: 0.5)
        case .midnight: return Color(red: 0.10, green: 0.10, blue: 0.22)
        case .ocean: return Color(red: 0.25, green: 0.55, blue: 0.85)
        case .forest: return Color(red: 0.30, green: 0.60, blue: 0.32)
        case .bubblegum: return Color(red: 0.98, green: 0.55, blue: 0.75)
        case .volcano: return Color(red: 0.85, green: 0.30, blue: 0.12)
        case .aurora: return Color(red: 0.30, green: 0.90, blue: 0.70)
        case .cosmic: return Color(red: 0.55, green: 0.30, blue: 0.85)
        }
    }
}

/// A selectable cosmetic material for the player's own dot — §28/§29's
/// "Premium Dots" grown into a much larger catalog (§ new — "add more dots
/// wearing thing... set price for them"), each with its own Points price.
/// Layered on top of the existing eat-driven color blend, never replacing
/// it, so the dot is still obviously a dot either way (§82). The actual
/// tint/shine/hat each one draws lives in `visual` below, kept as plain data
/// here so `DotRenderer` never needs a giant per-case switch of its own.
enum DotStyle: String, Codable, CaseIterable, Identifiable, CosmeticOption {
    case classic, gold, diamond, galaxy
    case silver, ruby, emerald, sapphire, obsidian, roseGold, neon, rainbow,
         fire, ice, electric, toxic, mint, lava, crystal, shadow, chrome,
         nebula, candy, royal
    // § new — "the style of the dots needs more work and more styles":
    // a second wave on top of the first big expansion above.
    case frost, sunburst, amethyst, jade, platinum, coral, storm, blossom,
         ember, glacier, phantom, starlight, wildfire, velvet
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Default"
        case .gold: return "Gold"
        case .diamond: return "Diamond"
        case .galaxy: return "Galaxy"
        case .silver: return "Silver"
        case .ruby: return "Ruby"
        case .emerald: return "Emerald"
        case .sapphire: return "Sapphire"
        case .obsidian: return "Obsidian"
        case .roseGold: return "Rose Gold"
        case .neon: return "Neon"
        case .rainbow: return "Rainbow"
        case .fire: return "Fire"
        case .ice: return "Ice"
        case .electric: return "Electric"
        case .toxic: return "Toxic"
        case .mint: return "Mint"
        case .lava: return "Lava"
        case .crystal: return "Crystal"
        case .shadow: return "Shadow"
        case .chrome: return "Chrome"
        case .nebula: return "Nebula"
        case .candy: return "Candy"
        case .royal: return "Royal"
        case .frost: return "Frost"
        case .sunburst: return "Sunburst"
        case .amethyst: return "Amethyst"
        case .jade: return "Jade"
        case .platinum: return "Platinum"
        case .coral: return "Coral"
        case .storm: return "Storm"
        case .blossom: return "Blossom"
        case .ember: return "Ember"
        case .glacier: return "Glacier"
        case .phantom: return "Phantom"
        case .starlight: return "Starlight"
        case .wildfire: return "Wildfire"
        case .velvet: return "Velvet"
        }
    }

    var isPremium: Bool { self != .classic }

    var price: Int {
        switch self {
        case .classic: return 0
        case .silver: return 250
        case .mint: return 300
        case .gold: return 300
        case .blossom: return 350
        case .coral: return 350
        case .candy: return 350
        case .ruby: return 350
        case .emerald: return 350
        case .jade: return 400
        case .toxic: return 400
        case .sapphire: return 400
        case .obsidian: return 400
        case .roseGold: return 450
        case .ice: return 450
        case .shadow: return 450
        case .diamond: return 500
        case .neon: return 500
        case .electric: return 500
        case .ember: return 500
        case .frost: return 500
        case .fire: return 550
        case .lava: return 550
        case .amethyst: return 550
        case .wildfire: return 550
        case .glacier: return 550
        case .storm: return 600
        case .chrome: return 600
        case .sunburst: return 650
        case .crystal: return 650
        case .royal: return 700
        case .phantom: return 700
        case .platinum: return 750
        case .velvet: return 800
        case .galaxy: return 800
        case .rainbow: return 900
        case .nebula: return 1200
        case .starlight: return 1000
        }
    }

    var swatchColor: Color {
        switch self {
        case .classic: return Color(red: 41 / 255, green: 121 / 255, blue: 255 / 255)
        case .gold: return Color(red: 0.86, green: 0.66, blue: 0.13)
        case .diamond: return Color(red: 0.55, green: 0.92, blue: 1.0)
        case .galaxy: return Color(red: 0.50, green: 0.28, blue: 0.86)
        case .silver: return Color(red: 0.67, green: 0.75, blue: 0.86)
        case .ruby: return Color(red: 0.86, green: 0.13, blue: 0.27)
        case .emerald: return Color(red: 0.13, green: 0.86, blue: 0.48)
        case .sapphire: return Color(red: 0.13, green: 0.33, blue: 0.86)
        case .obsidian: return Color(red: 0.69, green: 0.69, blue: 0.86)
        case .roseGold: return Color(red: 0.90, green: 0.70, blue: 0.65)
        case .neon: return Color(red: 0.30, green: 1.0, blue: 0.50)
        case .rainbow: return Color(red: 0.95, green: 0.35, blue: 0.85)
        case .fire: return Color(red: 1.00, green: 0.42, blue: 0.15)
        case .ice: return Color(red: 0.65, green: 0.90, blue: 1.0)
        case .electric: return Color(red: 1.0, green: 0.92, blue: 0.15)
        case .toxic: return Color(red: 0.56, green: 0.92, blue: 0.14)
        case .mint: return Color(red: 0.60, green: 0.92, blue: 0.82)
        case .lava: return Color(red: 0.86, green: 0.22, blue: 0.13)
        case .crystal: return Color(red: 0.85, green: 0.95, blue: 1.0)
        case .shadow: return Color(red: 0.54, green: 0.54, blue: 0.86)
        case .chrome: return Color(red: 0.82, green: 0.85, blue: 0.88)
        case .nebula: return Color(red: 0.61, green: 0.25, blue: 0.86)
        case .candy: return Color(red: 1.0, green: 0.55, blue: 0.80)
        case .royal: return Color(red: 0.56, green: 0.15, blue: 0.86)
        case .frost: return Color(red: 0.80, green: 0.93, blue: 1.0)
        case .sunburst: return Color(red: 1.00, green: 0.67, blue: 0.15)
        case .amethyst: return Color(red: 0.63, green: 0.29, blue: 0.86)
        case .jade: return Color(red: 0.16, green: 0.86, blue: 0.70)
        case .platinum: return Color(red: 0.88, green: 0.90, blue: 0.92)
        case .coral: return Color(red: 1.0, green: 0.50, blue: 0.45)
        case .storm: return Color(red: 0.57, green: 0.67, blue: 0.86)
        case .blossom: return Color(red: 1.0, green: 0.78, blue: 0.86)
        case .ember: return Color(red: 0.90, green: 0.29, blue: 0.14)
        case .glacier: return Color(red: 0.70, green: 0.92, blue: 0.98)
        case .phantom: return Color(red: 0.69, green: 0.54, blue: 0.86)
        case .starlight: return Color(red: 0.95, green: 0.97, blue: 1.0)
        case .wildfire: return Color(red: 0.95, green: 0.28, blue: 0.14)
        case .velvet: return Color(red: 0.86, green: 0.13, blue: 0.49)
        }
    }

    /// A small worn accessory beyond the hat (§ new — "more cloths"), drawn
    /// as a simple vector shape (not another SF Symbol lookup) at chest
    /// level so it reads as something the dot is actually wearing rather
    /// than just another badge floating on its head. `DotRenderer` owns the
    /// actual drawing per case; this only names which one.
    enum Accessory: Equatable {
        case none, bowtie, scarf, collar, cape, medal
    }

    /// Everything `DotRenderer` needs to actually paint this style, kept as
    /// one small data bundle per case instead of a second giant switch
    /// living over in `DotRenderer` itself.
    struct Visual {
        /// The color the base transformation color mixes toward.
        let accentColor: Color
        /// 0 = no tint at all (the free `.classic` look), higher = stronger.
        let mixAmount: Double
        /// Extra brightness/gloss added to the highlight — premium styles
        /// read shinier than the plain classic dot.
        let shine: Double
        /// Galaxy/Nebula/Starlight's signature: a few tiny twinkling stars
        /// clipped to the body outline instead of a plain tinted fill.
        let hasStars: Bool
        /// Rainbow's signature: the accent color itself slowly cycles hue
        /// over time instead of staying fixed.
        let hasRainbow: Bool
        /// SF Symbol worn perched on top of the head — `nil` wears nothing.
        let hatSymbol: String?
        /// A second, lower worn item (§ new — "more cloths") — `.none` wears
        /// nothing extra beyond the hat.
        var accessory: Accessory = .none
    }

    var visual: Visual {
        switch self {
        case .classic:
            return Visual(accentColor: swatchColor, mixAmount: 0, shine: 0, hasStars: false, hasRainbow: false, hatSymbol: nil, accessory: .none)
        case .gold:
            return Visual(accentColor: Color(red: 1.0, green: 0.82, blue: 0.35), mixAmount: 0.55, shine: 0.15, hasStars: false, hasRainbow: false, hatSymbol: "crown.fill", accessory: .medal)
        case .diamond:
            return Visual(accentColor: Color(red: 0.75, green: 0.95, blue: 1.0), mixAmount: 0.5, shine: 0.25, hasStars: false, hasRainbow: false, hatSymbol: "diamond.fill", accessory: .collar)
        case .galaxy:
            return Visual(accentColor: Color(red: 0.22, green: 0.12, blue: 0.45), mixAmount: 0.6, shine: 0.05, hasStars: true, hasRainbow: false, hatSymbol: "moon.stars.fill", accessory: .cape)
        case .silver:
            return Visual(accentColor: Color(red: 0.80, green: 0.82, blue: 0.86), mixAmount: 0.5, shine: 0.2, hasStars: false, hasRainbow: false, hatSymbol: "medal.fill", accessory: .bowtie)
        case .ruby:
            return Visual(accentColor: swatchColor, mixAmount: 0.55, shine: 0.2, hasStars: false, hasRainbow: false, hatSymbol: "heart.fill", accessory: .medal)
        case .emerald:
            return Visual(accentColor: swatchColor, mixAmount: 0.55, shine: 0.2, hasStars: false, hasRainbow: false, hatSymbol: "leaf.fill", accessory: .collar)
        case .sapphire:
            return Visual(accentColor: swatchColor, mixAmount: 0.55, shine: 0.25, hasStars: false, hasRainbow: false, hatSymbol: "drop.fill", accessory: .bowtie)
        case .obsidian:
            return Visual(accentColor: swatchColor, mixAmount: 0.65, shine: 0.08, hasStars: false, hasRainbow: false, hatSymbol: "shield.fill", accessory: .cape)
        case .roseGold:
            return Visual(accentColor: swatchColor, mixAmount: 0.5, shine: 0.25, hasStars: false, hasRainbow: false, hatSymbol: "gift.fill", accessory: .bowtie)
        case .neon:
            return Visual(accentColor: swatchColor, mixAmount: 0.6, shine: 0.35, hasStars: false, hasRainbow: false, hatSymbol: "bolt.fill", accessory: .collar)
        case .rainbow:
            return Visual(accentColor: swatchColor, mixAmount: 0.5, shine: 0.3, hasStars: false, hasRainbow: true, hatSymbol: "sparkles", accessory: .bowtie)
        case .fire:
            return Visual(accentColor: swatchColor, mixAmount: 0.55, shine: 0.3, hasStars: false, hasRainbow: false, hatSymbol: "flame.fill", accessory: .scarf)
        case .ice:
            return Visual(accentColor: swatchColor, mixAmount: 0.55, shine: 0.3, hasStars: false, hasRainbow: false, hatSymbol: "snowflake", accessory: .scarf)
        case .electric:
            return Visual(accentColor: swatchColor, mixAmount: 0.5, shine: 0.35, hasStars: false, hasRainbow: false, hatSymbol: "bolt.fill", accessory: .collar)
        case .toxic:
            return Visual(accentColor: swatchColor, mixAmount: 0.6, shine: 0.2, hasStars: false, hasRainbow: false, hatSymbol: "leaf.fill", accessory: .collar)
        case .mint:
            return Visual(accentColor: swatchColor, mixAmount: 0.5, shine: 0.2, hasStars: false, hasRainbow: false, hatSymbol: "leaf.fill", accessory: .none)
        case .lava:
            return Visual(accentColor: swatchColor, mixAmount: 0.6, shine: 0.15, hasStars: false, hasRainbow: false, hatSymbol: "flame.fill", accessory: .scarf)
        case .crystal:
            return Visual(accentColor: swatchColor, mixAmount: 0.45, shine: 0.4, hasStars: false, hasRainbow: false, hatSymbol: "diamond.fill", accessory: .medal)
        case .shadow:
            return Visual(accentColor: swatchColor, mixAmount: 0.7, shine: 0.05, hasStars: false, hasRainbow: false, hatSymbol: "moon.fill", accessory: .cape)
        case .chrome:
            return Visual(accentColor: swatchColor, mixAmount: 0.6, shine: 0.5, hasStars: false, hasRainbow: false, hatSymbol: "shield.fill", accessory: .collar)
        case .nebula:
            return Visual(accentColor: swatchColor, mixAmount: 0.6, shine: 0.1, hasStars: true, hasRainbow: false, hatSymbol: "sparkles", accessory: .cape)
        case .candy:
            return Visual(accentColor: swatchColor, mixAmount: 0.5, shine: 0.25, hasStars: false, hasRainbow: false, hatSymbol: "gift.fill", accessory: .bowtie)
        case .royal:
            return Visual(accentColor: swatchColor, mixAmount: 0.55, shine: 0.2, hasStars: false, hasRainbow: false, hatSymbol: "crown.fill", accessory: .cape)
        case .frost:
            return Visual(accentColor: swatchColor, mixAmount: 0.5, shine: 0.3, hasStars: false, hasRainbow: false, hatSymbol: "snowflake", accessory: .scarf)
        case .sunburst:
            return Visual(accentColor: swatchColor, mixAmount: 0.55, shine: 0.35, hasStars: false, hasRainbow: false, hatSymbol: "sun.max.fill", accessory: .cape)
        case .amethyst:
            return Visual(accentColor: swatchColor, mixAmount: 0.55, shine: 0.3, hasStars: false, hasRainbow: false, hatSymbol: "diamond.fill", accessory: .medal)
        case .jade:
            return Visual(accentColor: swatchColor, mixAmount: 0.55, shine: 0.2, hasStars: false, hasRainbow: false, hatSymbol: "leaf.fill", accessory: .collar)
        case .platinum:
            return Visual(accentColor: swatchColor, mixAmount: 0.45, shine: 0.45, hasStars: false, hasRainbow: false, hatSymbol: "medal.fill", accessory: .bowtie)
        case .coral:
            return Visual(accentColor: swatchColor, mixAmount: 0.5, shine: 0.2, hasStars: false, hasRainbow: false, hatSymbol: "gift.fill", accessory: .bowtie)
        case .storm:
            return Visual(accentColor: swatchColor, mixAmount: 0.6, shine: 0.2, hasStars: false, hasRainbow: false, hatSymbol: "bolt.fill", accessory: .cape)
        case .blossom:
            return Visual(accentColor: swatchColor, mixAmount: 0.5, shine: 0.2, hasStars: false, hasRainbow: false, hatSymbol: "leaf.fill", accessory: .none)
        case .ember:
            return Visual(accentColor: swatchColor, mixAmount: 0.55, shine: 0.25, hasStars: false, hasRainbow: false, hatSymbol: "flame.fill", accessory: .scarf)
        case .glacier:
            return Visual(accentColor: swatchColor, mixAmount: 0.45, shine: 0.35, hasStars: false, hasRainbow: false, hatSymbol: "snowflake", accessory: .scarf)
        case .phantom:
            return Visual(accentColor: swatchColor, mixAmount: 0.65, shine: 0.15, hasStars: false, hasRainbow: false, hatSymbol: "moon.fill", accessory: .cape)
        case .starlight:
            return Visual(accentColor: swatchColor, mixAmount: 0.4, shine: 0.4, hasStars: true, hasRainbow: false, hatSymbol: "sparkles", accessory: .medal)
        case .wildfire:
            return Visual(accentColor: swatchColor, mixAmount: 0.6, shine: 0.3, hasStars: false, hasRainbow: false, hatSymbol: "flame.fill", accessory: .scarf)
        case .velvet:
            return Visual(accentColor: swatchColor, mixAmount: 0.6, shine: 0.25, hasStars: false, hasRainbow: false, hatSymbol: "crown.fill", accessory: .cape)
        }
    }
}
