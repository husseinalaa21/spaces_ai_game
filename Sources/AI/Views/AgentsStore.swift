import SwiftUI

/// An agent: a name, a job and how it behaves. The built-in ones can't be
/// deleted; the person can make their own.
struct SpacesAgent: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var role: String
    var instructions: String
    /// 0...1 hue of the agent's dot.
    var hue: Double
    var builtIn = false
    /// A few lines about who this dot is: shown under it and told to the dot as part of its prompt.
    var bio: String = ""
    /// One of the Spacechat dot shapes (nil: worked out from the dot's id).
    var shape: String? = nil
    /// What this agent may do with files, code and the team's notes.
    var access = AgentAccess()
    var color: Color { Color(hue: hue, saturation: 0.62, brightness: 1.0) }

    init(id: String, name: String, role: String, instructions: String, hue: Double, builtIn: Bool = false, access: AgentAccess = AgentAccess(), bio: String = "", shape: String? = nil) {
        self.id = id; self.name = name; self.role = role; self.instructions = instructions
        self.hue = hue; self.builtIn = builtIn; self.access = access; self.bio = bio; self.shape = shape
    }

    /// What the model is told about this dot: its instructions, then its bio.
    var prompt: String { bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? instructions : instructions + "\n\nAbout you: " + bio }

    private enum CodingKeys: String, CodingKey { case id, name, role, instructions, hue, builtIn, access, bio, shape }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decode(String.self, forKey: .role)
        instructions = try c.decode(String.self, forKey: .instructions)
        hue = try c.decode(Double.self, forKey: .hue)
        builtIn = try c.decodeIfPresent(Bool.self, forKey: .builtIn) ?? false
        access = try c.decodeIfPresent(AgentAccess.self, forKey: .access) ?? AgentAccess()
        bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
        shape = try c.decodeIfPresent(String.self, forKey: .shape)
    }
}

/// What the person changed on a built-in dot: its look, its bio and a few extra instructions.
struct AgentTweak: Codable, Equatable {
    var hue: Double?
    var shape: String?
    var bio: String = ""
    var extra: String = ""
}

/// How each dot looks right now, so an avatar drawn from just an id still gets the person's colour and shape.
enum AgentLookRegistry {
    static var shapes: [String: String] = [:]
    static var hues: [String: Double] = [:]
}

struct AgentMessage: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case user, agent, system, change }
    var id = UUID()
    let kind: Kind
    let from: String
    var to: String? = nil
    let text: String
    var at = Date()
    /// For `.change` messages: which change this is, so it can be undone.
    var changeID: UUID? = nil
}

@MainActor
final class AgentsStore: ObservableObject {
    static let builtIns: [SpacesAgent] = [
        SpacesAgent(id: "builtin-dots", name: "Dots", role: "Lead: plans the work, hands parts to teammates and sums up",
                    instructions: "You coordinate. Break the task into small parts, give each part to the teammate best suited to it by name, check their work and finish with a clear summary.", hue: 0.60, builtIn: true, access: AgentAccess(read: true, write: true, run: false, notes: true)),
        SpacesAgent(id: "builtin-coder", name: "Coder", role: "Writes and fixes code",
                    instructions: "You write clean, working code and small focused edits. You read a file before changing it.", hue: 0.36, builtIn: true, access: AgentAccess(read: true, write: true, run: true, notes: true)),
        SpacesAgent(id: "builtin-writer", name: "Writer", role: "Writes and edits text and documents",
                    instructions: "You write clear, friendly text: documents, READMEs, notes and copy. You keep the person's voice.", hue: 0.08, builtIn: true, access: AgentAccess(read: true, write: true, run: false, notes: true)),
        SpacesAgent(id: "builtin-reviewer", name: "Reviewer", role: "Checks work and finds mistakes",
                    instructions: "You review what teammates made, point out problems briefly and ask for fixes. You do not rewrite everything yourself.", hue: 0.84, builtIn: true, access: AgentAccess(read: true, write: false, run: true, notes: true))
    ]

