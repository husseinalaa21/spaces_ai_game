import SwiftUI

/// Runs agents, the way SpaceAILM runs its team. One turn at a time: ask the
/// server what an agent does next (`POST /api/spaces/agents`, mode "agent"),
/// show what it says, carry out the actions it asked for, and pass the results
/// on to the next turn. The server only decides; everything that touches the
/// files or runs code happens here, inside the agent's access, with the
/// person's approval for anything that changes something, and every file edit
/// can be undone.
@MainActor
final class AgentRunner: ObservableObject {
    @Published private(set) var transcript: [AgentMessage] = []
    @Published private(set) var running = false
    @Published private(set) var speaking: String?
    @Published private(set) var summary: String?
    /// Copies of a dot started for small jobs: they show beside the team while they work.
    @Published private(set) var copies: [CopyJob] = []
    @Published var notice: String?

    private let folders: FolderStore
    private let approvals: ApprovalCenter
    private var job: Task<Void, Never>?
    static let maxSteps = 10

    init(folders: FolderStore = .shared, approvals: ApprovalCenter = .shared) {
        self.folders = folders
        self.approvals = approvals
    }

    struct CopyJob: Identifiable, Equatable {
        enum Status { case working, done, failed }
        let id = UUID()
        let parentID: String
        let parentName: String
        let number: Int
        /// The copy's own name (it is a dot of its own while it works).
        var name: String { Self.names[(number - 1) % Self.names.count] }
        static let names = ["Pip", "Nova", "Bolt", "Mochi", "Zed", "Luna", "Kiko", "Ember", "Juno", "Rio"]
        /// How it is named in the chat: "Pip · Dots copy".
        var label: String { "\(name) · \(parentName) copy" }
        let task: String
        var status: Status = .working
        var result = ""
    }

    /// The most copies one dot may start at once, and how many of them work at the same time.
    static let maxCopies = 10
    private static let copiesAtOnce = 2

    struct Action {
        var type: String
        var path = ""
        var content = ""
        var find = ""
        var replace = ""
        var query = ""
        var code = ""
        var text = ""
        var tasks: [String] = []
        var start: Int?
        var end: Int?
    }
    private struct Turn { var to: String?; var text: String?; var actions: [Action]; var done: Bool; var summary: String }

    /// What carrying out a turn's actions gave back.
    struct Outcome {
        var files: [(path: String, content: String)] = []
        var results: [(tool: String, label: String, content: String)] = []
        var asked = false
        var isEmpty: Bool { files.isEmpty && results.isEmpty }
    }

    func stop() { job?.cancel(); approvals.denyAll() }
    func reset() { transcript = []; summary = nil; notice = nil; copies = [] }

    // MARK: A team on a task

    /// The first agent leads: it hands work to the others by name and finishes with a summary.
    func runTeam(task: String, team: [SpacesAgent], folder: String?, canEdit: Bool, store: AgentsStore) {
        guard !running, let lead = team.first else { return }
        reset()
        running = true
        transcript.append(AgentMessage(kind: .user, from: "You", to: lead.name, text: task))
        job = Task { [weak self] in
            await self?.teamLoop(task: task, team: team, lead: lead, folder: folder, canEdit: canEdit, store: store)
            self?.running = false; self?.speaking = nil
        }
    }

