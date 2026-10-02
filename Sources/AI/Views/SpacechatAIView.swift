import SwiftUI

/// The Spacechat AI page, laid out like Spacechat's own AI tab: conversation
/// history and a new-chat button on top, "What can I help with?" when empty,
/// and a composer with a voice-chat button. Dots is the only agent here.
///
/// Talks to the same assistant the Spacechat app does (`POST
/// /api/guide/message`); history stays on this device per account.
struct SpacechatAIView: View {
    @ObservedObject var authState: AuthState
    @ObservedObject var player: PlayerState
    var save: () -> Void

    private static let blue = Color(red: 0.23, green: 0.48, blue: 1.0)
    private static let field = Color(white: 0.955)

    @StateObject private var store = SpacesAIStore()
    @State private var activeThreadID: String?
    @State private var showHistory = false
    @State private var historySearch = ""
    @State private var showSignIn = false
    @State private var showVoice = false
    @State private var mode = "Chat"
    @State private var generatedDot: NamedCustomDot?
    @State private var generatedUniverse: CustomUniverse?
    @State private var savedDesignID: UUID?
    @State private var draft = ""
    @State private var isThinking = false
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    private var messages: [SpacesAIMessage] { store.thread(activeThreadID)?.messages ?? [] }
    private var signedIn: Bool { authState.spacechatUsername != nil }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Color.clear.frame(height: GameHubView.bannerTopInset + 46)
                if !signedIn {
                    signedOutNotice
                } else {
                    header
                    if messages.isEmpty && generatedDot == nil && generatedUniverse == nil { emptyState } else { conversation }
                    composer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)

