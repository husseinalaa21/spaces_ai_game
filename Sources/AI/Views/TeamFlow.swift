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
    let onLogin: () -> Void
    let onClose: () -> Void

    @State private var team: [SpacesAgent]?

    private var available: [SpacesAgent] {
        guard let ids = workspace.team else { return agents.all }
        let picked = agents.all.filter { ids.contains($0.id) }
        return picked.isEmpty ? agents.all : picked
    }

    var body: some View {
        ZStack {
            if let team {
                ProjectRoomView(team: team, agents: agents, folders: folders, projects: projects, authState: authState,
                                workspace: workspace, project: project, onLogin: onLogin, onClose: onClose)
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            } else {
                TeamLobbyView(agents: available, palette: WorldBackground.palette(for: workspace.theme), onStart: { picked in
                    withAnimation(.easeInOut(duration: 0.45)) { team = picked }
                }, onClose: onClose)
                .transition(.opacity)
            }
        }
        .onAppear {
            if let project, team == nil {
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
    @FocusState private var focused: Bool

    private var lead: SpacesAgent { team.first ?? agents.all[0] }
    /// A copy ("Dots copy 2") looks exactly like the dot it was made from.
    private func agent(named name: String) -> SpacesAgent? {
        let base = name.range(of: " copy \\d+$", options: .regularExpression).map { String(name[..<$0.lowerBound]) } ?? name
        return agents.all.first { $0.name == base }
    }
    /// The runner opens its transcript with the whole task as a message from you; that is the brief you already gave, so it is not shown again.
    private var work: [AgentMessage] { Array(runner.transcript.drop(while: { $0.kind == .user })) }
    private var everything: [AgentMessage] { messages + work }
    private var palette: WorldBackground.Palette { WorldBackground.palette(for: workspace.theme) }
    private var ink: Color { palette.isDark ? .white : .black }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if !runner.copies.isEmpty { copiesStrip }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(everything) { message in
                            AgentBubble(message: message, agent: agent(named: message.from), folders: folders).id(message.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if let typing { typingRow(typing) }
                        if runner.running, let who = runner.speaking { workingRow(who) }
                        if step == .done { doneCard }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: everything.count)
                }
                .onChange(of: everything.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: typing) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: step) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
            composer
        }
        .background(palette.background.ignoresSafeArea())
        .overlay(alignment: .bottom) { ApprovalCard().padding(.bottom, 80) }
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .task { await begin() }
        .onChange(of: runner.running) { running in
            guard !running, step == .working else { return }
            summary = runner.summary ?? ""
            // A lead that never closed the task still left its last words: the best summary there is.
            if summary.isEmpty, let last = work.last(where: { $0.kind == .agent && $0.from == lead.name && $0.text.count > 40 }) { summary = last.text }
            if summary.isEmpty, let last = work.last(where: { $0.kind == .agent && $0.text.count > 40 }) { summary = last.text }
            if !summary.isEmpty { writeFiles() }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { step = .done }
            if !summary.isEmpty { HapticsManager.shared.success() }
        }
    }

    // MARK: pieces

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { runner.stop(); onClose() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundColor(ink)
                    .frame(width: 40, height: 40).background(ink.opacity(0.08), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Close")
            VStack(alignment: .leading, spacing: 1) {
                Text(name.isEmpty ? "New project" : name).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(ink).lineLimit(1)
                Text(runner.running ? "Working…" : (step == .done ? "Finished" : "Your team")).font(.system(size: 11.5, weight: .semibold)).foregroundColor(ink.opacity(0.5))
            }
            Spacer()
            HStack(spacing: -8) {
                ForEach(team) { member in
                    AgentAvatar(agent: member, size: 34, animated: false)
                        .overlay(Circle().stroke(palette.background, lineWidth: 2))
                        .scaleEffect(runner.speaking == member.name || typing == member.name ? 1.2 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: runner.speaking)
                }
            }
        }
        .padding(.horizontal, 14).padding(.top, GameHubView.bannerTopInset - 6).padding(.bottom, 8)
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
            if let folder {
                Label("Work saved in the folder “\(folder)”", systemImage: "folder.fill").font(.system(size: 12.5, weight: .semibold)).foregroundColor(ink.opacity(0.6))
            } else if !filesNote.isEmpty {
                Text(filesNote).font(.system(size: 12)).foregroundColor(.orange)
            }
            if saved {
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
        .background(Color(red: 0.2, green: 0.7, blue: 0.4).opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        case .askIdea: return "The idea: who it is for and what it does"
        case .working: return "The team is working…"
        case .done: return "Ask the team for changes"
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
            projectID = project.id; name = project.name; idea = project.idea; summary = project.summary; saved = true; folder = project.folder
            messages = project.transcript; step = .done
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
        var task = "Product name: \(name)\nIdea: \(idea)\n\nWork as a team to turn this idea into a clear first plan: who it is for, the main features, a short tagline, and the first steps to build it. Split the work between the teammates by name, check each other's parts, and finish with a short summary for the person: when the work is done, close it yourself with done set to true and the summary filled in, and do not ask whether to continue. For small separate jobs (for example several taglines or a list of features to check) you can start copies of yourself, up to 10 at a time."
        if let change {
            archive += work
            task += "\n\nWhat the team came up with so far:\n\(summary)\n\nThe person now asks for this change: \(change)"
        }
        if step != .working { step = .working }
        focused = false
        summary = ""
        runner.runTeam(task: task, team: team, folder: nil, canEdit: false, store: agents)
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
                try store.write(folder, "copies/\(copy.parentName.lowercased())-copy-\(copy.number).md", content: "# \(copy.parentName) copy \(copy.number)\n\nJob: \(copy.task)\n\n\(copy.result)\n", by: copy.parentName)
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