    private func teamLoop(task: String, team: [SpacesAgent], lead: SpacesAgent, folder: String?, canEdit: Bool, store: AgentsStore) async {
        var speaker = lead
        var outcome = Outcome()
        var rotation = 0
        for step in 1...Self.maxSteps {
            if Task.isCancelled { transcript.append(system("Stopped.")); return }
            speaking = speaker.name
            let turn: Turn
            do {
                turn = try await ask(agent: speaker, team: team, task: task, folder: folder, canEdit: canEdit, outcome: outcome,
                                     step: step, lead: speaker.id == lead.id, notes: store.notes)
            } catch {
                transcript.append(system(Self.explain(error))); return
            }
            if let text = turn.text, !text.isEmpty { transcript.append(AgentMessage(kind: .agent, from: speaker.name, to: turn.to, text: text)) }
            else if turn.actions.isEmpty && !turn.done { transcript.append(AgentMessage(kind: .agent, from: speaker.name, to: nil, text: "…")) }
            outcome = await carryOut(turn.actions, agent: speaker, folder: folder, store: store) { [weak self] in self?.transcript.append($0) }

            if outcome.asked { summary = nil; return }
            if turn.done && speaker.id == lead.id && outcome.isEmpty {
                summary = turn.summary.isEmpty ? turn.text : turn.summary
                if let summary, !summary.isEmpty, summary != turn.text { transcript.append(AgentMessage(kind: .agent, from: speaker.name, to: "You", text: summary)) }
                return
            }
            // Who goes next: whoever was addressed by name, else the lead after a teammate, else the next teammate.
            if let to = turn.to, let named = team.first(where: { $0.name == to }), named.id != speaker.id {
                speaker = named
            } else if speaker.id != lead.id {
                speaker = lead
            } else {
                let others = team.filter { $0.id != lead.id }
                guard !others.isEmpty else { continue }
                speaker = others[rotation % others.count]; rotation += 1
            }
        }
        transcript.append(system("Stopped after \(Self.maxSteps) steps. You can ask them to continue."))
    }

    // MARK: One agent, one conversation

    /// Talks with a single agent. It can read, edit and run code too; after an action
    /// it gets another turn to act on what came back.
    func chat(agent: SpacesAgent, message: String, history: [AgentMessage], folder: String?, canEdit: Bool, store: AgentsStore, post: @escaping (AgentMessage) -> Void) {
        guard !running else { return }
        running = true; notice = nil
        job = Task { [weak self] in
            guard let self else { return }
            var outcome = Outcome()
            var seen = history
            for step in 1...4 {
                if Task.isCancelled { break }
                self.speaking = agent.name
                do {
                    let turn = try await self.ask(agent: agent, team: [agent], task: message, folder: folder, canEdit: canEdit, outcome: outcome,
                                                  step: step, lead: true, notes: store.notes, transcript: seen)
                    if let text = turn.text, !text.isEmpty {
                        let reply = AgentMessage(kind: .agent, from: agent.name, to: "You", text: text)
                        post(reply); seen.append(reply)
                    }
                    outcome = await self.carryOut(turn.actions, agent: agent, folder: folder, store: store) { post($0); seen.append($0) }
                    // Results (a file it read, program output) still need an answer: carry on until it has had its say.
                    if outcome.isEmpty || outcome.asked || (turn.done && outcome.isEmpty) { break }
                } catch {
                    post(self.system(Self.explain(error))); break
                }
            }
            self.running = false; self.speaking = nil
        }
    }

    // MARK: One dot's part of a topic

    /// One dot does its part of a topic and answers with its result (no chat, no folder). It may take a few turns to look things up
    /// or note something; the text it said is what is handed on.
    func handOff(agent: SpacesAgent, message: String, store: AgentsStore, copy: Bool = false, folder: String? = nil, canEdit: Bool = false) async -> (ok: Bool, text: String) {
        var outcome = Outcome()
        var said: [String] = []
        for step in 1...(folder == nil ? 3 : 5) {
            if Task.isCancelled { break }
            do {
                let turn = try await ask(agent: agent, team: [agent], task: message, folder: folder, canEdit: canEdit, outcome: outcome,
                                         step: step, lead: true, notes: store.notes, transcript: [], copy: copy)
                if let text = turn.text, !text.isEmpty { said.append(text) }
                if turn.done, !turn.summary.isEmpty, !said.contains(turn.summary) { said.append(turn.summary) }
                outcome = await carryOut(turn.actions, agent: agent, folder: folder, store: store) { _ in }
                if outcome.isEmpty || outcome.asked || turn.done { break }
            } catch {
                return (false, Self.explain(error))
            }
        }
        let text = said.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? (false, "\(agent.name) had nothing to say. Try running it again.") : (true, text)
    }

    // MARK: Copies

