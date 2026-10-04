import SwiftUI

/// Collect a team, tell it what you want to make, watch it work, keep the result.
/// Stage one picks the dots, stage two is the room where they talk to you and to each other.
struct TeamFlowView: View {
    @ObservedObject var agents: AgentsStore
    @ObservedObject var folders: FolderStore
    @ObservedObject var projects: ProjectStore
    @ObservedObject var authState: AuthState
    let workspace: Workspace
    /// A saved project opens straight in its room.
    var project: Project? = nil
    /// Opened from a folder: the space belongs to that folder (its own team, files and conversation history).
    var folderName: String? = nil
    let onLogin: () -> Void
    let onClose: () -> Void

    @State private var team: [SpacesAgent]?

    /// The project to restore: the one given, or the folder's own space from last time.
    private var existing: Project? {
        if let project { return project }
        guard let folderName else { return nil }
        return projects.projects.first { $0.linkedFolder == folderName }
    }

    private var available: [SpacesAgent] {
        guard let ids = workspace.team else { return agents.all }
        let picked = agents.all.filter { ids.contains($0.id) }
        return picked.isEmpty ? agents.all : picked
    }

    var body: some View {
        ZStack {
            if let team {
                ProjectRoomView(team: team, agents: agents, folders: folders, projects: projects, authState: authState,
                                workspace: workspace, project: existing, forFolder: folderName ?? project?.linkedFolder, onLogin: onLogin, onClose: onClose)
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            } else {
                TeamLobbyView(agents: available, palette: WorldBackground.palette(for: workspace.theme), onStart: { picked in
                    withAnimation(.easeInOut(duration: 0.45)) { team = picked }
                }, onClose: onClose)
                .transition(.opacity)
            }
        }
        .onAppear {
            if let project = existing, team == nil {
                let restored = project.teamIDs.compactMap { id in agents.all.first { $0.id == id } }
                team = restored.isEmpty ? Array(available.prefix(1)) : restored
            }
        }
    }
}

// MARK: - Collect your team

/// The universe of dots: an endless map you drag and zoom, in the look of the workspace. Dots drift about on it, each one free to join. Tap a dot to
/// collect it: a line joins it to your team in the middle, in the order you pick them (1 leads).
struct TeamLobbyView: View {
    let agents: [SpacesAgent]
    let palette: WorldBackground.Palette
    let onStart: ([SpacesAgent]) -> Void
    let onClose: () -> Void

    @State private var shown = 0
    @State private var picked: [String] = []
    @State private var offset = CGSize.zero
    @State private var dragBase: CGSize?
    @State private var scale: CGFloat = 0.62
    @State private var pinchBase: CGFloat?
    @State private var touched = false
    @State private var showMembers = false
    @ObservedObject private var shop = StoreManager.shared

    private var dark: Bool { palette.isDark }
    private var ink: Color { dark ? .white : .black }
    private var chosen: [SpacesAgent] { picked.compactMap { id in agents.first { $0.id == id } } }
    private var searching: Bool { shown < agents.count }
    private let dotSize: CGFloat = 84

