import SwiftUI

/// Minimal settings screen (§77). Only what the MVP core loop actually uses —
/// account/notifications/etc. get added once those systems exist.
struct SettingsView: View {
    @ObservedObject var player: PlayerState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
