import SwiftUI

/// A workspace is its own map: its own topics, its own team of dots and its own look (the old "universes"). People keep one for each
/// thing they work on, and switch between them from the top of the map.
struct Workspace: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var theme: UniverseTheme
    /// The dots on this workspace's map. nil means every dot.
    var team: [String]?
}

@MainActor
final class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()
    /// Topics made before workspaces existed belong to this one.
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Published private(set) var all: [Workspace]
    @Published private(set) var currentID: UUID
    private let url: URL?

    var current: Workspace { all.first { $0.id == currentID } ?? all[0] }

    init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("SpacesAI", isDirectory: true)) {
        url = directory?.appendingPathComponent("SpacesWorkspaces.json")
        let fallback = [Workspace(id: Self.defaultID, name: "My space", theme: .white, team: nil)]
        if let url, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data), !saved.all.isEmpty {
            all = saved.all
            currentID = saved.all.contains { $0.id == saved.currentID } ? saved.currentID : saved.all[0].id
        } else {
            all = fallback; currentID = Self.defaultID
        }
    }

    private struct Saved: Codable { var all: [Workspace]; var currentID: UUID }

    private func persist() {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Saved(all: all, currentID: currentID)) { try? data.write(to: url, options: .atomic) }
    }

    func select(_ id: UUID) {
        guard all.contains(where: { $0.id == id }) else { return }
        currentID = id; persist()
    }

    @discardableResult
    func add(name: String, theme: UniverseTheme, team: [String]?) -> Workspace {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let space = Workspace(name: clean.isEmpty ? "New space" : String(clean.prefix(28)), theme: theme, team: team)
        all.append(space); currentID = space.id; persist()
        return space
    }

    func update(_ space: Workspace) {
        guard let i = all.firstIndex(where: { $0.id == space.id }) else { return }
        var next = space
        next.name = String(next.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(28))
        if next.name.isEmpty { next.name = all[i].name }
        all[i] = next; persist()
    }

    /// The last workspace can't be deleted.
    func delete(_ id: UUID) {
        guard all.count > 1 else { return }
        all.removeAll { $0.id == id }
        if currentID == id { currentID = all[0].id }
        persist()
    }
}

extension WorldBackground.Palette {
    /// True when the workspace's look is dark, so the map draws its labels and lines in white.
    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(background).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b < 0.45
    }
}