    /// Where each dot sits in the universe: a loose spiral around the team.
    private func home(_ index: Int) -> CGPoint {
        let angle = Double(index) * 2.39996 - Double.pi / 2
        let radius = 195 + 62 * Double(index).squareRoot()
        return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius * 0.95)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                palette.background.ignoresSafeArea()
                stars(geo.size)
                world
                    .scaleEffect(scale)
                    .offset(x: offset.width, y: offset.height)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(drag)
            .simultaneousGesture(pinch)
            .overlay(alignment: .top) { header }
            .overlay(alignment: .bottom) { trayBar }
            .overlay(alignment: .bottomTrailing) { zoomButtons }
        }
        .ignoresSafeArea()
        .preferredColorScheme(dark ? .dark : .light)
        .sheet(isPresented: $showMembers) { MembersOnlySheet() }
        .task {
            for i in 0..<agents.count {
                try? await Task.sleep(nanoseconds: 300_000_000)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { shown = i + 1 }
                HapticsManager.shared.impact(.light)
            }
        }
    }

    // MARK: world

    private var world: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // lines from the team hub to each collected dot
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    for (order, agent) in chosen.enumerated() {
                        guard let i = agents.firstIndex(where: { $0.id == agent.id }) else { continue }
                        let p = drift(home(i), i, t)
                        var line = Path(); line.move(to: c); line.addLine(to: CGPoint(x: c.x + p.x, y: c.y + p.y))
                        ctx.stroke(line, with: .color(Color(red: 0.16, green: 0.47, blue: 1).opacity(order == 0 ? 0.9 : 0.55)), style: StrokeStyle(lineWidth: order == 0 ? 3.5 : 2.5, lineCap: .round))
                    }
                    for i in 0..<min(shown, agents.count) where !picked.contains(agents[i].id) {
                        let p = drift(home(i), i, t)
                        var line = Path(); line.move(to: c); line.addLine(to: CGPoint(x: c.x + p.x, y: c.y + p.y))
                        ctx.stroke(line, with: .color(ink.opacity(0.06)), style: StrokeStyle(lineWidth: 1.5, dash: [2, 7]))
                    }
                }
                hub
                ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                    if index < shown {
                        let p = drift(home(index), index, t)
                        dotView(agent).offset(x: p.x, y: p.y).transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
            }
            .frame(width: 2000, height: 2000)
        }
    }

    private func drift(_ p: CGPoint, _ index: Int, _ t: Double) -> CGPoint {
        let phase = Double(index) * 1.7
        return CGPoint(x: p.x + sin(t * 0.5 + phase) * 7, y: p.y + cos(t * 0.42 + phase * 1.3) * 9)
    }

    private var hub: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color(red: 0.16, green: 0.47, blue: 1).opacity(0.14)).frame(width: 118, height: 118)
                Circle().stroke(Color(red: 0.16, green: 0.47, blue: 1).opacity(0.5), lineWidth: 2).frame(width: 118, height: 118)
                if chosen.isEmpty {
                    Image(systemName: "person.3.fill").font(.system(size: 30, weight: .bold)).foregroundColor(ink.opacity(0.4))
                } else {
                    HStack(spacing: -14) {
                        ForEach(chosen.prefix(4)) { a in AgentAvatar(agent: a, size: 38, animated: false).overlay(Circle().stroke(palette.background, lineWidth: 2)) }
                    }
                }
            }
            Text(chosen.isEmpty ? "Your team" : "\(chosen.count) in your team").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(ink.opacity(0.7))
        }
    }

    private func dotView(_ agent: SpacesAgent) -> some View {
        let order = picked.firstIndex(of: agent.id)
        return Button { toggle(agent) } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    AgentAvatar(agent: agent, size: dotSize)
                        .overlay(alignment: .topTrailing) { if agent.membersOnly && !shop.isMember { MemberLockBadge().offset(x: 4, y: -2) } }
                        .overlay(Circle().stroke(order != nil ? Color(red: 0.16, green: 0.47, blue: 1) : .clear, lineWidth: 4).padding(-6))
                        .scaleEffect(order != nil ? 1.1 : 1)
                    if let order {
                        Text("\(order + 1)").font(.system(size: 12, weight: .heavy)).foregroundColor(.white)
                            .frame(width: 24, height: 24).background(Color(red: 0.16, green: 0.47, blue: 1), in: Circle()).offset(x: 6, y: -6)
                    }
                }
                Text(agent.name).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundColor(ink)
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text(order == 0 ? "Lead" : (order != nil ? "In team" : "Available")).font(.system(size: 11, weight: .semibold)).foregroundColor(ink.opacity(0.55))
                }
                Text(agent.bio.isEmpty ? agent.role : agent.bio).font(.system(size: 10.5)).foregroundColor(ink.opacity(0.4)).lineLimit(2).multilineTextAlignment(.center).frame(width: 130)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(agent.name), \(order == nil ? "available" : "in your team")")
    }

    private func toggle(_ agent: SpacesAgent) {
        HapticsManager.shared.impact(.light)
        if agent.membersOnly && !shop.isMember { showMembers = true; return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
            if let i = picked.firstIndex(of: agent.id) { picked.remove(at: i) } else { picked.append(agent.id) }
        }
    }

    /// The workspace's own dots and stars, drifting a little slower than the map.
    private func stars(_ size: CGSize) -> some View {
        Canvas { ctx, s in
            let step: CGFloat = 44 * max(0.6, min(1.5, scale))
            let cx = s.width / 2 + offset.width, cy = s.height / 2 + offset.height
            var x = cx.truncatingRemainder(dividingBy: step) - step
            while x < s.width + step {
                var y = cy.truncatingRemainder(dividingBy: step) - step
                while y < s.height + step {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(palette.line.opacity(dark ? 0.55 : 0.8)))
                    y += step
                }
                x += step
            }
            if palette.isCosmic {
                for i in 0..<70 {
                    let seed = Double(i) * 12.9898
                    let fx = abs(sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1), fy = abs(sin(seed * 1.7) * 24634.6345).truncatingRemainder(dividingBy: 1)
                    let px = ((fx * s.width + offset.width * 0.25).truncatingRemainder(dividingBy: s.width) + s.width).truncatingRemainder(dividingBy: s.width)
                    let py = ((fy * s.height + offset.height * 0.25).truncatingRemainder(dividingBy: s.height) + s.height).truncatingRemainder(dividingBy: s.height)
                    let r = 0.8 + abs(sin(seed * 3.1)) * 1.4
                    ctx.fill(Path(ellipseIn: CGRect(x: px, y: py, width: r, height: r)), with: .color(.white.opacity(0.35 + abs(sin(seed * 5.1)) * 0.5)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: chrome

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundColor(ink)
                        .frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Close")
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, GameHubView.bannerTopInset)
            Text("Collect your team").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundColor(ink)
            HStack(spacing: 8) {
                if searching { ProgressView().controlSize(.small).tint(ink) } else { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
                Text(searching ? "Looking for dots in the universe…" : (touched ? "Tap a dot to add it to your team" : "Drag to explore · pinch to zoom · tap a dot to collect it"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(ink.opacity(0.6))
            }
        }
    }

    private var zoomButtons: some View {
        VStack(spacing: 8) {
            ForEach(Array([("plus", 1.3), ("minus", 1 / 1.3)].enumerated()), id: \.offset) { _, step in
                Button { HapticsManager.shared.impact(.light); withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { scale = min(2.2, max(0.25, scale * CGFloat(step.1))) } } label: {
                    Image(systemName: step.0).font(.system(size: 15, weight: .bold)).foregroundColor(ink).frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel(step.0 == "plus" ? "Zoom in" : "Zoom out")
            }
            Button { HapticsManager.shared.impact(.light); withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { offset = .zero; scale = 0.62 } } label: {
                Image(systemName: "scope").font(.system(size: 15, weight: .bold)).foregroundColor(ink).frame(width: 40, height: 40).background(.ultraThinMaterial, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Back to the middle")
        }
        .padding(.trailing, 14).padding(.bottom, 170 + GameHubView.homeIndicatorInset)
    }

    private var trayBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: -6) {
                if chosen.isEmpty {
                    Text("Collect dots on the map. The first one leads the work.").font(.system(size: 13, weight: .medium)).foregroundColor(ink.opacity(0.5))
                }
                ForEach(chosen) { agent in
                    AgentAvatar(agent: agent, size: 40, animated: false).overlay(Circle().stroke(palette.background, lineWidth: 2)).transition(.scale.combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 44)
            Button { onStart(chosen) } label: {
                Text(chosen.isEmpty ? "Collect at least one dot" : "Start with \(chosen.count) dot\(chosen.count == 1 ? "" : "s")")
                    .font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundColor(chosen.isEmpty ? ink.opacity(0.4) : (dark ? .black : .white))
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(chosen.isEmpty ? ink.opacity(0.1) : ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle()).disabled(chosen.isEmpty)
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, GameHubView.homeIndicatorInset + 14)
        .background(.ultraThinMaterial)
    }

    // MARK: moving about

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                if pinchBase != nil { return }
                if dragBase == nil { dragBase = offset; touched = true }
                offset = CGSize(width: (dragBase?.width ?? 0) + v.translation.width, height: (dragBase?.height ?? 0) + v.translation.height)
            }
            .onEnded { v in
                guard dragBase != nil else { return }
                let base = dragBase ?? offset; dragBase = nil
                withAnimation(.easeOut(duration: 0.5)) {
                    offset = CGSize(width: base.width + v.predictedEndTranslation.width * 0.7, height: base.height + v.predictedEndTranslation.height * 0.7)
                }
            }
    }

    private var pinch: some Gesture {
        MagnificationGesture()
            .onChanged { v in if pinchBase == nil { pinchBase = scale; touched = true }; scale = min(2.2, max(0.25, (pinchBase ?? scale) * v)) }
            .onEnded { _ in pinchBase = nil }
    }
}

// MARK: - The room

/// The team, you, and the work. The dots ask for the product's name and idea, then work on it, talking to each other and to you.
/// When they are done you can keep it: it goes on the home map.
struct ProjectRoomView: View {
    /// The dots the room opened with (the first one leads). Dots can be added and deleted on the map after that: see `crew`.
    let team: [SpacesAgent]
    @ObservedObject var agents: AgentsStore
    @ObservedObject var folders: FolderStore
    @ObservedObject var projects: ProjectStore
    @ObservedObject var authState: AuthState
    let workspace: Workspace
    let project: Project?
    /// A folder's own space: the team works on this folder's real files.
    var forFolder: String? = nil
    let onLogin: () -> Void
    let onClose: () -> Void

    private enum Step { case askName, askIdea, working, done }

    @StateObject private var runner = AgentRunner()
    @State private var messages: [AgentMessage] = []
    @State private var archive: [AgentMessage] = []
    @State private var step: Step = .askName
    @State private var input = ""
    @State private var name = ""
    @State private var idea = ""
    @State private var typing: String?
    @State private var summary = ""
    @State private var saved = false
    @State private var projectID = UUID()
    @State private var folder: String?
    @State private var filesNote = ""
    @State private var messagesOpen = false
    @State private var filesOpen = false
    @State private var graph = UniverseGraph()
    @State private var added: [SpacesAgent] = []
    @State private var removed: Set<String> = []
    @State private var showAdd = false
    @State private var addParent: String?
    @FocusState private var focused: Bool

    /// Everyone on the map now: the dots it opened with and the ones added, without the ones deleted.
    private var crew: [SpacesAgent] { (team + added.filter { a in !team.contains(where: { $0.id == a.id }) }).filter { !removed.contains($0.id) } }

    private var lead: SpacesAgent { team.first ?? agents.all[0] }
    /// A copy ("Dots copy 2") looks exactly like the dot it was made from.
    private func agent(named name: String) -> SpacesAgent? {
        // "Pip · Dots copy" is a copy of Dots
        let base = name.components(separatedBy: " · ").last.map { $0.hasSuffix(" copy") ? String($0.dropLast(5)) : name } ?? name
        return agents.all.first { $0.name == base }
    }
    /// The runner opens its transcript with the whole task as a message from you; that is the brief you already gave, so it is not shown again.
    private var work: [AgentMessage] { Array(runner.transcript.drop(while: { $0.kind == .user })) }
    private var everything: [AgentMessage] { messages + work }
    private var palette: WorldBackground.Palette { WorldBackground.palette(for: workspace.theme) }
    private var ink: Color { palette.isDark ? .white : .black }

    var body: some View {
        ZStack {
            // The project's universe fills the screen: the team and its copies on a map, in the workspace's look.
            ProjectUniverse(team: crew, copies: runner.copies, speaking: runner.speaking ?? typing, running: runner.running, palette: palette,
                            latest: latestWords, finished: step == .done, summary: summary, leadFooter: step == .done ? AnyView(finishActions) : nil,
                            graph: $graph, onAdd: { parent in addParent = parent; showAdd = true }, onDelete: removeDot, onDeleteCopy: { runner.removeCopy($0) },
                            agentFor: agent(named:))
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 8) { filesCard; addCard }
                    Spacer(minLength: 0)
                    messagesCard
                }
                .padding(.horizontal, 12).padding(.top, 4)
                Spacer(minLength: 0)
                composer
            }
            if filesOpen, let folder { ProjectFilesPanel(folder: folder, palette: palette, who: lead.name) { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { filesOpen = false } }.transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity)).zIndex(5) }
            if messagesOpen { messagesPanel.transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity)).zIndex(5) }
        }
        .background(palette.background.ignoresSafeArea())
        .overlay(alignment: .bottom) { ApprovalCard().padding(.bottom, 80) }
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .task { await begin() }
        .sheet(isPresented: $showAdd) {
            AddDotSheet(agents: agents.all.filter { dot in !crew.contains(where: { $0.id == dot.id }) }, parent: addParent.flatMap { id in crew.first { $0.id == id }?.name } ?? lead.name, running: runner.running) { dot in addDot(dot) }
        }
        .onChange(of: graph) { _ in if forFolder != nil, step != .askIdea, !messages.isEmpty { autoSave() } }
        .onDisappear { if forFolder != nil, !messages.isEmpty { autoSave() } }
        // a folder's space keeps itself as it goes, so leaving at any moment still reopens exactly here
        .onChange(of: messages.count) { _ in if forFolder != nil, step != .askIdea { autoSave() } }
        .onChange(of: runner.transcript.count) { _ in if forFolder != nil { autoSave() } }
        .onChange(of: runner.copies) { jobs in
            // every finished copy leaves its own file in the folder
            guard forFolder == nil, let folder else { return }
            for job in jobs where job.status == .done {
                _ = try? FolderStore.shared.write(folder, "copies/\(job.name.lowercased())-\(job.parentName.lowercased())-copy.md", content: "# \(job.name), a copy of \(job.parentName)\n\nJob: \(job.task)\n\n\(job.result)\n", by: job.parentName)
            }
        }
        .onChange(of: runner.running) { running in
            guard !running, step == .working else { return }
            summary = runner.summary ?? ""
            // A lead that never closed the task still left its last words: the best summary there is.
            if summary.isEmpty, let last = work.last(where: { $0.kind == .agent && $0.from == lead.name && $0.text.count > 40 }) { summary = last.text }
            if summary.isEmpty, let last = work.last(where: { $0.kind == .agent && $0.text.count > 40 }) { summary = last.text }
            if forFolder != nil { autoSave() } else if !summary.isEmpty { writeFiles() }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { step = .done }
            if !summary.isEmpty { HapticsManager.shared.success() }
        }
    }

    /// What each dot said last (a copy by its own name), shown beside it on the map.
    private var latestWords: [String: String] {
        var out: [String: String] = [:]
        for m in everything where m.kind == .agent { out[m.from] = m.text }
        return out
    }

    private var cardFill: Color { palette.isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.92) }

    /// Under the title, on the left: a round Files button. It opens the project's folder to browse, move, rename, edit and delete.
    private var filesCard: some View {
        let count = folder.map { FolderStore.shared.files($0).count } ?? 0
        return Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { filesOpen = true } } label: {
            Image(systemName: "folder.fill").font(.system(size: 19, weight: .bold)).foregroundColor(ink)
                .frame(width: 48, height: 48)
                .background(cardFill, in: Circle())
                .overlay(Circle().stroke(ink.opacity(0.12)))
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)").font(.system(size: 10, weight: .heavy)).foregroundColor(.white)
                            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18).background(Color(red: 0.16, green: 0.47, blue: 1), in: Capsule()).offset(x: 4, y: -4)
                    }
                }
        }.buttonStyle(.plain).accessibilityLabel("Files, \(count)")
    }

    /// Top right: the conversation, newest three lines. Tap to open all of it.
    private var messagesCard: some View {
        let recent = Array(everything.filter { $0.kind == .agent || $0.kind == .user }.suffix(3))
        return Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { messagesOpen = true } } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 12, weight: .bold))
                    Text("Messages").font(.system(size: 13, weight: .heavy, design: .rounded))
                    Spacer(minLength: 0)
                    if runner.running || typing != nil { ProgressView().controlSize(.mini) }
                }
                ForEach(recent) { m in
                    (Text(m.from + ": ").fontWeight(.bold) + Text(m.text)).font(.system(size: 10.5)).lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .foregroundColor(ink)
            .padding(10).frame(width: 190, alignment: .leading)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ink.opacity(0.12)))
        }.buttonStyle(.plain).accessibilityLabel("Messages")
    }

    /// The whole conversation, opened from the top right.
    private var messagesPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Messages").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(ink)
                Spacer()
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { messagesOpen = false } } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(ink).frame(width: 30, height: 30).background(ink.opacity(0.08), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Close messages")
            }.padding(.horizontal, 14).padding(.vertical, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(everything) { message in
                            AgentBubble(message: message, agent: agent(named: message.from), folders: folders).id(message.id)
                        }
                        if let typing { typingRow(typing) }
                        if runner.running, let who = runner.speaking { workingRow(who) }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(.horizontal, 12).padding(.bottom, 8)
                }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: everything.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
        .frame(width: 350, height: 520)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ink.opacity(0.15)))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, GameHubView.bannerTopInset + 52).padding(.trailing, 12)
    }

    // MARK: the dots on the map

    /// A round + under Files: choose a dot to bring into the universe.
    private var addCard: some View {
        Button { addParent = nil; showAdd = true } label: {
            Image(systemName: "plus").font(.system(size: 19, weight: .bold)).foregroundColor(ink)
                .frame(width: 48, height: 48)
                .background(cardFill, in: Circle())
                .overlay(Circle().stroke(ink.opacity(0.12)))
        }.buttonStyle(.plain).accessibilityLabel("Add a dot")
    }

    /// Brings a dot in under the one that was tapped (or under the lead).
    private func addDot(_ dot: SpacesAgent) {
        guard !crew.contains(where: { $0.id == dot.id }) else { return }
        removed.remove(dot.id)
        if !team.contains(where: { $0.id == dot.id }) { added.append(dot) }
        let parent = addParent.flatMap { id in crew.contains(where: { $0.id == id }) ? id : nil } ?? lead.id
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { graph.links[dot.id] = parent; graph.positions[dot.id] = nil }
        HapticsManager.shared.success()
        if forFolder != nil, !messages.isEmpty { autoSave() }
    }

    /// Takes a dot off the map; the dots that reported to it now report to the dot above it.
    private func removeDot(_ id: String) {
        guard id != lead.id, !runner.running else { return }
        let above = graph.parent(of: id, in: crew) ?? ""
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            for child in graph.children(of: id, in: crew) { graph.links[child.id] = above; graph.positions[child.id] = nil }
            graph.links[id] = nil; graph.positions[id] = nil
            added.removeAll { $0.id == id }
            removed.insert(id)
        }
        if forFolder != nil, !messages.isEmpty { autoSave() }
    }

    // MARK: pieces

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { runner.stop(); onClose() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundColor(ink)
                    .frame(width: 36, height: 36).background(ink.opacity(0.08), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Close")
            VStack(alignment: .leading, spacing: 1) {
                Text(name.isEmpty ? "New project" : name).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(ink).lineLimit(1)
                Text(runner.running ? "Working…" : (step == .done ? "Finished" : "Your team")).font(.system(size: 11, weight: .semibold)).foregroundColor(ink.opacity(0.5))
            }
            Spacer(minLength: 8)
            HStack(spacing: -8) {
                ForEach(crew) { member in
                    AgentAvatar(agent: member, size: 30, animated: false)
                        .overlay(Circle().stroke(palette.background, lineWidth: 2))
                        .scaleEffect(runner.speaking == member.name || typing == member.name ? 1.2 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: runner.speaking)
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 4)
    }

    /// The copies the dots started for small jobs, working beside the team.
    private var copiesStrip: some View {
        let working = runner.copies.filter { $0.status == .working }.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Text(working > 0 ? "\(working) cop\(working == 1 ? "y" : "ies") working" : "\(runner.copies.count) cop\(runner.copies.count == 1 ? "y" : "ies") done")
                    .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(ink.opacity(0.55))
                ForEach(runner.copies) { copy in
                    let parent = agents.all.first { $0.id == copy.parentID }
                    ZStack(alignment: .bottomTrailing) {
                        if let parent { AgentAvatar(agent: parent, size: 30, animated: false) }
                        switch copy.status {
                        case .working: ProgressView().scaleEffect(0.5).frame(width: 14, height: 14).background(palette.background, in: Circle())
                        case .done: Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundColor(.green).background(palette.background, in: Circle())
                        case .failed: Image(systemName: "exclamationmark.circle.fill").font(.system(size: 13)).foregroundColor(.red).background(palette.background, in: Circle())
                        }
                    }
                    .opacity(copy.status == .working ? 0.75 : 1)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: runner.copies)
        }
    }

    private func typingRow(_ who: String) -> some View {
        HStack(spacing: 8) {
            AgentAvatar(id: agent(named: who)?.id ?? "name-" + who, hue: agent(named: who)?.hue ?? 0.6, size: 30, animated: false)
            HStack(spacing: 4) { ForEach(0..<3, id: \.self) { _ in Circle().fill(ink.opacity(0.35)).frame(width: 6, height: 6) } }
                .padding(.horizontal, 12).padding(.vertical, 12).background(ink.opacity(0.08), in: Capsule())
            Spacer()
        }
    }

    private func workingRow(_ who: String) -> some View {
        HStack(spacing: 8) {
            AgentAvatar(id: agent(named: who)?.id ?? "name-" + who, hue: agent(named: who)?.hue ?? 0.6, size: 30, animated: false)
            Text("\(who) is working…").font(.system(size: 12, weight: .semibold)).foregroundColor(ink.opacity(0.5))
            ProgressView().controlSize(.small)
            Spacer()
        }
    }

    /// What can be done once the team has finished: shown under the lead dot on the map (not in a section of its own).
    private var finishActions: some View {
        VStack(spacing: 8) {
            if let folder, forFolder == nil {
                Label("Work saved in the folder “\(folder)”", systemImage: "folder.fill").font(.system(size: 11.5, weight: .semibold)).foregroundColor(ink.opacity(0.6))
            } else if !filesNote.isEmpty {
                Text(filesNote).font(.system(size: 11.5)).foregroundColor(.orange)
            }
            if authState.spacechatUsername == nil && summary.isEmpty {
                Button("Log in with Spacechat") { onLogin() }.font(.system(size: 13, weight: .bold))
            }
            if forFolder != nil {
                Button { onClose() } label: {
                    Text("Back to the folder").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(ink)
                        .padding(.horizontal, 16).frame(height: 36).background(ink.opacity(0.1), in: Capsule())
                }.buttonStyle(PressableButtonStyle())
            } else if saved {
                Label("Saved to your home page", systemImage: "checkmark").font(.system(size: 12.5, weight: .bold)).foregroundColor(.green)
            } else if !summary.isEmpty {
                HStack(spacing: 8) {
                    Button { save() } label: {
                        Text("Save to home").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.white)
                            .padding(.horizontal, 16).frame(height: 36).background(Color(red: 0.16, green: 0.47, blue: 1), in: Capsule())
                    }.buttonStyle(PressableButtonStyle())
                    Button { onClose() } label: {
                        Text("No").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(ink)
                            .padding(.horizontal, 18).frame(height: 36).background(ink.opacity(0.1), in: Capsule())
                    }.buttonStyle(PressableButtonStyle())
                }
            } else {
                Button("Try again") { Task { await run(change: nil) } }.font(.system(size: 13, weight: .bold))
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $input, axis: .vertical)
                .focused($focused).lineLimit(1...4).font(.system(size: 16)).foregroundColor(ink)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .disabled(!canType)
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up").font(.system(size: 16, weight: .heavy)).foregroundColor(palette.isDark ? .black : .white)
                    .frame(width: 42, height: 42).background(canSend ? ink : ink.opacity(0.2), in: Circle())
            }.buttonStyle(.plain).disabled(!canSend)
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, GameHubView.homeIndicatorInset + 10)
        .background(.ultraThinMaterial)
    }

    private var canType: Bool { typing == nil && !runner.running }
    private var canSend: Bool { canType && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var placeholder: String {
        switch step {
        case .askName: return "The name of your product"
        case .askIdea: return forFolder != nil ? "What should the team do in this folder?" : "The idea: who it is for and what it does"
        case .working: return "The team is working…"
        case .done: return forFolder != nil ? "Ask the team for more" : "Ask the team for changes"
        }
    }

    // MARK: the conversation

    private func say(_ agent: SpacesAgent, _ text: String, to: String = "You") async {
        typing = agent.name
        try? await Task.sleep(nanoseconds: UInt64(min(1.6, 0.5 + Double(text.count) * 0.012) * 1_000_000_000))
        typing = nil
        messages.append(AgentMessage(kind: .agent, from: agent.name, to: to, text: text))
        HapticsManager.shared.impact(.light)
    }

    private func begin() async {
        guard messages.isEmpty else { return }
        if let project {
            // a saved project: its whole conversation, finished
            graph = UniverseGraph(project: project)
            projectID = project.id; name = project.name; idea = project.idea; summary = project.summary; saved = true; folder = forFolder ?? project.folder
            messages = project.transcript
            // left before the first task was given: carry on asking for it; otherwise it is where it was left
            step = project.idea.trimmingCharacters(in: .whitespaces).isEmpty && forFolder != nil ? .askIdea : .done
            if step == .askIdea { saved = false; focused = true }
            return
        }
        if let forFolder {
            // a folder's space: the folder is the project, so the first question is what to do in it
            name = forFolder; folder = forFolder; step = .askIdea
            let others = crew.dropFirst().map(\.name)
            let crew = others.isEmpty ? "" : " \(others.joined(separator: ", ")) and I are here too."
            await say(lead, "Hi! I'm \(lead.name).\(crew) We're in your folder “\(forFolder)”. What should we do in it?")
            focused = true
            return
        }
        let others = crew.dropFirst().map(\.name)
        let crew = others.isEmpty ? "" : " With \(others.joined(separator: ", ")) we will build it together."
        await say(lead, "Hi! I'm \(lead.name).\(crew) What is the name of your product?")
        focused = true
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        messages.append(AgentMessage(kind: .user, from: "You", to: lead.name, text: text))
        switch step {
        case .askName:
            name = String(text.prefix(60))
            step = .askIdea
            let asker = crew.count > 1 ? crew[1] : lead
            await say(asker, "\(name) — I like it. What is the idea behind it? Who is it for and what should it do?")
            focused = true
        case .askIdea:
            idea = text
            step = .working
            let others = crew.dropFirst().map(\.name)
            await say(lead, others.isEmpty ? "Got it. Let me start." : "Got it. \(others.joined(separator: " and ")), let's get to work. I'll split it up.", to: "team")
            await run(change: nil)
        case .done:
            step = .working
            saved = false
            await run(change: text)
        case .working:
            break
        }
    }

    private func run(change: String?) async {
        if let forFolder { await runInFolder(forFolder, change: change); return }
        var task = "Product name: \(name)\nIdea: \(idea)\n\nWork as a team to turn this idea into a clear first plan: who it is for, the main features, a short tagline, and the first steps to build it. Split the work between the teammates by name, check each other's parts, and finish with a short summary for the person: when the work is done, close it yourself with done set to true and the summary filled in, and do not ask whether to continue. For small separate jobs (for example several taglines or a list of features to check) you can start copies of yourself, up to 10 at a time."
        if let change {
            archive += work
            task += "\n\nWhat the team came up with so far:\n\(summary)\n\nThe person now asks for this change: \(change)"
        }
        if step != .working { step = .working }
        focused = false
        summary = ""
        // the project's folder exists from the start, so its files show up top left as they are made
        if folder == nil { folder = FolderStore.shared.makeFolder(name.isEmpty ? "Project" : name) }
        runner.runTeam(task: task, team: graph.connected(crew), folder: nil, canEdit: false, store: agents, parents: graph.parentMap(crew))
    }

    /// Work on the folder's real files: read before changing, small exact edits, every change asks first and can be undone from Folders.
    private func runInFolder(_ target: String, change: String?) async {
        var task = "You are working in the person's folder \"\(target)\" (its files are listed for you). The person asks: \(change ?? idea)\n\nRead the files you need before you change them, make small exact edits, and split the work between the teammates by name. Finish with a short summary of what was done: close it yourself with done set to true and the summary filled in, and do not ask whether to continue. For small separate jobs you can start copies of yourself, up to 10 at a time."
        if change != nil {
            archive += work
            if !summary.isEmpty { task += "\n\nWhat the team did earlier in this folder:\n\(summary)" }
            let earlier = (messages + archive).filter { $0.kind == .user || $0.kind == .agent }.suffix(8).map { "\($0.from): \($0.text.prefix(200))" }.joined(separator: "\n")
            if !earlier.isEmpty { task += "\n\nThe conversation so far:\n\(earlier)" }
        }
        step = .working
        focused = false
        summary = ""
        folder = target
        runner.runTeam(task: task, team: graph.connected(crew), folder: target, canEdit: true, store: agents, parents: graph.parentMap(crew))
    }

    /// A folder's space keeps itself: the team, the conversation and the last result are saved after every run, and when it is closed.
    private func autoSave() {
        guard let target = forFolder else { return }
        let all = Array((messages + archive + work).suffix(120))
        projects.save(Project(id: projectID, name: target, idea: idea, teamIDs: crew.map(\.id), summary: summary, transcript: all,
                              workspaceID: workspace.id, folder: target, linkedFolder: target,
                              links: graph.links, positions: graph.savedPositions))
        saved = true
    }

    /// The team's work goes into a folder of its own (in Folders): a README with the result, the whole conversation, and one file per copy.
    private func writeFiles() {
        let store = FolderStore.shared
        if folder == nil { folder = store.makeFolder(name.isEmpty ? "Project" : name) }
        guard let folder else { filesNote = "The work could not be saved to a folder."; return }
        let members = crew.map(\.name).joined(separator: ", ")
        let all = messages + archive + work
        var chat = "# \(name)\n\nTeam: \(members)\n\n"
        for m in all where m.kind == .user || m.kind == .agent {
            chat += "**\(m.from)**\(m.to.map { " → \($0)" } ?? ""): \(m.text)\n\n"
        }
        do {
            try store.write(folder, "README.md", content: "# \(name)\n\n\(idea)\n\nTeam: \(members)\n\n## Result\n\n\(summary)\n", by: lead.name)
            try store.write(folder, "conversation.md", content: chat, by: lead.name)
            for copy in runner.copies {
                try store.write(folder, "copies/\(copy.name.lowercased())-\(copy.parentName.lowercased())-copy.md", content: "# \(copy.name), a copy of \(copy.parentName)\n\nJob: \(copy.task)\n\n\(copy.result)\n", by: copy.parentName)
            }
            filesNote = ""
        } catch {
            filesNote = "Some files could not be saved: \(error.localizedDescription)"
        }
    }

    private func save() {
        let all = Array((messages + archive + work).suffix(80))
        projects.save(Project(id: projectID, name: name.isEmpty ? "Untitled" : name, idea: idea, teamIDs: crew.map(\.id), summary: summary,
                              transcript: all, workspaceID: workspace.id, folder: folder, links: graph.links, positions: graph.savedPositions))
        HapticsManager.shared.success()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { onClose() }
    }
}


