import Foundation

/// Keeps the game connected to the Spacechat server: re-establishes the
/// session on launch, and — where the account allows it — keeps the player's
/// profile in the account's own database so progress follows them between
/// devices.
///
/// Two server facts shape everything here, both taken from
/// `handleUserDatabase` in the Spacechat server rather than assumed:
///
/// 1. Writing to `/api/user-db` is refused unless the session's
///    `databaseMode` is `prepaid` and an active prepaid record exists.
///    Ordinary accounts sign in fine but cannot store anything, so cloud save
///    stays off for them instead of failing on every save.
///
/// 2. A write REPLACES the whole `database` object (the server only preserves
///    `wallet`). Saving one key therefore means reading everything first and
///    writing it all back with that key merged in. Getting this wrong would
///    delete the player's Spacechat data, so `push` never sends a payload it
///    didn't build from a snapshot the server gave us.
@MainActor
final class SpacechatSync: ObservableObject {

    /// Where the game's save lives inside the account database. Namespaced so
    /// it can never collide with a key Spacechat itself uses.
    private static let profileKey = "spacesDotsGame"

    enum State: Equatable {
        case signedOut
        /// Signed in, but this account can't store data server-side.
        case localOnly
        case ready
        case syncing
        case failed(String)
    }

    @Published private(set) var state: State = .signedOut
    @Published private(set) var username: String?
    @Published private(set) var lastSyncedAt: Date?

    /// The account's full database as last seen from the server. Every write
    /// is built from this, never from scratch.
    private var database: [String: Any]?
    private var accountID: String = ""
    private var session: String = ""

    // MARK: - Connecting

    /// Re-establishes the session from the phrase in the Keychain.
    ///
    /// The Spacechat client refreshes an expired session exactly this way —
    /// by logging in again with the stored phrase — so there's no separate
    /// refresh endpoint to call.
    @discardableResult
    func connect() async -> Bool {
        guard let phrase = SpacechatAuth.storedPhrase(), SpacechatAuth.isValid(phrase) else {
            state = .signedOut
            return false
        }
        do {
            adopt(try await SpacechatAuth.login(phrase: phrase))
            return true
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't reach Spacechat.")
            return false
        }
    }

    /// Takes a freshly-returned account as the current connection.
    func adopt(_ account: SpacechatAuth.Account) {
        accountID = account.id
        session = account.session
        username = account.username
        database = account.database
        SpacechatAuth.storeSession(account.session)
        state = account.supportsCloudSave ? .ready : .localOnly
    }

    func disconnect() {
        accountID = ""
        session = ""
        username = nil
        database = nil
        lastSyncedAt = nil
        state = .signedOut
    }

    // MARK: - Pulling

    /// The profile stored in the account, if there is one.
    func cloudProfile() -> PlayerProfile? {
        guard let stored = database?[Self.profileKey] as? [String: Any],
              let payload = stored["profile"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return try? JSONDecoder().decode(PlayerProfile.self, from: data)
    }

    /// True once there is a live session and an account that accepts writes.
    /// A previous failure still counts — otherwise one bad network moment
    /// would switch cloud save off for the rest of the session.
    var canPush: Bool {
        guard !session.isEmpty, database != nil else { return false }
        switch state {
        case .ready, .syncing, .failed: return true
        case .signedOut, .localOnly: return false
        }
    }

    // MARK: - Pushing

    /// Merges the profile into the account database and writes the whole
    /// thing back.
    ///
    /// Silently does nothing when the account can't store data — that's the
    /// normal case for a non-prepaid account, not an error worth showing on
    /// every autosave.
    func push(_ profile: PlayerProfile) async {
        guard canPush, var merged = database else { return }
        guard let encoded = try? JSONEncoder().encode(profile),
              let object = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return }

        state = .syncing
        merged[Self.profileKey] = [
            "profile": object,
            "updatedAt": Date().timeIntervalSince1970 * 1000
        ]

        var request = URLRequest(url: SpacechatAuth.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("user-db"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(session, forHTTPHeaderField: "x-spacechat-session")
        guard let body = try? JSONSerialization.data(withJSONObject: [
            "id": accountID,
            "username": username ?? "",
            "database": merged
        ]) else {
            state = .ready
            return
        }
        request.httpBody = body

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if json["ok"] as? Bool == true {
                // Only adopt the merged copy once the server accepted it, so a
                // rejected write can't leave a local snapshot that disagrees
                // with what's actually stored.
                database = merged
                lastSyncedAt = Date()
                state = .ready
            } else {
                state = .failed(json["error"] as? String ?? "Couldn't save to Spacechat.")
            }
        } catch {
            state = .failed("Couldn't reach Spacechat.")
        }
    }
}
