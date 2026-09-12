import SwiftUI
import UIKit

/// Top-level switch between onboarding and the live game. This is also where
/// a title/menu screen or Dark Space portal transition would slot in later
/// (§63) without changing how `AIApp` is wired up.
struct RootView: View {
    @StateObject private var player: PlayerState
    @StateObject private var engine: GameEngine
    private let saveManager: SaveManager

    init() {
        let manager = SaveManager()
        let loadedProfile = manager.load()
        let playerState = PlayerState(profile: loadedProfile)
        _player = StateObject(wrappedValue: playerState)
        _engine = StateObject(wrappedValue: GameEngine(player: playerState, saveManager: manager))
        saveManager = manager
    }

    var body: some View {
        Group {
            if player.profile.hasCompletedOnboarding {
                WhiteSpaceView(engine: engine, player: player)
            } else {
                OnboardingView {
                    player.profile.hasCompletedOnboarding = true
                    saveManager.saveNow(player.profile)
                }
            }
        }
        .onChange(of: player.profile.soundEnabled) { v in AudioManager.shared.soundEnabled = v }
        .onChange(of: player.profile.musicEnabled) { v in AudioManager.shared.musicEnabled = v }
        .onAppear {
            HapticsManager.shared.isEnabled = player.profile.hapticsEnabled
            AudioManager.shared.soundEnabled = player.profile.soundEnabled
            AudioManager.shared.musicEnabled = player.profile.musicEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            saveManager.saveNow(player.profile)
        }
        .preferredColorScheme(.light)
        .statusBar(hidden: true)
    }
}