    @Published private(set) var custom: [SpacesAgent] = []
    /// What the team has learned, shared by every agent (like SpaceAILM's shared notebook).
    @Published private(set) var notes: [String] = []
    /// Access the person changed on a built-in agent.
    @Published private(set) var builtInAccess: [String: AgentAccess] = [:]
    @Published private(set) var tweaks: [String: AgentTweak] = [:]
    @Published private(set) var chats: [String: [AgentMessage]] = [:]
    var all: [SpacesAgent] {
        let list = Self.builtIns.map { builtIn -> SpacesAgent in
            var a = builtIn
            if let changed = builtInAccess[a.id] { a.access = changed }
            if let tweak = tweaks[a.id] {
                if let hue = tweak.hue { a.hue = hue }
                a.shape = tweak.shape
                a.bio = tweak.bio
                let extra = tweak.extra.trimmingCharacters(in: .whitespacesAndNewlines)
                if !extra.isEmpty { a.instructions += "\n\n" + extra }
            }
            return a
        } + custom
        for agent in list { if let shape = agent.shape { AgentLookRegistry.shapes[agent.id] = shape } else { AgentLookRegistry.shapes.removeValue(forKey: agent.id) }; AgentLookRegistry.hues[agent.id] = agent.hue }
        return list
    }

    private let directory: URL?
    private var fileURL: URL? { directory?.appendingPathComponent("SpacesAgents.json") }

    init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("SpacesAI", isDirectory: true)) {
        self.directory = directory
        guard let url = fileURL, let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        custom = saved.custom; chats = saved.chats; notes = saved.notes ?? []; builtInAccess = saved.builtInAccess ?? [:]; tweaks = saved.tweaks ?? [:]
    }

    private struct Saved: Codable {
        var custom: [SpacesAgent]; var chats: [String: [AgentMessage]]
        var notes: [String]? = nil; var builtInAccess: [String: AgentAccess]? = nil; var tweaks: [String: AgentTweak]? = nil
    }

    private func persist() {
        guard let url = fileURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Saved(custom: custom, chats: chats, notes: notes, builtInAccess: builtInAccess, tweaks: tweaks)) { try? data.write(to: url, options: .atomic) }
    }

    func add(id: String? = nil, name: String, role: String, instructions: String, hue: Double, access: AgentAccess = AgentAccess(), bio: String = "", shape: String? = nil) -> SpacesAgent {
        let agent = SpacesAgent(id: id ?? "agent-" + UUID().uuidString, name: uniqueName(name), role: role, instructions: instructions, hue: hue, access: access, bio: bio, shape: shape)
        custom.append(agent); persist()
        return agent
    }

    /// Saves changes to a dot the person made.
    func update(_ agent: SpacesAgent) {
        guard !agent.builtIn, let i = custom.firstIndex(where: { $0.id == agent.id }) else { return }
        var next = agent
        let clean = agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(all.filter { $0.id != agent.id }.map { $0.name.lowercased() })
        next.name = clean.isEmpty || taken.contains(clean.lowercased()) ? custom[i].name : String(clean.prefix(24))
        custom[i] = next; persist()
    }

    /// Saves the person's changes to a built-in dot (they can't rename or delete it).
    func setTweak(_ tweak: AgentTweak, for id: String) {
        tweaks[id] = tweak; persist()
    }

    func setAccess(_ access: AgentAccess, for agent: SpacesAgent) {
        if agent.builtIn { builtInAccess[agent.id] = access }
        else if let i = custom.firstIndex(where: { $0.id == agent.id }) { custom[i].access = access }
        persist()
    }

    func addNote(_ text: String, by agent: String) {
        let line = "\(agent): \(text)"
        guard !notes.contains(line) else { return }
        notes.append(line)
        if notes.count > 50 { notes.removeFirst(notes.count - 50) }
        persist()
    }

    func clearNotes() { notes = []; persist() }

    func delete(_ agent: SpacesAgent) {
        guard !agent.builtIn else { return }
        custom.removeAll { $0.id == agent.id }
        chats.removeValue(forKey: agent.id)
        persist()
    }

    /// Names are how agents address each other, so each must be unique.
    private func uniqueName(_ raw: String) -> String {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)
        let name = base.isEmpty ? "Agent" : String(base)
        let taken = Set(all.map { $0.name.lowercased() })
        if !taken.contains(name.lowercased()) { return name }
        for i in 2...99 where !taken.contains("\(name) \(i)".lowercased()) { return "\(name) \(i)" }
        return name + " " + String(UUID().uuidString.prefix(4))
    }

    func messages(for agent: SpacesAgent) -> [AgentMessage] { chats[agent.id] ?? [] }

    func append(_ message: AgentMessage, to agent: SpacesAgent) {
        chats[agent.id, default: []].append(message)
        if chats[agent.id]!.count > 200 { chats[agent.id]!.removeFirst(chats[agent.id]!.count - 200) }
        persist()
    }

    func clearChat(_ agent: SpacesAgent) { chats[agent.id] = []; persist() }
}