            if showHistory {
                historyScreen
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: showHistory)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showSignIn) {
            SpacechatPhraseView(authState: authState) { showSignIn = false }
        }
        .fullScreenCover(isPresented: $showVoice) {
            NativeAIVoiceScreen(
                persona: "spaceai",
                agentName: "Dots",
                greeting: messages.last(where: { $0.role == "assistant" })?.text ?? "",
                api: SpacesVoiceAPI(),
                sessionToken: "",
                sendTurn: { text in await sendVoiceTurn(text) },
                onClose: { typeText in
                    showVoice = false
                    if typeText { inputFocused = true }
                }
            )
        }
        .task(id: authState.spacechatUsername) {
            store.configure(account: authState.spacechatUsername)
            activeThreadID = nil; draft = ""; generatedDot = nil; generatedUniverse = nil; errorMessage = nil
        }
    }

    // MARK: - Pieces

    private var signedOutNotice: some View {
        VStack(spacing: 12) {
            Spacer()
            DotsAgentAvatar(size: 72)
            Text("Spacechat AI")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Sign in with Apple or a Spacechat phrase to chat with the Dots agent.")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Sign in") { showSignIn = true }
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 26).padding(.vertical, 14)
                .background(Color(white: 0.94), in: Capsule())
            Spacer()
        }
    }

    private var header: some View {
        HStack {
            iconButton("line.3.horizontal", label: "Conversation history") { inputFocused = false; showHistory = true }
            Spacer()
            HStack(spacing: 8) {
                DotsAgentAvatar(size: 24)
                Text("Dots").font(.system(size: 17, weight: .heavy, design: .rounded))
            }
            Spacer()
            iconButton("plus", label: "New conversation") { newConversation() }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    private func iconButton(_ name: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.black.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// The starting choices: each has its own colour and its own shaped dot, so the page reads as a set of
    /// different things to try rather than one list.
    private struct Option: Identifiable {
        let id: String
        let title: String
        let caption: String
        let shape: DotShape
        let hue: Double
        let mode: String
        let prompt: String?
    }

    private static let options: [Option] = [
        Option(id: "grow", title: "Grow faster", caption: "Tips to level up", shape: .star5, hue: 0.60, mode: "Chat", prompt: "How do I grow faster in Spaces?"),
        Option(id: "dot", title: "Design a dot", caption: "A new look for you", shape: .heart, hue: 0.92, mode: "Dot", prompt: "A glossy ocean-blue dot with silver stars"),
        Option(id: "universe", title: "Design a universe", caption: "Your own world", shape: .hexagon, hue: 0.76, mode: "Universe", prompt: "A sunset world with a warm golden grid"),
        Option(id: "eat", title: "How eating works", caption: "Merge and win", shape: .flower5, hue: 0.36, mode: "Chat", prompt: "Explain how eating and merging works in Spaces."),
        Option(id: "shapes", title: "Dot shapes", caption: "What each one is", shape: .diamond, hue: 0.50, mode: "Chat", prompt: "What are the different dot shapes and how do I get them?"),
        Option(id: "challenge", title: "Daily challenge", caption: "Something to try", shape: .bolt, hue: 0.10, mode: "Chat", prompt: "Give me a fun challenge to try in my next match.")
    ]

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 8) {
                ZStack {
                    ForEach(Array(Self.options.enumerated()), id: \.element.id) { index, option in
                        FloatingDot(shape: option.shape, hue: option.hue, index: index)
                    }
                    DotsAgentAvatar(size: 92)
                }
                .frame(height: 150).padding(.top, 14)
                Text("What can I help with?")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                Text("Ask Dots anything about Spaces, or have it design a dot or a universe for you.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black.opacity(0.5))
                    .multilineTextAlignment(.center).padding(.horizontal, 10)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Self.options) { option in optionCard(option) }
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 18).padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture { inputFocused = false }
    }

    private func optionCard(_ option: Option) -> some View {
        let tint = Color(hue: option.hue, saturation: 0.5, brightness: 1.0)
        let ink = Color(hue: option.hue, saturation: 0.8, brightness: 0.42)
        return Button {
            mode = option.mode
            draft = option.prompt ?? option.title
            if option.mode == "Chat" { send() } else { inputFocused = true }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ShapedDot(shape: option.shape, hue: option.hue, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(ink)
                    Text(option.caption).font(.system(size: 12, weight: .medium)).foregroundColor(ink.opacity(0.65))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(tint.opacity(0.32), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .disabled(isThinking)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { message in
                        bubble(message).id(message.id)
                    }
                    if generatedDot != nil || generatedUniverse != nil { designPreview.id("design") }
                    if isThinking { typingIndicator.id("thinking") }
                    if let errorMessage {
                        Text(errorMessage).font(.system(size: 12)).foregroundColor(.red.opacity(0.85)).padding(.horizontal, 4)
                    }
                    if !player.profile.customDotLibrary.isEmpty || !player.profile.customUniverses.isEmpty { creationsLibrary }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { inputFocused = false }
            .onChange(of: messages.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: isThinking) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    private func bubble(_ message: SpacesAIMessage) -> some View {
        let mine = message.role == "user"
        return HStack(alignment: .top, spacing: 8) {
            if mine { Spacer(minLength: 48) } else { DotsAgentAvatar(size: 30) }
            Text(message.text)
                .font(.system(size: 15))
                .foregroundColor(mine ? .white : .black)
                .padding(.horizontal, 15).padding(.vertical, 11)
                .background {
                    if mine {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.58, blue: 1.0), Self.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Self.field)
                    }
                }
                .textSelection(.enabled)
            if !mine { Spacer(minLength: 48) }
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            TypingDots()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Self.field, in: Capsule())
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if mode != "Chat" {
                HStack(spacing: 6) {
                    Image(systemName: mode == "Dot" ? "circle.hexagongrid.fill" : "sparkles").font(.system(size: 12, weight: .bold))
                    Text(mode == "Dot" ? "Designing a dot" : "Designing a universe").font(.system(size: 12, weight: .semibold))
                    Button { mode = "Chat" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 14)) }.buttonStyle(.plain)
                }
                .foregroundColor(Self.blue).padding(.horizontal, 12).padding(.vertical, 6)
                .background(Self.blue.opacity(0.12), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button("Chat with Dots") { mode = "Chat" }
                    Button("Design a dot") { mode = "Dot" }
                    Button("Design a universe") { mode = "Universe" }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 26)).foregroundColor(.black.opacity(0.35)).frame(width: 32, height: 44)
                }
                .accessibilityLabel("Chat or design")

                TextField(mode == "Chat" ? "Message Dots" : "Describe your \(mode.lowercased())…", text: $draft, axis: .vertical)
                    .focused($inputFocused)
                    .font(.system(size: 16))
                    .tint(Self.blue)
                    .lineLimit(1...6)
                    .padding(.vertical, 12)

                if inputFocused {
                    Button { inputFocused = false } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 17, weight: .medium)).foregroundColor(.black.opacity(0.45)).frame(width: 36, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Hide keyboard")
                } else {
                    Button { showVoice = true } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 17, weight: .medium)).foregroundColor(.black.opacity(0.45)).frame(width: 36, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel("Start voice conversation")
                }

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(canSend ? .white : .black.opacity(0.35))
                        .frame(width: 38, height: 38)
                        .background(canSend ? Self.blue : Color.black.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain).disabled(!canSend).frame(height: 44).accessibilityLabel("Send message")
            }
            .padding(.horizontal, 10)
            .background(Self.field, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(inputFocused ? Self.blue.opacity(0.55) : Color.black.opacity(0.08), lineWidth: inputFocused ? 1.5 : 1))
            .padding(.horizontal, 14)
        }
        .padding(.top, 6)
        .padding(.bottom, inputFocused ? 10 : GameHubView.homeIndicatorInset + 10)
        .animation(.easeOut(duration: 0.16), value: inputFocused)
    }

    // MARK: - History

    private var historySections: [(title: String, threads: [SpacesAIThread])] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = store.threads.filter { !$0.messages.isEmpty && (query.isEmpty || $0.title.lowercased().contains(query)) }
            .sorted { $0.updatedAt > $1.updatedAt }
        let calendar = Calendar.current
        var buckets: [(title: String, threads: [SpacesAIThread])] = [("Today", []), ("Yesterday", []), ("Previous 7 days", []), ("Earlier", [])]
        for thread in filtered {
            let date = Date(timeIntervalSince1970: thread.updatedAt / 1000)
            let index: Int
            if calendar.isDateInToday(date) { index = 0 }
            else if calendar.isDateInYesterday(date) { index = 1 }
            else if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 { index = 2 }
            else { index = 3 }
            buckets[index].threads.append(thread)
        }
        return buckets.filter { !$0.threads.isEmpty }
    }

    private var historyScreen: some View {
        let sections = historySections
        return VStack(spacing: 0) {
            Color.clear.frame(height: GameHubView.bannerTopInset + 46)
            HStack {
                iconButton("chevron.left", label: "Close conversations") { showHistory = false }
                Spacer()
                iconButton("square.and.pencil", label: "New conversation") { newConversation() }
            }.padding(.horizontal, 16).padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 14) {
                Text("Conversations").font(.system(size: 32, weight: .bold))
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundColor(.black.opacity(0.45))
                    TextField("Search conversations", text: $historySearch)
                        .font(.system(size: 15, weight: .medium)).autocorrectionDisabled().submitLabel(.search)
                    if !historySearch.isEmpty {
                        Button { historySearch = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.black.opacity(0.4)) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).frame(height: 44).background(Color.black.opacity(0.06), in: Capsule())
            }.padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 12)

            if sections.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 22)).foregroundColor(.black.opacity(0.45))
                        .frame(width: 60, height: 60).background(Color.black.opacity(0.06), in: Circle())
                    Text(historySearch.isEmpty ? "No conversations yet" : "No matching conversations").font(.system(size: 16, weight: .semibold))
                    Text(historySearch.isEmpty ? "Start a new one and it will show up here." : "Try a different word.")
                        .font(.system(size: 13)).foregroundColor(.black.opacity(0.5))
                    Spacer(); Spacer()
                }.frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(sections, id: \.title) { section in
                        Section(header: Text(section.title).font(.system(size: 13, weight: .bold)).foregroundColor(.black.opacity(0.5))) {
                            ForEach(section.threads) { thread in
                                Button {
                                    activeThreadID = thread.id; showHistory = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(thread.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.black).lineLimit(1)
                                        Text(thread.messages.last?.text ?? "").font(.system(size: 13)).foregroundColor(.black.opacity(0.5)).lineLimit(1)
                                    }
                                }
                                .swipeActions { Button(role: .destructive) {
                                    store.delete(thread.id); if activeThreadID == thread.id { activeThreadID = nil }
                                } label: { Label("Delete", systemImage: "trash") } }
                            }
                        }
                    }
                }.listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    // MARK: - Sending

    private func newConversation() {
        activeThreadID = nil; showHistory = false; draft = ""; errorMessage = nil
        generatedDot = nil; generatedUniverse = nil; mode = "Chat"
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        draft = ""
        errorMessage = nil
        let thread = store.thread(activeThreadID) ?? store.create()
        activeThreadID = thread.id
        store.append(thread.id, role: "user", text: text)
        isThinking = true
        let account = authState.spacechatUsername
        let requestedMode = mode
        let history = store.history(thread.id)
        Task {
            defer { isThinking = false }
            do {
                let prompt = requestedMode == "Chat" ? text : creationPrompt(text, mode: requestedMode)
                let reply = try await SpacechatService.askSpacechatAI(prompt, history: requestedMode == "Chat" ? history : [])
                guard account == authState.spacechatUsername else { return }
                if requestedMode == "Chat" {
                    store.append(thread.id, role: "assistant", text: reply)
                } else {
                    let design = try SpacesGeneratedDesign.parse(reply)
                    if requestedMode == "Dot" { generatedDot = try design.dot(); generatedUniverse = nil }
                    else { generatedUniverse = try design.universe(); generatedDot = nil }
                    savedDesignID = nil
                    store.append(thread.id, role: "assistant", text: "Your design is ready. Preview it below, then save and equip it when you're happy with it.")
                }
            } catch {
                guard account == authState.spacechatUsername else { return }
                draft = text
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Dots couldn't answer that. Please try again."
            }
        }
    }

    /// A spoken turn: same thread as typing, returns the reply so it is read aloud.
    private func sendVoiceTurn(_ text: String) async -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        let thread = store.thread(activeThreadID) ?? store.create()
        activeThreadID = thread.id
        store.append(thread.id, role: "user", text: clean)
        let reply: String
        do {
            reply = try await SpacechatService.askSpacechatAI(clean, voice: true, history: store.history(thread.id))
        } catch {
            reply = (error as? LocalizedError)?.errorDescription ?? "I couldn't reach Spacechat just now. Try again in a moment."
        }
        store.append(thread.id, role: "assistant", text: reply)
        return reply
    }
}