// MARK: - The universe of a project

/// The team at work, on a map: the lead in the middle, the teammates around it, and every copy orbiting the dot it was made from, all joined
/// by lines. The dot that is speaking grows and shows its latest words; a working copy pulses; a finished one gets a tick.
/// How the dots of a project are wired: who reports to whom, and where the person put each dot. The lead (first dot) is the root.
struct UniverseGraph: Equatable {
    /// dot id → the dot it reports to. No entry: it reports to the lead. "": cut loose from everyone.
    var links: [String: String] = [:]
    /// Where the person left a dot, from the middle of the map.
    var positions: [String: CGPoint] = [:]

    init() {}
    init(project: Project) {
        links = project.links ?? [:]
        positions = (project.positions ?? [:]).reduce(into: [:]) { out, row in if row.value.count == 2 { out[row.key] = CGPoint(x: row.value[0], y: row.value[1]) } }
    }
    var savedPositions: [String: [Double]] { positions.mapValues { [Double($0.x), Double($0.y)] } }

    func parent(of id: String, in crew: [SpacesAgent]) -> String? {
        guard let lead = crew.first, id != lead.id else { return nil }
        guard let link = links[id] else { return lead.id }
        return link.isEmpty || !crew.contains(where: { $0.id == link }) ? nil : link
    }

