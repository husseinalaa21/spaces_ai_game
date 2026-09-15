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

    var selectedUniverse: UniverseTheme = .white
    var selectedDotStyle: DotStyle = .classic

    /// The dot the player designed in the Dot Studio, and whether it's the
    /// one currently equipped. Kept separate from `selectedDotStyle` so
    /// switching back to a catalog style and back again doesn't lose the
    /// artwork.
    var customDot: CustomDot = CustomDot()
    var usesCustomDot: Bool = false

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

    /// Points earned through play (and the daily reward) so far today, with
    /// the day they were counted against. Together these enforce
    /// `PlayerState.dailyEarnCap`. Purchased Points are deliberately not
    /// counted here — you can always spend money, the cap is only on earning.
    var pointsEarnedToday: Int = 0
    var pointsEarnedDate: Date? = nil

    /// A profile nothing has happened to yet.
    ///
    /// Gates adopting a cloud save: pulling one over a profile that has real
    /// progress would silently destroy it, so a cloud save is only ever taken
    /// on a device that has nothing of its own.
    var isUntouched: Bool {
        intelligence == 0
            && intelligenceLevel <= 1
            && points == 0
            && completedForms.isEmpty
            && progress.isEmpty
            && !hasCompletedOnboarding
            && customDot.isBlank
    }

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
        selectedUniverse = try c.decodeIfPresent(UniverseTheme.self, forKey: .selectedUniverse) ?? .white
        selectedDotStyle = try c.decodeIfPresent(DotStyle.self, forKey: .selectedDotStyle) ?? .classic
        customDot = try c.decodeIfPresent(CustomDot.self, forKey: .customDot) ?? CustomDot()
        usesCustomDot = try c.decodeIfPresent(Bool.self, forKey: .usesCustomDot) ?? false
        unlockedUniverses = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedUniverses) ?? []
        unlockedDotStyles = try c.decodeIfPresent(Set<String>.self, forKey: .unlockedDotStyles) ?? []
        points = try c.decodeIfPresent(Int.self, forKey: .points) ?? 0
        lastDailyClaimDate = try c.decodeIfPresent(Date.self, forKey: .lastDailyClaimDate)
        dailyStreak = try c.decodeIfPresent(Int.self, forKey: .dailyStreak) ?? 0
        pointsEarnedToday = try c.decodeIfPresent(Int.self, forKey: .pointsEarnedToday) ?? 0
        pointsEarnedDate = try c.decodeIfPresent(Date.self, forKey: .pointsEarnedDate)
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
    /// Most a player can *earn* in one calendar day, across gameplay and the
    /// daily reward together (§ new — "max 70 a day"). Purchased Points are
    /// uncapped; this only limits free accrual.
    static let dailyEarnCap = 70

    static let dailyRewardLadder: [Int] = [10, 12, 15, 18, 20, 25, 30]

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
        // Don't burn the day's claim against a full allowance — leaving it
        // unclaimed means it's still there once the cap rolls over, instead
        // of the button silently consuming the streak for zero Points.
        guard pointsRemainingToday > 0 else { return 0 }
        if let last = profile.lastDailyClaimDate, !Calendar.current.isDateInYesterday(last) {
            // More than one day since the last claim — the streak doesn't
            // carry over, but nothing already earned is ever taken away.
            profile.dailyStreak = 0
        }
        let amount = awardPoints(PlayerState.dailyRewardLadder[nextDailyRewardIndex])
        profile.dailyStreak += 1
        profile.lastDailyClaimDate = Date()
        return amount
    }

    // MARK: - Per-item cosmetic purchases (§ new — buy a single Universe or
    // Dot Style with Points, alongside the existing "unlock everything" AI+
    // subscription rather than instead of it).

    /// The custom dot to render right now, or nil when a catalog `DotStyle`
    /// is equipped. A blank custom dot never renders — there'd be nothing to
    /// see and it would silently override the chosen style.
    var activeCustomDot: CustomDot? {
        guard profile.usesCustomDot, !profile.customDot.isBlank else { return nil }
        return profile.customDot
    }

    // MARK: - Earning (daily-capped)

    /// The single funnel every *earned* Point goes through — gameplay awards
    /// and the daily reward alike. Rolls the day's tally over on a calendar
    /// boundary and clamps the grant to whatever is left of
    /// `dailyEarnCap`, returning what was actually credited so callers can
    /// show the real number rather than the number they asked for.
    ///
    /// Points bought with money bypass this entirely.
    @discardableResult
    func awardPoints(_ amount: Int) -> Int {
        guard amount > 0 else { return 0 }
        rollOverEarnedDayIfNeeded()
        let granted = min(amount, max(0, PlayerState.dailyEarnCap - profile.pointsEarnedToday))
        guard granted > 0 else { return 0 }
        profile.points += granted
        profile.pointsEarnedToday += granted
        profile.pointsEarnedDate = Date()
        return granted
    }

    /// How much of today's earning allowance is still available.
    var pointsRemainingToday: Int {
        guard let last = profile.pointsEarnedDate,
              Calendar.current.isDateInToday(last) else { return PlayerState.dailyEarnCap }
        return max(0, PlayerState.dailyEarnCap - profile.pointsEarnedToday)
    }

    private func rollOverEarnedDayIfNeeded() {
        if let last = profile.pointsEarnedDate, !Calendar.current.isDateInToday(last) {
            profile.pointsEarnedToday = 0
        }
    }

    /// Mirrors Apple's live subscription state onto the saved profile.
    /// Premium is the subscription and nothing else — there's no Points
    /// redemption — so cancelling, lapsing or refunding re-locks the premium
    /// cosmetics on the next refresh. Called on launch, whenever
    /// `StoreManager.isSubscribed` changes, and after a purchase or restore.
    func refreshPremium(subscribed: Bool) {
        guard profile.isPremium != subscribed else { return }
        profile.isPremium = subscribed
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
