import Foundation

/// Local persistence for `PlayerProfile` (§102: "Persist... progression").
///
/// This is a placeholder for cloud/server persistence — the spec calls for
/// server-backed saves once accounts exist (§57 User model), but a local
/// JSON file lets the MVP core loop be fully playable and durable offline
/// today. Swapping this for a network-backed implementation later shouldn't
/// require touching `GameEngine` or the views, since they only see
/// `scheduleSave` / `load`.
final class SaveManager {
    private let fileURL: URL
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "ai.game.save", qos: .utility)

    init(filename: String = "ai_player_profile.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = dir.appendingPathComponent(filename)
    }

    func load() -> PlayerProfile {
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
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow(profile)
        }
        pendingSaveWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow(_ profile: PlayerProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
