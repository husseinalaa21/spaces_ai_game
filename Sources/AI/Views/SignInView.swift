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

                Button(action: continueAsGuest) {
                    Text("Continue without an account")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.black.opacity(0.55))
                        .frame(width: 260, height: 40)
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
