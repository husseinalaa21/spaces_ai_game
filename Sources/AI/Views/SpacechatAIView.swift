import SwiftUI

/// The Spacechat AI page, in the game's own white frame rather than the
/// Spacechat app's dark one.
///
/// Talks to the same assistant the Spacechat app does — `POST
/// /api/guide/message`, whose server-side system prompt opens "You are
/// Spacechat AI". The server keeps conversation history against the session,
/// so each turn sends only the new message.
struct SpacechatAIView: View {
    @ObservedObject var authState: AuthState
    @ObservedObject var player: PlayerState
    var save: () -> Void
    @State private var mode = "Chat"
    @State private var showSignIn = false
    @State private var generatedDot: NamedCustomDot?
    @State private var generatedUniverse: CustomUniverse?
    @State private var savedDesignID: UUID?

    private struct Turn: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let fromAI: Bool
    }

    @State private var turns: [Turn] = []
    @State private var draft = ""
    @State private var isThinking = false
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Clears the banner floating above, which now sits below the
            // device's own top inset.
            Color.clear.frame(height: GameHubView.bannerTopInset + 46)

            if authState.spacechatUsername == nil {
                signedOutNotice
            } else {
                Picker("Spacechat AI mode", selection: $mode) {
                    Text("Chat").tag("Chat")
                    Text("Create dot").tag("Dot")
                    Text("Create universe").tag("Universe")
                }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 12).disabled(isThinking)
                conversation
                composer
            }
        }
        // Fills the display end to end; the composer below keeps its own
        // clearance from the home indicator.
        .background(Color.white)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showSignIn) {
            SpacechatPhraseView(authState: authState) { showSignIn = false }
        }
        .onChange(of: authState.spacechatUsername) { _ in
            turns = []; draft = ""; generatedDot = nil; generatedUniverse = nil
        }
    }

    private var signedOutNotice: some View {
        VStack(spacing: 12) {
            Spacer()
            SpacechatMark(size: 44)
            Text("Spacechat AI")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Sign in with a Spacechat phrase to chat with Spacechat AI.")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Sign in with Spacechat") { showSignIn = true }
                .font(.subheadline.weight(.semibold)).padding(15)
                .background(Color(white: 0.94), in: Capsule())
            Spacer()
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if turns.isEmpty {
                        emptyState
                    }
                    ForEach(turns) { turn in
                        bubble(turn)
                            .id(turn.id)
                    }
                    if generatedDot != nil || generatedUniverse != nil { designPreview }
                    if !player.profile.customDotLibrary.isEmpty || !player.profile.customUniverses.isEmpty { creationsLibrary }
                    if isThinking {
                        typingIndicator.id("thinking")
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.85))
                            .padding(.horizontal, 4)
                    }
                }
                .padding(16)
            }
            // Keeps the newest turn in view as the conversation grows.
            .onChange(of: turns.count) { _ in
                guard let last = turns.last else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: isThinking) { thinking in
                guard thinking else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("thinking", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SpacechatMark(size: 20)
                Text("Spacechat AI")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            Text(mode == "Chat" ? "Chat with Spacechat AI, or create a dot and a universe of your own." : "Describe your \(mode.lowercased()). Try icy blue with silver stars, or a sunset world with a warm golden grid.")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.5))
        }
        .padding(.vertical, 12)
    }

    private func bubble(_ turn: Turn) -> some View {
        HStack {
            if !turn.fromAI { Spacer(minLength: 40) }
            Text(turn.text)
                .font(.system(size: 14))
                .foregroundColor(turn.fromAI ? .black : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(turn.fromAI ? Color(white: 0.94) : Color.black,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .textSelection(.enabled)
            if turn.fromAI { Spacer(minLength: 40) }
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(Color.black.opacity(0.28)).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(white: 0.94), in: Capsule())
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(mode == "Chat" ? "Message Spacechat AI" : "Describe your \(mode.lowercased())…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 20))
                .focused($inputFocused)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(canSend ? Color.black : Color.black.opacity(0.25), in: Circle())
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        // Keeps the send button clear of the home indicator now that the
        // page itself runs under it.
        .padding(.bottom, GameHubView.homeIndicatorInset + 10)
        .background(Color.white)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        draft = ""
        errorMessage = nil
        turns.append(Turn(text: text, fromAI: false))
        isThinking = true
        let account = authState.spacechatUsername
        let requestedMode = mode
        Task {
            defer { isThinking = false }
            do {
                let prompt = requestedMode == "Chat" ? text : creationPrompt(text, mode: requestedMode)
                let reply = try await SpacechatService.askSpacechatAI(prompt)
                guard account == authState.spacechatUsername else { return }
                if requestedMode == "Chat" { turns.append(Turn(text: reply, fromAI: true)) }
                else {
                    let design = try SpacesGeneratedDesign.parse(reply)
                    if requestedMode == "Dot" { generatedDot = try design.dot(); generatedUniverse = nil }
                    else { generatedUniverse = try design.universe(); generatedDot = nil }
                    savedDesignID = nil
                    turns.append(Turn(text: "Your design is ready. Preview it below, then save and equip it when you're happy with it.", fromAI: true))
                }
            } catch {
                guard account == authState.spacechatUsername else { return }
                draft = text
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Spacechat AI is unavailable right now."
            }
            isThinking = false
        }
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
