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
    /// player comes in through the test "Continue" button (see
    /// `completeTestSignIn`). Never a value Apple would issue, so it's safe
    /// to special-case.
    private let testUserID = "local-test-user"

    init() {
        isSignedIn = defaults.string(forKey: userIDKey) != nil
        displayName = defaults.string(forKey: nameKey)
    }

    func completeSignIn(userID: String, fullName: PersonNameComponents?) {
        defaults.set(userID, forKey: userIDKey)
        if let fullName {
            let formatted = PersonNameComponentsFormatter().string(from: fullName)
            if !formatted.isEmpty {
                displayName = formatted
                defaults.set(formatted, forKey: nameKey)
            }
        }
        isSignedIn = true
    }

    /// Placeholder sign-in for the "Continue" button used while there's no
    /// real Apple Developer / backend setup to test against. Swap this back
    /// to the real Sign in with Apple button once that's in place — nothing
    /// else in `RootView` needs to change, it only ever looks at
    /// `isSignedIn`.
    func completeTestSignIn() {
        defaults.set(testUserID, forKey: userIDKey)
        isSignedIn = true
    }

    func signOut() {
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: nameKey)
        isSignedIn = false
        displayName = nil
    }

    /// Re-checks Apple's own record of the credential in case the player
    /// revoked "AI"'s access from their Apple ID settings since we last saw
    /// them. Cheap to call once at launch; silently no-ops if never signed in.
    func refreshCredentialState() {
        guard let userID = defaults.string(forKey: userIDKey), userID != testUserID else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, _ in
            guard state != .authorized else { return }
            Task { @MainActor in
                self?.signOut()
            }
        }
    }
}
