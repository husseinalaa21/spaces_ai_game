import SwiftUI

/// The app's main page: a map you drag and zoom. In the middle is Play, around it the big dots (the agents) with questions they can start
/// on, and below them your topics. A topic is a goal; its dots hang under it as a tree, each one handing its result to the next.
struct AgentMapView: View {
    @ObservedObject var authState: AuthState
    @ObservedObject var agents: AgentsStore
    @ObservedObject var folders: FolderStore
    @ObservedObject var topics: TopicStore
    let onPlay: () -> Void
    let onStore: () -> Void
    let onLogin: () -> Void

    @StateObject private var runner = TopicRunner()
    @State private var offset = CGSize(width: 0, height: 40)
    @State private var dragBase: CGSize?
    @State private var scale: CGFloat = 0.62
    @State private var pinchBase: CGFloat?
    @State private var touched = false
    @State private var chatting: SpacesAgent?
    @State private var showNew = false
    @State private var openNode: NodeRef?
    @State private var renaming: Topic?
    @State private var renameText = ""

    struct NodeRef: Identifiable { let topic: UUID; let node: UUID; var id: UUID { node } }

    private static let ringRadius: CGFloat = 270
    private static let dotSize: CGFloat = 108
    private static let nodeSize: CGFloat = 76
    private static let cardWidth: CGFloat = 220
    private static let minScale: CGFloat = 0.12
    private static let maxScale: CGFloat = 2.2

    // MARK: - Where things sit

    private struct Layout {
        var dots: [(agent: SpacesAgent, point: CGPoint)] = []
        var suggestions: [(id: String, agent: SpacesAgent, text: String, point: CGPoint)] = []
        var topicCards: [(topic: Topic, center: CGPoint, nodes: [TopicLayout.Placed])] = []
        var rect = CGRect.zero
    }

    private static func suggestions(for agent: SpacesAgent) -> [String] {
        switch agent.id {
        case "builtin-dots": return ["Plan my week in three steps", "Help me decide what to build first"]
        case "builtin-coder": return ["Write a small script that renames files", "Explain how to fix a slow loop"]
        case "builtin-writer": return ["Draft a friendly email to a customer", "Write a short README for my project"]
        case "builtin-reviewer": return ["Review my plan and list the risks", "Check my text for mistakes"]
        default: return ["What can you help me with?", "Give me a quick plan for today"]
        }
    }

