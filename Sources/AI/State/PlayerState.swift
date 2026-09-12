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
    @Published var chatBubble: String? = nil

    static let baseRadius: CGFloat = 16

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

    // MARK: - Absorption (TransformationEngine hands off here)

    func progress(for id: String) -> Double {
        profile.progress[id] ?? 0
    }

    func isCompleted(_ id: String) -> Bool {
        profile.completedForms.contains(id)
    }
}
