import Foundation
import Combine
import AuthenticationServices

/// One server-verified Spacechat identity, shared by phrase, Apple and Google login.
@MainActor
final class AuthState: ObservableObject {
    @Published var isSignedIn: Bool
    @Published var displayName: String?
    @Published var spacechatUsername: String?
    @Published var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published var needsPhraseBackup = false
    @Published private(set) var lastAccount: SpacechatAuth.Account?
    private(set) var accountWasDeleted = false
    private var importedGameProfile: [String: Any]?
    private let defaults: UserDefaults
    private var loginAttempt = UUID()
    private let userIDKey = "ai_apple_user_id"
    private let guestUserID = "local-guest-user"
    var isGuest: Bool { defaults.string(forKey: userIDKey) == guestUserID }
    var accountScope: String { lastAccount?.referenceID.nonEmpty ?? defaults.string(forKey: "ai_account_scope") ?? lastAccount?.privateUsername.nonEmpty ?? defaults.string(forKey: "ai_private_username") ?? spacechatUsername ?? "guest" }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isSignedIn = defaults.string(forKey: userIDKey) != nil
        displayName = defaults.string(forKey: "ai_display_name")
        spacechatUsername = defaults.string(forKey: "ai_spacechat_username")
        if let username = spacechatUsername {
            needsPhraseBackup = !defaults.bool(forKey: "ai_phrase_backed_up_" + (defaults.string(forKey: "ai_account_scope") ?? defaults.string(forKey: "ai_private_username") ?? username))
        }
    }

    private func adopt(_ account: SpacechatAuth.Account, phrase: String?, provider: String) {
        accountWasDeleted = false
        let previous = spacechatUsername
        let sameAccount = previous == account.username || (!account.privateUsername.isEmpty && defaults.string(forKey: "ai_private_username") == account.privateUsername)
        if let phrase, SpacechatAuth.isValid(phrase) { SpacechatAuth.storePhrase(phrase) }
        else if !sameAccount { SpacechatAuth.clearStoredCredentials() }
        SpacechatAuth.storeSession(account.session)
        defaults.set(account.id, forKey: userIDKey)
        defaults.set(account.referenceID.nonEmpty ?? account.privateUsername.nonEmpty ?? account.username, forKey: "ai_account_scope")
        defaults.set(provider, forKey: "ai_sign_in_kind")
        defaults.set(account.username, forKey: "ai_spacechat_username")
        if !account.privateUsername.isEmpty { defaults.set(account.privateUsername, forKey: "ai_private_username") }
        defaults.set(account.displayName, forKey: "ai_display_name")
        displayName = account.displayName
        spacechatUsername = account.username
        lastAccount = account
        SpacechatAuth.preferredDatabaseMode = account.databaseMode
        errorMessage = nil
        needsPhraseBackup = !defaults.bool(forKey: "ai_phrase_backed_up_" + accountScope)
        isSignedIn = true
    }

    func acknowledgePhraseBackup() {
        if spacechatUsername != nil { defaults.set(true, forKey: "ai_phrase_backed_up_" + accountScope) }
        needsPhraseBackup = false
    }

    @discardableResult
    func signInWithSpacechat(phrase: String, backup: [String: Any]? = nil) async -> Bool {
        guard !isWorking else { return false }
        let attempt = UUID(); loginAttempt = attempt; isWorking = true
        defer { if loginAttempt == attempt { isWorking = false } }
        do {
            let account = try await SpacechatAuth.login(phrase: phrase)
            guard loginAttempt == attempt, !Task.isCancelled else { return false }
            adopt(account, phrase: phrase, provider: "phrase")
            if let backup, SpacechatBackup.owns(backup, account: account),
               let game = SpacechatBackup.database(from: backup)["spacesDotsGame"] as? [String: Any] {
                importedGameProfile = game["profile"] as? [String: Any]
            }
            return true
        } catch {
            if loginAttempt == attempt { errorMessage = error.localizedDescription }
            return false
        }
    }

    @discardableResult
    func signInWithSocial(provider: String, idToken: String, authorizationCode: String = "") async -> Bool {
        guard !isWorking else { return false }
        let attempt = UUID(); loginAttempt = attempt; isWorking = true
        defer { if loginAttempt == attempt { isWorking = false } }
        do {
            let result = try await SpacechatAuth.socialLogin(provider: provider, idToken: idToken, authorizationCode: authorizationCode)
            guard loginAttempt == attempt, !Task.isCancelled else { return false }
            adopt(result.account, phrase: result.newPhrase, provider: provider)
            return true
        } catch {
            if loginAttempt == attempt { errorMessage = error.localizedDescription }
            return false
        }
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async -> Bool {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                errorMessage = "Apple did not return an identity token. Try again."
                return false
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let ok = await signInWithSocial(provider: "apple", idToken: token, authorizationCode: code)
            if ok && isSignedIn { defaults.set(credential.user, forKey: "ai_verified_apple_user") }
            return ok
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { errorMessage = "Apple sign-in did not finish. Try again or use your recovery phrase." }
            return false
        }
    }

    /// Restore by authenticated bootstrap first; provider sessions need no locally invented phrase.
    func restoreSession() async {
        guard isSignedIn, !isGuest else { return }
        let attempt = loginAttempt
        let session = SpacechatAuth.storedSession() ?? ""
        do {
            let account: SpacechatAuth.Account
            if !session.isEmpty { account = try await SpacechatAuth.bootstrap(session: session) }
            else if let phrase = SpacechatAuth.storedPhrase() { account = try await SpacechatAuth.login(phrase: phrase) }
            else { return }
            guard loginAttempt == attempt, isSignedIn, !Task.isCancelled else { return }
            adopt(account, phrase: nil, provider: defaults.string(forKey: "ai_sign_in_kind") ?? "phrase")
        } catch {
            // Offline sessions keep their account-scoped local progress.
            guard loginAttempt == attempt else { return }
            errorMessage = error.localizedDescription
        }
    }

    func refreshAccount() async throws {
        let owner = accountScope
        let json = try await SpacechatService.post("session/bootstrap", body: ["includeDatabase": true])
        guard owner == accountScope else { throw CancellationError() }
        let account = try SpacechatAuth.account(from: json, session: SpacechatAuth.storedSession() ?? "")
        guard lastAccount?.privateUsername.isEmpty != false || account.privateUsername == lastAccount?.privateUsername else { throw CancellationError() }
        adopt(account, phrase: nil, provider: defaults.string(forKey: "ai_sign_in_kind") ?? "phrase")
    }

    func continueAsGuest() {
        loginAttempt = UUID(); isWorking = false
        defaults.set(guestUserID, forKey: userIDKey)
        needsPhraseBackup = false
        isSignedIn = true
    }

    func takeImportedGameProfile() -> [String: Any]? {
        defer { importedGameProfile = nil }
        return importedGameProfile
    }

    func finishAccountDeletion() {
        if let username = spacechatUsername { defaults.removeObject(forKey: "ai_storage_" + username) }
        defaults.removeObject(forKey: "ai_phrase_backed_up_" + accountScope)
        accountWasDeleted = true
        signOut(revoke: false)
    }

    func signOut(revoke: Bool = true) {
        let session = SpacechatAuth.storedSession()
        loginAttempt = UUID(); isWorking = false
        for key in [userIDKey, "ai_display_name", "ai_spacechat_username", "ai_sign_in_kind", "ai_private_username", "ai_account_scope", "ai_verified_apple_user"] { defaults.removeObject(forKey: key) }
        SpacechatAuth.clearStoredCredentials()
        importedGameProfile = nil
        isSignedIn = false; displayName = nil; spacechatUsername = nil; lastAccount = nil; needsPhraseBackup = false
        if revoke, let session {
            Task { _ = try? await SpacechatAuth.request("disconnect", body: ["endSession": true], session: session) }
        }
    }

    func refreshCredentialState() {
        guard defaults.string(forKey: "ai_sign_in_kind") == "apple",
              let user = defaults.string(forKey: "ai_verified_apple_user") else { return }
        let attempt = loginAttempt
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: user) { [weak self] state, _ in
            guard state == .revoked || state == .notFound else { return }
            Task { @MainActor in
                guard let self, self.loginAttempt == attempt else { return }
                self.signOut()
            }
        }
    }
    func retryAppleLinkIfNeeded() async { await restoreSession() }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
