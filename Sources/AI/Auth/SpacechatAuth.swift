import Foundation
import Security

/// Signing in with a Spacechat recovery phrase, against the same server and
/// the same endpoint the Spacechat iOS client uses.
///
/// Everything here mirrors `SpacechatAPI.login` and `AppState.login` in the
/// Spacechat app so the two stay interchangeable: the same
/// `POST /api/dna` endpoint, the same `passphrase` / `databaseMode` /
/// `native` body, the same normalization rules, and the same 12-to-18-word
/// validity range. A phrase that works in Spacechat works here, and one
/// created here works there.
enum SpacechatAuth {

    /// Matches the Spacechat client's own default. Overridable for staging
    /// the same way the Spacechat app allows.
    static var baseURL: URL {
        let stored = UserDefaults.standard.string(forKey: "spacechat.native.apiBaseURL")
        return URL(string: stored ?? "https://www.spacechat.app")
            ?? URL(string: "https://www.spacechat.app")!
    }

    // MARK: - Phrase rules (identical to NativeRecoveryPhrase)

    /// Lowercases, drops anything that isn't a-z or whitespace, and collapses
    /// runs of spaces — but keeps a trailing space, so it can be applied on
    /// every keystroke without fighting someone mid-word.
    static func normalizeForEditing(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^\s+"#, with: "", options: .regularExpression)
    }

