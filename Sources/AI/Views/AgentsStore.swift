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
    /// The Spacechat dot this agent is (Space Magic, ...): its picture is drawn from this key, exactly as in the Spacechat app.
    var dotKey: String? { Self.spacechatDotKeys[id] }
    /// What the picture is drawn from: the Spacechat dot's key, or the agent's own id.
    var visualKey: String { dotKey ?? id }
    /// The AI dots wear their logo: a round picture filled with it (the same pictures as in the Spacechat app).
    static let logos: [String: String] = [
        "builtin-spaceai": "LogoSpacechatAI", "builtin-ai-claude": "LogoClaude", "builtin-ai-chatgpt": "LogoChatGPT", "builtin-ai-grok": "LogoGrok",
    ]
    var logo: String? { Self.logos[id] }
    /// Claude, ChatGPT and Grok are for members, as in the Spacechat app; Spacechat AI is free.
    static let memberOnlyIDs: Set<String> = ["builtin-ai-claude", "builtin-ai-chatgpt", "builtin-ai-grok"]
    var membersOnly: Bool { Self.memberOnlyIDs.contains(id) }
    static let spacechatDotKeys: [String: String] = [
        "builtin-spaceai": "spaceai", "builtin-spacemagic": "spacemagic", "builtin-spacetrading": "spacetrading", "builtin-spaceideas": "spaceideas",
        "builtin-spacedrive": "spacedrive", "builtin-spacemusic": "spacemusic", "builtin-spacephotos": "spacephotos", "builtin-spacevideos": "spacevideos",
        "builtin-spaceshows": "spaceshows",
    ]
    /// The colour a Spacechat dot has in the Spacechat app (0...1), so it looks the same here.
    static func spacechatHue(_ key: String) -> Double {
        (SpacechatDotGeometry.brandHues[key] ?? Double((SpacechatDotGeometry.hash(key) >> 3) % 360)) / 360
    }

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
    /// The Spacechat dot key an agent is drawn from (Space Magic, ...).
    static var keys: [String: String] = [:]
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


    /// Every dot of the Spacechat app (Spacechat AI and its eight focused versions), with the same names, jobs and colours.
    static let spacechatDots: [SpacesAgent] = [
        ("builtin-spaceai", "Spacechat AI", "Answers questions about anything", "You are Spacechat AI: you answer any question clearly and honestly, and help with everyday tasks."),
        ("builtin-spacemagic", "Space Magic", "Tech tricks, shortcuts and how-tos", "You are Space Magic. You get answers fast and teach clever tech tricks, shortcuts and how-tos."),
        ("builtin-spacetrading", "Space Trading", "Money skills: investing basics and risk", "You are Space Trading. You grow money skills: investing basics, risk management and steady habits. You never promise returns."),
        ("builtin-spaceideas", "Space Ideas", "Turns ideas into projects and income", "You are Space Ideas. You grow ideas into real projects, products and income."),
        ("builtin-spacedrive", "Space Drive", "Habits, discipline and momentum", "You are Space Drive. You build discipline, habits and momentum to reach goals."),
        ("builtin-spacemusic", "Space Music", "Practice, songwriting and audience", "You are Space Music. You help people grow as musicians: practice, songwriting, theory and audience."),
        ("builtin-spacephotos", "Space Photos", "Composition, light and editing", "You are Space Photos. You help people grow as photographers: composition, light, editing and sharing work."),
        ("builtin-spacevideos", "Space Videos", "Hooks, scripts and editing", "You are Space Videos. You help people grow as video creators: hooks, scripts, editing and audience."),
        ("builtin-spaceshows", "Space Shows", "Taste and storytelling from shows and films", "You are Space Shows. You grow taste and storytelling through great shows and films."),
    ].map { row in
        SpacesAgent(id: row.0, name: row.1, role: row.2, instructions: row.3, hue: SpacesAgent.spacechatHue(SpacesAgent.spacechatDotKeys[row.0] ?? row.0), builtIn: true,
                    access: AgentAccess(read: true, write: true, run: false, notes: true))
    }

    /// The AI model dots (members only): each one is drawn as its logo.
    static let aiModelDots: [SpacesAgent] = [
        ("builtin-ai-claude", "Claude", "Careful thinking, writing and analysis", "You are the Claude dot. You think carefully, explain your reasoning plainly, write clearly and say when you are unsure.", 0.05),
        ("builtin-ai-chatgpt", "ChatGPT", "All-round answers, ideas and drafts", "You are the ChatGPT dot. You give direct, well-organised answers, draft quickly and offer practical next steps.", 0.45),
        ("builtin-ai-grok", "Grok", "Fast, direct answers with a bit of wit", "You are the Grok dot. You answer fast and directly, with a light, witty tone, and you stay accurate.", 0.0),
    ].map { row in
        SpacesAgent(id: row.0, name: row.1, role: row.2, instructions: row.3, hue: row.4, builtIn: true, access: AgentAccess(read: true, write: true, run: false, notes: true))
    }

    /// The questions each Spacechat dot suggests (the same ones as in the Spacechat app).
    static let spacechatSuggestions: [String: [String]] = [
        "builtin-spaceai": ["Write a bio for my profile", "Help me plan a small project"],
        "builtin-spacemagic": ["Teach me 5 iPhone tricks most people don’t know", "How do I make a slow laptop faster?"],
        "builtin-spacetrading": ["Explain how investing works for a beginner", "Help me build a simple plan to grow my savings"],
        "builtin-spaceideas": ["Help me turn my idea into a simple plan", "Give me 5 side-project ideas that can grow"],
        "builtin-spacedrive": ["Help me build a daily routine I can stick to", "I feel unmotivated. How do I get moving?"],
        "builtin-spacemusic": ["Make me a 4-week practice plan for guitar", "How do I write my first song?"],
        "builtin-spacephotos": ["Teach me composition rules to improve my photos", "How do I get better light without a studio?"],
        "builtin-spacevideos": ["Plan a short video that can grow my audience", "How do I write a strong hook in 3 seconds?"],
        "builtin-ai-claude": ["Help me think through a hard decision", "Review my writing and make it clearer"],
        "builtin-ai-chatgpt": ["Draft a short announcement for my project", "Give me 5 ideas to improve this plan"],
        "builtin-ai-grok": ["Give me a straight answer: is my idea worth building?", "Explain this in two sentences"],
        "builtin-spaceshows": ["Recommend shows that will teach me something new", "Break down what makes a great story"],
    ]

    @Published private(set) var custom: [SpacesAgent] = []
    /// What the team has learned, shared by every agent (like SpaceAILM's shared notebook).
    @Published private(set) var notes: [String] = []
    /// Access the person changed on a built-in agent.
    @Published private(set) var builtInAccess: [String: AgentAccess] = [:]
    @Published private(set) var tweaks: [String: AgentTweak] = [:]
    @Published private(set) var chats: [String: [AgentMessage]] = [:]
    var all: [SpacesAgent] {
        let list = (Self.builtIns + Self.spacechatDots + Self.aiModelDots).map { builtIn -> SpacesAgent in
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
        for agent in list {
            if let shape = agent.shape { AgentLookRegistry.shapes[agent.id] = shape } else { AgentLookRegistry.shapes.removeValue(forKey: agent.id) }
            AgentLookRegistry.hues[agent.id] = agent.hue
            if let key = agent.dotKey { AgentLookRegistry.keys[agent.id] = key }
        }
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
