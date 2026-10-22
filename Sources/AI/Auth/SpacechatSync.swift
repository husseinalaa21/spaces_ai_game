import Foundation
import Combine

/// Cloud game saves use an account-owned revisioned record. This never writes
/// the full Spacechat database, so messages and profile edits stay intact.
@MainActor
final class SpacechatSync: ObservableObject {
    enum State: Equatable { case signedOut, localOnly, ready, syncing, failed(String) }
    @Published private(set) var state: State = .signedOut
    @Published private(set) var username: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var cloudAvailable = false
    @Published private(set) var databaseMode = "browser"
    private var accountScope = ""
    private var profile: PlayerProfile?
    private var version: Int?
    private var busy = false
    private var needsProgressChoice = false
    private var connection = UUID()
    private var pendingSave: Task<Void, Never>?

    func adopt(_ account: SpacechatAuth.Account) {
        let scope = account.privateUsername.isEmpty ? account.id : account.privateUsername
        if scope != accountScope {
            pendingSave?.cancel()
            connection = UUID(); profile = nil; version = nil; lastSyncedAt = nil; busy = false; needsProgressChoice = false
        }
        accountScope = scope
        username = account.username
        databaseMode = account.databaseMode
        cloudAvailable = account.cloudAvailable
        if profile == nil, let legacy = account.database?["spacesDotsGame"] as? [String: Any],
           let raw = legacy["profile"] as? [String: Any], let data = try? JSONSerialization.data(withJSONObject: raw) {
            profile = try? JSONDecoder().decode(PlayerProfile.self, from: data)
        }
        state = databaseMode == "prepaid" && cloudAvailable ? .ready : .localOnly
    }

    func disconnect() {
        pendingSave?.cancel(); pendingSave = nil
        connection = UUID(); accountScope = ""; username = nil; profile = nil; version = nil
        lastSyncedAt = nil; cloudAvailable = false; databaseMode = "browser"; busy = false; state = .signedOut
        needsProgressChoice = false
    }

    func cloudProfile() -> PlayerProfile? { profile }
    var canPush: Bool { !accountScope.isEmpty && databaseMode == "prepaid" && cloudAvailable && !busy }

    /// Coalesce gameplay/settings updates while the app is still foregrounded.
    /// A background-only save can be suspended before its HTTP request finishes.
    func schedulePush(_ snapshot: PlayerProfile) {
        pendingSave?.cancel()
        guard databaseMode == "prepaid", cloudAvailable else { return }
        let stamp = connection
        pendingSave = Task {
            do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            while busy && connection == stamp && !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            }
            guard connection == stamp, !Task.isCancelled else { return }
            await push(snapshot)
        }
    }

    /// Reading never overwrites the UI's local progress. The caller chooses
    /// whether to restore it (automatic only for a fresh local profile).
    @discardableResult
    func refresh() async -> Bool {
        guard canPush else { return false }
        let stamp = connection
        busy = true; state = .syncing
        defer { if stamp == connection { busy = false } }
        do {
            let json = try await SpacechatService.post("spaces/game-state")
            guard connection == stamp else { return false }
            if let raw = json["profile"] as? [String: Any] {
                let data = try JSONSerialization.data(withJSONObject: raw)
                profile = try JSONDecoder().decode(PlayerProfile.self, from: data)
            } else { profile = nil }
            version = json["version"] as? Int ?? 0
            needsProgressChoice = profile != nil
            let updated = json["updatedAt"] as? Double ?? 0
            lastSyncedAt = updated > 0 ? Date(timeIntervalSince1970: updated / 1000) : nil
            state = .ready
            return true
        } catch {
            if stamp == connection { state = .failed(error.localizedDescription) }
            return false
        }
    }

    /// Called after choosing the cloud copy, or when both copies are identical.
    func confirmLoadedProfile(_ local: PlayerProfile) {
        guard let profile else { needsProgressChoice = false; return }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        if (try? encoder.encode(local)) == (try? encoder.encode(profile)) {
            needsProgressChoice = false
        } else {
            state = .failed("Device and cloud progress differ. In Settings, reload cloud progress or choose Save game progress to cloud to keep this device's copy.")
        }
    }

    func push(_ snapshot: PlayerProfile, replaceCloud: Bool = false) async {
        guard canPush else { return }
        if version == nil {
            guard await refresh() else { return }
            if profile != nil && !replaceCloud {
                state = .failed("Cloud progress already exists. Reload it in Settings before saving from this device.")
                return
            }
        }
        guard !needsProgressChoice || replaceCloud else {
            state = .failed("Choose which progress to keep in Settings before cloud autosave can continue.")
            return
        }
        guard canPush, let expectedVersion = version else { return }
        let stamp = connection
        busy = true; state = .syncing
        defer { if stamp == connection { busy = false } }
        do {
            let data = try JSONEncoder().encode(snapshot)
            let raw = try JSONSerialization.jsonObject(with: data)
            let json = try await SpacechatService.post("spaces/game-state", body: ["profile": raw, "expectedVersion": expectedVersion])
            guard stamp == connection else { return }
            guard json["saved"] as? Bool == true, let next = json["version"] as? Int else {
                throw SpacechatAuth.AuthError.rejected("Spacechat did not confirm this save. Try again.")
            }
            version = next; profile = snapshot; needsProgressChoice = false; lastSyncedAt = Date(); state = .ready
        } catch {
            if stamp == connection { state = .failed(error.localizedDescription) }
        }
    }
}
