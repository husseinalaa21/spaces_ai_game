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
    @FocusState private var focused: Bool

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
            ProjectUniverse(team: team, copies: runner.copies, speaking: runner.speaking ?? typing, running: runner.running, palette: palette,
                            latest: latestWords, agentFor: agent(named:))
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                HStack(alignment: .top, spacing: 10) {
                    filesCard
                    Spacer(minLength: 0)
                    messagesCard
                }
                .padding(.horizontal, 12).padding(.top, 4)
                Spacer(minLength: 0)
                if step == .done { doneCard.padding(.horizontal, 14).padding(.bottom, 8) }
                composer
            }
            if filesOpen, let folder { ProjectFilesPanel(folder: folder, palette: palette, who: lead.name) { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { filesOpen = false } }.transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity)).zIndex(5) }
            if messagesOpen { messagesPanel.transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity)).zIndex(5) }
        }
        .background(palette.background.ignoresSafeArea())
        .overlay(alignment: .bottom) { ApprovalCard().padding(.bottom, 80) }
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .task { await begin() }
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
                ForEach(team) { member in
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

    private var doneCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(summary.isEmpty ? "The team stopped" : "Finished", systemImage: summary.isEmpty ? "pause.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundColor(summary.isEmpty ? .orange : Color(red: 0.2, green: 0.7, blue: 0.4))
            if !summary.isEmpty { Text(summary).font(.system(size: 14.5)).foregroundColor(ink).textSelection(.enabled) }
            if authState.spacechatUsername == nil && summary.isEmpty {
                Button("Log in with Spacechat") { onLogin() }.font(.system(size: 14, weight: .bold))
            }
            if let folder, forFolder == nil {
                Label("Work saved in the folder “\(folder)”", systemImage: "folder.fill").font(.system(size: 12.5, weight: .semibold)).foregroundColor(ink.opacity(0.6))
            } else if !filesNote.isEmpty {
                Text(filesNote).font(.system(size: 12)).foregroundColor(.orange)
            }
            if forFolder != nil {
                Label("This folder's space is saved: its team, files and history", systemImage: "checkmark").font(.system(size: 12.5, weight: .bold)).foregroundColor(.green)
                Button { onClose() } label: {
                    Text("Back to the folder").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(ink)
                        .frame(maxWidth: .infinity).frame(height: 44).background(ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.buttonStyle(PressableButtonStyle())
            } else if saved {
                Label("Saved to your home page", systemImage: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(.green)
            } else if !summary.isEmpty {
                Text("Save this project to your home page?").font(.system(size: 13, weight: .semibold)).foregroundColor(ink.opacity(0.6))
                HStack(spacing: 10) {
                    Button { save() } label: {
                        Text("Yes, save it").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 46).background(Color(red: 0.16, green: 0.47, blue: 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(PressableButtonStyle())
                    Button { onClose() } label: {
                        Text("No").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(ink)
                            .frame(width: 90, height: 46).background(ink.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(PressableButtonStyle())
                }
            } else {
                Button("Try again") { Task { await run(change: nil) } }.font(.system(size: 14, weight: .bold))
            }
            Text("Want changes? Tell the team below.").font(.system(size: 12)).foregroundColor(ink.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(Color(red: 0.2, green: 0.7, blue: 0.4).opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(palette.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ink.opacity(0.1)))
        .transition(.scale(scale: 0.92).combined(with: .opacity))
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
            let others = team.dropFirst().map(\.name)
            let crew = others.isEmpty ? "" : " \(others.joined(separator: ", ")) and I are here too."
            await say(lead, "Hi! I'm \(lead.name).\(crew) We're in your folder “\(forFolder)”. What should we do in it?")
            focused = true
            return
        }
        let others = team.dropFirst().map(\.name)
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
            let asker = team.count > 1 ? team[1] : lead
            await say(asker, "\(name) — I like it. What is the idea behind it? Who is it for and what should it do?")
            focused = true
        case .askIdea:
            idea = text
            step = .working
            let others = team.dropFirst().map(\.name)
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
        runner.runTeam(task: task, team: team, folder: nil, canEdit: false, store: agents)
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
        runner.runTeam(task: task, team: team, folder: target, canEdit: true, store: agents)
    }

    /// A folder's space keeps itself: the team, the conversation and the last result are saved after every run, and when it is closed.
    private func autoSave() {
        guard let target = forFolder else { return }
        let all = Array((messages + archive + work).suffix(120))
        projects.save(Project(id: projectID, name: target, idea: idea, teamIDs: team.map(\.id), summary: summary, transcript: all,
                              workspaceID: workspace.id, folder: target, linkedFolder: target))
        saved = true
    }

    /// The team's work goes into a folder of its own (in Folders): a README with the result, the whole conversation, and one file per copy.
    private func writeFiles() {
        let store = FolderStore.shared
        if folder == nil { folder = store.makeFolder(name.isEmpty ? "Project" : name) }
        guard let folder else { filesNote = "The work could not be saved to a folder."; return }
        let members = team.map(\.name).joined(separator: ", ")
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
        projects.save(Project(id: projectID, name: name.isEmpty ? "Untitled" : name, idea: idea, teamIDs: team.map(\.id), summary: summary,
                              transcript: all, workspaceID: workspace.id, folder: folder))
        HapticsManager.shared.success()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { onClose() }
    }
}


// MARK: - The universe of a project

/// The team at work, on a map: the lead in the middle, the teammates around it, and every copy orbiting the dot it was made from, all joined
/// by lines. The dot that is speaking grows and shows its latest words; a working copy pulses; a finished one gets a tick.
struct ProjectUniverse: View {
    let team: [SpacesAgent]
    let copies: [AgentRunner.CopyJob]
    let speaking: String?
    let running: Bool
    let palette: WorldBackground.Palette
    let latest: [String: String]
    let agentFor: (String) -> SpacesAgent?

    @State private var offset = CGSize.zero
    @State private var dragBase: CGSize?
    @State private var scale: CGFloat = 0.85
    @State private var pinchBase: CGFloat?

    private var dark: Bool { palette.isDark }
    private var ink: Color { dark ? .white : .black }
    private let ring: CGFloat = 150

    private func teamPoint(_ index: Int) -> CGPoint {
        if index == 0 { return .zero }
        let n = max(1, team.count - 1)
        let angle = -Double.pi / 2 + Double(index - 1) * 2 * Double.pi / Double(n)
        return CGPoint(x: cos(angle) * ring, y: sin(angle) * ring * 0.9)
    }

    private func copyPoint(_ job: AgentRunner.CopyJob) -> CGPoint {
        guard let i = team.firstIndex(where: { $0.id == job.parentID }) else { return .zero }
        let base = teamPoint(i)
        let angle = Double(job.number) * 0.9 + 0.6
        return CGPoint(x: base.x + cos(angle) * 78, y: base.y + sin(angle) * 78)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                palette.background
                backdrop
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        Canvas { ctx, size in
                            let c = CGPoint(x: size.width / 2, y: size.height / 2)
                            for i in 1..<max(1, team.count) {
                                let p = drift(teamPoint(i), i, t)
                                var line = Path(); line.move(to: c); line.addLine(to: CGPoint(x: c.x + p.x, y: c.y + p.y))
                                ctx.stroke(line, with: .color(Color(red: 0.16, green: 0.47, blue: 1).opacity(0.5)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            }
                            for job in copies {
                                guard let pi = team.firstIndex(where: { $0.id == job.parentID }) else { continue }
                                let a = drift(teamPoint(pi), pi, t), b = drift(copyPoint(job), 20 + job.number, t)
                                var line = Path(); line.move(to: CGPoint(x: c.x + a.x, y: c.y + a.y)); line.addLine(to: CGPoint(x: c.x + b.x, y: c.y + b.y))
                                let color: Color = job.status == .failed ? .red : (job.status == .done ? .green : Color(red: 0.16, green: 0.47, blue: 1))
                                ctx.stroke(line, with: .color(color.opacity(job.status == .working ? 0.8 : 0.45)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: job.status == .working ? [5, 5] : []))
                            }
                        }
                        ForEach(Array(team.enumerated()), id: \.element.id) { index, member in
                            let p = drift(teamPoint(index), index, t)
                            member_view(member, lead: index == 0).offset(x: p.x, y: p.y)
                        }
                        ForEach(copies) { job in
                            let p = drift(copyPoint(job), 20 + job.number, t)
                            copy_view(job).offset(x: p.x, y: p.y).transition(.scale(scale: 0.1).combined(with: .opacity))
                        }
                    }
                    .frame(width: 1600, height: 1600)
                }
                .scaleEffect(scale)
                .offset(x: offset.width, y: offset.height)
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: copies.count)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { v in
                if pinchBase != nil { return }
                if dragBase == nil { dragBase = offset }
                offset = CGSize(width: (dragBase?.width ?? 0) + v.translation.width, height: (dragBase?.height ?? 0) + v.translation.height)
            }.onEnded { _ in dragBase = nil })
            .simultaneousGesture(MagnificationGesture().onChanged { v in
                if pinchBase == nil { pinchBase = scale }
                scale = min(2, max(0.3, (pinchBase ?? scale) * v))
            }.onEnded { _ in pinchBase = nil })
            .overlay(alignment: .topTrailing) {
                Button { withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { offset = .zero; scale = 0.85 } } label: {
                    Image(systemName: "scope").font(.system(size: 14, weight: .bold)).foregroundColor(ink).frame(width: 36, height: 36).background(.ultraThinMaterial, in: Circle())
                }.buttonStyle(.plain).padding(12).accessibilityLabel("Back to the middle")
            }
        }
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

    private func member_view(_ agent: SpacesAgent, lead: Bool) -> some View {
        let talking = speaking == agent.name
        let words = latest[agent.name]
        return VStack(spacing: 4) {
            if talking, let words {
                Text(words).font(.system(size: 11, weight: .medium)).foregroundColor(ink).lineLimit(3).multilineTextAlignment(.leading)
                    .padding(.horizontal, 10).padding(.vertical, 7).frame(width: 170)
                    .background(dark ? Color.white.opacity(0.14) : .white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ink.opacity(0.12)))
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
            }
            ZStack {
                if talking { Circle().stroke(Color(red: 0.16, green: 0.47, blue: 1), lineWidth: 3).frame(width: (lead ? 108 : 86), height: (lead ? 108 : 86)) }
                AgentAvatar(agent: agent, size: lead ? 88 : 68)
            }
            .scaleEffect(talking ? 1.12 : 1)
            Text(agent.name + (lead ? " · lead" : "")).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(ink)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: talking)
    }

    private func copy_view(_ job: AgentRunner.CopyJob) -> some View {
        let parent = team.first { $0.id == job.parentID }
        let working = job.status == .working
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
