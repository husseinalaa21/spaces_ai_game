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
        guard isValid(normalized) else { throw AuthError.invalidPhrase }

        var request = URLRequest(url: baseURL.appendingPathComponent("api").appendingPathComponent("dna"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "passphrase": normalized,
            // Spacechat's client maps its local mode to "browser" on the
            // wire; sending "local" is not a value the server knows.
            "databaseMode": "browser",
            "native": true
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.network
        }

        // Parsed as raw JSON rather than through Codable so `prepaidDatabase`
        // survives untouched — see the note on `Account.database`.
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let message = json["message"] as? String ?? ""

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw AuthError.rejected(message)
        }

        let session = json["session"] as? String ?? ""
        guard json["connected"] as? Bool == true, !session.isEmpty else {
            throw AuthError.rejected(message)
        }

        let username = json["username"] as? String ?? ""
        let name = json["name"] as? String ?? ""
        return Account(
            id: json["id"] as? String ?? "",
            session: session,
            username: username,
            displayName: name.isEmpty ? username : name,
            isNewAccount: json["isNewAccount"] as? Bool ?? false,
            databaseMode: json["databaseMode"] as? String ?? "browser",
            database: json["prepaidDatabase"] as? [String: Any]
        )
    }

    // MARK: - Storage

    /// The phrase is the account — anyone holding it owns it outright — so it
    /// goes in the Keychain, not `UserDefaults`, and is marked
    /// `ThisDeviceOnly` so it never rides along in an iCloud or iTunes backup.
    private static let phraseAccount = "com.spacechat.ai.recoveryPhrase"
    private static let sessionAccount = "com.spacechat.ai.session"

    static func storePhrase(_ phrase: String) { keychainSet(phraseAccount, normalize(phrase)) }
    static func storedPhrase() -> String? { keychainGet(phraseAccount) }
    static func storeSession(_ session: String) { keychainSet(sessionAccount, session) }
    static func storedSession() -> String? { keychainGet(sessionAccount) }

    static func clearStoredCredentials() {
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
        var query = keychainQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(_ account: String) {
        SecItemDelete(keychainQuery(account) as CFDictionary)
    }
}
