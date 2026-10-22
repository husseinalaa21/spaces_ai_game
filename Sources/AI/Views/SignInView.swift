import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

/// Spacechat's shared account entry, with the app's approved four-Dot identity.
/// Uses the existing Apple, configured Google and recovery-phrase authentication flows.
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
    @StateObject private var googleSignIn = GameGoogleSignIn()
    @State private var googleClientID = ""
    @State private var socialBusy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 14) {
                        // Title first, then the logo beneath it.
                        Text("Space - Dots & AI")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 24)

                        // The approved modern four-Dot logo, gently floating.
                        GameLogoMark(size: 240, animated: !reduceMotion)
                            .padding(.bottom, 2)

                        Text("One Spacechat account for your dots,\nworkspaces, and saved progress.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        loginButtons
                            .frame(maxWidth: 380)
                            .padding(.horizontal, 24)
                            .padding(.top, 14)

                        if let message = authState.errorMessage {
                            Text(message)
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                    .padding(.top, onClose == nil ? 24 : 56)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
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
        .disabled(authState.isWorking || socialBusy)
        .task {
            if let config = try? await SpacechatAuth.request("auth/social/config", body: ["nativeApp": "spaces"]),
               let google = config["google"] as? [String: Any], config["nativeApp"] as? String == "spaces", google["iosEnabled"] as? Bool == true {
                googleClientID = google["iosClientId"] as? String ?? ""
            }
        }
        .sheet(isPresented: $showPhraseSheet) { phraseSheet }
    }

    private var loginButtons: some View {
        VStack(spacing: 12) {
            spacechatButton
            if !googleClientID.isEmpty { googleButton }
            appleButton
            if authState.isWorking || socialBusy {
                ProgressView("Signing in…")
                    .font(.subheadline)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("login.progress")
            }
            if onClose == nil {
                Divider().padding(.vertical, 6)
                guestButton
            }
        }
    }

    private var spacechatButton: some View {
        Button { showPhraseSheet = true } label: {
            HStack(spacing: 12) {
                Image("SpacechatLoginLogo")
                    .resizable().scaledToFit()
                    .frame(width: 28, height: 28)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
                    .accessibilityHidden(true)
                Text("Sign in with Spacechat")
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundColor(.white)
            .padding(.leading, 6).padding(.trailing, 20)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Self.loginGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .accessibilityIdentifier("login.spacechat")
        .accessibilityLabel("Sign in with Spacechat")
        .accessibilityHint("Use, upload, or create your recovery phrase")
    }

    private var googleButton: some View {
        Button(action: continueWithGoogle) {
            ZStack {
                Text("Continue with Google")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 54)
                HStack {
                    Image("GoogleLoginLogo").resizable().scaledToFit()
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }.padding(.leading, 20)
            }
            .foregroundColor(Color(white: 0.89))
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color(red: 0.075, green: 0.075, blue: 0.078), in: Capsule())
            .overlay(Capsule().stroke(Color(red: 0.557, green: 0.569, blue: 0.561), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .accessibilityIdentifier("login.google")
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.email]
        } onCompletion: { result in
            Task {
                if await authState.handleAppleSignIn(result) { onSignedIn() }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(Capsule())
        .accessibilityIdentifier("login.apple")
    }

    private var guestButton: some View {
        Button(action: continueAsGuest) {
            Text("Continue without an account")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.black.opacity(0.045), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
        .accessibilityIdentifier("login.guest")
    }

    private static let loginGradient = LinearGradient(
        colors: [Color(red: 0.110, green: 0.373, blue: 0.769), Color(red: 0.165, green: 0.435, blue: 0.878)],
        startPoint: .leading, endPoint: .trailing
    )

    private func continueWithGoogle() {
        socialBusy = true
        Task {
            defer { socialBusy = false }
            do {
                let token = try await googleSignIn.identityToken(clientId: googleClientID)
                if await authState.signInWithSocial(provider: "google", idToken: token) { onSignedIn() }
            } catch is CancellationError { }
            catch { authState.errorMessage = error.localizedDescription }
        }
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

/// Spacechat's system-browser Google flow with PKCE and callback state validation.
@MainActor
final class GameGoogleSignIn: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    private var webSession: ASWebAuthenticationSession?
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
    private static func randomURLSafe(_ byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) != errSecSuccess {
            bytes = (0..<byteCount).map { _ in UInt8.random(in: 0...255) }
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// `clientId` is the Google OAuth client of type iOS (GOOGLE_IOS_CLIENT_ID on the server). Its reversed form is the URL scheme
    /// Google redirects to; the system sign-in sheet catches it, so nothing has to be registered in Info.plist.
    func identityToken(clientId: String) async throws -> String {
        let cleanClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanClientId.isEmpty else {
            throw SpacechatAuth.AuthError.rejected("Google sign-in is not set up for this app yet.")
        }
        let scheme = cleanClientId.split(separator: ".").reversed().joined(separator: ".")
        let redirectURI = "\(scheme):/oauth2redirect"
        let verifier = Self.randomURLSafe(48)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(16)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: cleanClientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let authURL = components.url else {
            throw SpacechatAuth.AuthError.rejected("Google sign-in could not start.")
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let webSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let webError = error as? ASWebAuthenticationSessionError, webError.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: SpacechatAuth.AuthError.rejected("Google sign-in did not finish. Please try again."))
                }
            }
            webSession.presentationContextProvider = self
            self.webSession = webSession
            if !webSession.start() {
                continuation.resume(throwing: SpacechatAuth.AuthError.rejected("Google sign-in could not open."))
            }
        }
        webSession = nil

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let returnedState = items.first { $0.name == "state" }?.value ?? ""
        guard returnedState == state, let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw SpacechatAuth.AuthError.rejected("Google sign-in was not completed.")
        }

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: cleanClientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let token = json?["id_token"] as? String, !token.isEmpty else {
            throw SpacechatAuth.AuthError.rejected("Google did not return a sign-in token. Please try again.")
        }
        return token
    }
}
