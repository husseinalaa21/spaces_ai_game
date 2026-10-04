import SwiftUI

/// A finished piece of work the person chose to keep: what it was, who worked on it, what they said and what they came up with.
/// Saved projects sit on the home map.
struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var idea: String
    var teamIDs: [String]
    var summary: String
    var transcript: [AgentMessage]
    var createdAt = Date()
    var workspaceID: UUID?
    /// The folder (in Folders) holding this project's files.
    var folder: String?
}

@MainActor
final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()
    @Published private(set) var projects: [Project] = []
    private let url: URL?

    init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("SpacesAI", isDirectory: true)) {
        url = directory?.appendingPathComponent("SpacesProjects.json")
        if let url, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([Project].self, from: data) { projects = saved }
    }

    private func persist() {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(projects) { try? data.write(to: url, options: .atomic) }
    }

    func projects(in workspace: UUID) -> [Project] {
        projects.filter { ($0.workspaceID ?? WorkspaceStore.defaultID) == workspace }.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ project: Project) {
        if let i = projects.firstIndex(where: { $0.id == project.id }) { projects[i] = project } else { projects.append(project) }
        persist()
    }

    func delete(_ id: UUID) { projects.removeAll { $0.id == id }; persist() }
}