    /// Starts one copy of `agent` for each small job (at most ten), a few at a time, and gathers what they made.
    /// Each copy is the same dot (same role, bio and instructions) and talks to the same model; it cannot start copies of its own.
    private func runCopies(of agent: SpacesAgent, jobs: [String], store: AgentsStore, folder: String?, canEdit: Bool, note: @escaping (AgentMessage) -> Void) async -> String {
        let base = copies.count
        let started = jobs.enumerated().map { CopyJob(parentID: agent.id, parentName: agent.name, number: base + $0.offset + 1, task: $0.element) }
        copies += started
        var texts = [Int: String]()
        var next = 0
        await withTaskGroup(of: (Int, String).self) { group in
            func launch() {
                guard next < started.count else { return }
                let index = next; next += 1
                let job = started[index]
                group.addTask { [weak self] in
                    guard let self else { return (index, "") }
                    let message = "You are a copy of \(agent.name), started for ONE small job: \(job.task)\nDo only that job and answer with the result."
                    let outcome = await self.handOff(agent: agent, message: message, store: store, copy: true, folder: folder, canEdit: canEdit)
                    await MainActor.run {
                        if let i = self.copies.firstIndex(where: { $0.id == job.id }) {
                            self.copies[i].status = outcome.ok ? .done : .failed
                            self.copies[i].result = outcome.text
                        }
                        note(AgentMessage(kind: .agent, from: job.label, to: agent.name, text: outcome.text))
                    }
                    return (index, outcome.text)
                }
            }
            for _ in 0..<Self.copiesAtOnce { launch() }
            for await (index, text) in group {
                texts[index] = text
                if Task.isCancelled { group.cancelAll(); continue }
                launch()
            }
        }
        return started.enumerated().map { "Copy \($0.offset + 1) (\(jobs[$0.offset])): \(texts[$0.offset] ?? "no result")" }.joined(separator: "\n\n")
    }

    // MARK: Plumbing

    private func system(_ text: String) -> AgentMessage { AgentMessage(kind: .system, from: "Spaces", text: text) }

    private static func explain(_ error: Error) -> String {
        if case SpacechatService.ServiceError.missing = error { return "Agents need the newer Spacechat server. It isn't there yet." }
        if case SpacechatService.ServiceError.notSignedIn = error { return "Sign in with Spacechat to use agents." }
        return (error as? LocalizedError)?.errorDescription ?? "The agents couldn't be reached. Try again in a moment."
    }