    func children(of id: String, in crew: [SpacesAgent]) -> [SpacesAgent] { crew.filter { parent(of: $0.id, in: crew) == id } }

    /// Everything below a dot (its helpers, their helpers…).
    func descendants(of id: String, in crew: [SpacesAgent]) -> Set<String> {
        var out = Set<String>(), queue = [id]
        while let next = queue.popLast() {
            for child in children(of: next, in: crew) where !out.contains(child.id) { out.insert(child.id); queue.append(child.id) }
        }
        return out
    }

    /// The dots the lead can reach through connections: the ones that take part in the work.
    func connected(_ crew: [SpacesAgent]) -> [SpacesAgent] {
        guard let lead = crew.first else { return [] }
        let below = descendants(of: lead.id, in: crew)
        return [lead] + crew.filter { below.contains($0.id) }
    }

    /// Who each connected dot reports to.
    func parentMap(_ crew: [SpacesAgent]) -> [String: String] {
        var out: [String: String] = [:]
        for member in connected(crew).dropFirst() { if let p = parent(of: member.id, in: crew) { out[member.id] = p } }
        return out
    }

    /// A dot may not report to itself or to something below it.
    func canConnect(_ id: String, to target: String, in crew: [SpacesAgent]) -> Bool {
        guard let lead = crew.first, id != lead.id, id != target else { return false }
        return !descendants(of: id, in: crew).contains(target)
    }

