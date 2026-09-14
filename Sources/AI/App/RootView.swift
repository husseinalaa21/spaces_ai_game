import SwiftUI
import UIKit

/// Top-level app flow: splash (loading, shaking dots) → sign in with Apple
/// (if no signed-in player yet) → main menu (Play button + animated preview
/// cards) → onboarding/game, only actually entering White Space once the
/// player taps Play. This is also where a Dark Space portal transition
/// would slot in later (§63) without changing how `AIApp` is wired up.
struct RootView: View {
    @StateObject private var player: PlayerState
    @StateObject private var engine: GameEngine
    @StateObject private var authState = AuthState()
    private let saveManager: SaveManager

    // `.playing` is now four steps (§ new Play flow, replaces the old
    // one-time onboarding entirely): `.intro` is the falling-dot cinematic,
    // shown every time; `.practiceRound` is the short 30-second room right
    // after it; `.levelTransition` is a second falling-dot beat marking the
    // move into `.finalRound`, the real, full-length round — its own
    // Nebulous.io-style universe, with the "big eats small" rivalry active.
    private enum Phase { case splash, signIn, home, intro, practiceRound, levelTransition, finalRound }
    @State private var phase: Phase = .splash

    init() {
        let manager = SaveManager()
        let loadedProfile = manager.load()
        let playerState = PlayerState(profile: loadedProfile)
        // Fills in a generated "davi_32"-style handle on a fresh profile (or
        // one saved before this field existed) so there's always a name to
        // show under the player's own dot from the very first frame.
        playerState.ensureUsername()
        if playerState.profile.username != loadedProfile.username {
            manager.saveNow(playerState.profile)
        }
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
                    phase = authState.isSignedIn ? .home : .signIn
                }

            case .signIn:
                SignInView(authState: authState) {
                    withAnimation { phase = .home }
                }

            case .home:
                MainMenuView(player: player, save: { saveManager.saveNow(player.profile) }) {
                    withAnimation { phase = .intro }
                }

            case .intro:
                OnboardingView {
                    // § user feedback: "make the waiting time about 30 seconds"
                    // — was 15.
                    engine.startRound(mode: .practice, duration: 30)
                    withAnimation { phase = .practiceRound }
                }

            case .practiceRound:
                WhiteSpaceView(engine: engine, player: player, onQuit: {
                    withAnimation { phase = .home }
                }, onRoundComplete: {
                    withAnimation { phase = .levelTransition }
                })

            case .levelTransition:
                LevelTransitionView {
                    engine.startRound(mode: .final)
                    withAnimation { phase = .finalRound }
                }

            case .finalRound:
                WhiteSpaceView(engine: engine, player: player, onQuit: {
                    withAnimation { phase = .home }
                })
            }
        }
        .onChange(of: player.profile.soundEnabled) { v in AudioManager.shared.soundEnabled = v }
        .onChange(of: player.profile.musicEnabled) { v in
            let inWhiteSpace = phase == .practiceRound || phase == .finalRound
            AudioManager.shared.setMusicEnabled(v, wantsMusic: inWhiteSpace ? "ambient" : nil)
        }
        .onChange(of: authState.isSignedIn) { signedIn in
            // Handles the rare case where Apple reports the credential was
            // revoked after we'd already let the player into the game.
            let inGameFlow = phase == .home || phase == .intro || phase == .practiceRound
                || phase == .levelTransition || phase == .finalRound
            if inGameFlow && !signedIn {
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
