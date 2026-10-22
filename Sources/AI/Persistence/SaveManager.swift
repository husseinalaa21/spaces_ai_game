import Foundation
import CryptoKit

/// Account-scoped device persistence, with atomic writes and a captured file
/// destination so a delayed save cannot cross an account switch. Cloud saves
/// are owned by SpacechatSync and do not replace local/offline persistence.
final class SaveManager {
    private var fileURL: URL
    private let pathLock = NSLock()
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "ai.game.save", qos: .utility)

    init(filename: String = "ai_player_profile.json", accountScope: String? = nil, storageDirectory: URL? = nil) {
        let dir = storageDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = dir.appendingPathComponent(filename)
        fileURL = accountScope.map { dir.appendingPathComponent(Self.filename(for: $0)) } ?? legacy
        // Migrate only to the account that owned this installation before
        // account-scoped files existed; never copy it into later accounts.
        if accountScope != nil, !FileManager.default.fileExists(atPath: fileURL.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: fileURL)
        }
    }

    static func filename(for scope: String) -> String {
        let hash = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return "ai_player_" + hash + ".json"
    }

    func switchAccount(to scope: String, migrateCurrent: Bool = false) {
        pendingSaveWorkItem?.cancel()
        pathLock.lock(); defer { pathLock.unlock() }
        let next = fileURL.deletingLastPathComponent().appendingPathComponent(Self.filename(for: scope))
        if migrateCurrent, !FileManager.default.fileExists(atPath: next.path), FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.moveItem(at: fileURL, to: next)
        }
        fileURL = next
    }

    func removeCurrentSave() {
        pendingSaveWorkItem?.cancel()
        let target = destination
        queue.sync { try? FileManager.default.removeItem(at: target) }
    }

    private var destination: URL {
        pathLock.lock(); defer { pathLock.unlock() }
        return fileURL
    }

    func load() -> PlayerProfile {
        let fileURL = destination
        guard let data = try? Data(contentsOf: fileURL) else {
            return PlayerProfile()
        }
        if let profile = try? JSONDecoder().decode(PlayerProfile.self, from: data) {
            return profile
        }
        // The save file exists but won't decode — e.g. a partial write from
        // the app being killed mid-save, or a future build changing the
        // schema in an incompatible way. Move it aside instead of silently
        // starting fresh and then overwriting it for good on the next save,
        // so there's at least a chance of recovering it by hand later.
        let backupURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.lastPathComponent + ".corrupt-\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
        return PlayerProfile()
    }

    /// Debounced save so rapid eating doesn't hit disk every frame.
    func scheduleSave(_ profile: PlayerProfile) {
        pendingSaveWorkItem?.cancel()
        let target = destination
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(profile) else { return }
            try? data.write(to: target, options: .atomic)
        }
        pendingSaveWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow(_ profile: PlayerProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: destination, options: .atomic)
    }
}
