import SwiftUI

/// A match's other players are driven by the Spacechat language model (the
/// same one behind the AI tab). To the person playing they are simply
/// players: nothing here or on screen says otherwise.

// MARK: - Characters

/// Who a player is: a voice, a mood and how often they talk. Every message
/// the player sends comes from the language model prompted as this person,
/// so each one sounds different and speaks on their own schedule.
struct DotPersona {
    let name: String
    let character: String
    /// Seconds between their messages (min, max): talkative players are quick,
    /// quiet ones can go a long while without saying anything.
    let gap: ClosedRange<Double>
    /// Chance they answer when somebody speaks to the room.
    let chattiness: Double
    /// Used only when the model can't be reached.
    let fallback: [String]
    /// How they play until the model decides otherwise.
    let style: AgentStyle
    let aggression: Double

    private typealias Archetype = (character: String, gap: ClosedRange<Double>, chattiness: Double, fallback: [String], style: AgentStyle, aggression: Double)
    private static let archetypes: [Archetype] = [
        ("a cocky trash-talker who brags about their size and teases others, short punchy sentences", 7...15, 0.85, ["too easy", "you're lunch", "watch me grow"], .hunt, 0.8),
        ("a friendly newcomer who asks questions and gets excited about small wins, uses an exclamation mark sometimes", 9...18, 0.8, ["wait how do i grow faster?", "this is fun!", "oh nice one"], .farm, 0.3),
        ("a calm strategist who gives short practical tips about when to eat and when to run, never uses emojis", 14...28, 0.6, ["stay near the middle", "eat small, avoid big", "patience wins"], .ambush, 0.5),
        ("a joker who makes puns and silly comparisons, often adds one emoji", 8...17, 0.75, ["im on a roll 😄", "dot worry about it", "that was a snack"], .hunt, 0.5),
        ("a sleepy player who types in lowercase with the odd typo and sounds half asleep", 18...36, 0.45, ["so tired lol", "wher did everyone go", "eating slowly"], .farm, 0.15),
        ("a hyper player who gets loud, uses CAPS for a word or two and reacts to everything instantly", 6...12, 0.9, ["WOW that was close", "im HUGE now", "run run run"], .hunt, 0.95),
        ("a polite older player, courteous and a little formal, writes full sentences", 16...30, 0.55, ["Good luck everyone.", "Well played.", "That was a fine move."], .flee, 0.3),
        ("a quiet deadpan player who speaks rarely, in very few words", 28...55, 0.3, ["hm.", "ok.", "nice."], .ambush, 0.4)
    ]

    private static var registry: [String: DotPersona] = [:]

    /// A crew with all-different characters.
    static func crew(for names: [String]) -> [DotPersona] {
        let order = archetypes.indices.shuffled()
        return names.enumerated().map { i, name in
            let a = archetypes[order[i % order.count]]
            let persona = DotPersona(name: name, character: a.character, gap: a.gap, chattiness: a.chattiness, fallback: a.fallback, style: a.style, aggression: a.aggression)
            registry[name] = persona
            return persona
        }
    }

    /// The same person every time you meet them (private chats, servers).
    static func persona(for name: String) -> DotPersona {
        if let known = registry[name] { return known }
        let hash = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        let a = archetypes[abs(hash) % archetypes.count]
        let persona = DotPersona(name: name, character: a.character, gap: a.gap, chattiness: a.chattiness, fallback: a.fallback, style: a.style, aggression: a.aggression)
        registry[name] = persona
        return persona
    }
}

// MARK: - Chat director

/// Runs the match's players. Talking is the slow part of a match, so it never
/// happens per frame and never one player at a time: every second the director
/// looks at who feels like speaking, asks the server ONE batched question for
/// all of them (`POST /api/spaces/agents`, mode "chat"), and shows each line at
/// its own moment. How each player plays is decided separately, every ~15
/// seconds ("strategy"), and the engine only reads the result.
///
/// A server without that endpoint still works: the director falls back to the
/// older one-player-at-a-time route, and offline to each character's own lines.
@MainActor
final class DotChatDirector: ObservableObject {
    private var personas: [DotPersona] = []
    private var opening: [String: String] = [:]
    private var nextAt: [String: Date] = [:]
    private var recent: [(name: String, text: String, at: Date)] = []
    private var loop: Task<Void, Never>?
    private var strategyLoop: Task<Void, Never>?
    private weak var engine: GameEngine?

    private var batchWorks = true
    private var lastCall = Date.distantPast
    private static let minGap: TimeInterval = 2.0

