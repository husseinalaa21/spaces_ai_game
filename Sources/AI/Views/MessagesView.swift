import SwiftUI

/// The Messages page, in the game's white frame.
///
/// Scoped to what a game needs: find someone by their Spacechat username,
/// read the thread, and reply. It uses the same endpoints the Spacechat
/// client does — `/api/user-db` to resolve a username and load the thread,
/// `/api/send-message` to send — so a conversation started here is the same
/// conversation in Spacechat.
struct MessagesView: View {
    @ObservedObject var authState: AuthState

    @State private var peer: SpacechatService.Peer?
    @State private var messages: [SpacechatService.Message] = []
    @State private var usernameQuery = ""
    @State private var draft = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Clears the banner floating above.
            Color.clear.frame(height: 56)

            if authState.spacechatUsername == nil {
                signedOutNotice
            } else if let peer {
                thread(with: peer)
            } else {
                finder
            }
        }
        .background(Color.white.ignoresSafeArea())
    }

    private var signedOutNotice: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 34))
                .foregroundColor(.black.opacity(0.3))
            Text("Messages")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Sign in with a Spacechat phrase to message other players.")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Finding someone

    private var finder: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Messages")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text("Enter a Spacechat username to open a chat. It's the same conversation you'd see in Spacechat.")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.55))

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("@").foregroundColor(.black.opacity(0.35))
                    TextField("username", text: $usernameQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(openConversation)
                        .submitLabel(.go)
                }
                .font(.system(size: 15))
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 12))

                Button(action: openConversation) {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(canOpen ? Color.black : Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canOpen)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.85))
            }

            Spacer()
        }
        .padding(20)
    }

    private var canOpen: Bool {
        !usernameQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    // MARK: - Thread

    private func thread(with peer: SpacechatService.Peer) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    self.peer = nil
                    messages = []
                    errorMessage = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black.opacity(0.6))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(peer.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("@\(peer.username)")
                        .font(.system(size: 11))
                        .foregroundColor(.black.opacity(0.45))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if messages.isEmpty {
                            Text("No messages yet. Say something.")
                                .font(.system(size: 13))
                                .foregroundColor(.black.opacity(0.4))
                                .padding(.vertical, 12)
                        }
                        ForEach(messages) { message in
                            bubble(message).id(message.id)
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.85))
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) { _ in
                    guard let last = messages.last else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            composer(peer)
        }
    }

    private func bubble(_ message: SpacechatService.Message) -> some View {
        HStack {
            if !message.incoming { Spacer(minLength: 40) }
            VStack(alignment: message.incoming ? .leading : .trailing, spacing: 2) {
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundColor(message.incoming ? .black : .white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(message.incoming ? Color(white: 0.94) : Color.black,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if !message.timeLabel.isEmpty {
                    Text(message.timeLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.black.opacity(0.35))
                }
            }
            if message.incoming { Spacer(minLength: 40) }
        }
    }

    private func composer(_ peer: SpacechatService.Peer) -> some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 20))

            Button { send(to: peer) } label: {
                Group {
                    if isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(canSend ? Color.black : Color.black.opacity(0.25), in: Circle())
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    // MARK: - Actions

    private func openConversation() {
        guard canOpen else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let (found, thread) = try await SpacechatService.openConversation(username: usernameQuery)
                peer = found
                messages = thread
                usernameQuery = ""
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't open that chat."
            }
            isLoading = false
        }
    }

    private func send(to peer: SpacechatService.Peer) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        isSending = true
        errorMessage = nil
        Task {
            do {
                messages = try await SpacechatService.send(text, to: peer)
                HapticsManager.shared.impact(.light)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't send that."
                // Put the text back rather than losing it to a failed send.
                draft = text
            }
            isSending = false
        }
    }
}
