import SwiftUI

/// Shown after the splash screen when there's no signed-in player yet (§76).
/// A small row of dots up top for continuity with the app's own logo/splash,
/// and a single white button front and center — nothing else competing for
/// attention.
///
/// NOTE: this currently shows a plain "Continue" button instead of the real
/// Sign in with Apple button, so the game can be tested end to end without
/// a paid Apple Developer account / Sign in with Apple capability set up
/// yet. `AuthState.completeTestSignIn()` is a local-only placeholder for
/// `AuthState.completeSignIn(userID:fullName:)` — swap the button's action
/// back to the real Apple flow (see git history / AI.entitlements, which is
/// already wired up and ready) once that's set up.
struct SignInView: View {
    @ObservedObject var authState: AuthState
    let onSignedIn: () -> Void

    private let blueDot = Color(red: 41/255, green: 121/255, blue: 255/255)
    private let blackDot = Color(white: 0.12)

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack {
                dotHeader
                    .padding(.top, 70)
                Spacer()
            }

            VStack(spacing: 16) {
                Text("Spaces - AI Game")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 24)

                Text("Sign in to save your progress\nacross devices.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: continueTapped) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(width: 260, height: 50)
                }
                .background(Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black.opacity(0.15), lineWidth: 1))
                .padding(.top, 12)
            }
        }
    }

    private var dotHeader: some View {
        HStack(spacing: 9) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(i == 2 ? blueDot : blackDot)
                    .frame(width: 9, height: 9)
            }
        }
    }

    private func continueTapped() {
        authState.completeTestSignIn()
        onSignedIn()
    }
}