    static func normalize(_ value: String) -> String {
        normalizeForEditing(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func wordCount(_ value: String) -> Int {
        normalize(value).split(separator: " ").count
    }

    static func isValid(_ value: String) -> Bool {
        (12...18).contains(wordCount(value))
    }

    /// A fresh 12-word phrase drawn from the same 2,048-word list Spacechat
    /// uses. `SystemRandomNumberGenerator`, which `shuffled()` uses, is
    /// cryptographically secure on Apple platforms.
    static func generatePhrase(words: Int = 12) -> String {
        SpacechatWords.all.shuffled().prefix(max(12, min(18, words))).joined(separator: " ")
    }

    /// Kept injectable for deterministic API-contract checks.
    static var urlSession: URLSession = .shared
    // Contract tests use in-memory credentials and never touch a real Keychain.
    static var keychainEnabled = true

    static var preferredDatabaseMode: String {
        get {
            let owner = UserDefaults.standard.string(forKey: "ai_spacechat_username") ?? "new"
            return UserDefaults.standard.string(forKey: "ai_storage_" + owner) ?? "browser"
        }
        set {
            let owner = UserDefaults.standard.string(forKey: "ai_spacechat_username") ?? "new"
            UserDefaults.standard.set(newValue, forKey: "ai_storage_" + owner)
        }
    }

    // MARK: - Login

    struct Account {
        let id: String
        let session: String
        let username: String
        let displayName: String
        let isNewAccount: Bool
        /// What the server says this account's storage mode is. Only
        /// "prepaid" accepts writes to the user database — see
        /// `handleUserDatabase` in the Spacechat server.
        let databaseMode: String
        /// The account's entire stored database, exactly as the server sent
        /// it, or nil when the account has no active prepaid record.
        ///
        /// Kept as raw JSON rather than decoded into a model on purpose: a
        /// write REPLACES the whole object server-side, so saving anything
        /// requires merging into a faithful copy of everything already there.
        /// Decoding to a typed model would quietly drop every key this app
        /// doesn't know about — i.e. all of the player's Spacechat data.
        let database: [String: Any]?
        var details: [String: Any] = [:]
        var privateUsername: String { details["privateUsername"] as? String ?? "" }
        var referenceID: String { details["referenceId"] as? String ?? "" }
        var description: String { details["description"] as? String ?? "" }
        var picture: String { details["pic"] as? String ?? details["picture"] as? String ?? "" }
        var cloudAvailable: Bool {
            let cloud = details["cloudDatabase"] as? [String: Any] ?? [:]
            if let available = cloud["available"] as? Bool { return available }
            return database != nil
        }

        var supportsCloudSave: Bool { databaseMode == "prepaid" && database != nil }
    }

    enum AuthError: LocalizedError {
        case invalidPhrase
        case rejected(String)
        case network

        var errorDescription: String? {
            switch self {
            case .invalidPhrase:
                return "Enter a recovery phrase with 12 to 18 words, letters only."
            case .rejected(let message):
                return message.isEmpty ? "Login failed. Check your recovery phrase." : message
            case .network:
                return "Couldn't reach Spacechat. Check your connection and try again."
            }
        }
    }

    /// Signs in (or creates the account, if the phrase is new — the server
    /// decides, and reports it back via `isNewAccount`).
    static func login(phrase: String) async throws -> Account {
        let normalized = normalize(phrase)
        guard SpacechatBackup.validRawPhrase(phrase) else { throw AuthError.invalidPhrase }

        let json = try await request("dna", body: [
            "passphrase": normalized, "databaseMode": preferredDatabaseMode, "native": true
        ])
        guard json["connected"] as? Bool == true else { throw AuthError.rejected(json["mes"] as? String ?? "Sign-in did not complete.") }
        return try account(from: json)
    }

    static func request(_ path: String, body: [String: Any], session: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api").appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let session { request.setValue(session, forHTTPHeaderField: "x-spacechat-session") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await urlSession.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw AuthError.network }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.rejected("Spacechat returned an invalid response. Try again.")
        }
        let message = json["mes"] as? String ?? json["error"] as? String ?? json["message"] as? String ?? ""
        guard (200...299).contains(http.statusCode), json["ok"] as? Bool != false else {
            throw AuthError.rejected(message.isEmpty ? "Spacechat couldn't finish this request. Try again." : message)
        }
        return json
    }

    static func account(from json: [String: Any], session fallback: String = "") throws -> Account {
        let session = json["sessionToken"] as? String ?? json["session"] as? String ?? fallback
        let username = json["username"] as? String ?? json["user"] as? String ?? ""
        let id = json["tempId"] as? String ?? json["id"] as? String ?? ""
        guard json["connected"] as? Bool != false, !session.isEmpty, !username.isEmpty, !id.isEmpty else {
            throw AuthError.rejected(json["mes"] as? String ?? json["error"] as? String ?? "Sign-in did not complete. Try again.")
        }
        let name = json["name"] as? String ?? ""
        return Account(id: id,
                       session: session, username: username, displayName: name.isEmpty ? username : name,
                       isNewAccount: json["isNewAccount"] as? Bool ?? false,
                       databaseMode: json["databaseMode"] as? String ?? "browser",
                       database: json["prepaidDatabase"] as? [String: Any], details: json)
    }

    static func bootstrap(session: String) async throws -> Account {
        let json = try await request("session/bootstrap", body: ["includeDatabase": true], session: session)
        return try account(from: json, session: session)
    }

    struct SocialResult {
        let account: Account
        let newPhrase: String?
    }

    static func socialLogin(provider: String, idToken: String, authorizationCode: String = "") async throws -> SocialResult {
        guard ["apple", "google"].contains(provider), !idToken.isEmpty else { throw AuthError.rejected("Sign-in did not return an identity token.") }
        var body: [String: Any] = ["provider": provider, "idToken": idToken, "databaseMode": "prepaid", "native": true]
        if !authorizationCode.isEmpty { body["authorizationCode"] = authorizationCode }
        for _ in 0..<4 {
            let json = try await request("auth/social/login", body: body)
            if json["needsAccount"] as? Bool == true {
                body["newPassphrase"] = generatePhrase()
                continue
            }
            guard json["connected"] as? Bool == true else { throw AuthError.rejected(json["mes"] as? String ?? "Sign-in did not complete. Try again.") }
            return SocialResult(account: try account(from: json), newPhrase: body["newPassphrase"] as? String)
        }
        throw AuthError.rejected("Couldn't create an account right now. Try again.")
    }

    // MARK: - Storage

    /// The phrase is the account — anyone holding it owns it outright — so it
    /// goes in the Keychain, not `UserDefaults`, and is marked
    /// `ThisDeviceOnly` so it never rides along in an iCloud or iTunes backup.
    private static let phraseAccount = "com.spacechat.ai.recoveryPhrase"
    private static let sessionAccount = "com.spacechat.ai.session"

    /// Process-lifetime copies. If the Keychain refuses a write (a build
    /// without keychain entitlements, a locked device) the player must still
    /// be able to use the app until it is closed, instead of being told their
    /// session expired right after signing in.
    private static var memory: [String: String] = [:]
    private static let memoryLock = NSLock()
    private static func remember(_ account: String, _ value: String?) {
        memoryLock.lock(); defer { memoryLock.unlock() }
        memory[account] = value
    }
    private static func remembered(_ account: String) -> String? {
        memoryLock.lock(); defer { memoryLock.unlock() }
        return memory[account]
    }

    static func storePhrase(_ phrase: String) { remember(phraseAccount, normalize(phrase)); keychainSet(phraseAccount, normalize(phrase)) }
    static func storedPhrase() -> String? { keychainGet(phraseAccount) ?? remembered(phraseAccount) }
    static func storeSession(_ session: String) { remember(sessionAccount, session); keychainSet(sessionAccount, session) }
    static func storedSession() -> String? { keychainGet(sessionAccount) ?? remembered(sessionAccount) }

    static func clearStoredCredentials() {
        remember(phraseAccount, nil)
        remember(sessionAccount, nil)
        keychainDelete(phraseAccount)
        keychainDelete(sessionAccount)
    }

    private static func keychainQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.spacechat.ai",
            kSecAttrAccount as String: account
        ]
    }

    private static func keychainSet(_ account: String, _ value: String) {
        guard keychainEnabled else { return }
        guard let data = value.data(using: .utf8) else { return }
        // Delete first: SecItemAdd fails with errSecDuplicateItem rather than
        // overwriting, which would silently keep a stale phrase forever.
        SecItemDelete(keychainQuery(account) as CFDictionary)
        var query = keychainQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func keychainGet(_ account: String) -> String? {
        guard keychainEnabled else { return nil }
        var query = keychainQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(_ account: String) {
        guard keychainEnabled else { return }
        SecItemDelete(keychainQuery(account) as CFDictionary)
    }
}

/// Interoperable with Spacechat web/iOS account-database exports.
enum SpacechatBackup {
    static func object(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8), data.count <= 4_000_000 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func phrase(from text: String) -> String? {
        if let object = object(from: text) {
            let database = object["localDatabase"] as? [String: Any] ?? object
            let account = database["account"] as? [String: Any] ?? [:]
            for value in [object["passphrase"], object["recoveryPhrase"], account["passphrase"]] {
                if let phrase = value as? String, validRawPhrase(phrase) { return SpacechatAuth.normalize(phrase) }
            }
            return nil
        }
        if validRawPhrase(text) { return SpacechatAuth.normalize(text) }
        // Spacechat's text download includes a title and a privacy note.
        return text.components(separatedBy: .newlines).first(where: validRawPhrase).map(SpacechatAuth.normalize)
    }

    static func validRawPhrase(_ text: String) -> Bool {
        text.range(of: #"^[a-zA-Z\s]+$"#, options: .regularExpression) != nil && SpacechatAuth.isValid(text)
    }

    static func database(from object: [String: Any]) -> [String: Any] {
        object["localDatabase"] as? [String: Any] ?? object["payload"] as? [String: Any] ?? object
    }

    static func owns(_ object: [String: Any], account: SpacechatAuth.Account) -> Bool {
        let db = database(from: object)
        let identity = db["account"] as? [String: Any] ?? [:]
        let reference = object["referenceId"] as? String ?? db["referenceId"] as? String ?? identity["referenceId"] as? String ?? ""
        if !reference.isEmpty && !account.referenceID.isEmpty { return reference.uppercased() == account.referenceID.uppercased() }
        let privateOwner = object["privateUsername"] as? String ?? db["privateUsername"] as? String ?? identity["privateUsername"] as? String ?? ""
        if !privateOwner.isEmpty { return privateOwner == account.privateUsername }
        let username = object["username"] as? String ?? db["username"] as? String ?? identity["username"] as? String ?? ""
        return !username.isEmpty && username == account.username
    }
}