    /// Carries out the actions an agent asked for. Reading and searching just happen (when the agent
    /// has read access); changing files and running code ask first. What came back is returned for
    /// the agent's next turn.
    private func carryOut(_ actions: [Action], agent: SpacesAgent, folder: String?, store: AgentsStore, note: @escaping (AgentMessage) -> Void) async -> Outcome {
        var outcome = Outcome()
        let name = agent.name
        let access = agent.access
        for action in actions {
            if Task.isCancelled { break }
            switch action.type {
            case "list":
                guard let folder, access.read else { continue }
                let tree = folders.tree(folder)
                outcome.results.append(("list", folder, tree.isEmpty ? "(empty)" : tree.map { ($0.isDirectory ? "[dir] " : "") + $0.path + ($0.isDirectory ? "" : " (\($0.size))") }.joined(separator: "\n")))

            case "read":
                guard let folder, access.read else { continue }
                guard let text = folders.read(folder, action.path) else {
                    outcome.results.append(("read", action.path, "Could not read it: it is not text or is too large."))
                    continue
                }
                if action.start != nil || action.end != nil {
                    let lines = text.components(separatedBy: "\n")
                    let from = max(1, action.start ?? 1), to = min(lines.count, action.end ?? lines.count)
                    outcome.files.append((action.path, from <= to ? lines[(from - 1)..<to].joined(separator: "\n") : ""))
                } else {
                    outcome.files.append((action.path, text))
                }

            case "search":
                guard let folder, access.read else { continue }
                outcome.results.append(("search", action.query, search(folder, action.query)))

            case "write", "create":
                guard let folder, access.write else { continue }
                // Never let an edit throw away most of a file: the agent may have left out the rest of it.
                if let old = folders.read(folder, action.path), old.count > 120, action.content.count * 5 < old.count * 4 {
                    let line = "\(name)'s edit to \(action.path) was not applied: it would have cut the file down too much. Agents keep the whole file and add to it."
                    note(system(line)); outcome.results.append(("write", action.path, line)); continue
                }
                let exists = folders.exists(folder, action.path)
                let ok = await approvals.authorize(.change, agent: name, summary: "\(exists ? "Edit" : "Create") \(action.path)", detail: Self.preview(of: action.content))
                guard ok else { note(system("Denied: \(name) \(exists ? "editing" : "creating") \(action.path).")); outcome.results.append(("write", action.path, "The owner denied this. Do not try it again; say what you could not do.")); continue }
                do {
                    let change = try folders.write(folder, action.path, content: action.content, by: name)
                    note(AgentMessage(kind: .change, from: name, text: "\(change.kind == .created ? "Created" : "Edited") \(action.path)", changeID: change.id))
                    outcome.results.append(("write", action.path, "Saved."))
                } catch {
                    note(system("\(name) couldn't change \(action.path): \(error.localizedDescription)"))
                    outcome.results.append(("write", action.path, "Failed: \(error.localizedDescription)"))
                }

            case "edit":
                guard let folder, access.write else { continue }
                guard let old = folders.read(folder, action.path) else { outcome.results.append(("edit", action.path, "Could not read the file to edit it.")); continue }
                let matches = old.components(separatedBy: action.find).count - 1
                guard matches == 1 else {
                    let why = matches == 0 ? "The text to find was not in the file. Read the file again and copy the exact text." : "The text to find appears \(matches) times. Use a longer, unique piece of text."
                    note(system("\(name)'s edit to \(action.path) didn't apply: \(why)")); outcome.results.append(("edit", action.path, why)); continue
                }
                let ok = await approvals.authorize(.change, agent: name, summary: "Edit \(action.path)", detail: "Replace:\n\(Self.preview(of: action.find))\n\nWith:\n\(Self.preview(of: action.replace))")
                guard ok else { note(system("Denied: \(name) editing \(action.path).")); outcome.results.append(("edit", action.path, "The owner denied this. Do not try it again; say what you could not do.")); continue }
                do {
                    let updated = old.replacingOccurrences(of: action.find, with: action.replace)
                    let change = try folders.write(folder, action.path, content: updated, by: name)
                    note(AgentMessage(kind: .change, from: name, text: "Edited \(action.path)", changeID: change.id))
                    outcome.results.append(("edit", action.path, "Saved."))
                } catch {
                    note(system("\(name) couldn't change \(action.path): \(error.localizedDescription)"))
                    outcome.results.append(("edit", action.path, "Failed: \(error.localizedDescription)"))
                }

            case "delete":
                guard let folder, access.write else { continue }
                let ok = await approvals.authorize(.delete, agent: name, summary: "Delete \(action.path)", detail: "The file is removed. You can undo it afterwards.")
                guard ok else { note(system("Denied: \(name) deleting \(action.path).")); outcome.results.append(("delete", action.path, "The owner denied this.")); continue }
                do {
                    let change = try folders.delete(folder, action.path, by: name)
                    note(AgentMessage(kind: .change, from: name, text: "Deleted \(action.path)", changeID: change.id))
                    outcome.results.append(("delete", action.path, "Deleted."))
                } catch { note(system("\(name) couldn't delete \(action.path): \(error.localizedDescription)")) }

            case "run":
                guard access.run else { continue }
                let ok = await approvals.authorize(.run, agent: name, summary: "Run a program", detail: Self.preview(of: action.code, limit: 900))
                guard ok else { note(system("Denied: \(name) running code.")); outcome.results.append(("run", "", "The owner denied this.")); continue }
                let result = await JSSandbox.run(action.code)
                note(AgentMessage(kind: .system, from: name, text: "\(name) ran a program: \(result.ok ? "ok" : "it failed")\n\(String(result.output.prefix(300)))"))
                outcome.results.append(("run", result.ok ? "ok" : "failed", result.output))

            case "note":
                guard access.notes else { continue }
                store.addNote(action.text, by: name)
                note(AgentMessage(kind: .system, from: name, text: "\(name) noted: \(action.text)"))

            case "spawn":
                let jobs = Array(action.tasks.prefix(Self.maxCopies))
                guard !jobs.isEmpty else { continue }
                note(system("\(name) is starting \(jobs.count) cop\(jobs.count == 1 ? "y" : "ies") for small jobs."))
                let results = await runCopies(of: agent, jobs: jobs, store: store, folder: folder, canEdit: folder != nil && access.write, note: note)
                outcome.results.append(("spawn", "\(jobs.count) copies", results))

            case "ask":
                note(AgentMessage(kind: .agent, from: name, to: "You", text: action.text))
                outcome.asked = true

            default: break
            }
        }
        return outcome
    }