/// Dots, the one agent on this page: a blue dot with eyes.
struct DotsAgentAvatar: View {
    var size: CGFloat = 32
    var body: some View { AgentAvatar(id: "builtin-dots", hue: 0.60, size: size) }
}

private struct TypingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.black.opacity(phase == i ? 0.55 : 0.2)).frame(width: 6, height: 6)
            }
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

extension SpacechatAIView {
    private func creationPrompt(_ text: String, mode: String) -> String {
        let schema = mode == "Dot"
            ? "{\"name\":\"Short name\",\"base\":[0.2,0.5,0.9],\"stickers\":[{\"symbol\":\"star.fill\",\"x\":-0.4,\"y\":0.4,\"scale\":0.35,\"color\":[1,1,1]}]}"
            : "{\"name\":\"Short name\",\"background\":[0.1,0.15,0.3],\"grid\":[0.5,0.7,0.9],\"stars\":true}"
        return """
        Design a cosmetic \(mode.lowercased()) for Spaces, the dot game. Return ONLY valid JSON matching this example: \(schema)
        Colors are three finite RGB numbers from 0 to 1. Name must be 1–60 characters.
        For dots use 1–8 stickers, positions -0.65 to 0.65, scale 0.12 to 0.65. Place decorations away from the upper-center eyes.
        Allowed symbols: \(DotSticker.catalog.joined(separator: ", ")).
        Universes change background, grid color and starfield only; do not promise new game mechanics.
        User's design description: \(text)
        """
    }

