import SwiftUI

/// A topic is a goal the person types ("Plan a birthday party"). Dots work on it as a tree: the first dot starts, and any dot can hand
/// its result over to the next, which carries on from there. The tree is saved, so the map looks the same next time.
struct TopicNode: Codable, Identifiable, Equatable {
    enum Status: String, Codable { case idle, running, done, failed }
    var id = UUID()
    var agentID: String
    var parentID: UUID?
    var status: Status = .idle
    /// What this dot made (or why it could not).
    var result: String = ""
}

struct Topic: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var nodes: [TopicNode]
    var createdAt = Date()
    /// Which workspace's map it lives on (nil: the first one, for topics made before workspaces).
    var workspaceID: UUID?

    var root: TopicNode? { nodes.first { $0.parentID == nil } }
    func children(of id: UUID) -> [TopicNode] { nodes.filter { $0.parentID == id } }
    func node(_ id: UUID) -> TopicNode? { nodes.first { $0.id == id } }
    /// The node and everything below it, parent first.
    func subtree(from id: UUID) -> [TopicNode] {
        guard let start = node(id) else { return [] }
        return [start] + children(of: id).flatMap { subtree(from: $0.id) }
    }
}

@MainActor
final class TopicStore: ObservableObject {
    static let shared = TopicStore()

    @Published private(set) var topics: [Topic] = []
    private let url: URL?

    init(directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("SpacesAI", isDirectory: true)) {
        url = directory?.appendingPathComponent("SpacesTopics.json")
        if let url, let data = try? Data(contentsOf: url), var saved = try? JSONDecoder().decode([Topic].self, from: data) {
            // A node that was mid-run when the app closed did not finish.
            for t in saved.indices { for n in saved[t].nodes.indices where saved[t].nodes[n].status == .running { saved[t].nodes[n].status = .idle } }
            topics = saved
        }
    }

    private func persist() {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(topics) { try? data.write(to: url, options: .atomic) }
    }

    @discardableResult
    func create(title: String, firstAgent: SpacesAgent, workspace: UUID) -> Topic {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = Topic(title: clean.isEmpty ? "New topic" : String(clean.prefix(120)), nodes: [TopicNode(agentID: firstAgent.id, parentID: nil)], workspaceID: workspace)
        topics.append(topic); persist()
        return topic
    }

    func topic(_ id: UUID) -> Topic? { topics.first { $0.id == id } }

    func topics(in workspace: UUID) -> [Topic] { topics.filter { ($0.workspaceID ?? WorkspaceStore.defaultID) == workspace } }

    func deleteAll(in workspace: UUID) { topics.removeAll { ($0.workspaceID ?? WorkspaceStore.defaultID) == workspace }; persist() }

    func delete(_ id: UUID) { topics.removeAll { $0.id == id }; persist() }

    func rename(_ id: UUID, to title: String) {
        guard let i = topics.firstIndex(where: { $0.id == id }) else { return }
        topics[i].title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)); persist()
    }

    /// Hands the work of `parent` over to another dot.
    @discardableResult
    func handOver(topic id: UUID, from parent: UUID, to agent: SpacesAgent) -> TopicNode? {
        guard let i = topics.firstIndex(where: { $0.id == id }), topics[i].node(parent) != nil else { return nil }
        let node = TopicNode(agentID: agent.id, parentID: parent)
        topics[i].nodes.append(node); persist()
        return node
    }

    /// Removes a node and everything handed down from it. The first dot stays (delete the topic to remove it all).
    func remove(topic id: UUID, node nodeID: UUID) {
        guard let i = topics.firstIndex(where: { $0.id == id }), topics[i].node(nodeID)?.parentID != nil else { return }
        let gone = Set(topics[i].subtree(from: nodeID).map(\.id))
        topics[i].nodes.removeAll { gone.contains($0.id) }; persist()
    }

    func update(topic id: UUID, node nodeID: UUID, status: TopicNode.Status? = nil, result: String? = nil) {
        guard let t = topics.firstIndex(where: { $0.id == id }), let n = topics[t].nodes.firstIndex(where: { $0.id == nodeID }) else { return }
        if let status { topics[t].nodes[n].status = status }
        if let result { topics[t].nodes[n].result = result }
        persist()
    }

    func clearResults(topic id: UUID, from nodeID: UUID) {
        guard let t = topics.firstIndex(where: { $0.id == id }) else { return }
        let ids = Set(topics[t].subtree(from: nodeID).map(\.id))
        for n in topics[t].nodes.indices where ids.contains(topics[t].nodes[n].id) { topics[t].nodes[n].status = .idle; topics[t].nodes[n].result = "" }
        persist()
    }
}

