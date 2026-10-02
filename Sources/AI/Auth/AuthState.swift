import Foundation
import AuthenticationServices

/// Tracks whether the player has signed in with Apple (§76: "Sign in with
/// Apple" as the account option). This is local-only for now — there's no
/// backend yet to exchange the Apple credential for a real account, so this
/// simply remembers the Apple user identifier locally so a returning player
/// skips straight past the sign-in screen next launch. Swapping this for a
/// real backend-verified session later shouldn't change `RootView` at all —
/// it only ever looks at `isSignedIn`.
@MainActor
final class AuthState: ObservableObject {
    @Published var isSignedIn: Bool
    @Published var displayName: String?

    private let userIDKey = "ai_apple_user_id"
    private let nameKey = "ai_display_name"
    private let defaults = UserDefaults.standard

    /// Sentinel stored instead of a real Apple user identifier when the
    /// player comes in as a guest. Never a value Apple would issue, so it's
    /// safe to special-case when re-checking credential state.
    private let guestUserID = "local-guest-user"

    /// Set when Apple returns a real failure (not a plain cancellation), so
    /// the sign-in screen can say something instead of appearing to do
    /// nothing at all.
    @Published var errorMessage: String?

    /// Whether the current session is a guest rather than a real account —
    /// used to gate purchases and to offer signing in again later.
    var isGuest: Bool { defaults.string(forKey: userIDKey) == guestUserID }

    /// Set when the player signed in with a Spacechat recovery phrase rather
    /// than with Apple. The Spacechat session token itself lives in the
    /// Keychain (see `SpacechatAuth`), never here.
    @Published var spacechatUsername: String?

    /// "apple" or "phrase": which route the account came in by. Apple players
    /// also hold a Spacechat session now, so the username alone can't say.
    private let kindKey = "ai_sign_in_kind"
    private let spacechatUsernameKey = "ai_spacechat_username"

    /// The most recent Spacechat account, handed to `SpacechatSync` so it
    /// doesn't have to log in a second time right after signing in.
    private(set) var lastAccount: SpacechatAuth.Account?

    /// True for an Apple sign-in, including ones made before `kindKey` existed
    /// (those have no kind, no Spacechat username and aren't the guest).
    private var isAppleSession: Bool {
        let kind = defaults.string(forKey: kindKey)
        if kind == "apple" { return true }
        guard kind == nil, defaults.string(forKey: spacechatUsernameKey) == nil,
              let id = defaults.string(forKey: userIDKey) else { return false }
        return id != guestUserID
    }

    init() {
        isSignedIn = defaults.string(forKey: userIDKey) != nil
        displayName = defaults.string(forKey: nameKey)
        spacechatUsername = defaults.string(forKey: spacechatUsernameKey)
    }

    /// Signs in against Spacechat with a recovery phrase — the same endpoint,
    /// body and phrase rules the Spacechat app itself uses, so an account is
    /// shared between the two.
    ///
    /// The server creates the account when it doesn't recognize the phrase,
    /// which is what makes "create a new phrase" work without a separate
    /// sign-up call.
    @discardableResult
    func signInWithSpacechat(phrase: String) async -> Bool {
        do {
            let account = try await SpacechatAuth.login(phrase: phrase)
            SpacechatAuth.storePhrase(phrase)
            SpacechatAuth.storeSession(account.session)
            lastAccount = account
            defaults.set(account.id, forKey: userIDKey)
            defaults.set("phrase", forKey: kindKey)
            defaults.set(account.username, forKey: spacechatUsernameKey)
            if !account.displayName.isEmpty {
                defaults.set(account.displayName, forKey: nameKey)
                displayName = account.displayName
            }
            spacechatUsername = account.username
            errorMessage = nil
            isSignedIn = true
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Login failed. Check your recovery phrase."
            return false
        }
    }

