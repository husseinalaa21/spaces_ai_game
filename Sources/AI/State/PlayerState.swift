import Foundation
import CoreGraphics
import SwiftUI

/// Everything about the player that needs to persist between launches.
/// Kept as plain Codable data so `SaveManager` can serialize it directly —
/// this is the local stand-in for the "User" model in §57 until a backend exists.
struct PlayerProfile: Codable {
    var progress: [String: Double] = [:]        // collectible id -> 0...100
    var completedForms: Set<String> = []
    var activeFormID: String? = nil
    var intelligence: Int = 0
    var intelligenceLevel: Int = 1
    var hasCompletedOnboarding: Bool = false
    var soundEnabled: Bool = true
    var musicEnabled: Bool = true
    var hapticsEnabled: Bool = true
    var reduceMotion: Bool = false

    /// Whether Premium is active right now, from either source. Recomputed
    /// by `PlayerState.refreshPremium(subscribed:)` — never set directly any
    /// more. It's still persisted so the picker isn't briefly locked on
    /// launch while StoreKit is queried, but Apple's own entitlement always
    /// wins once that query returns.
    var isPremium: Bool = false

    /// Premium bought with in-game Points rather than money (`StoreView`'s
    /// "Redeem N Points"). Kept separate from the real subscription so that
    /// a lapsed or refunded App Store subscription doesn't take away
    /// something the player paid for with Points they earned.
    var premiumFromPoints: Bool = false
    var selectedUniverse: UniverseTheme = .white
    var selectedDotStyle: DotStyle = .classic

    /// Individually-bought premium cosmetics (§ new — "add more to buy...
    /// set price for them"), stored by raw value so a save from before a
    /// given case existed just decodes as "not owned" rather than failing.
    /// Separate from `isPremium`, which still unlocks everything at once —
    /// an item counts as owned if it's free, if AI+ is active, or if its id
    /// is in the matching set here (see `owns` below).
    var unlockedUniverses: Set<String> = []
    var unlockedDotStyles: Set<String> = []

    /// A simple earned/spendable soft currency — awarded automatically for
    /// eating, finishing a form, and leveling up (`GameEngine.absorb`), shown
    /// top-right on the main menu, and spendable in the Store (`StoreView`)
    /// toward Premium. The "buy more points" side of
    /// the Store is still a local stand-in — no real payment is taken there.
    var points: Int = 0

    /// Daily login reward streak (§ new retention nudge, `DailyRewardSheet`
    /// in `MainMenuView.swift`) — a free, no-payment Points ladder, distinct
    /// from the Store's paid packs. Missing a day resets the streak back to
    /// Day 1; it never takes back Points already earned. `lastDailyClaimDate`
    /// gates the reward to one claim per calendar day.
    var lastDailyClaimDate: Date? = nil
    var dailyStreak: Int = 0

    /// A "davi_32"-style handle shown under the player's own dot in the
    /// universe (§ new — matches the names shown under every rival dot) and
    /// editable from the main menu. Optional, and decoded as such, so a
    /// profile saved before this field existed loads without a decode
    /// error — `PlayerState.ensureUsername()` fills in a generated default
    /// the first time one's needed and it's `nil`, rather than every
    /// `PlayerProfile` needing a non-optional value from the start.
    var username: String? = nil

    /// Plain zero-arg init, still needed once `init(from:)` below is
    /// declared — writing any initializer for a type turns off Swift's
    /// automatic memberwise one, and both `SaveManager` and `PlayerState`
    /// construct a fresh profile with `PlayerProfile()`.
    init() {}