    private var layout: Layout {
        var out = Layout()
        let all = agents.all
        let count = max(1, all.count)
        let radius = max(Self.ringRadius, CGFloat(count) * 62)
        var minX: CGFloat = -200, maxX: CGFloat = 200, minY: CGFloat = -200, maxY: CGFloat = 200
        func grow(_ p: CGPoint, _ rx: CGFloat, _ ry: CGFloat) {
            minX = min(minX, p.x - rx); maxX = max(maxX, p.x + rx); minY = min(minY, p.y - ry); maxY = max(maxY, p.y + ry)
        }
        for (i, agent) in all.enumerated() {
            let angle = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(count)
            let p = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            out.dots.append((agent, p)); grow(p, 70, 90)
            for (j, text) in Self.suggestions(for: agent).enumerated() {
                let a = angle + (j == 0 ? -0.34 : 0.34)
                let sp = CGPoint(x: cos(a) * (radius + 185), y: sin(a) * (radius + 185))
                out.suggestions.append(("\(agent.id)-\(j)", agent, text, sp)); grow(sp, 95, 40)
            }
        }
        // topics sit in a row under the ring, each as wide as its tree
        let top = radius + 380
        var widths: [CGFloat] = []
        var placed: [[TopicLayout.Placed]] = []
        for topic in topics.topics {
            let tree = TopicLayout.place(topic)
            widths.append(max(Self.cardWidth, tree.width) + 90)
            placed.append(tree.nodes)
        }
        let total = widths.reduce(0, +)
        var cursor = -total / 2
        for (i, topic) in topics.topics.enumerated() {
            let center = CGPoint(x: cursor + widths[i] / 2, y: top)
            out.topicCards.append((topic, center, placed[i]))
            grow(center, widths[i] / 2, 60)
            for n in placed[i] { grow(CGPoint(x: center.x + n.x, y: center.y + n.y), 80, 110) }
            cursor += widths[i]
        }
        if topics.topics.isEmpty { grow(CGPoint(x: 0, y: top), 160, 120) }
        out.rect = CGRect(x: minX - 160, y: minY - 160, width: maxX - minX + 320, height: maxY - minY + 320)
        return out
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let scene = layout
            ZStack {
                Color.white
                grid(size: geo.size)
                world(scene)
                    .frame(width: scene.rect.width, height: scene.rect.height)
                    .scaleEffect(scale)
                    .offset(x: offset.width + scale * scene.rect.midX, y: offset.height + scale * scene.rect.midY)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) { bottomBar(scene) }
            .overlay(alignment: .bottomTrailing) { zoomControls }
        }
        .ignoresSafeArea()
        .background(Color.white)
        .preferredColorScheme(.light)
        .fullScreenCover(item: $chatting) { agent in AgentChatView(agent: agent, store: agents, folders: folders) { chatting = nil } }
        .sheet(isPresented: $showNew) {
            NewTopicSheet(agents: agents) { title, agent, runNow in
                let topic = topics.create(title: title, firstAgent: agent)
                showNew = false
                focusOnTopic(topic.id)
                if runNow { runner.run(topic: topic.id, topics: topics, agents: agents) }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $openNode) { ref in
            NodeSheet(ref: ref, agents: agents, topics: topics, runner: runner) { openNode = nil }
                .presentationDetents([.medium, .large])
        }
        .alert("Rename topic", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Topic", text: $renameText)
            Button("Save") { if let t = renaming { topics.rename(t.id, to: renameText) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // MARK: - World

    private func world(_ scene: Layout) -> some View {
        let origin = scene.rect.origin
        func wp(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - origin.x, y: p.y - origin.y) }
        return ZStack(alignment: .topLeading) {
            // lines: Play to every big dot, and each topic's tree
            Canvas { ctx, _ in
                let center = wp(.zero)
                for item in scene.dots {
                    var line = Path(); line.move(to: center); line.addLine(to: wp(item.point))
                    ctx.stroke(line, with: .color(.black.opacity(0.07)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))
                }
                for card in scene.topicCards {
                    let cardBottom = CGPoint(x: card.center.x, y: card.center.y + 52)
                    for n in card.nodes {
                        let node = card.topic.node(n.id)
                        let to = CGPoint(x: card.center.x + n.x, y: card.center.y + n.y - Self.nodeSize / 2 - 4)
                        let from: CGPoint
                        if let parent = node?.parentID, let pp = card.nodes.first(where: { $0.id == parent }) {
                            from = CGPoint(x: card.center.x + pp.x, y: card.center.y + pp.y + Self.nodeSize / 2 + 34)
                        } else { from = cardBottom }
                        let active = runner.activeNode == n.id
                        var curve = Path()
                        curve.move(to: wp(from))
                        let mid = (from.y + to.y) / 2
                        curve.addCurve(to: wp(to), control1: wp(CGPoint(x: from.x, y: mid)), control2: wp(CGPoint(x: to.x, y: mid)))
                        let tint: Color = node?.status == .done ? .black.opacity(0.55) : (active ? Color(red: 0.16, green: 0.47, blue: 1) : .black.opacity(0.22))
                        ctx.stroke(curve, with: .color(tint), style: StrokeStyle(lineWidth: active ? 3.5 : 2.5, lineCap: .round))
                        var head = Path()
                        head.move(to: wp(to)); head.addLine(to: wp(CGPoint(x: to.x - 6, y: to.y - 10))); head.move(to: wp(to)); head.addLine(to: wp(CGPoint(x: to.x + 6, y: to.y - 10)))
                        ctx.stroke(head, with: .color(tint), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                }
            }
            .frame(width: scene.rect.width, height: scene.rect.height)
            .allowsHitTesting(false)

            playDot.position(wp(.zero))
            storeDot.position(wp(CGPoint(x: -150, y: 150)))
            newTopicDot.position(wp(CGPoint(x: 150, y: 150)))

            ForEach(scene.dots, id: \.agent.id) { item in
                agentDot(item.agent).position(wp(item.point))
            }
            ForEach(scene.suggestions, id: \.id) { item in
                suggestionBubble(item.agent, item.text).position(wp(item.point))
            }
            ForEach(scene.topicCards, id: \.topic.id) { card in
                topicCard(card.topic).position(wp(card.center))
                ForEach(card.nodes, id: \.id) { n in
                    if let node = card.topic.node(n.id) {
                        nodeView(card.topic, node).position(wp(CGPoint(x: card.center.x + n.x, y: card.center.y + n.y)))
                    }
                }
            }
            if topics.topics.isEmpty {
                Text("Your topics will grow here")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.black.opacity(0.3))
                    .position(wp(CGPoint(x: 0, y: (scene.dots.map { $0.point.y }.max() ?? 270) + 380)))
            }
        }
    }

    private func grid(size: CGSize) -> some View {
        Canvas { ctx, s in
            let step = 44 * max(0.5, min(1.6, scale))
            let cx = s.width / 2 + offset.width, cy = s.height / 2 + offset.height
            var x = cx.truncatingRemainder(dividingBy: step) - step
            while x < s.width + step {
                var y = cy.truncatingRemainder(dividingBy: step) - step
                while y < s.height + step {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(.black.opacity(0.07)))
                    y += step
                }
                x += step
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Pieces

    private var playDot: some View {
        Button { HapticsManager.shared.impact(.medium); onPlay() } label: {
            ZStack {
                Circle().fill(LinearGradient(colors: [DotRenderer.defaultColor.opacity(0.8), DotRenderer.defaultColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "play.fill").font(.system(size: 44, weight: .bold)).foregroundColor(.white).offset(x: 3)
            }
            .frame(width: 150, height: 150)
            .overlay(alignment: .bottom) { Text("Play").font(.system(size: 14, weight: .heavy)).foregroundColor(.white).padding(.bottom, 20) }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Play")
    }

    private var storeDot: some View {
        smallDot(symbol: "bag.fill", label: "Store", fill: [Color(red: 0.99, green: 0.84, blue: 0.4), Color(red: 0.92, green: 0.62, blue: 0.1)], action: onStore)
    }

    private var newTopicDot: some View {
        smallDot(symbol: "plus", label: "New topic", fill: [Color(white: 0.28), .black]) { showNew = true }
    }

    private func smallDot(symbol: String, label: String, fill: [Color], action: @escaping () -> Void) -> some View {
        Button { HapticsManager.shared.impact(.light); action() } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                    .frame(width: 84, height: 84)
                    .background(LinearGradient(colors: fill, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                Text(label).font(.system(size: 13, weight: .bold)).foregroundColor(.black.opacity(0.7))
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }

    private func agentDot(_ agent: SpacesAgent) -> some View {
        Button { HapticsManager.shared.impact(.light); chatting = agent } label: {
            VStack(spacing: 6) {
                AgentAvatar(agent: agent, size: Self.dotSize)
                Text(agent.name).font(.system(size: 15, weight: .heavy)).foregroundColor(.black)
                Text(agent.role).font(.system(size: 11, weight: .medium)).foregroundColor(.black.opacity(0.45))
                    .lineLimit(2).multilineTextAlignment(.center).frame(width: 150)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Chat with \(agent.name)")
    }

    private func suggestionBubble(_ agent: SpacesAgent, _ text: String) -> some View {
        Button {
            HapticsManager.shared.impact(.light)
            let topic = topics.create(title: text, firstAgent: agent)
            focusOnTopic(topic.id)
            runner.run(topic: topic.id, topics: topics, agents: agents)
        } label: {
            HStack(spacing: 8) {
                AgentAvatar(agent: agent, size: 24)
                Text(text).font(.system(size: 12.5, weight: .semibold)).foregroundColor(.black).multilineTextAlignment(.leading).lineLimit(3)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(width: 190, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(agent.color.opacity(0.7), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Start a topic: \(text), with \(agent.name)")
    }

    private func topicCard(_ topic: Topic) -> some View {
        let running = runner.isRunning(topic.id)
        return VStack(spacing: 8) {
            Text(topic.title).font(.system(size: 14, weight: .bold)).foregroundColor(.white).multilineTextAlignment(.center).lineLimit(3)
            HStack(spacing: 8) {
                Button {
                    HapticsManager.shared.impact(.light)
                    if running { runner.stop() } else { runner.run(topic: topic.id, topics: topics, agents: agents) }
                } label: {
                    Label(running ? "Stop" : "Run", systemImage: running ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.black)
                        .padding(.horizontal, 12).frame(height: 28).background(Color.white, in: Capsule())
                }.buttonStyle(.plain)
                Menu {
                    Button("Rename", systemImage: "pencil") { renameText = topic.title; renaming = topic }
                    Button("Delete topic", systemImage: "trash", role: .destructive) { topics.delete(topic.id) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        .frame(width: 28, height: 28).background(Color.white.opacity(0.2), in: Circle())
                }
            }
        }
        .padding(14)
        .frame(width: Self.cardWidth)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func nodeView(_ topic: Topic, _ node: TopicNode) -> some View {
        let agent = agents.all.first { $0.id == node.agentID }
        let active = runner.activeNode == node.id
        return VStack(spacing: 4) {
            Button { HapticsManager.shared.impact(.light); openNode = NodeRef(topic: topic.id, node: node.id) } label: {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let agent { AgentAvatar(agent: agent, size: Self.nodeSize) }
                        else { Circle().fill(Color.black.opacity(0.1)).frame(width: Self.nodeSize, height: Self.nodeSize) }
                    }
                    .overlay(Circle().stroke(active ? Color(red: 0.16, green: 0.47, blue: 1) : .clear, lineWidth: 4).padding(-4))
                    statusBadge(node.status).offset(x: 4, y: -4)
                }
            }
            .buttonStyle(PressableButtonStyle())
            Text(agent?.name ?? "Gone").font(.system(size: 12, weight: .bold)).foregroundColor(.black)
            if !node.result.isEmpty {
                Text(node.result).font(.system(size: 10.5)).foregroundColor(.black.opacity(0.5)).lineLimit(2)
                    .frame(width: 128).multilineTextAlignment(.center)
            }
            // hand this dot's work over to another dot
            Menu {
                ForEach(agents.all, id: \.id) { other in
                    Button { handOver(topic: topic.id, from: node, to: other) } label: { Text(other.name) }
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
                    .frame(width: 24, height: 24).background(Color.black, in: Circle())
            }
            .accessibilityLabel("Hand over to another dot")
        }
        .frame(width: 140)
    }

    @ViewBuilder
    private func statusBadge(_ status: TopicNode.Status) -> some View {
        switch status {
        case .idle: EmptyView()
        case .running:
            ProgressView().scaleEffect(0.7).frame(width: 24, height: 24).background(Color.white, in: Circle()).shadow(color: .black.opacity(0.15), radius: 3)
        case .done:
            Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundColor(.white).frame(width: 22, height: 22).background(Color.green, in: Circle())
        case .failed:
            Image(systemName: "exclamationmark").font(.system(size: 11, weight: .heavy)).foregroundColor(.white).frame(width: 22, height: 22).background(Color.red, in: Circle())
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: GameHubView.bannerTopInset + 50)
            if authState.spacechatUsername == nil {
                Button { onLogin() } label: {
                    Label("Log in with Spacechat so the dots can work", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundColor(.black)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.black.opacity(0.08)))
                }.buttonStyle(.plain)
            } else {
                Text("Drag to explore · pinch to zoom")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.black.opacity(0.4))
                    .opacity(touched ? 0 : 1).animation(.easeOut(duration: 0.4), value: touched)
            }
        }
        .allowsHitTesting(authState.spacechatUsername == nil)
    }

    private func bottomBar(_ scene: Layout) -> some View {
        Button { HapticsManager.shared.impact(.light); showNew = true } label: {
            Label("New topic", systemImage: "plus")
                .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 22).frame(height: 50)
                .background(Color.black, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.bottom, GameHubView.homeIndicatorInset + 18)
    }

    private var zoomControls: some View {
        VStack(spacing: 8) {
            ForEach(Array([("plus", 1.35), ("minus", 1 / 1.35)].enumerated()), id: \.offset) { _, step in
                Button { HapticsManager.shared.impact(.light); withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { zoom(to: scale * CGFloat(step.1)) } } label: {
                    Image(systemName: step.0).font(.system(size: 15, weight: .bold)).foregroundColor(.black).frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle()).overlay(Circle().stroke(Color.black.opacity(0.08)))
                }.buttonStyle(.plain).accessibilityLabel(step.0 == "plus" ? "Zoom in" : "Zoom out")
            }
            Button { HapticsManager.shared.impact(.light); recenter() } label: {
                Image(systemName: "scope").font(.system(size: 15, weight: .bold)).foregroundColor(.black).frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle()).overlay(Circle().stroke(Color.black.opacity(0.08)))
            }.buttonStyle(.plain).accessibilityLabel("Back to the middle")
        }
        .padding(.trailing, 14).padding(.bottom, GameHubView.homeIndicatorInset + 18)
    }

    // MARK: - Moving about

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if pinchBase != nil { return }
                if dragBase == nil { dragBase = offset; touched = true }
                offset = CGSize(width: (dragBase?.width ?? 0) + value.translation.width, height: (dragBase?.height ?? 0) + value.translation.height)
            }
            .onEnded { value in
                guard dragBase != nil else { return }
                let base = dragBase ?? offset
                dragBase = nil
                let glide = CGSize(width: (value.predictedEndTranslation.width - value.translation.width) * 0.6, height: (value.predictedEndTranslation.height - value.translation.height) * 0.6)
                withAnimation(.easeOut(duration: 0.55)) {
                    offset = CGSize(width: base.width + value.translation.width + glide.width, height: base.height + value.translation.height + glide.height)
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if pinchBase == nil { pinchBase = scale; touched = true }
                zoom(to: (pinchBase ?? scale) * value)
            }
            .onEnded { _ in pinchBase = nil }
    }

    private func zoom(to target: CGFloat) {
        let next = min(Self.maxScale, max(Self.minScale, target))
        let ratio = next / scale
        offset = CGSize(width: offset.width * ratio, height: offset.height * ratio)
        scale = next
    }

    private func recenter() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { offset = CGSize(width: 0, height: 40); scale = 0.62 }
    }

    private func focusOnTopic(_ id: UUID) {
        let scene = layout
        guard let card = scene.topicCards.first(where: { $0.topic.id == id }) else { return }
        let target = CGPoint(x: card.center.x, y: card.center.y + 160)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            scale = 0.85
            offset = CGSize(width: -target.x * 0.85, height: -target.y * 0.85)
        }
    }

    private func handOver(topic id: UUID, from node: TopicNode, to agent: SpacesAgent) {
        HapticsManager.shared.impact(.light)
        guard let child = topics.handOver(topic: id, from: node.id, to: agent) else { return }
        // If the dot above has already made something, the new dot gets going on it straight away.
        if node.status == .done { runner.run(topic: id, from: child.id, topics: topics, agents: agents) }
    }
}

// MARK: - New topic

private struct NewTopicSheet: View {
    @ObservedObject var agents: AgentsStore
    let onCreate: (String, SpacesAgent, Bool) -> Void
    @State private var title = ""
    @State private var chosen = "builtin-dots"
    @State private var runNow = true
    @FocusState private var focused: Bool

    private let ideas = ["Plan a birthday party", "Make a study plan for exams", "Write and check a short story", "Build a simple budget"]

    var body: some View {
        NavigationStack {
            Form {
                Section("What should the dots work on?") {
                    TextField("A goal, like \"Plan a birthday party\"", text: $title, axis: .vertical).lineLimit(2...4).focused($focused)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(ideas, id: \.self) { idea in
                            Button(idea) { title = idea }.font(.system(size: 12, weight: .semibold)).buttonStyle(.bordered).tint(.black)
                        } }
                    }
                }
                Section("First dot") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(agents.all, id: \.id) { agent in
                                Button { chosen = agent.id } label: {
                                    VStack(spacing: 4) {
                                        AgentAvatar(agent: agent, size: 52)
                                            .overlay(Circle().stroke(chosen == agent.id ? Color.black : .clear, lineWidth: 3).padding(-4))
                                        Text(agent.name).font(.system(size: 11, weight: .bold)).foregroundColor(.black)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }.padding(.vertical, 6)
                    }
                    Toggle("Start working now", isOn: $runNow)
                }
                Section { Text("Afterwards, tap + under a dot to hand its work over to another dot. The result flows down the tree.").font(.system(size: 12)).foregroundColor(.secondary) }
            }
            .navigationTitle("New topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let agent = agents.all.first { $0.id == chosen } ?? agents.all[0]
                        onCreate(title, agent, runNow)
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).fontWeight(.bold)
                }
            }
            .onAppear { focused = true }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - One dot in a topic

private struct NodeSheet: View {
    let ref: AgentMapView.NodeRef
    @ObservedObject var agents: AgentsStore
    @ObservedObject var topics: TopicStore
    @ObservedObject var runner: TopicRunner
    let onClose: () -> Void

    private var topic: Topic? { topics.topic(ref.topic) }
    private var node: TopicNode? { topic?.node(ref.node) }
    private var agent: SpacesAgent? { node.flatMap { n in agents.all.first { $0.id == n.agentID } } }

    var body: some View {
        NavigationStack {
            if let topic, let node {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            if let agent { AgentAvatar(agent: agent, size: 56) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent?.name ?? "Gone").font(.system(size: 20, weight: .bold))
                                Text(agent?.role ?? "").font(.system(size: 12)).foregroundColor(.secondary)
                            }
                            Spacer()
                            status(node.status)
                        }
                        Text(topic.title).font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                        if node.result.isEmpty {
                            Text(node.status == .running ? "Working on it…" : "Nothing yet. Run the topic, or run from this dot.")
                                .foregroundColor(.secondary)
                        } else {
                            Text(node.result).textSelection(.enabled).font(.system(size: 15)).lineSpacing(3)
                        }
                        VStack(spacing: 10) {
                            Button {
                                runner.run(topic: topic.id, from: node.id, topics: topics, agents: agents); onClose()
                            } label: { Label(node.parentID == nil ? "Run the whole topic" : "Run from this dot", systemImage: "play.fill").frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent).tint(.black).disabled(runner.runningTopic != nil)
                            Menu {
                                ForEach(agents.all, id: \.id) { other in
                                    Button(other.name) {
                                        if let child = topics.handOver(topic: topic.id, from: node.id, to: other), node.status == .done {
                                            runner.run(topic: topic.id, from: child.id, topics: topics, agents: agents)
                                        }
                                        onClose()
                                    }
                                }
                            } label: { Label("Hand over to…", systemImage: "arrow.down.right").frame(maxWidth: .infinity) }
                                .buttonStyle(.bordered).tint(.black)
                            if node.parentID != nil {
                                Button(role: .destructive) { topics.remove(topic: topic.id, node: node.id); onClose() } label: {
                                    Label("Remove this dot and what it handed on", systemImage: "trash").frame(maxWidth: .infinity)
                                }.buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(20)
                }
                .navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done", action: onClose) } }
            } else {
                Text("This dot is gone.").foregroundColor(.secondary)
            }
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private func status(_ s: TopicNode.Status) -> some View {
        switch s {
        case .idle: Text("Ready").font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
        case .running: ProgressView()
        case .done: Label("Done", systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .bold)).foregroundColor(.green)
        case .failed: Label("Failed", systemImage: "exclamationmark.circle.fill").font(.system(size: 12, weight: .bold)).foregroundColor(.red)
        }
    }
}
