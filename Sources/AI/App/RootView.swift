import SwiftUI
import UIKit
import AuthenticationServices

/// Modern splash → shared login → recovery backup → app hub. Device saves
/// follow the selected account, and optional cloud saves use the same service.
struct RootView: View {
    @StateObject private var player: PlayerState
    @StateObject private var authState = AuthState()
    @StateObject private var sync = SpacechatSync()
    @ObservedObject private var friends = FriendsStore.shared
    private let saveManager: SaveManager

    private enum Phase { case splash, signIn, home }
    @State private var phase: Phase = .splash
    @State private var activeScope: String

    init() {
        let defaults = UserDefaults.standard
        let scope = defaults.string(forKey: "ai_account_scope") ?? defaults.string(forKey: "ai_private_username") ?? defaults.string(forKey: "ai_spacechat_username") ?? "guest"
        _activeScope = State(initialValue: scope)
        let manager = SaveManager(accountScope: scope)
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
        saveManager = manager
    }

    /// Hands a just-signed-in Spacechat account straight to the sync layer,
    /// so signing in doesn't cost a second round trip.
    private func adoptSpacechatAccountIfAny(savePrevious: Bool = true) {
        let scope = authState.accountScope
        if scope != activeScope {
            if savePrevious { saveManager.saveNow(player.profile) }
            saveManager.switchAccount(to: scope, migrateCurrent: activeScope == authState.spacechatUsername || activeScope == authState.lastAccount?.privateUsername)
            player.profile = saveManager.load()
            player.ensureUsername()
            activeScope = scope
        }
        guard let account = authState.lastAccount else { return }
        sync.adopt(account)
        if let raw = authState.takeImportedGameProfile(),
           let data = try? JSONSerialization.data(withJSONObject: raw),
           let imported = try? JSONDecoder().decode(PlayerProfile.self, from: data) {
            player.profile = imported; player.ensureUsername(); saveManager.saveNow(player.profile)
        }
        Task {
            guard await sync.refresh(), authState.accountScope == scope else { return }
            if let cloud = sync.cloudProfile(), player.profile.isUntouched {
                player.profile = cloud
                sync.confirmLoadedProfile(cloud)
                player.ensureUsername()
                saveManager.saveNow(player.profile)
            } else {
                sync.confirmLoadedProfile(player.profile)
            }
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
                if authState.needsPhraseBackup && !authState.isGuest {
                    RecoveryPhraseSheet(firstLogin: true, onContinue: authState.acknowledgePhraseBackup)
                } else {
                    GameHubView(player: player, authState: authState, sync: sync,
                                save: { saveManager.saveNow(player.profile) })
                }

            }
        }
        .onChange(of: player.profile.soundEnabled) { v in AudioManager.shared.soundEnabled = v }
        .onReceive(player.objectWillChange) { _ in
            let owner = activeScope
            // objectWillChange arrives before the new value is assigned.
            DispatchQueue.main.async {
                guard owner == activeScope, owner == authState.accountScope else { return }
                saveManager.scheduleSave(player.profile)
                if authState.isSignedIn && !authState.isGuest { sync.schedulePush(player.profile) }
            }
        }
        .onChange(of: player.profile.musicEnabled) { v in
            AudioManager.shared.setMusicEnabled(v, wantsMusic: nil)
        }
        .onChange(of: authState.spacechatUsername) { _ in
            adoptSpacechatAccountIfAny()
        }
        .onChange(of: authState.isSignedIn) { signedIn in
            // Handles the rare case where Apple reports the credential was
            // revoked after we'd already let the player into the game.
            if phase == .home && !signedIn {
                sync.disconnect()
                if authState.accountWasDeleted { saveManager.removeCurrentSave() }
                adoptSpacechatAccountIfAny(savePrevious: !authState.accountWasDeleted)
                phase = .signIn
            }
        }
        .task {
            // Re-establishes the Spacechat session from the phrase in the
            // Keychain, then adopts a cloud save only when this device has
            // none of its own — never overwriting real progress.
            await authState.restoreSession()
            adoptSpacechatAccountIfAny()
        }
        .task {
            DailyChallenges.shared.onReward = { points in
                _ = player.awardPoints(points)
                saveManager.saveNow(player.profile)
            }
            await DailyChallenges.shared.refresh()
        }
        .onAppear {
            HapticsManager.shared.isEnabled = player.profile.hapticsEnabled
            AudioManager.shared.soundEnabled = player.profile.soundEnabled
            AudioManager.shared.musicEnabled = player.profile.musicEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            saveManager.saveNow(player.profile)
        }
        .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
            authState.refreshCredentialState()
        }
        // Push on background rather than on every autosave: the whole
        // account database goes over the wire each time, so this is not a
        // call to make on every eaten dot.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            let snapshot = player.profile
            if authState.isSignedIn && !authState.isGuest { Task { await sync.push(snapshot) } }
        }
        .preferredColorScheme(.light)
        .statusBar(hidden: true)
        // Lets the pages run edge to edge: the status bar is already hidden,
        // and this dims the home indicator so the bottom of a page isn't
        // permanently underlined by it.
        .persistentSystemOverlays(.hidden)
        // Container only: ignoring the keyboard safe area too left every
        // composer hidden behind the keyboard.
        .ignoresSafeArea(.container)
    }
}
