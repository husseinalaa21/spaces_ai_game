import Foundation

// The production auth/backup code is exercised with fixture HTTP responses.
// Neither provider credentials nor a real account/Keychain are used.
struct PlayerProfile: Codable {
    var points: Int = 0
}

enum SpacechatService {
    static func post(_ path: String, body: [String: Any] = [:]) async throws -> [String: Any] {
        try await SpacechatAuth.request(path, body: body, session: SpacechatAuth.storedSession())
    }
}
final class AccountFixture: URLProtocol {
    static var handler: (URLRequest) throws -> (Int, [String: Any]) = { _ in throw URLError(.badServerResponse) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, json) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: json))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

@main struct SharedAccountChecks {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AccountFixture.self]
        SpacechatAuth.urlSession = URLSession(configuration: config)
        SpacechatAuth.keychainEnabled = false
        SpacechatAuth.clearStoredCredentials()
        let suite = "spaces.shared-account.checks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); SpacechatAuth.clearStoredCredentials() }
        var passed = 0
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw NSError(domain: label, code: 1) }
            passed += 1; print("PASS: " + label)
        }
        let phrase = "abandon ability able about above absent absorb abstract absurd abuse access accident"
        let payload: [String: Any] = ["ok": true, "connected": true, "id": "account-a", "sessionToken": "session-a", "username": "alice", "privateUsername": "private-a", "name": "Alice", "referenceId": "ref-a", "databaseMode": "prepaid", "prepaidDatabase": ["messages": ["keep": true], "futureField": ["keep": true]]]
        try check(SpacechatAuth.wordCount(SpacechatAuth.generatePhrase()) == 12, "new recovery phrases contain exactly 12 words")
        try check(SpacechatAuth.isValid(phrase + " achieve acid acoustic actor actress actual"), "legacy 18-word phrases remain valid")
        try check(!SpacechatBackup.validRawPhrase(phrase + "1"), "invalid phrase characters are rejected")
        AccountFixture.handler = { request in
            let data = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
                stream.open(); defer { stream.close() }; var result = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; result.append(buffer, count: n) }; return result
            } ?? Data()
            let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            guard request.url!.path == "/api/dna", body["passphrase"] as? String == phrase, body["native"] as? Bool == true else { throw URLError(.badURL) }
            return (200, payload)
        }
        let account = try await SpacechatAuth.login(phrase: phrase)
        try check(account.privateUsername == "private-a" && account.referenceID == "ref-a", "shared identity and recovery reference are parsed")
        try check((account.database?["futureField"] as? [String: Bool])?["keep"] == true, "unknown shared database fields survive login parsing")
        let auth = AuthState(defaults: defaults)
        let signedIn = await auth.signInWithSpacechat(phrase: phrase)
        try check(signedIn && auth.isSignedIn && auth.needsPhraseBackup, "first successful phrase login requires backup screen")
        try check(SpacechatAuth.storedPhrase() == phrase, "successful phrase login retains the recoverable phrase")
        auth.acknowledgePhraseBackup()
        try check(!auth.needsPhraseBackup, "Continue acknowledges phrase backup for this account")
        auth.signOut(revoke: false)
        try check(!auth.isSignedIn && SpacechatAuth.storedPhrase() == nil && SpacechatAuth.storedSession() == nil, "sign-out clears account credentials")
        _ = await auth.signInWithSpacechat(phrase: phrase)
        try check(!auth.needsPhraseBackup, "returning account does not repeat acknowledged backup")
        auth.signOut(revoke: false)
        AccountFixture.handler = { _ in (503, ["ok": false, "error": "Try again later", "retryable": true]) }
        let failed = await auth.signInWithSpacechat(phrase: phrase)
        try check(!failed && !auth.isSignedIn && SpacechatAuth.storedPhrase() == nil, "failed login commits no identity or phrase")
        var socialCalls = 0
        AccountFixture.handler = { request in
            guard request.url!.path == "/api/auth/social/login" else { throw URLError(.badURL) }
            socialCalls += 1
            return socialCalls == 1 ? (200, ["ok": true, "connected": false, "needsAccount": true]) : (200, payload)
        }
        let social = try await SpacechatAuth.socialLogin(provider: "apple", idToken: "fixture-token")
        try check(socialCalls == 2 && social.newPhrase.map(SpacechatAuth.wordCount) == 12, "unknown provider uses server needsAccount before generating 12 words")
        socialCalls = 0
        AccountFixture.handler = { _ in socialCalls += 1; return (200, payload) }
        let existing = try await SpacechatAuth.socialLogin(provider: "google", idToken: "fixture-token")
        try check(socialCalls == 1 && existing.newPhrase == nil, "existing provider account never receives an invented recovery phrase")
        let bundle: [String: Any] = ["kind": "spacechat-account-database", "passphrase": phrase, "localDatabase": ["privateUsername": "private-a", "spacesDotsGame": ["profile": ["points": 3]], "futureField": ["x": 1]]]
        let text = String(data: try JSONSerialization.data(withJSONObject: bundle), encoding: .utf8)!
        try check(SpacechatBackup.phrase(from: text) == phrase, "Spacechat account database upload extracts the original phrase")
        try check(SpacechatBackup.phrase(from: "Spacechat recovery phrase for alice\n\n" + phrase + "\n\nKeep this private.") == phrase, "Spacechat formatted text phrase downloads can be imported")
        try check(SpacechatBackup.owns(bundle, account: account), "matching private account may restore a database")
        let foreign: [String: Any] = ["localDatabase": ["privateUsername": "private-b", "username": "alice"]]
        try check(!SpacechatBackup.owns(foreign, account: account), "public username cannot override a different private backup owner")
        let nativeBundle: [String: Any] = ["localDatabase": ["account": ["privateUsername": "private-a"]]]
        try check(SpacechatBackup.owns(nativeBundle, account: account), "Spacechat iOS nested account backup ownership is recognized")
        let recoveredBundle: [String: Any] = ["referenceId": "ref-a", "localDatabase": ["privateUsername": "old-private"]]
        try check(SpacechatBackup.owns(recoveredBundle, account: account), "a matching stable reference can restore the same account after phrase recovery")
        try check(SpacechatBackup.database(from: bundle)["futureField"] != nil, "portable backups preserve unrecognized database sections")
        var malformed = payload; malformed.removeValue(forKey: "sessionToken")
        do { _ = try SpacechatAuth.account(from: malformed); throw NSError(domain: "missing-session", code: 1) }
        catch is SpacechatAuth.AuthError { passed += 1; print("PASS: malformed login with no session is rejected") }
        AccountFixture.handler = { request in
            guard request.url!.path == "/api/spaces/game-state" else { throw URLError(.badURL) }
            return (200, ["ok": true, "profile": ["points": 10], "version": 2, "updatedAt": 1000])
        }
        let sync = SpacechatSync(); sync.adopt(account)
        let refreshed = await sync.refresh()
        try check(refreshed && sync.cloudProfile()?.points == 10, "cloud game profile loads through the separate account-owned endpoint")
        AccountFixture.handler = { request in
            guard request.url!.path == "/api/spaces/game-state" else { throw URLError(.badURL) }
            return (200, ["ok": true, "saved": true, "version": 3])
        }
        await sync.push(PlayerProfile(points: 11))
        try check(sync.cloudProfile()?.points == 10 && sync.state != .ready, "different device progress requires an explicit choice before cloud autosave")
        await sync.push(PlayerProfile(points: 11), replaceCloud: true)
        try check(sync.state == .ready && sync.cloudProfile()?.points == 11, "revisioned cloud save adopts progress only after confirmation")
        AccountFixture.handler = { _ in (409, ["ok": false, "code": "GAME_SAVE_CONFLICT", "error": "Another device saved newer progress."]) }
        await sync.push(PlayerProfile(points: 1))
        try check(sync.cloudProfile()?.points == 11 && sync.state != .ready, "cloud conflicts retain previously confirmed progress and show failure")
        sync.disconnect()
        try check(sync.cloudProfile() == nil && sync.username == nil && sync.state == .signedOut, "sign-out clears the cloud account snapshot")
        var local = account; local = SpacechatAuth.Account(id: local.id, session: local.session, username: local.username, displayName: local.displayName, isNewAccount: false, databaseMode: "browser", database: nil)
        sync.adopt(local)
        try check(!sync.canPush, "device-only accounts cannot send a cloud save")
        sync.adopt(account)
        AccountFixture.handler = { _ in (404, ["ok": false, "error": "Game save API is not deployed."]) }
        await sync.push(PlayerProfile(points: 12))
        try check(sync.state != .ready && sync.cloudProfile() == nil, "missing cloud endpoint never falls back to overwriting the shared database")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("spaces-saves-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let saves = SaveManager(accountScope: "private-a", storageDirectory: directory)
        saves.saveNow(PlayerProfile(points: 42)); saves.switchAccount(to: "private-b")
        try check(saves.load().points == 0, "new account never loads another account's device progress")
        saves.saveNow(PlayerProfile(points: 9)); saves.switchAccount(to: "private-a")
        try check(saves.load().points == 42, "returning account restores its own device progress")
        saves.scheduleSave(PlayerProfile(points: 77)); saves.switchAccount(to: "private-b")
        try await Task.sleep(nanoseconds: 700_000_000)
        try check(saves.load().points == 9, "debounced save cannot write into a switched account")
        saves.removeCurrentSave()
        try check(saves.load().points == 0, "deleted account's device game save is removed")
        print("\(passed) shared account checks passed")
    }
}
