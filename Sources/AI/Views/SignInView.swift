import SwiftUI
import AuthenticationServices

/// Shown after the splash screen when there's no signed-in player yet (§76).
/// A small row of dots up top for continuity with the app's own logo/splash,
/// then the real Sign in with Apple button — and, below it, a guest path.
///
/// The guest path is not optional politeness: App Review Guideline 5.1.1(v)
/// forbids requiring an account for an app whose core features don't need
/// one. Progress saves locally either way, so signing in only adds a display
/// name today. When a backend exists, that's when the pitch for signing in
/// becomes real, and the copy here should change with it — not before.
struct SignInView: View {
    @ObservedObject var authState: AuthState
    let onSignedIn: () -> Void
    /// Set when the page is opened on demand from the "Log in" button (see
    /// `LogInButton`) rather than shown as the launch screen. That changes two
    /// things: there is a close button to go back without choosing anything,
    /// and the "Continue without an account" route is dropped — the player
    /// opening this is already playing as a guest.
    let onClose: (() -> Void)?

    /// Written out so `SignInView(authState:) { … }` keeps meaning "the
    /// sign-in closure" at the launch call site, whatever is added after it.
    init(authState: AuthState, onSignedIn: @escaping () -> Void, onClose: (() -> Void)? = nil) {
        self.authState = authState
        self.onSignedIn = onSignedIn
        self.onClose = onClose
    }

    @State private var showPhraseSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 14) {
                // Title first, then the logo beneath it.
                Text("Spaces")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 24)

                // The game's actual logo — the same seven-dot cluster the
                // splash screen and app icon use — rather than the row of
                // five plain dots that used to stand in for it.
                GameLogoMark(size: 150, animated: !reduceMotion)
                    .padding(.bottom, 2)

                Text("Sign in to keep your name on your dot,\nor jump straight in.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                SignInWithAppleButton(.signIn) { request in
                    // Only the name is requested. Asking for the email would
                    // hand back a private-relay address there's currently no
                    // backend to send anything to.
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    if authState.handleAppleSignIn(result) {
                        onSignedIn()
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(width: 260, height: 50)
                .clipShape(Capsule())
                .padding(.top, 12)

                // Second route, directly under Apple: the same Spacechat
                // recovery phrase, against the same server — so one account
                // covers both apps.
                Button { showPhraseSheet = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Continue with Spacechat phrase")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .frame(width: 260, height: 50)
                }
                .overlay(Capsule().stroke(Color.black.opacity(0.18), lineWidth: 1.5))
                .clipShape(Capsule())

                if onClose == nil {
                    Button(action: continueAsGuest) {
                        Text("Continue without an account")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.black.opacity(0.55))
                            .frame(width: 260, height: 40)
                    }
                }

                if let message = authState.errorMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.leading, 16)
                .padding(.top, 12)
                .accessibilityLabel("Close")
            }
        }
        .sheet(isPresented: $showPhraseSheet) { phraseSheet }
    }

    private var phraseSheet: some View {
        SpacechatPhraseView(authState: authState, onSignedIn: onSignedIn)
    }


    private func continueAsGuest() {
        authState.continueAsGuest()
        onSignedIn()
    }
}

/// The "Log in" button that opens the login page (`SignInView`) on demand.
///
/// Sits under Play on the home page and under the Account card in Settings —
/// one view, so the two can't drift apart. Shown only while the player is
/// playing as a guest (`AuthState.isGuest`): once there is an account there is
/// nothing to log in to, and Settings already has its own Sign Out.
///
/// A compact pill rather than another full-width capsule: on the home page
/// Play already sits at the bottom of the tallest phones, so the button under
/// it has to be small, and it should read as secondary to Play anyway.
struct LogInButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text("Log in")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundColor(.black.opacity(0.75))
            .padding(.horizontal, 22)
            .frame(height: 36)
            .background(Color.black.opacity(0.07), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}