    // The older per-player route answers one request at a time.
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    private enum Trigger { case opening, free, reply(String, String), player(String) }

    // MARK: Lobby

    /// Creates the match's characters and has them write their first lines:
    /// one batched call. This is the real wait the lobby shows. True when the
    /// model answered.
    @discardableResult
    func prepare(names: [String]) async -> Bool {
        personas = DotPersona.crew(for: names)
        opening.removeAll(); recent.removeAll(); nextAt.removeAll()
        guard !personas.isEmpty else { return false }
        if let lines = await batch(personas.map { ($0, Trigger.opening) }), !lines.isEmpty {
            opening = lines
            return true
        }
        // A hiccup or an offline model: the characters open with their own lines.
        guard !batchWorks else { return false }
        // No batch route (older server): one player at a time, as before.
        var answered = false
        for persona in personas {
            if Task.isCancelled { break }
            if let line = await speakLegacy(persona, trigger: .opening) { opening[persona.name] = line; answered = true }
        }
        return answered
    }

    // MARK: During the match

    func start(engine: GameEngine) {
        self.engine = engine
        // Everybody plays like their character from the first second; the
        // strategy loop below refines it from what is actually around them.
        engine.applyPlans(personas.map { ($0.name, $0.style, $0.aggression) })
        for persona in personas {
            nextAt[persona.name] = Date().addingTimeInterval(Double.random(in: 1.5...(persona.gap.lowerBound + 4)))
        }
        loop?.cancel(); strategyLoop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await self?.tick()
            }
        }
        strategyLoop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            while !Task.isCancelled {
                await self?.decideStrategies()
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 14...20) * 1_000_000_000))
            }
        }
    }

    func stop() {
        loop?.cancel(); loop = nil
        strategyLoop?.cancel(); strategyLoop = nil
    }

    /// One look at who is due to speak.
    private func tick() async {
        guard UIApplication.shared.applicationState == .active, Date().timeIntervalSince(lastCall) >= Self.minGap else { return }
        let now = Date()
        var due = personas.filter { (nextAt[$0.name] ?? .distantFuture) <= now }.shuffled()
        // Those whose first line was already written speak it right away.
        for persona in due {
            if let line = opening.removeValue(forKey: persona.name) {
                post(persona, line)
                nextAt[persona.name] = Date().addingTimeInterval(Double.random(in: persona.gap))
            }
        }
        due = due.filter { (nextAt[$0.name] ?? .distantFuture) <= Date() }
        guard !due.isEmpty else { return }
        await speak(Array(due.prefix(3)).map { ($0, replyTrigger(for: $0)) })
    }

    /// The person playing wrote in the match chat: the characters who feel
    /// like answering do, in one call, each at their own moment.
    func answer(_ text: String) {
        recent.append(("you", text, Date()))
        var responders = personas.filter { Double.random(in: 0...1) < $0.chattiness }
        if responders.isEmpty, let any = personas.randomElement() { responders = [any] }
        Task { [weak self] in
            await self?.speak(responders.prefix(3).map { ($0, Trigger.player(text)) })
        }
    }

    /// Sometimes they answer what somebody just said, sometimes they say
    /// something of their own.
    private func replyTrigger(for persona: DotPersona) -> Trigger {
        if let last = recent.last, last.name != persona.name, Date().timeIntervalSince(last.at) < 14, Double.random(in: 0...1) < 0.55 {
            return .reply(last.name, last.text)
        }
        return .free
    }

    /// Gets a line for each of these players and posts them one by one.
    private func speak(_ speakers: [(DotPersona, Trigger)]) async {
        guard !speakers.isEmpty else { return }
        lastCall = Date()
        var lines = await batch(speakers) ?? [:]
        if !batchWorks {
            // The server has no batch route: ask for each, one at a time.
            for (persona, trigger) in speakers where lines[persona.name] == nil {
                if let line = await speakLegacy(persona, trigger: trigger) { lines[persona.name] = line }
            }
        }
        for (persona, trigger) in speakers {
            var wasAnswer = false
            if case .player = trigger { wasAnswer = true }
            let line = lines[persona.name] ?? persona.fallback.randomElement()
            nextAt[persona.name] = Date().addingTimeInterval(Double.random(in: persona.gap))
            guard let line else { continue }
            // Each one types for a moment of their own before it appears.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.3...(wasAnswer ? 3.5 : 2.2)) * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.post(persona, line)
            }
        }
    }

    private func post(_ persona: DotPersona, _ text: String) {
        engine?.say(name: persona.name, text: text)
        recent.append((persona.name, text, Date()))
        if recent.count > 10 { recent.removeFirst(recent.count - 10) }
    }

    // MARK: Server calls

    private var crewBody: [[String: Any]] { personas.map { ["name": $0.name, "character": $0.character] } }

    /// One batched call for all of these players. nil when the route is not
    /// there or failed; [:] when it answered but offline.
    private func batch(_ speakers: [(DotPersona, Trigger)]) async -> [String: String]? {
        guard batchWorks, !personas.isEmpty else { return nil }
        let rows: [[String: Any]] = speakers.map { persona, trigger in
            switch trigger {
            case .reply(let who, let said): return ["name": persona.name, "reply": ["to": who, "text": said]]
            case .player(let said): return ["name": persona.name, "reply": ["to": "you", "text": said]]
            default: return ["name": persona.name]
            }
        }
        let chat = recent.suffix(8).map { ["name": $0.name, "text": $0.text] }
        do {
            let json = try await SpacechatService.spacesAgents(["mode": "chat", "players": crewBody, "speakers": rows, "chat": chat])
            var out: [String: String] = [:]
            for row in json["lines"] as? [[String: Any]] ?? [] {
                if let n = row["n"] as? String, let t = row["t"] as? String, !t.isEmpty { out[n] = t }
            }
            return out
        } catch {
            // Only a server that has no such route turns batching off; a slow
            // or unreachable moment just means this round uses fallback lines.
            if case SpacechatService.ServiceError.missing = error { batchWorks = false }
            return nil
        }
    }

    /// Every ~15 seconds: how each player plays next, from what is around it.
    private func decideStrategies() async {
        guard batchWorks, UIApplication.shared.applicationState == .active, let engine, !personas.isEmpty else { return }
        let state: [[String: Any]] = engine.strategySnapshot().map { row in
            var item: [String: Any] = ["name": row.name, "size": Double(row.size), "food": row.hasFood ? 1 : 0]
            if let b = row.biggerNear { item["biggerNear"] = Double(b) }
            if let s = row.smallerNear { item["smallerNear"] = Double(s) }
            return item
        }
        guard let json = try? await SpacechatService.spacesAgents(["mode": "strategy", "players": crewBody, "state": state]) else { return }
        let plans: [(name: String, style: AgentStyle, aggression: Double)] = (json["plans"] as? [[String: Any]] ?? []).compactMap { row in
            guard let n = row["n"] as? String, let style = (row["style"] as? String).flatMap(AgentStyle.init(rawValue:)),
                  let a = (row["aggression"] as? NSNumber)?.doubleValue else { return nil }
            return (n, style, a)
        }
        engine.applyPlans(plans)
    }

    // MARK: Older route (one player per request)

    private func speakLegacy(_ persona: DotPersona, trigger: Trigger) async -> String? {
        let others = personas.map(\.name).filter { $0 != persona.name }.joined(separator: ", ")
        let chat = recent.suffix(6).map { "\($0.name): \($0.text)" }.joined(separator: "\n")
        var task: String
        switch trigger {
        case .opening: task = "Say your first message as the match begins: a greeting or a remark about the map."
        case .free: task = "Say something of your own about the match: what you just ate, who you're avoiding, a thought, a joke."
        case .reply(let who, let said): task = "\(who) just said: \"\(said)\". Reply to them."
        case .player(let said): task = "A player named you just said in the chat: \"\(said)\". Answer them."
        }
        let prompt = """
        You are \(persona.name), a real person playing a live online match of Spaces, a game where you are a dot that grows by eating. The other players are \(others).
        Your character: \(persona.character).
        \(chat.isEmpty ? "" : "The chat so far:\n\(chat)\n")\(task)
        Write ONE chat message of at most 10 words, typed the way your character would. Never mention being an AI, a bot or a model. Output only the message.
        """
        await acquire()
        defer { release() }
        guard !Task.isCancelled, let reply = try? await SpacechatService.askSpacechatAI(prompt) else { return nil }
        return Self.clean(reply)
    }

    /// One short line, or nil when the model answered with something that is
    /// not a chat message (its own fallback text, a refusal, a paragraph).
    static func clean(_ reply: String) -> String? {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.components(separatedBy: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        text = text.replacingOccurrences(of: "\"", with: "")
        if let colon = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: colon) < 20 { text = String(text[text.index(after: colon)...]) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let bad = ["reliable answer", "rephras", "spacechat ai", "as an ai", "language model", "i can't", "i cannot", "i'm sorry", "i am sorry"]
        guard !text.isEmpty, text.count <= 90, !bad.contains(where: { lower.contains($0) }) else { return nil }
        return text
    }

    // MARK: Private conversations with a player you added

    /// One short in-character reply, for chatting with a friend from Messages
    /// or from a server you created with them. The friend remembers what they
    /// know about you (`memory`).
    static func reply(as name: String, to message: String, history: [String] = [], room: String? = nil, memory: [String] = []) async -> String {
        let persona = DotPersona.persona(for: name)
        let rows: [[String: String]] = history.suffix(6).map { line in
            if let r = line.range(of: ": ") { return ["name": String(line[..<r.lowerBound]), "text": String(line[r.upperBound...])] }
            return ["name": "them", "text": line]
        }
        var body: [String: Any] = ["mode": "friend", "name": name, "character": persona.character, "memory": memory, "message": message, "history": rows]
        if let room { body["room"] = room }
        if let json = try? await SpacechatService.spacesAgents(body), let line = json["reply"] as? String, !line.isEmpty { return line }

        // Older server: the general route.
        let place = room.map { "in the chatroom \"\($0)\"" } ?? "in a private chat"
        let prompt = """
        You are \(name), a real person who plays a dot-eating game called Spaces. You are chatting \(place) with someone you met in a match.
        Your character: \(persona.character).
        \(memory.isEmpty ? "" : "What you remember about them: " + memory.joined(separator: "; ") + "\n")\(history.isEmpty ? "" : "Conversation so far:\n" + history.suffix(6).joined(separator: "\n") + "\n")They said: \(message)
        Reply with ONE short message (max 14 words) in your character's voice. Never mention being an AI, a bot or a model. Output only the message.
        """
        if let reply = try? await SpacechatService.askSpacechatAI(prompt), let line = clean(reply) { return line }
        return persona.fallback.randomElement() ?? "haha nice"
    }

    /// Up to three facts about the person from what they wrote, so a friend
    /// can remember them next time.
    static func learn(from lines: [String]) async -> [String] {
        guard !lines.isEmpty, let json = try? await SpacechatService.spacesAgents(["mode": "memory", "lines": Array(lines.suffix(12))]) else { return [] }
        return (json["facts"] as? [String]) ?? []
    }
}

