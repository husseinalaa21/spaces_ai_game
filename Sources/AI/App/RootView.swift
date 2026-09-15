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
    @StateObject private var sync = SpacechatSync()
    private let saveManager: SaveManager

    // Play opens a 30-second food universe, then moves directly into combat.
    private enum Phase { case splash, signIn, home, intro, practiceRound, finalRound }
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

    /// Hands a just-signed-in Spacechat account straight to the sync layer,
    /// so signing in doesn't cost a second round trip.
    private func adoptSpacechatAccountIfAny() {
        guard let account = authState.lastAccount else { return }
        sync.adopt(account)
        if let cloud = sync.cloudProfile(), player.profile.isUntouched {
            player.profile = cloud
            player.ensureUsername()
            saveManager.saveNow(player.profile)
        }
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
                    adoptSpacechatAccountIfAny()
                    withAnimation { phase = .home }
                }

            case .home:
                GameHubView(player: player, authState: authState, sync: sync,
                            save: { saveManager.saveNow(player.profile) }) {
                    withAnimation { phase = .intro }
                }

            case .intro:
                OnboardingView {
                    engine.startRound(mode: .practice, duration: GameEngine.practiceDuration)
                    withAnimation { phase = .practiceRound }
                }

            case .practiceRound:
                WhiteSpaceView(engine: engine, player: player, authState: authState, sync: sync, onQuit: {
                    withAnimation { phase = .home }
                }, onRoundComplete: {
                    engine.startRound(mode: .final)
                    withAnimation { phase = .finalRound }
                })

            case .finalRound:
                WhiteSpaceView(engine: engine, player: player, authState: authState, sync: sync, onQuit: {
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
                || phase == .finalRound
            if inGameFlow && !signedIn {
                phase = .signIn
            }
        }
        .task {
            // Re-establishes the Spacechat session from the phrase in the
            // Keychain, then adopts a cloud save only when this device has
            // none of its own — never overwriting real progress.
            guard await sync.connect() else { return }
            if let cloud = sync.cloudProfile(), player.profile.isUntouched {
                player.profile = cloud
                player.ensureUsername()
                saveManager.saveNow(player.profile)
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
        // Push on background rather than on every autosave: the whole
        // account database goes over the wire each time, so this is not a
        // call to make on every eaten dot.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            let snapshot = player.profile
            Task { await sync.push(snapshot) }
        }
        .preferredColorScheme(.light)
        .statusBar(hidden: true)
        // Lets the pages run edge to edge: the status bar is already hidden,
        // and this dims the home indicator so the bottom of a page isn't
        // permanently underlined by it.
        .persistentSystemOverlays(.hidden)
        .ignoresSafeArea()
    }
}
