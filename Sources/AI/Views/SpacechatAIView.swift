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
                conversation
                composer
            }
        }
        // Fills the display end to end; the composer below keeps its own
        // clearance from the home indicator.
        .background(Color.white)
        .ignoresSafeArea()
    }

    private var signedOutNotice: some View {
        VStack(spacing: 12) {
            Spacer()
            SpacechatMark(size: 40).foregroundColor(.black.opacity(0.35))
            Text("Spacechat AI")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Sign in with a Spacechat phrase to chat with Spacechat AI.")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
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
                SpacechatMark(size: 20).foregroundColor(.black)
                Text("Spacechat AI")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            Text("Ask anything — about Spacechat, about this game, or about nothing in particular.")
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
            TextField("Message Spacechat AI", text: $draft, axis: .vertical)
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
        guard !text.isEmpty else { return }
        draft = ""
        errorMessage = nil
        turns.append(Turn(text: text, fromAI: false))
        isThinking = true
        Task {
            do {
                let reply = try await SpacechatService.askSpacechatAI(text)
                turns.append(Turn(text: reply, fromAI: true))
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Spacechat AI is unavailable right now."
            }
            isThinking = false
        }
    }
}