    private static func preview(of text: String, limit: Int = 600) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "\n…"
    }

    /// Lines containing `query` (case-insensitive) in the folder's text files.
    private func search(_ folder: String, _ query: String) -> String {
        var hits: [String] = []
        for file in folders.files(folder) where file.size <= 200_000 {
            guard let text = folders.read(folder, file.path) else { continue }
            for (index, line) in text.components(separatedBy: "\n").enumerated() where line.range(of: query, options: .caseInsensitive) != nil {
                hits.append("\(file.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces).prefix(140))")
                if hits.count >= 30 { return hits.joined(separator: "\n") + "\n…(more matches not shown)" }
            }
        }
        return hits.isEmpty ? "No matches." : hits.joined(separator: "\n")
    }

    private func ask(agent: SpacesAgent, team: [SpacesAgent], task: String, folder: String?, canEdit: Bool, outcome: Outcome,
                     step: Int, lead: Bool, notes: [String], transcript override: [AgentMessage]? = nil, copy: Bool = false) async throws -> Turn {
        var body: [String: Any] = [
            "mode": "agent",
            "agent": ["name": agent.name, "role": agent.role, "instructions": agent.prompt, "access": agent.access.payload],
            "team": team.map { ["name": $0.name, "role": $0.role] },
            "task": task,
            "transcript": (override ?? transcript).suffix(12).map { m -> [String: Any] in
                var row: [String: Any] = ["from": m.from, "text": m.text]
                if let to = m.to { row["to"] = to }
                return row
            },
            "observations": outcome.files.map { ["path": $0.path, "content": $0.content] },
            "results": outcome.results.map { ["tool": $0.tool, "label": $0.label, "content": $0.content] },
            "notes": Array(notes.suffix(12)),
            "step": step, "maxSteps": override == nil ? Self.maxSteps : 4, "lead": lead, "copy": copy
        ]
        if let folder {
            body["workspace"] = ["name": folder, "canEdit": canEdit,
                                 "files": folders.files(folder).prefix(120).map { ["path": $0.path, "size": $0.size] }]
        }
        let json = try await SpacechatService.post("spaces/agents", body: body, timeout: 150)
        var turn = Turn(to: nil, text: nil, actions: [], done: json["done"] as? Bool == true, summary: (json["summary"] as? String) ?? "")
        if let message = json["message"] as? [String: Any] {
            turn.text = message["text"] as? String
            turn.to = message["to"] as? String
        }
        for row in json["actions"] as? [[String: Any]] ?? [] {
            guard let type = row["type"] as? String else { continue }
            var action = Action(type: type)
            action.path = (row["path"] as? String) ?? ""
            action.content = (row["content"] as? String) ?? ""
            action.find = (row["find"] as? String) ?? ""
            action.replace = (row["replace"] as? String) ?? ""
            action.query = (row["query"] as? String) ?? ""
            action.code = (row["code"] as? String) ?? ""
            action.text = (row["text"] as? String) ?? ""
            action.tasks = (row["tasks"] as? [String]) ?? []
            action.start = (row["start"] as? NSNumber)?.intValue
            action.end = (row["end"] as? NSNumber)?.intValue
            turn.actions.append(action)
        }
        if json["source"] as? String == "offline" && turn.text == nil && turn.actions.isEmpty {
            throw SpacechatService.ServiceError.unavailable("The AI model isn't available right now.")
        }
        return turn
    }
}