    /// A hand-written decoder that reads every field with `decodeIfPresent`
    /// and falls back to that field's own default when the key is missing
    /// (§ new — a save from before *any* future field gets added should
    /// still load everything it already has, instead of failing the whole
    /// decode and silently resetting the player back to a brand-new
    /// profile, which is exactly what happened just now: adding
    /// `unlockedUniverses`/`unlockedDotStyles` as plain non-optional fields
    /// broke every existing save the same way `username` above already
    /// once did before it was made `Optional` to work around it). This
    /// makes every field — optional or not — tolerant of that the same way,
    /// so this shouldn't need doing again.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        progress = try c.decodeIfPresent([String: Double].self, forKey: .progress) ?? [:]
        completedForms = try c.decodeIfPresent(Set<String>.self, forKey: .completedForms) ?? []
        activeFormID = try c.decodeIfPresent(String.self, forKey: .activeFormID)
        intelligence = try c.decodeIfPresent(Int.self, forKey: .intelligence) ?? 0
        intelligenceLevel = try c.decodeIfPresent(Int.self, forKey: .intelligenceLevel) ?? 1
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        musicEnabled = try c.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? true
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        isPremium = try c.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        premiumFromPoints = try c.decodeIfPresent(Bool.self, forKey: .premiumFromPoints) ?? false
        selectedUniverse = try c.decodeIfPresent(UniverseTheme.self, forKey: .selectedUniverse) ?? .white
        selectedDotStyle = try c.decodeIfPresent(DotStyle.self, forKey: .selectedDotStyle) ?? .classic
        unlockedUniverses = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedUniverses) ?? []
        unlockedDotStyles = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedDotStyles) ?? []
        points = try c.decodeIfPresent(Int.self, forKey: .points) ?? 0
        lastDailyClaimDate = try c.decodeIfPresent(Date.self, forKey: .lastDailyClaimDate)
        dailyStreak = try c.decodeIfPresent(Int.self, forKey: .dailyStreak) ?? 0
        username = try c.decodeIfPresent(String.self, forKey: .username)
    }
}

/// The player's live, observable game state. `PlayerProfile` is the durable
/// subset that gets saved; this class also tracks transient per-session values
/// (position, size, ability cooldowns) that don't need to survive a relaunch.
@MainActor
final class PlayerState: ObservableObject {
    @Published var profile: PlayerProfile
    @Published var position: CGPoint = .zero
    @Published var size: CGFloat = PlayerState.baseRadius
    @Published var lastEatenID: String? = nil
    @Published var abilityCooldownRemaining: Double = 0
    @Published var abilityEffectRemaining: Double = 0
    @Published var formCompleteBanner: CollectibleDefinition? = nil
    @Published var levelUpBanner: Int? = nil
    @Published var chatBubble: String? = nil

    static let baseRadius: CGFloat = 16
    /// Floor for the new per-eat grow/shrink rule (`CollectibleDefinition.sizeEffect`)
    /// — small enough to visibly shrink, never so small the dot stops reading as
    /// the same player or the eat radius collapses to nothing.
    static let minRadius: CGFloat = 9
    static let maxRadius: CGFloat = baseRadius * 3.2

    init(profile: PlayerProfile = PlayerProfile()) {
        self.profile = profile
    }

    // MARK: - Derived state

    var activeForm: CollectibleDefinition? {
        guard let id = profile.activeFormID else { return nil }
        return CollectibleCatalog.definition(for: id)
    }

    var activeFormProgress: Double {
        guard let id = profile.activeFormID else { return 0 }
        return profile.progress[id] ?? 0
    }

    var equippedAbility: AbilityID? {
        // MVP loadout (§66): the ability tied to the active form, but only
        // usable once that form has actually been completed at least once.
        guard let id = profile.activeFormID,
              profile.completedForms.contains(id),
              let def = CollectibleCatalog.definition(for: id) else { return nil }
        return def.activeAbility
    }

    var canUseAbility: Bool {
        equippedAbility != nil && abilityCooldownRemaining <= 0
    }

    /// Generates a stable default handle the first time one's needed (a
    /// fresh profile, or one saved before this field existed), then leaves
    /// it alone — editing it afterward is the main menu's job, not this.
    func ensureUsername() {
        guard profile.username == nil else { return }
        profile.username = NameGenerator.uniqueNames(count: 1).first
    }