    private var designPreview: some View {
        VStack(spacing: 14) {
            if let dot = generatedDot {
                Canvas { context, size in
                    DotRenderer.drawPlayer(context, center: CGPoint(x: size.width / 2, y: size.height / 2), radius: 48,
                                           color: dot.artwork.baseColor.color, stretch: 0, angle: .zero, lookDirection: .zero,
                                           time: 0, reduceMotion: true, customDot: dot.artwork)
                }.frame(height: 160)
                Text(dot.name).font(.headline)
            }
            if let universe = generatedUniverse {
                Canvas { context, size in
                    WorldBackground.draw(context, screenSize: size, cameraOffset: .zero, palette: universe.palette, reduceMotion: true)
                }.frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 18))
                Text(universe.name).font(.headline)
            }
            Button(savedDesignID == nil ? "Save & equip" : "Saved and equipped") {
                if let dot = generatedDot {
                    if !player.profile.customDotLibrary.contains(where: { $0.id == dot.id }) { player.profile.customDotLibrary.append(dot) }
                    player.profile.customDot = dot.artwork; player.profile.usesCustomDot = true; savedDesignID = dot.id
                }
                if let universe = generatedUniverse {
                    if !player.profile.customUniverses.contains(where: { $0.id == universe.id }) { player.profile.customUniverses.append(universe) }
                    player.profile.selectedCustomUniverseID = universe.id; savedDesignID = universe.id
                }
                save()
            }.font(.subheadline.weight(.semibold)).padding(14).frame(maxWidth: .infinity)
                .foregroundColor(.white).background(Color.black, in: Capsule()).disabled(savedDesignID != nil)
        }.padding(18).background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 22))
    }

    private var creationsLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your creations").font(.headline)
            ForEach(player.profile.customDotLibrary) { dot in
                HStack {
                    Circle().fill(dot.artwork.baseColor.color).frame(width: 24, height: 24)
                    Text(dot.name).font(.subheadline)
                    Spacer()
                    Button("Equip dot") { player.profile.customDot = dot.artwork; player.profile.usesCustomDot = true; save() }.font(.caption.weight(.semibold))
                }
            }
            ForEach(player.profile.customUniverses) { universe in
                HStack {
                    Circle().fill(universe.background.color).frame(width: 24, height: 24)
                    Text(universe.name).font(.subheadline)
                    Spacer()
                    Button("Equip universe") { player.profile.selectedCustomUniverseID = universe.id; save() }.font(.caption.weight(.semibold))
                }
            }
        }.padding(.vertical, 16)
    }
}