// MARK: - Running a topic

/// Runs a topic's tree one dot at a time: the first dot gets the goal, and each dot that was handed work gets the goal plus what the dot
/// before it made, so the work flows down the tree. A dot that fails stops its own branch; the other branches carry on.
@MainActor
final class TopicRunner: ObservableObject {
    @Published private(set) var runningTopic: UUID?
    @Published private(set) var activeNode: UUID?
    private let runner = AgentRunner()
    private var job: Task<Void, Never>?

    func isRunning(_ id: UUID) -> Bool { runningTopic == id }

    func stop() { job?.cancel() }

    /// Runs the whole tree (`from` nil) or one branch again, starting at that node.
    func run(topic id: UUID, from start: UUID? = nil, topics: TopicStore, agents: AgentsStore) {
        guard runningTopic == nil, let topic = topics.topic(id), let first = start ?? topic.root?.id else { return }
        runningTopic = id
        topics.clearResults(topic: id, from: first)
        // A branch started from the middle carries on from what the dot above it already made.
        let carried = topic.node(first)?.parentID.flatMap { topic.node($0)?.result }
        job = Task { [weak self] in
            guard let self else { return }
            await self.walk(topic: id, node: first, parentResult: carried, topics: topics, agents: agents)
            self.runningTopic = nil; self.activeNode = nil
        }
    }

    private func walk(topic id: UUID, node nodeID: UUID, parentResult: String?, topics: TopicStore, agents: AgentsStore) async {
        guard !Task.isCancelled, let topic = topics.topic(id), let node = topic.node(nodeID) else { return }
        guard let agent = agents.all.first(where: { $0.id == node.agentID }) else {
            topics.update(topic: id, node: nodeID, status: .failed, result: "This dot is gone, so it can't take part any more."); return
        }
        activeNode = nodeID
        topics.update(topic: id, node: nodeID, status: .running)
        var message = "Topic: \(topic.title)\n\n"
        if let parentResult, !parentResult.isEmpty, let parent = node.parentID.flatMap({ topic.node($0) }),
           let from = agents.all.first(where: { $0.id == parent.agentID }) {
            message += "\(from.name) handed this work over to you:\n\(String(parentResult.prefix(1800)))\n\nCarry on from there: do your part and answer with your result."
        } else {
            message += "Start the work: do your part and answer with your result."
        }
        let outcome = await runner.handOff(agent: agent, message: message, store: agents)
        if Task.isCancelled { topics.update(topic: id, node: nodeID, status: .idle); return }
        topics.update(topic: id, node: nodeID, status: outcome.ok ? .done : .failed, result: outcome.text)
        guard outcome.ok else { return }
        // Hand the result on to every dot below this one.
        for child in topic.children(of: nodeID) {
            await walk(topic: id, node: child.id, parentResult: outcome.text, topics: topics, agents: agents)
        }
    }
}

// MARK: - Where things sit on the map

/// A tidy tree: the first dot under the topic card, each dot's children below it, a parent centred over its children.
enum TopicLayout {
    static let nodeSpacing: CGFloat = 150
    static let levelGap: CGFloat = 190
    static let cardGap: CGFloat = 150

    struct Placed { let id: UUID; let x: CGFloat; let y: CGFloat }

    /// Positions relative to the topic card's centre (x) and top (y).
    static func place(_ topic: Topic) -> (nodes: [Placed], width: CGFloat) {
        guard let root = topic.root else { return ([], nodeSpacing) }
        var leaf: CGFloat = 0
        var out: [UUID: (x: CGFloat, depth: Int)] = [:]
        func visit(_ node: TopicNode, depth: Int) -> CGFloat {
            let kids = topic.children(of: node.id)
            let x: CGFloat
            if kids.isEmpty { x = leaf * nodeSpacing; leaf += 1 }
            else {
                let xs = kids.map { visit($0, depth: depth + 1) }
                x = ((xs.first ?? 0) + (xs.last ?? 0)) / 2
            }
            out[node.id] = (x, depth)
            return x
        }
        let rootX = visit(root, depth: 0)
        let width = max(1, leaf) * nodeSpacing
        let placed = out.map { Placed(id: $0.key, x: $0.value.x - rootX, y: cardGap + CGFloat($0.value.depth) * levelGap) }
        return (placed, width)
    }
}