    /// Where every dot sits: the lead in the middle, its helpers around it, theirs around them, loose dots further out. A spot the person
    /// chose wins; a dot nobody moved follows its parent. `overrides` is for a dot being dragged right now.
    func layout(crew: [SpacesAgent], overrides: [String: CGPoint] = [:]) -> [String: CGPoint] {
        guard let lead = crew.first else { return [:] }
        var out: [String: CGPoint] = [:]
        func settle(_ id: String, default point: CGPoint) -> CGPoint {
            let chosen = overrides[id] ?? positions[id] ?? point
            out[id] = chosen
            return chosen
        }
        func place(children kids: [SpacesAgent], around origin: CGPoint, facing angle: Double, radius: Double, spread: Double) {
            let n = kids.count
            for (j, kid) in kids.enumerated() {
                let theta = n == 1 ? angle : angle + (Double(j) - Double(n - 1) / 2) * min(spread, Double.pi * 1.6 / Double(n))
                let point = settle(kid.id, default: CGPoint(x: origin.x + cos(theta) * radius, y: origin.y + sin(theta) * radius * 0.92))
                let outward = atan2(point.y - origin.y, point.x - origin.x)
                place(children: children(of: kid.id, in: crew), around: point, facing: outward, radius: 112, spread: 0.85)
            }
        }
        let center = settle(lead.id, default: .zero)
        let first = children(of: lead.id, in: crew)
        for (j, kid) in first.enumerated() {
            let theta = -Double.pi / 2 + (Double(j) + (first.count % 2 == 0 ? 0.5 : 0)) * 2 * Double.pi / Double(max(1, first.count))
            let point = settle(kid.id, default: CGPoint(x: center.x + cos(theta) * 150, y: center.y + sin(theta) * 150 * 0.9))
            place(children: children(of: kid.id, in: crew), around: point, facing: atan2(point.y - center.y, point.x - center.x), radius: 112, spread: 0.85)
        }
        // loose dots (and what hangs from them) float further out
        let loose = crew.dropFirst().filter { parent(of: $0.id, in: crew) == nil }
        for (j, dot) in loose.enumerated() {
            let theta = Double.pi / 4 + Double(j) * 2 * Double.pi / Double(max(1, loose.count))
            let point = settle(dot.id, default: CGPoint(x: cos(theta) * 300, y: sin(theta) * 280))
            place(children: children(of: dot.id, in: crew), around: point, facing: theta, radius: 112, spread: 0.85)
        }
        return out
    }
}