/// A dot of one of the game's shapes: glossy fill, a strong border, no shadow.
struct ShapedDot: View {
    let shape: DotShape
    let hue: Double
    var size: CGFloat = 40
    var body: some View {
        let light = Color(hue: hue, saturation: 0.4, brightness: 1.0)
        let mid = Color(hue: hue, saturation: 0.72, brightness: 0.96)
        let dark = Color(hue: hue, saturation: 0.85, brightness: 0.6)
        Canvas { ctx, s in
            let r = min(s.width, s.height) / 2 - size * 0.05
            let path = DotShape.path(shape, radius: r).offsetBy(dx: s.width / 2, dy: s.height / 2)
            ctx.fill(path, with: .linearGradient(Gradient(colors: [light, mid]), startPoint: CGPoint(x: s.width * 0.25, y: 0), endPoint: CGPoint(x: s.width * 0.8, y: s.height)))
            ctx.stroke(path, with: .color(dark), style: StrokeStyle(lineWidth: max(1.5, size * 0.06), lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Small dots drifting around the page's hero, each on its own slow loop. They stay still with Reduce Motion on.
private struct FloatingDot: View {
    let shape: DotShape
    let hue: Double
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let angle = Double(index) / 6 * 2 * .pi - .pi / 2
        let radius: CGFloat = 108
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let wobble = CGFloat(sin(t * 0.9 + Double(index) * 1.3)) * 5
            ShapedDot(shape: shape, hue: hue, size: 24 + CGFloat(index % 3) * 4)
                .offset(x: cos(angle) * radius + wobble, y: sin(angle) * radius * 0.66 + CGFloat(cos(t * 0.8 + Double(index))) * 4)
        }
    }
}
