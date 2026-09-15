import SwiftUI

/// Minimal settings screen (§77). Only what the MVP core loop actually uses —
/// account/notifications/etc. get added once those systems exist.
struct SettingsView: View {
    @ObservedObject var player: PlayerState
    @ObservedObject var authState: AuthState
    @ObservedObject var sync: SpacechatSync
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Signed in as")
                        Spacer()
                        Text(accountLabel).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Cloud save")
                        Spacer()
                        Text(cloudLabel).foregroundColor(.secondary)
                    }
                    if let synced = sync.lastSyncedAt {
                        HStack {
                            Text("Last synced")
                            Spacer()
                            Text(synced, style: .relative).foregroundColor(.secondary)
                        }
                    }
                    if authState.isSignedIn && !authState.isGuest {
                        Button("Sign Out", role: .destructive) { showSignOutConfirm = true }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    // Said plainly rather than left as a silent no-op: on an
                    // ordinary Spacechat account the server refuses writes to
                    // the user database, so progress genuinely stays on this
                    // device.
                    Text(cloudFooter)
                }

                Section("Audio & Feedback") {
                    Toggle("Sound", isOn: $player.profile.soundEnabled)
                    Toggle("Music", isOn: $player.profile.musicEnabled)
                    Toggle("Haptics", isOn: $player.profile.hapticsEnabled)
                        .onChange(of: player.profile.hapticsEnabled) { newValue in
                            HapticsManager.shared.isEnabled = newValue
                        }
                }
                Section("Accessibility") {
                    Toggle("Reduce Motion", isOn: $player.profile.reduceMotion)
                }
                Section {
                    HStack {
                        Text("Intelligence Level")
                        Spacer()
                        Text("\(player.profile.intelligenceLevel)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Forms Completed")
                        Spacer()
                        Text("\(player.profile.completedForms.count)").foregroundColor(.secondary)
                    }
                } header: {
                    Text("Progress")
                }
            }
            .confirmationDialog("Sign out of this account?",
                                isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    authState.signOut()
                    sync.disconnect()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(authState.spacechatUsername == nil
                     ? "You can sign back in with Apple at any time."
                     : "Your recovery phrase will be removed from this device. Make sure you have it saved — it cannot be recovered.")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var accountLabel: String {
        if let username = authState.spacechatUsername { return "@\(username)" }
        if authState.isGuest { return "Guest" }
        if let name = authState.displayName, !name.isEmpty { return name }
        return authState.isSignedIn ? "Apple Account" : "Not signed in"
    }

    private var cloudLabel: String {
        switch sync.state {
        case .signedOut: return "Off"
        case .localOnly: return "This device only"
        case .ready: return "On"
        case .syncing: return "Syncing…"
        case .failed: return "Retrying"
        }
    }

    private var cloudFooter: String {
        switch sync.state {
        case .localOnly:
            return "This Spacechat account can't store data on the server, so your progress stays on this device."
        case .ready, .syncing:
            return "Progress is saved to your Spacechat account when the game closes."
        case .failed(let message):
            return message
        case .signedOut:
            return "Sign in with a Spacechat phrase to sync progress to your account."
        }
    }
}
