import SwiftUI

/// A folder an agent may work in, and whether it may change it.
struct FolderChoice: Equatable {
    var folder: String?
    var canEdit = true
}

/// The Agents page: the person's agents, a button to make a new one, and a
/// team task, where several agents talk to each other to get something done.
struct AgentsView: View {
    @ObservedObject var authState: AuthState
    @ObservedObject var store: AgentsStore
    @ObservedObject var folders: FolderStore
    /// Inside the Messages page, which already supplies the top spacing.
    var embedded = false

    @State private var chatting: SpacesAgent?
    @State private var showCreate = false
    @State private var showTeam = false
    @State private var showAccess = false
    @State private var showSignIn = false

    var body: some View {
        VStack(spacing: 0) {
            if !embedded { Color.clear.frame(height: GameHubView.bannerTopInset + 46) }
            if authState.spacechatUsername == nil {
                notice
            } else {
                header
                ScrollView {
                    VStack(spacing: 12) {
                        teamCard
                        ForEach(store.all) { agent in
                            Button { chatting = agent } label: { row(agent) }
                                .buttonStyle(PressableButtonStyle(scale: 0.98))
                                .contextMenu {
                                    if !agent.builtIn { Button("Delete agent", systemImage: "trash", role: .destructive) { store.delete(agent) } }
                                }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 120)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showSignIn) { SpacechatPhraseView(authState: authState) { showSignIn = false } }
        .sheet(isPresented: $showCreate) { DotEditorView(store: store, agent: nil) { showCreate = false } }
        .sheet(isPresented: $showAccess) { AccessView(store: store) { showAccess = false } }
        .fullScreenCover(item: $chatting) { agent in AgentChatView(agent: agent, store: store, folders: folders) { chatting = nil } }
        .fullScreenCover(isPresented: $showTeam) { TeamRoomView(store: store, folders: folders, preselected: nil) { showTeam = false } }
    }

    private var header: some View {
        HStack {
            Text("Agents").font(.system(size: 26, weight: .bold))
            Spacer()
            Button { showAccess = true } label: {
                Image(systemName: "lock.shield.fill").font(.system(size: 16, weight: .bold)).foregroundColor(.black.opacity(0.75))
                    .frame(width: 40, height: 40).background(Color.black.opacity(0.06), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Access and approvals")
            Button { showCreate = true } label: {
                Image(systemName: "plus").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                    .frame(width: 40, height: 40).background(DotRenderer.defaultColor, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("New agent")
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    private var teamCard: some View {
        Button { showTeam = true } label: {
            HStack(spacing: 14) {
                HStack(spacing: -10) {
                    ForEach(Array(store.all.prefix(3))) { AgentAvatar(agent: $0, size: 38) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Team task").font(.system(size: 17, weight: .bold))
                    Text("Give a task to several agents. They talk to each other and work on it, in your folders too.")
                        .font(.system(size: 13)).foregroundColor(.black.opacity(0.55)).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundColor(.black.opacity(0.3))
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.58, blue: 1.0).opacity(0.30), Color(red: 0.74, green: 0.45, blue: 0.98).opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color(red: 0.36, green: 0.58, blue: 1.0).opacity(0.35), lineWidth: 1))
        }.buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    private func row(_ agent: SpacesAgent) -> some View {
        HStack(spacing: 14) {
            AgentAvatar(agent: agent, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.name).font(.system(size: 17, weight: .bold)).foregroundColor(.black)
                    if agent.builtIn { Text("built in").font(.system(size: 10, weight: .bold)).foregroundColor(.black.opacity(0.4)) }
                }
                Text(store.messages(for: agent).last?.text ?? agent.role)
                    .font(.system(size: 13)).foregroundColor(.black.opacity(0.5)).lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            // Tinted with the agent's own colour, strongest where its avatar sits.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [agent.color.opacity(0.26), agent.color.opacity(0.07)], startPoint: .leading, endPoint: .trailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(agent.color.opacity(0.28), lineWidth: 1))
    }

    private var notice: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.3.fill").font(.system(size: 40)).foregroundColor(.black.opacity(0.7))
            Text("Agents").font(.system(size: 21, weight: .bold, design: .rounded))
            Text("Sign in to make agents, chat with them and let them work together.")
                .font(.system(size: 13)).foregroundColor(.black.opacity(0.55)).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Sign in") { showSignIn = true }
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 26).padding(.vertical, 14)
                .background(Color(white: 0.94), in: Capsule())
            Spacer()
        }
    }
}

// MARK: - Make an agent

// MARK: - Folder choice menu

struct FolderMenu: View {
    @Binding var choice: FolderChoice
    @ObservedObject var folders: FolderStore

    var body: some View {
        Menu {
            Button { choice.folder = nil } label: { Label("No folder", systemImage: choice.folder == nil ? "checkmark" : "") }
            ForEach(folders.folders, id: \.self) { name in
                Button { choice.folder = name } label: { Label(name, systemImage: choice.folder == name ? "checkmark" : "folder") }
            }
            if choice.folder != nil {
                Divider()
                Toggle("Allow editing", isOn: $choice.canEdit)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: choice.folder == nil ? "folder" : "folder.fill").font(.system(size: 14, weight: .bold))
                Text(choice.folder ?? "No folder").font(.system(size: 13, weight: .bold)).lineLimit(1)
                if choice.folder != nil { Image(systemName: choice.canEdit ? "pencil" : "eye").font(.system(size: 11, weight: .bold)) }
            }
            .foregroundColor(.black.opacity(0.75)).padding(.horizontal, 12).frame(height: 36)
            .background(Color.black.opacity(0.06), in: Capsule())
        }
    }
}

// MARK: - Chat bubbles shared by chat and team room

struct AgentBubble: View {
    let message: AgentMessage
    let agent: SpacesAgent?
    var folders: FolderStore
    private static let blue = Color(red: 0.23, green: 0.48, blue: 1.0)

    var body: some View {
        switch message.kind {
        case .user:
            HStack { Spacer(minLength: 50)
                Text(message.text).font(.system(size: 14.5)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Self.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case .agent:
            HStack(alignment: .top, spacing: 8) {
                AgentAvatar(id: agent?.id ?? "name-" + message.from, hue: agent?.hue ?? 0.6, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(message.from).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(.black.opacity(0.7))
                        if let to = message.to, to != "team" { Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundColor(.black.opacity(0.35)); Text(to).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.black.opacity(0.45)) }
                    }
                    Text(message.text).font(.system(size: 14.5)).foregroundColor(.black).textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                Spacer(minLength: 30)
            }
        case .change:
            let change = folders.changes.first { $0.id == message.changeID }
            HStack(spacing: 8) {
                Image(systemName: "pencil.line").font(.system(size: 13, weight: .bold)).foregroundColor(.black.opacity(0.55))
                Text("\(message.from): \(message.text)").font(.system(size: 12.5, weight: .semibold)).foregroundColor(.black.opacity(0.7)).lineLimit(2)
                Spacer(minLength: 6)
                if let change, !change.undone { Button("Undo") { folders.undo(change) }.font(.system(size: 12.5, weight: .bold)).foregroundColor(DotRenderer.defaultColor) }
                else if change?.undone == true { Text("Undone").font(.system(size: 12, weight: .semibold)).foregroundColor(.black.opacity(0.35)) }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color(red: 1, green: 0.96, blue: 0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .system:
            Text(message.text).font(.system(size: 12, weight: .semibold)).foregroundColor(.black.opacity(0.45))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 4)
        }
    }
}

// MARK: - Chat with one agent

struct AgentChatView: View {
    let agent: SpacesAgent
    @ObservedObject var store: AgentsStore
    @ObservedObject var folders: FolderStore
    let onClose: () -> Void

    @StateObject private var runner = AgentRunner()
    @State private var draft = ""
    @State private var choice = FolderChoice()
    @FocusState private var focused: Bool

    private var messages: [AgentMessage] { store.messages(for: agent) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundColor(.black)
                        .frame(width: 42, height: 42).background(Color.black.opacity(0.06), in: Circle())
                }.buttonStyle(.plain)
                AgentAvatar(agent: agent, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.name).font(.system(size: 17, weight: .bold))
                    Text(runner.running ? "working…" : agent.role).font(.system(size: 12)).foregroundColor(.black.opacity(0.5)).lineLimit(1)
                }
                Spacer()
                Menu {
                    Button("Clear chat", systemImage: "trash", role: .destructive) { store.clearChat(agent) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundColor(.black)
                        .frame(width: 42, height: 42).background(Color.black.opacity(0.06), in: Circle())
                }
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
            HStack { FolderMenu(choice: $choice, folders: folders); Spacer() }.padding(.horizontal, 14).padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty {
                            VStack(spacing: 8) {
                                AgentAvatar(agent: agent, size: 64)
                                Text("Chat with \(agent.name)").font(.system(size: 18, weight: .bold))
                                Text(choice.folder == nil ? "Pick a folder above to let \(agent.name) read and edit your files." : "\(agent.name) can work in \"\(choice.folder ?? "")\". Ask for a change.")
                                    .font(.system(size: 13)).foregroundColor(.black.opacity(0.5)).multilineTextAlignment(.center)
                            }.padding(.top, 50).padding(.horizontal, 30)
                        }
                        ForEach(messages) { AgentBubble(message: $0, agent: agent, folders: folders).id($0.id) }
                        if runner.running {
                            HStack(spacing: 8) { AgentAvatar(agent: agent, size: 28); ProgressView().controlSize(.small); Spacer() }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: runner.running) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message \(agent.name)", text: $draft, axis: .vertical)
                    .focused($focused).lineLimit(1...5).font(.system(size: 16)).padding(.horizontal, 16).padding(.vertical, 11)
                    .background(Color(white: 0.955), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                if focused {
                    Button { focused = false } label: {
                        Image(systemName: "keyboard.chevron.compact.down").font(.system(size: 17, weight: .medium)).foregroundColor(.black.opacity(0.45)).frame(width: 34, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Hide keyboard")
                }
                Button(action: send) {
                    Image(systemName: runner.running ? "stop.fill" : "arrow.up").font(.system(size: 16, weight: .bold))
                        .foregroundColor(canSend || runner.running ? .white : .black.opacity(0.3)).frame(width: 44, height: 44)
                        .background(canSend || runner.running ? DotRenderer.defaultColor : Color.black.opacity(0.08), in: Circle())
                }.buttonStyle(.plain).disabled(!canSend && !runner.running)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, focused ? 8 : 10 + GameHubView.homeIndicatorInset)
        }
        .overlay(alignment: .bottom) { ApprovalCard().padding(.bottom, 80) }
        .background(Color.white)
        .preferredColorScheme(.light)
        .onDisappear { runner.stop() }
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !runner.running }

    private func send() {
        if runner.running { runner.stop(); return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""; focused = false
        let mine = AgentMessage(kind: .user, from: "You", to: agent.name, text: text)
        store.append(mine, to: agent)
        runner.chat(agent: agent, message: text, history: store.messages(for: agent), folder: choice.folder, canEdit: choice.canEdit, store: store) { reply in
            store.append(reply, to: agent)
        }
    }
}

// MARK: - A team on a task

struct TeamRoomView: View {
    @ObservedObject var store: AgentsStore
    @ObservedObject var folders: FolderStore
    let preselected: String?
    let onClose: () -> Void

    @StateObject private var runner = AgentRunner()
    @State private var task = ""
    @State private var chosen: Set<String> = ["builtin-dots", "builtin-coder", "builtin-writer"]
    @State private var choice = FolderChoice()
    @State private var started = false
    @FocusState private var focused: Bool

    private var team: [SpacesAgent] { store.all.filter { chosen.contains($0.id) } }
    private func agent(named name: String) -> SpacesAgent? { store.all.first { $0.name == name } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: { runner.stop(); onClose() }) {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundColor(.black)
                        .frame(width: 42, height: 42).background(Color.black.opacity(0.06), in: Circle())
                }.buttonStyle(.plain)
                Text("Team task").font(.system(size: 20, weight: .bold))
                Spacer()
                if started && !runner.running {
                    Button("New task") { runner.reset(); started = false }.font(.system(size: 14, weight: .bold)).foregroundColor(DotRenderer.defaultColor)
                }
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
            if started { room } else { setup }
        }
        .overlay(alignment: .bottom) { ApprovalCard().padding(.bottom, 70) }
        .background(Color.white)
        .preferredColorScheme(.light)
        .onAppear { if let preselected { choice.folder = preselected } }
    }

    // Setup: the task, who is on the team, which folder
    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What should they do?").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.black.opacity(0.5))
                    TextField("For example: write a README for my project", text: $task, axis: .vertical)
                        .focused($focused).lineLimit(2...6).font(.system(size: 16)).padding(14)
                        .background(Color(white: 0.955), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    if focused { Button("Done") { focused = false }.font(.system(size: 14, weight: .bold)).foregroundColor(DotRenderer.defaultColor) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Who is on the team?").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.black.opacity(0.5))
                    Text("The first one in the list leads: it splits the work and hands parts to the others.").font(.system(size: 12)).foregroundColor(.black.opacity(0.45))
                    ForEach(store.all) { agent in
                        Button {
                            if chosen.contains(agent.id) { if chosen.count > 1 { chosen.remove(agent.id) } } else { chosen.insert(agent.id) }
                        } label: {
                            HStack(spacing: 12) {
                                AgentAvatar(agent: agent, size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(agent.name).font(.system(size: 15, weight: .bold)).foregroundColor(.black)
                                    Text(agent.role).font(.system(size: 12)).foregroundColor(.black.opacity(0.5)).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: chosen.contains(agent.id) ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                                    .foregroundColor(chosen.contains(agent.id) ? DotRenderer.defaultColor : .black.opacity(0.2))
                            }
                            .padding(10).background(Color(white: 0.965), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Folder to work in").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.black.opacity(0.5))
                    HStack { FolderMenu(choice: $choice, folders: folders); Spacer() }
                }
                Button(action: start) {
                    Text("Start").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(canStart ? DotRenderer.defaultColor : Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }.buttonStyle(.plain).disabled(!canStart)
            }
            .padding(.horizontal, 18).padding(.bottom, 40)
        }
    }

    private var canStart: Bool { !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func start() {
        focused = false
        started = true
        runner.runTeam(task: task.trimmingCharacters(in: .whitespacesAndNewlines), team: team, folder: choice.folder, canEdit: choice.canEdit, store: store)
    }

    // The room: agents talking to each other
    private var room: some View {
        VStack(spacing: 0) {
            HStack(spacing: -8) {
                ForEach(team) { agent in
                    AgentAvatar(agent: agent, size: 30)
                        .scaleEffect(runner.speaking == agent.name ? 1.18 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: runner.speaking)
                }
                Spacer()
                if let folder = choice.folder { Label(folder, systemImage: "folder.fill").font(.system(size: 12, weight: .bold)).foregroundColor(.black.opacity(0.55)) }
            }.padding(.horizontal, 18).padding(.bottom, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(runner.transcript) { AgentBubble(message: $0, agent: agent(named: $0.from), folders: folders).id($0.id) }
                        if runner.running, let who = runner.speaking {
                            HStack(spacing: 8) { AgentAvatar(id: agent(named: who)?.id ?? "name-" + who, hue: agent(named: who)?.hue ?? 0.6, size: 30); Text("\(who) is working…").font(.system(size: 12, weight: .semibold)).foregroundColor(.black.opacity(0.45)); ProgressView().controlSize(.small); Spacer() }
                        }
                        if let summary = runner.summary, !runner.running {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Done", systemImage: "checkmark.circle.fill").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(Color(red: 0.2, green: 0.7, blue: 0.4))
                                Text(summary).font(.system(size: 14.5)).foregroundColor(.black)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                             .background(Color(red: 0.9, green: 0.97, blue: 0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                }
                .onChange(of: runner.transcript.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
            if runner.running {
                Button { runner.stop() } label: {
                    Text("Stop").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 50).background(Color(red: 0.95, green: 0.3, blue: 0.38), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 10 + GameHubView.homeIndicatorInset / 2)
            }
        }
    }
}


// MARK: - Access and approvals

struct AccessToggles: View {
    @Binding var access: AgentAccess
    var body: some View {
        Toggle(isOn: $access.read) { label("Read files", "Look at, search and list files in a folder", "doc.text.magnifyingglass") }
        Toggle(isOn: $access.write) { label("Edit files", "Create, change and delete files (you approve each change)", "pencil.line") }
        Toggle(isOn: $access.run) { label("Run code", "Test algorithms with sandboxed JavaScript (you approve each run)", "chevron.left.forwardslash.chevron.right") }
        Toggle(isOn: $access.notes) { label("Share notes", "Add what it learns to the team's notes", "note.text") }
    }
    private func label(_ title: String, _ detail: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundColor(.secondary)
            }
        }
    }
}

/// What each agent may do, and when the person is asked. Like SpaceAILM's
/// tool lists and approval settings.
struct AccessView: View {
    @ObservedObject var store: AgentsStore
    @ObservedObject private var approvals = ApprovalCenter.shared
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ApprovalKind.allCases) { kind in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(kind.title).font(.system(size: 15, weight: .semibold))
                            Text(kind.detail).font(.system(size: 12)).foregroundColor(.secondary)
                            Picker(kind.title, selection: Binding(get: { approvals.mode(for: kind) }, set: { approvals.setMode($0, for: kind) })) {
                                ForEach(ApprovalMode.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                        }.padding(.vertical, 4)
                    }
                    Button("Back to the defaults") { approvals.resetToDefaults() }.font(.system(size: 14, weight: .semibold))
                } header: { Text("When to ask you") } footer: { Text("Reading files never asks. Everything an agent changes can be undone from the folder's changes list.") }

                ForEach(store.all) { agent in
                    Section {
                        AccessToggles(access: Binding(get: { store.all.first { $0.id == agent.id }?.access ?? agent.access }, set: { store.setAccess($0, for: agent) }))
                    } header: {
                        HStack(spacing: 8) { AgentAvatar(agent: agent, size: 20); Text(agent.name) }
                    }
                }

                Section {
                    if store.notes.isEmpty { Text("Nothing yet. Agents add what they learn here.").font(.system(size: 13)).foregroundColor(.secondary) }
                    ForEach(store.notes, id: \.self) { Text($0).font(.system(size: 13)) }
                    if !store.notes.isEmpty { Button("Clear notes", role: .destructive) { store.clearNotes() } }
                } header: { Text("Team notes") }
            }
            .navigationTitle("Access").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
        }.tint(.black).preferredColorScheme(.light)
    }
}

/// The question an agent asks before it changes a file or runs code.
struct ApprovalCard: View {
    @ObservedObject private var approvals = ApprovalCenter.shared

    var body: some View {
        if let request = approvals.current {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon(request.kind)).font(.system(size: 15, weight: .bold)).foregroundColor(DotRenderer.defaultColor)
                    Text("\(request.agent) wants to").font(.system(size: 13, weight: .bold)).foregroundColor(.black.opacity(0.55))
                    if approvals.queue.count > 1 { Text("· \(approvals.queue.count) waiting").font(.system(size: 12, weight: .semibold)).foregroundColor(.black.opacity(0.4)) }
                }
                Text(request.summary).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundColor(.black)
                if !request.detail.isEmpty {
                    ScrollView { Text(request.detail).font(.system(size: 12, design: .monospaced)).foregroundColor(.black.opacity(0.75)).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 130).padding(10).background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                HStack(spacing: 8) {
                    button("Allow", fill: DotRenderer.defaultColor, text: .white) { approvals.resolve(request.id, .once) }
                    button("Deny", fill: Color(red: 0.95, green: 0.3, blue: 0.38), text: .white) { approvals.resolve(request.id, .deny) }
                }
                HStack(spacing: 14) {
                    Button("Allow for this session") { approvals.resolve(request.id, .session) }
                    Button("Always allow") { approvals.resolve(request.id, .always) }
                }.font(.system(size: 12.5, weight: .bold)).foregroundColor(DotRenderer.defaultColor)
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DotRenderer.defaultColor.opacity(0.35), lineWidth: 2.5))
            .padding(.horizontal, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: request.id)
        }
    }

    private func icon(_ kind: ApprovalKind) -> String {
        switch kind { case .change: return "pencil.line"; case .delete: return "trash"; case .run: return "chevron.left.forwardslash.chevron.right" }
    }

    private func button(_ title: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundColor(text)
                .frame(maxWidth: .infinity).frame(height: 44).background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.plain)
    }
}