    func completeSignIn(userID: String, fullName: PersonNameComponents?) {
        defaults.set(userID, forKey: userIDKey)
        defaults.set("apple", forKey: kindKey)
        if let fullName {
            let formatted = PersonNameComponentsFormatter().string(from: fullName)
            if !formatted.isEmpty {
                displayName = formatted
                defaults.set(formatted, forKey: nameKey)
            }
        }
        isSignedIn = true
    }

    /// Lets someone play without an account at all.
    ///
    /// App Review requires this: Guideline 5.1.1(v) says an app can't force
    /// account creation when its core features don't depend on one, and a
    /// dots game plainly doesn't. Progress is saved locally either way; the
    /// only thing an Apple account adds today is a display name.
    func continueAsGuest() {
        defaults.set(guestUserID, forKey: userIDKey)
        isSignedIn = true
    }

    /// Handles the result handed back by `SignInWithAppleButton`.
    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) -> Bool {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Sign in didn't complete. Please try again."
                return false
            }
            // Apple sends the full name exactly once, on the very first
            // authorization for this app — it is nil on every later sign-in,
            // so it has to be persisted now or it's gone for good.
            completeSignIn(userID: credential.user, fullName: credential.fullName)
            errorMessage = nil
            // Apple only proves who this is; Messages and Spacechat AI need a
            // Spacechat session, so one is created in the background (and
            // retried at launch if the network is down right now).
            Task { await linkAppleToSpacechat(userID: credential.user) }
            return true
        case .failure(let error):
            // Cancelling isn't an error worth surfacing.
            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled: errorMessage = nil
                case .unknown, .notHandled:
                    errorMessage = "Sign in with Apple isn't available right now. Check that you're signed in to iCloud in Settings, or use your Spacechat phrase."
                default: errorMessage = "Apple sign in didn't complete. Please try again."
                }
            } else {
                errorMessage = "Sign in didn't complete. Please try again."
            }
            return false
        }
    }

    /// Creates (or signs back in to) the Spacechat account that belongs to
    /// this Apple ID. The phrase lives in the iCloud Keychain, so the same
    /// Apple ID on a new device reaches the same account.
    func linkAppleToSpacechat(userID: String) async {
        guard spacechatUsername == nil else { return }
        let phrase = SpacechatAuth.applePhrase(forAppleUser: userID)
        do {
            let account = try await SpacechatAuth.login(phrase: phrase)
            SpacechatAuth.storePhrase(phrase)
            SpacechatAuth.storeSession(account.session)
            lastAccount = account
            defaults.set(account.username, forKey: spacechatUsernameKey)
            if displayName == nil, !account.displayName.isEmpty { displayName = account.displayName }
            spacechatUsername = account.username
        } catch {
            // Not fatal: the player is still signed in with Apple and plays on.
        }
    }

    /// Called at launch: an Apple player whose account link did not finish
    /// (offline at the time) gets another go.
    func retryAppleLinkIfNeeded() async {
        guard spacechatUsername == nil, isAppleSession,
              let userID = defaults.string(forKey: userIDKey), userID != guestUserID else { return }
        await linkAppleToSpacechat(userID: userID)
    }

    func signOut() {
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: spacechatUsernameKey)
        defaults.removeObject(forKey: kindKey)
        // The phrase is the account: leaving it in the Keychain after a sign
        // out would let the next person on this device walk straight back in.
        SpacechatAuth.clearStoredCredentials()
        isSignedIn = false
        displayName = nil
        spacechatUsername = nil
        lastAccount = nil
    }

    /// Re-checks Apple's own record of the credential in case the player
    /// revoked "AI"'s access from their Apple ID settings since we last saw
    /// them. Cheap to call once at launch; silently no-ops if never signed in.
    func refreshCredentialState() {
        // Only meaningful for an Apple session: a Spacechat id is not an
        // Apple user identifier, and asking Apple about one returns
        // .notFound, which would sign the player straight back out.
        guard isAppleSession,
              let userID = defaults.string(forKey: userIDKey),
              userID != guestUserID else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, _ in
            guard state != .authorized else { return }
            Task { @MainActor in
                self?.signOut()
            }
        }
    }
}