struct ProjectUniverse: View {
    let team: [SpacesAgent]
    let copies: [AgentRunner.CopyJob]
    let speaking: String?
    let running: Bool
    let palette: WorldBackground.Palette
    let latest: [String: String]
    /// The team has finished: each dot shows it, and the lead shows the result and what to do next.
    var finished = false
    var summary = ""
    var leadFooter: AnyView? = nil
    /// The wiring and the places of the dots. Hold a dot to move it, drop it on another dot to connect it, or on the bin to delete it.
    @Binding var graph: UniverseGraph
    var onAdd: (String?) -> Void = { _ in }
    var onDelete: (String) -> Void = { _ in }
    var onDeleteCopy: (UUID) -> Void = { _ in }
    let agentFor: (String) -> SpacesAgent?

    @State private var offset = CGSize.zero
    @State private var dragBase: CGSize?
    @State private var scale: CGFloat = 0.85
    @State private var pinchBase: CGFloat?
    // holding a dot
    @State private var held: String?
    @State private var heldPoint = CGPoint.zero
    @State private var heldBase = CGPoint.zero
    @State private var overTarget: String?
    @State private var overBin = false
    @State private var copySpots: [UUID: CGPoint] = [:]
    // tapping a dot
    @State private var menuFor: String?
    @State private var menuOpen = false
    @State private var hint: String?

    private var dark: Bool { palette.isDark }
    private var ink: Color { dark ? .white : .black }
    private let blue = Color(red: 0.16, green: 0.47, blue: 1)

    private var lead: SpacesAgent? { team.first }

    /// Where a copy sits: where the person left it, or near the dot it was made from.
    private func copySpot(_ job: AgentRunner.CopyJob, _ spots: [String: CGPoint]) -> CGPoint {
        if held == "copy:\(job.id)" { return heldPoint }
        if let own = copySpots[job.id] { return own }
        let base = spots[job.parentID] ?? .zero
        let angle = Double(job.number) * 0.9 + 0.6
        return CGPoint(x: base.x + cos(angle) * 78, y: base.y + sin(angle) * 78)
    }

