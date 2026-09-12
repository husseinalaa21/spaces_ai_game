import SwiftUI
import AuthenticationServices

/// Shown after the splash screen when there's no signed-in player yet (§76).
/// A small row of dots up top for continuity with the app's own logo/splash,
/// and a single white "Sign in with Apple" button front and center — nothing
/// else competing for attention.
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
                Text("AI")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.black)

                Text("Sign in to save your progress\nacross devices.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                SignInWithAppleButton(.signIn, onRequest: configure, onCompletion: handle)
                    .signInWithAppleButtonStyle(.white)
                    .frame(width: 260, height: 50)
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

    private func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                authState.completeSignIn(userID: credential.user, fullName: credential.fullName)
                onSignedIn()
            }
        case .failure(let error):
            // Cancelled or failed — stay on this screen so the player can retry.
            print("Sign in with Apple failed: \(error.localizedDescription)")
        }
    }
}