    // MARK: - Absorption (TransformationEngine hands off here)

    func progress(for id: String) -> Double {
        profile.progress[id] ?? 0
    }

    func isCompleted(_ id: String) -> Bool {
        profile.completedForms.contains(id)
    }

    // MARK: - Daily reward (§ new)

    /// The 7-day ladder shown in `DailyRewardSheet` — deliberately fixed and
    /// short rather than scaling forever, so a long streak never quietly
    /// implies a bigger next reward than what's actually paid out.
    static let dailyRewardLadder: [Int] = [20, 30, 45, 60, 80, 120, 200]

    /// Which ladder day (0-based) the *next* claim would land on.
    var nextDailyRewardIndex: Int {
        profile.dailyStreak % PlayerState.dailyRewardLadder.count
    }

    var nextDailyRewardAmount: Int {
        PlayerState.dailyRewardLadder[nextDailyRewardIndex]
    }

    /// True once a new calendar day has turned over since the last claim (or
    /// there's never been one) — the only gate on `claimDailyReward()`.
    var canClaimDailyReward: Bool {
        guard let last = profile.lastDailyClaimDate else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    /// Awards the next reward on the ladder, advances (or resets, if a full
    /// day was missed) the streak, and returns the amount actually awarded
    /// so `DailyRewardSheet` can animate it. A no-op past the first call any
    /// given day.
    @discardableResult
    func claimDailyReward() -> Int {
        guard canClaimDailyReward else { return 0 }
        if let last = profile.lastDailyClaimDate, !Calendar.current.isDateInYesterday(last) {
            // More than one day since the last claim — the streak doesn't
            // carry over, but nothing already earned is ever taken away.
            profile.dailyStreak = 0
        }
        let amount = PlayerState.dailyRewardLadder[nextDailyRewardIndex]
        profile.points += amount
        profile.dailyStreak += 1
        profile.lastDailyClaimDate = Date()
        return amount
    }

    // MARK: - Per-item cosmetic purchases (§ new — buy a single Universe or
    // Dot Style with Points, alongside the existing "unlock everything" AI+
    // subscription rather than instead of it).

    /// Folds Apple's live subscription state together with Points-redeemed
    /// Premium. Called on launch, whenever `StoreManager.isSubscribed`
    /// changes, and after a successful purchase or restore — so cancelling,
    /// lapsing or refunding the subscription re-locks the premium cosmetics
    /// unless they were redeemed with Points.
    func refreshPremium(subscribed: Bool) {
        let active = subscribed || profile.premiumFromPoints
        guard profile.isPremium != active else { return }
        profile.isPremium = active
    }

    /// Attempts to spend Points to unlock a single Universe. No-ops (and
    /// returns `false`) if it's already owned or there aren't enough Points.
    @discardableResult
    func purchase(_ theme: UniverseTheme) -> Bool {
        guard !profile.owns(theme), profile.points >= theme.price else { return false }
        profile.points -= theme.price
        profile.unlockedUniverses.insert(theme.rawValue)
        return true
    }

    /// Same as above, for a single Dot Style.
    @discardableResult
    func purchase(_ style: DotStyle) -> Bool {
        guard !profile.owns(style), profile.points >= style.price else { return false }
        profile.points -= style.price
        profile.unlockedDotStyles.insert(style.rawValue)
        return true
    }
}

extension PlayerProfile {
    /// Whether this Universe is available to select right now: every free
    /// option always is, AI+ unlocks every premium one at once, and a
    /// premium one bought individually is remembered in `unlockedUniverses`.
    func owns(_ theme: UniverseTheme) -> Bool {
        !theme.isPremium || isPremium || unlockedUniverses.contains(theme.rawValue)
    }

    /// Same rule as `owns(_ theme:)`, for Dot Styles.
    func owns(_ style: DotStyle) -> Bool {
        !style.isPremium || isPremium || unlockedDotStyles.contains(style.rawValue)
    }
}