    var body: some View {
        GeometryReader { geo in
            let lifted: [String: CGPoint] = held.map { $0.hasPrefix("copy:") ? [:] : [$0: heldPoint] } ?? [:]
            let spots = graph.layout(crew: team, overrides: lifted)
            let bin = CGPoint(x: geo.size.width / 2, y: geo.size.height - 210)
            ZStack {
                palette.background
                backdrop
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let at: (String, Int) -> CGPoint = { id, i in
                        let base = spots[id] ?? .zero
                        return self.held == id ? base : self.drift(base, i, t)
                    }
                    ZStack {
                        Canvas { ctx, size in
                            let c = CGPoint(x: size.width / 2, y: size.height / 2)
                            for (i, member) in team.enumerated() {
                                guard let parentID = graph.parent(of: member.id, in: team), let pi = team.firstIndex(where: { $0.id == parentID }) else { continue }
                                let a = at(parentID, pi), b = at(member.id, i)
                                let from = CGPoint(x: c.x + a.x, y: c.y + a.y), to = CGPoint(x: c.x + b.x, y: c.y + b.y)
                                var line = Path(); line.move(to: from); line.addLine(to: to)
                                let active = overTarget == parentID && held == member.id
                                ctx.stroke(line, with: .color(blue.opacity(active ? 0.9 : 0.5)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                // a small arrow along the line, pointing up to the dot it reports to
                                let mid = CGPoint(x: from.x + (to.x - from.x) * 0.5, y: from.y + (to.y - from.y) * 0.5)
                                let ang = atan2(from.y - to.y, from.x - to.x)
                                var arrow = Path()
                                arrow.move(to: CGPoint(x: mid.x + cos(ang) * 7, y: mid.y + sin(ang) * 7))
                                arrow.addLine(to: CGPoint(x: mid.x + cos(ang + 2.5) * 7, y: mid.y + sin(ang + 2.5) * 7))
                                arrow.addLine(to: CGPoint(x: mid.x + cos(ang - 2.5) * 7, y: mid.y + sin(ang - 2.5) * 7))
                                arrow.closeSubpath()
                                ctx.fill(arrow, with: .color(blue.opacity(0.7)))
                            }
                            for job in copies {
                                guard let pi = team.firstIndex(where: { $0.id == job.parentID }) else { continue }
                                let a = at(job.parentID, pi)
                                let spot = copySpot(job, spots)
                                let b = held == "copy:\(job.id)" ? spot : drift(spot, 20 + job.number, t)
                                var line = Path(); line.move(to: CGPoint(x: c.x + a.x, y: c.y + a.y)); line.addLine(to: CGPoint(x: c.x + b.x, y: c.y + b.y))
                                let color: Color = job.status == .failed ? .red : (job.status == .done ? .green : blue)
                                ctx.stroke(line, with: .color(color.opacity(job.status == .working ? 0.8 : 0.45)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: job.status == .working ? [5, 5] : []))
                            }
                        }
                        ForEach(Array(team.enumerated()), id: \.element.id) { index, member in
                            let p = at(member.id, index)
                            member_view(member, lead: index == 0, spots: spots)
                                .scaleEffect(held == member.id ? 1.12 : 1)
                                .shadow(color: .black.opacity(held == member.id ? 0.25 : 0), radius: 12, y: 6)
                                .offset(x: p.x, y: p.y)
                                .zIndex(held == member.id ? 5 : 0)
                        }
                        ForEach(copies) { job in
                            let spot = copySpot(job, spots)
                            let p = held == "copy:\(job.id)" ? spot : drift(spot, 20 + job.number, t)
                            copy_view(job, spots: spots)
                                .scaleEffect(held == "copy:\(job.id)" ? 1.15 : 1)
                                .offset(x: p.x, y: p.y)
                                .zIndex(held == "copy:\(job.id)" ? 5 : 0)
                                .transition(.scale(scale: 0.1).combined(with: .opacity))
                        }
                    }
                    .frame(width: 1600, height: 1600)
                }
                .scaleEffect(scale)
                .offset(x: offset.width, y: offset.height)
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: copies.count)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: graph)
                if held != nil { binView(at: bin) }
                if let hint {
                    Text(hint).font(.system(size: 12.5, weight: .bold)).foregroundColor(ink).padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 150).allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .coordinateSpace(name: "universe")
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { v in
                if pinchBase != nil || held != nil { return }
                if dragBase == nil { dragBase = offset }
                offset = CGSize(width: (dragBase?.width ?? 0) + v.translation.width, height: (dragBase?.height ?? 0) + v.translation.height)
            }.onEnded { _ in dragBase = nil })
            .simultaneousGesture(MagnificationGesture().onChanged { v in
                if held != nil { return }
                if pinchBase == nil { pinchBase = scale }
                scale = min(2, max(0.3, (pinchBase ?? scale) * v))
            }.onEnded { _ in pinchBase = nil })
            .overlay(alignment: .topTrailing) {
                Button { withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { offset = .zero; scale = 0.85 } } label: {
                    Image(systemName: "scope").font(.system(size: 14, weight: .bold)).foregroundColor(ink).frame(width: 36, height: 36).background(.ultraThinMaterial, in: Circle())
                }.buttonStyle(.plain).padding(12).accessibilityLabel("Back to the middle")
            }
            .confirmationDialog(menuTitle, isPresented: $menuOpen, titleVisibility: .visible) { menuButtons } message: { Text(menuMessage) }
            .onChange(of: heldPoint) { point in updateTargets(point, bin: bin, spots: spots) }
        }
    }

    // MARK: holding, moving, connecting and deleting

    /// Hold a dot to pick it up, then drag. Let go on another dot to connect to it, on the bin to delete it, or anywhere else to leave it there.
    private func holdGesture(_ key: String, at spot: @escaping () -> CGPoint) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("universe")))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if held != key {
                    held = key; heldBase = spot(); heldPoint = heldBase
                    HapticsManager.shared.impact(.medium)
                }
                if let drag {
                    heldPoint = CGPoint(x: heldBase.x + drag.translation.width / scale, y: heldBase.y + drag.translation.height / scale)
                    dragLocation = drag.location
                }
            }
            .onEnded { value in
                defer { held = nil; overTarget = nil; overBin = false }
                guard held == key, case .second(true, let drag?) = value else { return }
                finishDrop(key, drag: drag)
            }
    }

    @State private var dragLocation = CGPoint.zero

    private func updateTargets(_ point: CGPoint, bin: CGPoint, spots: [String: CGPoint]) {
        guard let key = held else { return }
        overBin = hypot(dragLocation.x - bin.x, dragLocation.y - bin.y) < 70
        if key.hasPrefix("copy:") || key == lead?.id || running { overTarget = nil; return }
        let blocked = graph.descendants(of: key, in: team).union([key])
        overTarget = team.first { !blocked.contains($0.id) && hypot((spots[$0.id] ?? .zero).x - point.x, (spots[$0.id] ?? .zero).y - point.y) < 66 }?.id
    }

    private func finishDrop(_ key: String, drag: DragGesture.Value) {
        let place = CGPoint(x: max(-700, min(700, heldPoint.x)), y: max(-700, min(700, heldPoint.y)))
        if key.hasPrefix("copy:") {
            guard let id = UUID(uuidString: String(key.dropFirst(5))) else { return }
            if overBin {
                if copies.first(where: { $0.id == id })?.status == .working { say("That copy is still working. Delete it when it is done.") }
                else { HapticsManager.shared.success(); onDeleteCopy(id) }
            } else { copySpots[id] = place }
            return
        }
        if overBin {
            if key == lead?.id { say("The lead can't be deleted."); return }
            if running { say("Wait for the team to stop before deleting a dot."); return }
            HapticsManager.shared.success()
            onDelete(key)
            return
        }
        if let target = overTarget, graph.canConnect(key, to: target, in: team) {
            graph.links[key] = target
            graph.positions[key] = nil
            HapticsManager.shared.success()
            return
        }
        graph.positions[key] = place
    }

    private func say(_ text: String) {
        HapticsManager.shared.impact(.rigid)
        withAnimation { hint = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { withAnimation { if hint == text { hint = nil } } }
    }

    private func binView(at point: CGPoint) -> some View {
        let isLead = held == lead?.id
        return VStack(spacing: 4) {
            Image(systemName: overBin && !isLead ? "trash.fill" : "trash").font(.system(size: overBin ? 26 : 22, weight: .bold)).foregroundColor(isLead ? ink.opacity(0.3) : .white)
                .frame(width: overBin ? 72 : 60, height: overBin ? 72 : 60)
                .background(isLead ? ink.opacity(0.1) : Color.red.opacity(overBin ? 1 : 0.8), in: Circle())
            Text(isLead ? "Lead stays" : "Drop to delete").font(.system(size: 11, weight: .bold)).foregroundColor(ink.opacity(0.7))
        }
        .position(point)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: overBin)
        .allowsHitTesting(false)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: tapping a dot

    private var menuAgent: SpacesAgent? { team.first { $0.id == menuFor } }
    private var menuTitle: String { menuAgent?.name ?? "" }
    private var menuMessage: String {
        guard let agent = menuAgent else { return "" }
        if agent.id == lead?.id { return "The lead of the team. Everything the team makes comes back to it." }
        if let parent = graph.parent(of: agent.id, in: team), let name = team.first(where: { $0.id == parent })?.name { return "Reports to \(name)" }
        return "Not connected: it is not part of the work until you connect it."
    }

    @ViewBuilder
    private var menuButtons: some View {
        if let agent = menuAgent {
            Button("Add a dot under \(agent.name)") { onAdd(agent.id) }
            if agent.id != lead?.id {
                if graph.parent(of: agent.id, in: team) != nil {
                    Button("Disconnect") { withAnimation { graph.links[agent.id] = "" }; HapticsManager.shared.impact(.light) }
                }
                ForEach(team.filter { $0.id != agent.id && $0.id != graph.parent(of: agent.id, in: team) && graph.canConnect(agent.id, to: $0.id, in: team) }) { other in
                    Button("Connect to \(other.name)") { withAnimation { graph.links[agent.id] = other.id; graph.positions[agent.id] = nil }; HapticsManager.shared.success() }
                }
                Button("Delete \(agent.name)", role: .destructive) { onDelete(agent.id) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func openMenu(_ id: String) {
        if running { say("Wait for the team to stop before changing the dots."); return }
        menuFor = id; menuOpen = true
    }

    private func drift(_ p: CGPoint, _ index: Int, _ t: Double) -> CGPoint {
        let phase = Double(index) * 1.7
        return CGPoint(x: p.x + sin(t * 0.5 + phase) * 5, y: p.y + cos(t * 0.42 + phase * 1.3) * 6)
    }

    private var backdrop: some View {
        Canvas { ctx, s in
            let step: CGFloat = 44 * max(0.6, min(1.5, scale))
            let cx = s.width / 2 + offset.width, cy = s.height / 2 + offset.height
            var x = cx.truncatingRemainder(dividingBy: step) - step
            while x < s.width + step {
                var y = cy.truncatingRemainder(dividingBy: step) - step
                while y < s.height + step {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(palette.line.opacity(dark ? 0.55 : 0.8)))
                    y += step
                }
                x += step
            }
        }.allowsHitTesting(false)
    }

    /// What this dot is doing, in a word.
    private func status(_ agent: SpacesAgent, lead: Bool) -> (text: String, color: Color) {
        if !lead && graph.parent(of: agent.id, in: team) == nil { return ("Not connected", .orange) }
        if finished { return summary.isEmpty && lead ? ("Stopped", .orange) : (lead ? "Finished" : "Done", Color(red: 0.2, green: 0.7, blue: 0.4)) }
        if speaking == agent.name { return ("Working…", blue) }
        if running { return ("Waiting", ink.opacity(0.45)) }
        return ("Ready", ink.opacity(0.45))
    }

    private func member_view(_ agent: SpacesAgent, lead: Bool, spots: [String: CGPoint]) -> some View {
        let talking = speaking == agent.name
        let finalResult = finished && lead && !summary.isEmpty
        let words = finalResult ? summary : latest[agent.name]
        let state = status(agent, lead: lead)
        let target = overTarget == agent.id
        return VStack(spacing: 4) {
            // what the dot last said (the lead shows the final result when the work is done), above it
            if let words, !words.isEmpty {
                Text(words).font(.system(size: 11, weight: .medium)).foregroundColor(ink).lineLimit(finalResult ? 7 : 3).multilineTextAlignment(.leading)
                    .padding(.horizontal, 10).padding(.vertical, 7).frame(width: finalResult ? 230 : 170)
                    .background(dark ? Color.white.opacity(0.14) : .white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(finalResult ? state.color.opacity(0.6) : ink.opacity(0.12), lineWidth: finalResult ? 1.5 : 1))
                    .opacity(talking || finalResult ? 1 : 0.8)
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
            }
            ZStack {
                if talking { Circle().stroke(blue, lineWidth: 3).frame(width: (lead ? 108 : 86), height: (lead ? 108 : 86)) }
                if target { Circle().stroke(blue, style: StrokeStyle(lineWidth: 3, dash: [6, 5])).frame(width: lead ? 118 : 96, height: lead ? 118 : 96) }
                AgentAvatar(agent: agent, size: lead ? 88 : 68)
            }
            .scaleEffect(talking ? 1.12 : 1)
            .contentShape(Circle())
            .onTapGesture { openMenu(agent.id) }
            .gesture(holdGesture(agent.id, at: { spots[agent.id] ?? .zero }))
            Text(agent.name + (lead ? " · lead" : "")).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(ink)
            // its status, under it
            HStack(spacing: 4) {
                if talking && running { ProgressView().controlSize(.mini) } else { Circle().fill(state.color).frame(width: 6, height: 6) }
                Text(target ? "Connect here" : state.text).font(.system(size: 10.5, weight: .bold)).foregroundColor(target ? blue : state.color)
            }
            if lead, let leadFooter { leadFooter.padding(.top, 4).transition(.opacity) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: talking)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: words)
    }

    private func copy_view(_ job: AgentRunner.CopyJob, spots: [String: CGPoint]) -> some View {
        let parent = team.first { $0.id == job.parentID }
        let working = job.status == .working
        let key = "copy:\(job.id)"
        return VStack(spacing: 2) {
            ZStack(alignment: .bottomTrailing) {
                if let parent { AgentAvatar(agent: parent, size: 38, animated: false).opacity(working ? 0.8 : 1) }
                switch job.status {
                case .working: ProgressView().scaleEffect(0.5).frame(width: 15, height: 15).background(palette.background, in: Circle())
                case .done: Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundColor(.green).background(palette.background, in: Circle())
                case .failed: Image(systemName: "exclamationmark.circle.fill").font(.system(size: 14)).foregroundColor(.red).background(palette.background, in: Circle())
                }
            }
            Text(job.name).font(.system(size: 10.5, weight: .heavy, design: .rounded)).foregroundColor(ink.opacity(0.75))
        }
        .contentShape(Rectangle())
        .gesture(holdGesture(key, at: { copySpot(job, spots) }))
    }
}

/// Choose a dot to bring into the universe. Claude, ChatGPT and Grok are for members.
struct AddDotSheet: View {
    let agents: [SpacesAgent]
    let parent: String
    let running: Bool
    let onPick: (SpacesAgent) -> Void
    @ObservedObject private var shop = StoreManager.shared
    @State private var showMembers = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if running { Section { Text("The team is working. A new dot joins the next task.").font(.footnote).foregroundColor(.secondary) } }
                Section("Joins \(parent)") {
                    if agents.isEmpty { Text("Every dot is already here.").foregroundColor(.secondary) }
                    ForEach(agents) { agent in
                        Button {
                            if agent.membersOnly && !shop.isMember { showMembers = true } else { onPick(agent); dismiss() }
                        } label: {
                            HStack(spacing: 12) {
                                AgentAvatar(agent: agent, size: 40, animated: false)
                                    .overlay(alignment: .topTrailing) { if agent.membersOnly && !shop.isMember { MemberLockBadge(size: 16).offset(x: 3, y: -3) } }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(agent.name).font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                                    Text(agent.role).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if agent.membersOnly && !shop.isMember { Text("Members").font(.system(size: 11, weight: .bold)).foregroundColor(.secondary) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add a dot").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showMembers) { MembersOnlySheet() }
        }
    }
}

// MARK: - The project's files

/// A pop-up with the project's folder: every file and folder in it. Tap one to open its menu: edit, rename, move or delete (a folder can also get a new folder inside).
struct ProjectFilesPanel: View {
    let folder: String
    let palette: WorldBackground.Palette
    let who: String
    let onClose: () -> Void

    @ObservedObject private var store = FolderStore.shared
    @State private var editing: WorkspaceFile?
    @State private var renaming: WorkspaceFile?
    @State private var renameText = ""
    @State private var moving: WorkspaceFile?
    @State private var deleting: WorkspaceFile?
    @State private var makingIn: String?
    @State private var newName = ""
    @State private var problem: String?

    private var ink: Color { palette.isDark ? .white : .black }

    var body: some View {
        let tree = store.tree(folder)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill").font(.system(size: 14, weight: .bold)).foregroundColor(ink)
                Text(folder).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(ink).lineLimit(1)
                Spacer()
                Button { makingIn = ""; newName = "" } label: {
                    Image(systemName: "folder.badge.plus").font(.system(size: 13, weight: .bold)).foregroundColor(ink).frame(width: 30, height: 30).background(ink.opacity(0.08), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("New folder")
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundColor(ink).frame(width: 30, height: 30).background(ink.opacity(0.08), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Close files")
            }.padding(.horizontal, 14).padding(.vertical, 10)
            if let problem { Text(problem).font(.system(size: 12, weight: .semibold)).foregroundColor(.red).padding(.horizontal, 14).padding(.bottom, 6) }
            if tree.isEmpty {
                VStack(spacing: 6) {
                    Text("This folder is empty").font(.system(size: 14, weight: .bold)).foregroundColor(ink)
                    Text("The team's files show up here as they are made.").font(.system(size: 12)).foregroundColor(ink.opacity(0.55)).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tree) { item in row(item) }
                    }.padding(.horizontal, 8).padding(.bottom, 10)
                }
            }
        }
        .frame(width: 330, height: 480)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(ink.opacity(0.15)))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, GameHubView.bannerTopInset + 56).padding(.leading, 12)
        .sheet(item: $editing) { file in FileEditorView(folder: folder, file: file, folders: store) { editing = nil } }
        .sheet(item: $moving) { item in MoveSheet(folder: folder, item: item) { destination in
            moving = nil
            guard let destination else { return }
            do { try store.move(folder, item.path, into: destination); problem = nil } catch { problem = error.localizedDescription }
        } }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let item = renaming { do { try store.rename(folder, item.path, to: renameText); problem = nil } catch { problem = error.localizedDescription } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("New folder", isPresented: Binding(get: { makingIn != nil }, set: { if !$0 { makingIn = nil } })) {
            TextField("Name", text: $newName)
            Button("Create") {
                if let parent = makingIn { do { try store.makeDirectory(folder, in: parent, named: newName); problem = nil } catch { problem = error.localizedDescription } }
                makingIn = nil
            }
            Button("Cancel", role: .cancel) { makingIn = nil }
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let item = deleting { do { try store.deleteItem(folder, item, by: "You"); problem = nil } catch { problem = error.localizedDescription } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text(deleting?.isDirectory == true ? "The folder and everything in it will be removed." : "A text file can be brought back from Changes.") }
    }

    private func row(_ item: WorkspaceFile) -> some View {
        Menu {
            if !item.isDirectory { Button { editing = item } label: { Label("Edit", systemImage: "pencil") } }
            if item.isDirectory { Button { makingIn = item.path; newName = "" } label: { Label("New folder inside", systemImage: "folder.badge.plus") } }
            Button { renameText = item.name; renaming = item } label: { Label("Rename", systemImage: "character.cursor.ibeam") }
            Button { moving = item } label: { Label("Move to…", systemImage: "arrow.right.circle") }
            Button(role: .destructive) { deleting = item } label: { Label("Delete", systemImage: "trash") }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.isDirectory ? "folder.fill" : "doc.text").font(.system(size: 15)).foregroundColor(item.isDirectory ? Color(red: 0.16, green: 0.47, blue: 1) : ink.opacity(0.6)).frame(width: 22)
                Text(item.name).font(.system(size: 14, weight: item.isDirectory ? .bold : .medium)).foregroundColor(ink).lineLimit(1)
                Spacer()
                if !item.isDirectory { Text(item.size < 1024 ? "\(item.size) B" : "\(item.size / 1024) KB").font(.system(size: 10.5, weight: .semibold)).foregroundColor(ink.opacity(0.4)) }
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).foregroundColor(ink.opacity(0.35))
            }
            .padding(.leading, CGFloat(item.depth) * 16 + 6).padding(.trailing, 6).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Pick where to move a file or folder: the top of the project or any folder in it.
private struct MoveSheet: View {
    let folder: String
    let item: WorkspaceFile
    let onPick: (String?) -> Void
    @ObservedObject private var store = FolderStore.shared

    var body: some View {
        NavigationStack {
            List {
                Button { onPick("") } label: { Label("\(folder) (top)", systemImage: "folder.fill") }
                ForEach(store.tree(folder).filter { $0.isDirectory && $0.path != item.path && !$0.path.hasPrefix(item.path + "/") }) { dir in
                    Button { onPick(dir.path) } label: { Label(dir.path, systemImage: "folder") }
                }
            }
            .navigationTitle("Move “\(item.name)”").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onPick(nil) } } }
        }.preferredColorScheme(.light)
    }
}