// MARK: - Friends

/// People you added after a match. They live on this device and show up in
/// Messages and when creating a server.
struct DotFriend: Codable, Identifiable, Equatable {
    var id: String { "dot:" + username }
    let username: String
    var peer: SpacechatService.Peer { SpacechatService.Peer(id: id, username: username, displayName: username) }
}

@MainActor
final class FriendsStore: ObservableObject {
    static let shared = FriendsStore()
    @Published private(set) var friends: [DotFriend] = []
    private let key = "spaces.dotFriends"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([DotFriend].self, from: data) { friends = saved }
    }

    func isFriend(_ username: String) -> Bool { friends.contains { $0.username == username } }

    func add(_ username: String) {
        guard !isFriend(username) else { return }
        friends.append(DotFriend(username: username))
        save()
        DailyChallenges.shared.bump(.friends)
    }

    // What each friend remembers about you (a few short facts, on this device).
    @Published private(set) var memory: [String: [String]] = {
        guard let data = UserDefaults.standard.data(forKey: "spaces.dotFriendMemory"),
              let saved = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return saved
    }()

    func facts(for username: String) -> [String] { memory[username] ?? [] }

    func remember(_ facts: [String], for username: String) {
        var all = memory[username] ?? []
        for fact in facts where !all.contains(where: { $0.caseInsensitiveCompare(fact) == .orderedSame }) { all.append(fact) }
        memory[username] = Array(all.suffix(8))
        if let data = try? JSONEncoder().encode(memory) { UserDefaults.standard.set(data, forKey: "spaces.dotFriendMemory") }
    }

    func remove(_ username: String) {
        friends.removeAll { $0.username == username }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(friends) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Results

struct GameResult: Identifiable {
    struct Row: Identifiable {
        let id = UUID()
        let name: String
        let mass: Int
        let tint: Color
        let isYou: Bool
        let eaten: Bool
    }
    let id = UUID()
    let title: String
    let score: Int
    let rows: [Row]
    /// What the recap and the challenges are worked out from.
    var seconds: Double = 0
    var eatenCount: Int = 0
    var eatenBy: String? = nil
    var rank: Int { (rows.firstIndex(where: { $0.isYou }) ?? 0) + 1 }
    /// Challenges this match completed (points already given).
    var completed: [Challenge] = []
}
