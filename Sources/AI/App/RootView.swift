import SwiftUI
import UIKit

/// Top-level app flow: splash (loading, shaking dots) → sign in with Apple
/// (if no signed-in player yet) → onboarding/game. This is also where a
/// title/menu screen or Dark Space portal transition would slot in later
/// (§63) without changing how `AIApp` is wired up.
struct RootView: View {
    @StateObject private var player: PlayerState
    @StateObject private var engine: GameEngine
    @StateObject private var authState = AuthState()
    private let saveManager: SaveManager

    private enum Phase { case splash, signIn, main }
    @State private var phase: Phase = .splash

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
            switch phase {
            case .splash:
                SplashView {
                    authState.refreshCredentialState()
                    phase = authState.isSignedIn ? .main : .signIn
                }

            case .signIn:
                SignInView(authState: authState) {
                    withAnimation { phase = .main }
                }

            case .main:
                if player.profile.hasCompletedOnboarding {
                    WhiteSpaceView(engine: engine, player: player)
                } else {
                    OnboardingView {
                        player.profile.hasCompletedOnboarding = true
                        saveManager.saveNow(player.profile)
                    }
                }
            }
        }
        .onChange(of: player.profile.soundEnabled) { v in AudioManager.shared.soundEnabled = v }
        .onChange(of: player.profile.musicEnabled) { v in AudioManager.shared.musicEnabled = v }
        .onChange(of: authState.isSignedIn) { signedIn in
            // Handles the rare case where Apple reports the credential was
            // revoked after we'd already let the player into the game.
            if phase == .main && !signedIn {
                phase = .signIn
            }
        }
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
