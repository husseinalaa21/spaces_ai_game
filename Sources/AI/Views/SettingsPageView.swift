import SwiftUI
import StoreKit
import UIKit

/// The game's Settings page — the fourth tab in the hub banner.
///
/// Laid out the way the Spacechat iOS app's settings are (icon, title,
/// subtitle, chevron; grouped sections; a destructive sign-out at the
/// bottom), but in this game's white theme rather than Spacechat's dark one.
struct SettingsPageView: View {
    @ObservedObject var player: PlayerState
    @ObservedObject var authState: AuthState
    @ObservedObject var sync: SpacechatSync
    @ObservedObject var store: StoreManager
    var save: () -> Void

    @State private var showSignOutConfirm = false
    @State private var showPhraseSheet = false
    @State private var showPurchases = false
    @State private var showAbout = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    accountSection
                    membershipSection
                    gameSection
                    aboutSection
                    signOutSection
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, GameHubView.bannerTopInset + 52)
                .padding(.bottom, GameHubView.homeIndicatorInset + 28)
            }
            .background(Color(white: 0.97))
            .toolbar(.hidden, for: .navigationBar)
        }
        .background(Color(white: 0.97).ignoresSafeArea())
        .sheet(isPresented: $showPhraseSheet) { RecoveryPhraseSheet() }
        .sheet(isPresented: $showPurchases) { PurchaseHistoryView(store: store) }
        .sheet(isPresented: $showAbout) { AboutSpacechatView() }
        .sheet(isPresented: $showPaywall) {
            PremiumUnlockSheet(store: store, player: player, authState: authState, save: save) {
                showPaywall = false
            }
        }
        .confirmationDialog("Sign out of this account?",
                            isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                authState.signOut()
                sync.disconnect()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(authState.spacechatUsername == nil
                 ? "You can sign back in with Apple at any time."
                 : "Your recovery phrase will be removed from this device. Make sure you have it saved — it cannot be recovered.")
        }
        .task { await store.loadProduct(); await store.refreshEntitlement() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Settings")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(accountLabel)
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Account

    private var accountSection: some View {
        section("ACCOUNT") {
            infoRow(icon: "person.crop.circle",
                    title: "Signed in as",
                    subtitle: accountDetail)

            if authState.spacechatUsername != nil {
                // Only meaningful for a phrase account — an Apple or guest
                // session has no phrase to show.
                tapRow(icon: "key.fill",
                       title: "Recovery phrase",
                       subtitle: "View, copy, or save the phrase for this account") {
                    showPhraseSheet = true
                }
            }

            infoRow(icon: "icloud",
                    title: "Cloud save",
                    subtitle: cloudDetail)
        }
    }

    // MARK: - Membership & purchases

    private var membershipSection: some View {
        section("MEMBERSHIP & PURCHASES") {
            if player.profile.isPremium {
                infoRow(icon: "checkmark.seal.fill",
                        title: "Premium",
                        subtitle: "Active — every Universe and Dot Style unlocked",
                        tint: .green)
            } else {
                tapRow(icon: "star.circle",
                       title: "Premium",
                       subtitle: store.premiumProduct == nil
                            ? "Unlock every Universe and Dot Style"
                            : "\(store.displayPrice)/\(store.periodLabel) — unlock everything") {
                    showPaywall = true
                }
            }

            tapRow(icon: "creditcard",
                   title: "Manage subscription",
                   subtitle: "Change or cancel in the App Store") {
                manageSubscription()
            }

            tapRow(icon: "clock.arrow.circlepath",
                   title: "Purchase history",
                   subtitle: "Everything bought with this Apple Account") {
                showPurchases = true
            }

            tapRow(icon: "arrow.clockwise",
                   title: store.restoreInFlight ? "Restoring…" : "Restore purchases",
                   subtitle: "Bring back Premium on a new device") {
                Task {
                    await store.restorePurchases()
                    player.refreshPremium(subscribed: store.isSubscribed)
                    save()
                }
            }
        }
    }

    // MARK: - Game

    private var gameSection: some View {
        VStack(spacing: 22) {
            section("AUDIO & FEEDBACK") {
                toggleRow(icon: "speaker.wave.2.fill", title: "Sound",
                          isOn: $player.profile.soundEnabled)
                toggleRow(icon: "music.note", title: "Music",
                          isOn: $player.profile.musicEnabled)
                toggleRow(icon: "iphone.radiowaves.left.and.right", title: "Haptics",
                          isOn: $player.profile.hapticsEnabled)
                    .onChange(of: player.profile.hapticsEnabled) { newValue in
                        HapticsManager.shared.isEnabled = newValue
                    }
            }

            section("ACCESSIBILITY") {
                toggleRow(icon: "figure.walk.motion", title: "Reduce Motion",
                          isOn: $player.profile.reduceMotion)
            }

            section("PROGRESS") {
                infoRow(icon: "brain.head.profile", title: "Intelligence level",
                        subtitle: "\(player.profile.intelligenceLevel)")
                infoRow(icon: "checkmark.seal", title: "Forms completed",
                        subtitle: "\(player.profile.completedForms.count)")
                infoRow(icon: "sparkles", title: "Points",
                        subtitle: "\(player.profile.points) · \(player.pointsRemainingToday) still earnable today")
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        section("ABOUT") {
            tapRow(icon: "info.circle", title: "About Spacechat",
                   subtitle: "What Spacechat is, and how this game connects to it") {
                showAbout = true
            }
            linkRow(icon: "hand.raised", title: "Privacy Policy",
                    subtitle: "How your data is handled",
                    url: StoreManager.privacyPolicyURL)
            linkRow(icon: "doc.text", title: "Terms of Use",
                    subtitle: "Apple's standard licence agreement",
                    url: StoreManager.termsOfUseURL)
        }
    }

    private var signOutSection: some View {
        Group {
            if authState.isSignedIn && !authState.isGuest {
                Button { showSignOutConfirm = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 16))
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign out")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("Leave this device session and return to sign-in")
                                .font(.system(size: 12))
                                .opacity(0.7)
                        }
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PressableButtonStyle(scale: 0.98))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            SpacechatMark(size: 22)
            Text("Spaces — Dots Game\(versionLabel)")
                .font(.system(size: 11))
                .foregroundColor(.black.opacity(0.4))
            Text("Powered by Spacechat")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.black.opacity(0.35))
        }
        .padding(.top, 6)
    }

    // MARK: - Row builders

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.black.opacity(0.45))
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content() }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func rowBody(icon: String, title: String, subtitle: String?,
                         tint: Color, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.black)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black.opacity(0.25))
            }
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private func infoRow(icon: String, title: String, subtitle: String,
                         tint: Color = .black.opacity(0.65)) -> some View {
        rowBody(icon: icon, title: title, subtitle: subtitle, tint: tint, chevron: false)
    }

    private func tapRow(icon: String, title: String, subtitle: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowBody(icon: icon, title: title, subtitle: subtitle,
                    tint: .black.opacity(0.65), chevron: true)
        }
        .buttonStyle(.plain)
    }

    private func linkRow(icon: String, title: String, subtitle: String, url: URL) -> some View {
        Link(destination: url) {
            rowBody(icon: icon, title: title, subtitle: subtitle,
                    tint: .black.opacity(0.65), chevron: true)
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(.black.opacity(0.65))
                .frame(width: 26)
            Toggle(title, isOn: isOn)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .tint(.black)
        }
        .padding(14)
    }

    // MARK: - Labels & actions

    private var accountLabel: String {
        if let username = authState.spacechatUsername { return "@\(username)" }
        if authState.isGuest { return "Playing as a guest" }
        if let name = authState.displayName, !name.isEmpty { return name }
        return authState.isSignedIn ? "Signed in with Apple" : "Not signed in"
    }

    private var accountDetail: String {
        if let username = authState.spacechatUsername {
            return "Spacechat phrase account · @\(username)"
        }
        if authState.isGuest {
            return "Guest — sign in to buy Premium or use Messages"
        }
        return authState.isSignedIn ? "Apple Account" : "Not signed in"
    }

    private var cloudDetail: String {
        switch sync.state {
        case .ready, .syncing: return "On — progress saves to your Spacechat account"
        case .localOnly: return "This device only — account has no server storage"
        case .failed(let message): return message
        case .signedOut: return "Off — sign in with a Spacechat phrase"
        }
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        guard !version.isEmpty else { return "" }
        return build.isEmpty ? " \(version)" : " \(version) (\(build))"
    }

    /// Apple's own subscription management sheet. Needs the active window
    /// scene, so it can't be a plain URL open if we want it inline.
    private func manageSubscription() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            openAppleSubscriptions()
            return
        }
        Task {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
            } catch {
                // Falls back to the App Store page rather than dead-ending —
                // the sheet is unavailable in some states (no subscription
                // ever bought, Simulator).
                openAppleSubscriptions()
            }
        }
    }

    private func openAppleSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }
}
