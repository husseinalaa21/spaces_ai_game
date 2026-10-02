import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import AVFoundation

struct MessagesView: View {
    @ObservedObject var authState: AuthState
    @ObservedObject var inbox: SpacesInbox
    /// Agents live on this page too: a Chats | Agents switch under the banner.
    @ObservedObject var agents: AgentsStore
    @ObservedObject var folders: FolderStore
    @State private var section = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var query = ""
    @State private var results: [SpacechatService.Peer] = []
    @State private var searching = false
    @State private var searchError: String?
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var showSignIn = false
    @State private var sheet: InboxSheet?
    @State private var keyboardUp = false
    @ObservedObject private var friends = FriendsStore.shared
    @State private var deleteIDs: Set<String> = []
    @State private var opening = false
    @FocusState private var searchFocused: Bool

    private enum InboxSheet: String, Identifiable {
        case compose, group, qr, scan, invite
        var id: String { rawValue }
    }
    private let filters = ["All Messages", "Messages", "Groups", "Unread", "Archive", "Requests"]
    private var signedIn: Bool { authState.spacechatUsername != nil && !inbox.needsSignIn }
    private var active: SpacechatService.Conversation? { inbox.conversations.first { $0.id == inbox.activeID } }
    private var visible: [SpacechatService.Conversation] {
        inbox.conversations.filter { chat in
            let matchesFilter: Bool
            switch inbox.filter {
            case "Archive": matchesFilter = chat.archived
            case "Unread": matchesFilter = !chat.archived && !chat.isRequest && chat.unread > 0
            case "Groups": matchesFilter = !chat.archived && chat.isGroup
            case "Messages": matchesFilter = !chat.archived && !chat.isGroup && !chat.isRequest
            case "Requests": matchesFilter = !chat.archived && chat.isRequest
            default: matchesFilter = !chat.archived && !chat.isRequest
            }
            return matchesFilter && (query.isEmpty || chat.peer.displayName.localizedCaseInsensitiveContains(query) || chat.peer.username.localizedCaseInsensitiveContains(query) || chat.messages.last?.text.localizedCaseInsensitiveContains(query) == true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: GameHubView.bannerTopInset + 52)
            if !signedIn { signInNotice }
            else if let active { thread(active) }
            else {
                sectionSwitch
                if section == 0 { inboxPage }
                else { AgentsView(authState: authState, store: agents, folders: folders, embedded: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .foregroundColor(.black)
        .tint(.black)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showSignIn) {
            SpacechatPhraseView(authState: authState) {
                inbox.needsSignIn = false
                inbox.error = nil
                showSignIn = false
                Task { await inbox.refresh() }
            }
            .preferredColorScheme(.light)
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .compose:
                SpacesNewChatSheet(inbox: inbox, mode: .message) { sheet = nil }
            case .group:
                SpacesNewChatSheet(inbox: inbox, mode: .group) { sheet = nil }
            case .invite:
                if let active { SpacesNewChatSheet(inbox: inbox, mode: .invite(active)) { sheet = nil } }
            case .qr:
                SpacesProfileQR(username: authState.spacechatUsername ?? "")
            case .scan:
                SpacesQRScanner { value in
                    sheet = nil
                    open(value)
                }
            }
        }
        .confirmationDialog("Delete these conversations from this device?", isPresented: Binding(get: { !deleteIDs.isEmpty }, set: { if !$0 { deleteIDs = [] } }), titleVisibility: .visible) {
            Button("Delete from this device", role: .destructive) {
                inbox.delete(deleteIDs); deleteIDs = []; selected = []; selecting = false
            }
            Button("Cancel", role: .cancel) { deleteIDs = [] }
        } message: { Text("This does not delete messages from another person's device.") }
        .onChange(of: authState.spacechatUsername) { _ in
            query = ""; results = []; selected = []; selecting = false
        }
        .onDisappear { inbox.close() }
        .task(id: query) { await search() }
    }

    private func filterTitle(_ filter: String) -> String {
        let count: Int
        if filter == "Requests" { count = inbox.conversations.filter { $0.isRequest && !$0.archived }.count }
        else if filter == "Unread" { count = inbox.conversations.filter { $0.unread > 0 && !$0.archived && !$0.isRequest }.count }
        else { count = 0 }
        return count > 0 ? "\(filter) (\(count))" : filter
    }

    private var signInNotice: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 48)).foregroundColor(.gray.opacity(0.5))
            Text("Your conversations, connected.").font(.system(size: 25, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
            Text("Sign in with Spacechat to find friends, send messages, and create chatrooms.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button { showSignIn = true } label: {
                HStack { SpacechatMark(size: 20); Text("Sign in with Spacechat").fontWeight(.semibold) }
                    .padding(16).frame(maxWidth: .infinity).background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 16))
            }
            if inbox.needsSignIn { Text("Your session expired. Sign in again to reconnect.").font(.caption).foregroundColor(.secondary) }
            Spacer()
        }.padding(28)
    }

    private var sectionSwitch: some View {
        HStack(spacing: 4) {
            ForEach([(0, "Chats"), (1, "Agents")], id: \.0) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { section = item.0 }
                    searchFocused = false
                } label: {
                    HStack(spacing: 6) {
                        if item.0 == 1 { AgentAvatar(id: "builtin-dots", hue: 0.60, size: 18) }
                        Text(item.1).font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(section == item.0 ? .white : .black.opacity(0.55))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(section == item.0 ? Color.black : Color.clear, in: Capsule())
                }.buttonStyle(.plain)
                .accessibilityAddTraits(section == item.0 ? .isSelected : [])
            }
        }
        .padding(4).background(Color(white: 0.95), in: Capsule())
        .padding(.horizontal, 20).padding(.bottom, 8)
    }

    private var inboxPage: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Messages").font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer()
                Button(selecting ? "Done" : "Select") { selecting.toggle(); selected = [] }
                    .font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                    .disabled(inbox.conversations.isEmpty)
                Menu {
                    Button("Mark all read", systemImage: "envelope.open") { inbox.markRead(Set(visible.map(\.id))) }
                    if inbox.filter == "Archive" {
                        Button("Restore all", systemImage: "tray.and.arrow.up") { inbox.archive(Set(visible.map(\.id)), value: false) }
                    }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await inbox.refresh() } }
                    Button("My QR code", systemImage: "qrcode") { sheet = .qr }
                } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44) }
                .accessibilityLabel("Message options")
            }.padding(.horizontal, 20)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search users and messages", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($searchFocused)
                if !query.isEmpty {
                    Button { query = ""; searchFocused = false } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.gray) }
                    .accessibilityLabel("Clear search")
                }
            }.padding(13).background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.self) { filter in
                        Button {
                            inbox.filter = filter; selected = []
                        } label: {
                            Text(filterTitle(filter)).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 10)
                                .foregroundColor(inbox.filter == filter ? .white : .black.opacity(0.6))
                                .background(inbox.filter == filter ? Color.black : Color(white: 0.95), in: Capsule())
                        }.accessibilityAddTraits(inbox.filter == filter ? .isSelected : [])
                    }
                }.padding(.horizontal, 20).padding(.vertical, 14)
            }
            if let error = inbox.error { errorBanner(error) }
            if selecting { selectionBar }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !query.isEmpty { userResults }
                    if !friends.friends.isEmpty && query.isEmpty && !selecting && inbox.filter == "All Messages" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Friends").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.black.opacity(0.5))
                                .padding(.horizontal, 20)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(friends.friends) { friend in
                                        Button { inbox.openFriend(friend.peer) } label: {
                                            VStack(spacing: 5) {
                                                SpacesAvatar(peer: friend.peer, size: 52)
                                                Text(friend.username).font(.system(size: 11, weight: .bold, design: .rounded))
                                                    .foregroundColor(.black.opacity(0.7)).lineLimit(1).frame(width: 64)
                                            }
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(.horizontal, 20)
                            }
                        }.padding(.top, 6).padding(.bottom, 10)
                    }
                    let requestCount = inbox.conversations.filter { $0.isRequest && !$0.archived }.count
                    if requestCount > 0 && inbox.filter != "Requests" && query.isEmpty && !selecting {
                        Button { inbox.filter = "Requests" } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.badge.fill").font(.system(size: 18, weight: .semibold))
                                    .frame(width: 44, height: 44).background(Color.black.opacity(0.06), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Message requests").font(.system(size: 16, weight: .semibold))
                                    Text(requestCount == 1 ? "1 person wants to message you" : "\(requestCount) people want to message you")
                                        .font(.system(size: 13)).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(requestCount)").font(.caption2.bold()).foregroundColor(.white).padding(7).background(Color.black, in: Capsule())
                            }.padding(.horizontal, 20).padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider().padding(.leading, 80)
                    }
                    if inbox.loading { ProgressView("Loading messages…").padding(30) }
                    else if visible.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: inbox.filter == "Archive" ? "archivebox" : "bubble.left.and.bubble.right").font(.system(size: 36)).foregroundColor(.gray.opacity(0.45))
                            Text(query.isEmpty ? "No \(inbox.filter == "All Messages" ? "messages" : inbox.filter.lowercased()) yet" : "No matching conversations")
                                .font(.headline)
                            Text("Start a conversation using the button below.").font(.subheadline).foregroundColor(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 38)
                    } else {
                        ForEach(visible) { chat in
                            conversationRow(chat)
                            Divider().padding(.leading, 80)
                        }
                    }
                    if query.isEmpty && !selecting {
                        HStack(spacing: 12) {
                            quickCard("My QR code", subtitle: "Let friends find you", icon: "qrcode") { sheet = .qr }
                            ShareLink(item: SpacechatService.profileURL(authState.spacechatUsername ?? ""), subject: Text("Find me on Spacechat"), message: Text("Let's chat on Spacechat.")) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Image(systemName: "person.badge.plus").font(.title2)
                                    Text("Invite friends").font(.subheadline.weight(.semibold))
                                    Text("Share your profile").font(.caption).foregroundColor(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 18))
                            }
                        }.padding(20)
                    }
                }.padding(.bottom, 100 + GameHubView.homeIndicatorInset)
            }
            .refreshable { await inbox.refresh() }
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .bottomTrailing) {
            if !selecting {
                Menu {
                    Button("New message", systemImage: "square.and.pencil") { sheet = .compose }
                    Button("Scan QR code", systemImage: "qrcode.viewfinder") { sheet = .scan }
                    Button("Create chatroom", systemImage: "person.3.fill") { sheet = .group }
                } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 24, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 60, height: 60).background(Color.black, in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
                }.accessibilityLabel("Create new message or chatroom")
                    .padding(.trailing, 22).padding(.bottom, 20 + GameHubView.homeIndicatorInset)
            }
        }
    }

    private var userResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("USERS").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            if searching || opening { ProgressView() }
            if let searchError { Text(searchError).font(.caption).foregroundColor(.secondary) }
            ForEach(results) { peer in
                Button { open(peer.username) } label: { SpacesPeerRow(peer: peer) }.disabled(opening)
            }
            if !searching && results.isEmpty && searchError == nil { Text("Type at least two characters to find users.").font(.caption).foregroundColor(.secondary) }
            Text("CONVERSATIONS").font(.caption.weight(.semibold)).foregroundColor(.secondary).padding(.top, 14)
        }.padding(.horizontal, 20).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionBar: some View {
        HStack {
            Button(selected.count == visible.count ? "Deselect all" : "Select all") { selected = selected.count == visible.count ? [] : Set(visible.map(\.id)) }
            Spacer()
            Button { inbox.markRead(selected); selected = []; selecting = false } label: { Image(systemName: "envelope.open") }.accessibilityLabel("Mark selected read")
            Button { inbox.archive(selected, value: inbox.filter != "Archive"); selected = []; selecting = false } label: {
                Image(systemName: inbox.filter == "Archive" ? "tray.and.arrow.up" : "archivebox")
            }.accessibilityLabel(inbox.filter == "Archive" ? "Restore selected" : "Archive selected")
            Button(role: .destructive) { deleteIDs = selected } label: { Image(systemName: "trash") }.accessibilityLabel("Delete selected conversations")
        }.font(.subheadline).buttonStyle(.bordered).padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func conversationRow(_ chat: SpacechatService.Conversation) -> some View {
        Button {
            if selecting {
                if selected.contains(chat.id) { selected.remove(chat.id) } else { selected.insert(chat.id) }
            } else { searchFocused = false; inbox.select(chat) }
        } label: {
            HStack(spacing: 12) {
                if selecting { Image(systemName: selected.contains(chat.id) ? "checkmark.circle.fill" : "circle").font(.title3) }
                SpacesAvatar(peer: chat.peer, group: chat.isGroup)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(chat.peer.displayName).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        if chat.muted { Image(systemName: "bell.slash.fill").font(.caption2).foregroundColor(.gray) }
                        Spacer()
                        if let last = chat.messages.last { Text(last.timeLabel).font(.caption2).foregroundColor(.secondary) }
                    }
                    HStack {
                        Text(chat.messages.last?.text ?? (chat.isGroup ? "Chatroom ready" : "Say hello"))
                            .font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                        Spacer()
                        if chat.unread > 0 { Text("\(chat.unread)").font(.caption2.bold()).foregroundColor(.white).padding(6).background(Color.black, in: Capsule()) }
                    }
                }
            }.padding(.horizontal, 20).padding(.vertical, 15).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(chat.archived ? "Unarchive" : "Archive", systemImage: "archivebox") { inbox.archive([chat.id], value: !chat.archived) }
            Button("Mark as read", systemImage: "envelope.open") { inbox.markRead([chat.id]) }
            Button(chat.muted ? "Unmute" : "Mute", systemImage: "bell.slash") { inbox.mute(chat.id) }
            Button("Delete from this device", systemImage: "trash", role: .destructive) { deleteIDs = [chat.id] }
        }
    }

    private func quickCard(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.circle")
            Text(text).font(.caption)
            Spacer()
            Button("Retry") { Task { await inbox.refresh() } }.font(.caption.bold())
            Button { inbox.error = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss error")
        }.padding(12).background(Color(white: 0.95)).padding(.horizontal, 16).padding(.bottom, 8)
    }

    private static let outgoing = Color(red: 0.047, green: 0.588, blue: 0.847)
    private static let outgoingPending = Color(red: 0.047, green: 0.588, blue: 0.847).opacity(0.55)
    private static let incomingFill = Color(white: 0.945)

    private func thread(_ chat: SpacechatService.Conversation) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { inbox.close() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundColor(.black)
                        .frame(width: 42, height: 42).background(Color.black.opacity(0.06), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Back to messages")
                SpacesAvatar(peer: chat.peer, group: chat.isGroup, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.peer.displayName).font(.system(size: 17, weight: .bold)).lineLimit(1)
                    Text(chat.isGroup ? "Chatroom" : "@\(chat.peer.username)").font(.system(size: 12, weight: .medium)).foregroundColor(.black.opacity(0.55)).lineLimit(1)
                }
                Spacer()
                Menu {
                    if inbox.canInvite(chat) { Button("Add members", systemImage: "person.badge.plus") { sheet = .invite } }
                    Button(chat.archived ? "Unarchive" : "Archive", systemImage: "archivebox") { inbox.archive([chat.id], value: !chat.archived) }
                    Button(chat.muted ? "Unmute" : "Mute", systemImage: "bell.slash") { inbox.mute(chat.id) }
                    if !chat.isGroup { ShareLink("Share profile", item: SpacechatService.profileURL(chat.peer.username)) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundColor(.black)
                        .frame(width: 42, height: 42).background(Color.black.opacity(0.06), in: Circle())
                }.accessibilityLabel("Conversation options")
            }.padding(.horizontal, 12).padding(.bottom, 10)
            if let error = inbox.error { errorBanner(error) }
            if chat.isRequest {
                HStack {
                    Text("Message request").font(.subheadline)
                    Spacer()
                    Button("Accept") { inbox.accept(chat.id) }.fontWeight(.semibold)
                }.padding(16).background(Color(white: 0.95))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if chat.messages.isEmpty {
                            VStack(spacing: 10) {
                                SpacesAvatar(peer: chat.peer, group: chat.isGroup, size: 70)
                                Text("Start your conversation").font(.headline)
                                Text("Send a hello to \(chat.peer.displayName).").font(.subheadline).foregroundColor(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 35)
                        }
                        let latestOutgoing = chat.messages.last(where: { !$0.incoming })?.id
                        ForEach(Array(chat.messages.enumerated()), id: \.element.id) { index, message in
                            let previous = index > 0 ? chat.messages[index - 1] : nil
                            if previous == nil || !Calendar.current.isDate(Date(timeIntervalSince1970: previous!.createdAt / 1000), inSameDayAs: Date(timeIntervalSince1970: message.createdAt / 1000)) {
                                Text(dayLabel(message.createdAt)).font(.system(size: 11, weight: .semibold)).foregroundColor(.black.opacity(0.45))
                                    .padding(.horizontal, 12).padding(.vertical, 5).background(Color.black.opacity(0.05), in: Capsule())
                                    .padding(.vertical, 10)
                            }
                            let grouped = previous.map { $0.incoming == message.incoming && $0.senderName == message.senderName && abs(message.createdAt - $0.createdAt) < 5 * 60 * 1000 } ?? false
                            messageBubble(message, chat: chat, grouped: grouped, isLatestOutgoing: message.id == latestOutgoing)
                                .padding(.top, grouped ? 3 : 10).id(message.id)
                        }
                        if inbox.typingPeerID == chat.peer.id || inbox.typingPeerID == chat.peer.username {
                            HStack { TypingBubble(); Spacer() }.padding(.top, 10)
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(.horizontal, 14).padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { proxy.scrollTo("latest", anchor: .bottom) }
                .onChange(of: chat.messages.last?.id) { _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("latest", anchor: .bottom) } }
                .onChange(of: inbox.typingPeerID) { _ in withAnimation { proxy.scrollTo("latest", anchor: .bottom) } }
            }
            composer(chat)
        }
        .id(chat.id)
        .task(id: chat.id) { await inbox.poll() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
    }

    private func dayLabel(_ ms: Double) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000)
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func messageBubble(_ message: SpacechatService.Message, chat: SpacechatService.Conversation, grouped: Bool, isLatestOutgoing: Bool) -> some View {
        let pending = !message.incoming && (message.delivery == "Sending…" || message.delivery.hasPrefix("Not sent"))
        let failed = message.delivery.hasPrefix("Not sent")
        return HStack(alignment: .bottom, spacing: 8) {
            if !message.incoming { Spacer(minLength: 28) }
            if message.incoming && chat.isGroup {
                if grouped { Color.clear.frame(width: 30, height: 1) }
                else { SpacesAvatar(peer: SpacechatService.Peer(id: message.senderName, username: message.senderName, displayName: message.senderName), size: 30) }
            }
            VStack(alignment: message.incoming ? .leading : .trailing, spacing: 3) {
                if chat.isGroup && message.incoming && !grouped && !message.senderName.isEmpty {
                    Text(message.senderName).font(.system(size: 12, weight: .semibold)).foregroundColor(.black.opacity(0.55))
                }
                Text(message.text).font(.system(size: 16)).textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundColor(message.incoming ? .black : .white)
                    .background(message.incoming ? Self.incomingFill : (pending ? Self.outgoingPending : Self.outgoing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .contextMenu { Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text } }
                if !grouped || isLatestOutgoing || failed {
                    HStack(spacing: 4) {
                        Text(message.timeLabel.uppercased())
                        if !message.incoming && failed {
                            Button { Task { await inbox.send(text: message.text, chat: chat, retry: message) } } label: {
                                Label("Not sent · Retry", systemImage: "exclamationmark.circle.fill")
                            }.disabled(inbox.sendingIDs.contains(chat.id)).foregroundColor(.red)
                        } else if !message.incoming && isLatestOutgoing {
                            Image(systemName: message.delivery == "Delivered" ? "checkmark.circle.fill" : "checkmark")
                            Text(message.delivery)
                        }
                    }.font(.system(size: 10, weight: .medium)).foregroundColor(.black.opacity(0.45))
                }
            }
            if message.incoming { Spacer(minLength: 28) }
        }
    }

    private func composer(_ chat: SpacechatService.Conversation) -> some View {
        let bottomInset: CGFloat = keyboardUp ? 8 : 10 + GameHubView.homeIndicatorInset
        let draft = inbox.drafts[chat.id] ?? ""
        let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chat.joined
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: Binding(get: { inbox.drafts[chat.id] ?? "" }, set: { inbox.drafts[chat.id] = $0 }), axis: .vertical)
                .lineLimit(1...5).font(.system(size: 16)).tint(Self.outgoing)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Self.incomingFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
                .onChange(of: inbox.drafts[chat.id]) { value in Task { await inbox.typing(!(value ?? "").isEmpty, chat: chat) } }
            Button {
                let text = inbox.drafts[chat.id] ?? ""
                inbox.drafts[chat.id] = ""
                Task { await inbox.send(text: text, chat: chat) }
            } label: {
                Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundColor(canSend ? .white : .black.opacity(0.3))
                    .frame(width: 44, height: 44).background(canSend ? Self.outgoing : Color.black.opacity(0.08), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("Send message").disabled(!canSend)
        }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, bottomInset)
            .background(Color.white)
    }

    private func search() async {
        results = []; searchError = nil
        guard signedIn, query.count >= 2 else { searching = false; return }
        searching = true
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            let found = try await inbox.search(query)
            try Task.checkCancellation()
            results = found; searching = false
        } catch {
            guard !Task.isCancelled else { return }
            searching = false
            searchError = error.localizedDescription
            if case SpacechatService.ServiceError.notSignedIn = error { inbox.report(error) }
        }
    }

    private func open(_ username: String) {
        guard !opening else { return }
        opening = true; searchFocused = false
        Task {
            defer { opening = false }
            do { try await inbox.open(username: username); query = "" }
            catch { inbox.report(error) }
        }
    }
}

private struct TypingBubble: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in Circle().fill(Color.black.opacity(phase == i ? 0.55 : 0.2)).frame(width: 7, height: 7) }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(Color(white: 0.945), in: Capsule())
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

private struct SpacesAvatar: View {
    let peer: SpacechatService.Peer
    var group = false
    var size: CGFloat = 48
    var body: some View {
        AsyncImage(url: URL(string: peer.picture)) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else {
                ZStack {
                    Color(white: 0.93)
                    if group { Image(systemName: "person.3.fill").font(.system(size: size * 0.35)) }
                    else { Text(String(peer.displayName.prefix(1)).uppercased()).font(.system(size: size * 0.4, weight: .semibold, design: .rounded)) }
                }
            }
        }.frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}

private struct SpacesPeerRow: View {
    let peer: SpacechatService.Peer
    var body: some View {
        HStack(spacing: 12) {
            SpacesAvatar(peer: peer)
            VStack(alignment: .leading, spacing: 4) {
                Text(peer.displayName).font(.subheadline.weight(.semibold))
                Text("@\(peer.username)").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }.padding(.vertical, 7).contentShape(Rectangle())
    }
}

private struct SpacesNewChatSheet: View {
    @ObservedObject var inbox: SpacesInbox
    enum Mode { case message, group, invite(SpacechatService.Conversation) }
    let mode: Mode
    var finished: () -> Void
    @State private var query = ""
    @State private var results: [SpacechatService.Peer] = []
    @State private var members: [SpacechatService.Peer] = []
    @State private var name = ""
    @State private var description = ""
    @State private var visibility = "private"
    @State private var working = false
    @State private var searching = false
    @State private var error: String?
    @FocusState private var queryFocused: Bool
    @ObservedObject private var friends = FriendsStore.shared
    private var showsFriends: Bool {
        if case .invite = mode { return false }
        return query.isEmpty && !friends.friends.isEmpty
    }
    private var isGroup: Bool { if case .group = mode { return true }; return false }
    private var title: String {
        switch mode { case .message: return "New message"; case .group: return "Create chatroom"; case .invite: return "Add members" }
    }
    var body: some View {
        NavigationStack {
            Form {
                if isGroup {
                    Section("Chatroom") {
                        TextField("Name (2–20 characters)", text: $name)
                        TextField("Description", text: $description, axis: .vertical).lineLimit(2...4)
                        Picker("Visibility", selection: $visibility) {
                            Text("Private").tag("private"); Text("Public").tag("public")
                        }
                    }
                }
                if !members.isEmpty {
                    Section("Members (\(members.count))") {
                        ForEach(members) { peer in
                            HStack { Text("@\(peer.username)"); Spacer(); Button { members.removeAll { $0.id == peer.id } } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("Remove \(peer.username)") }
                        }
                    }
                }
                Section(isGroup ? "Find members" : "Find a Spacechat user") {
                    TextField("Username or Spacechat profile link", text: $query)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                        .focused($queryFocused)
                    if searching || working { ProgressView() }
                    if showsFriends {
                        Text("Friends").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundColor(.secondary)
                        ForEach(friends.friends) { friend in
                            Button { choose(friend.peer) } label: {
                                HStack { SpacesPeerRow(peer: friend.peer); if members.contains(where: { $0.id == friend.peer.id }) { Image(systemName: "checkmark.circle.fill") } }
                            }.disabled(working)
                        }
                    }
                    ForEach(results) { peer in
                        Button { choose(peer) } label: {
                            HStack { SpacesPeerRow(peer: peer); if members.contains(where: { $0.id == peer.id }) { Image(systemName: "checkmark.circle.fill") } }
                        }.disabled(working)
                    }
                    if results.isEmpty && !searching && !showsFriends { Text("Search for someone by username to connect.").font(.caption).foregroundColor(.secondary) }
                    if let error { Text(error).font(.caption).foregroundColor(.red) }
                }
                if isGroup {
                    Section {
                        Button("Create chatroom") { create() }
                            .disabled(working || name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || name.count > 20)
                    } footer: { Text(visibility == "public" ? "Other Spacechat users can discover this room." : "Only invited members can join this room.") }
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: finished).disabled(working) } }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { queryFocused = true } }
            .task(id: query) {
                results = []; error = nil
                guard query.count >= 2 else { searching = false; return }
                searching = true
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                    let peers = try await inbox.search(query)
                    try Task.checkCancellation()
                    results = peers; searching = false
                } catch {
                    guard !Task.isCancelled else { return }
                    searching = false; self.error = error.localizedDescription
                }
            }
        }.tint(.black).preferredColorScheme(.light).interactiveDismissDisabled(working)
    }

    private func choose(_ peer: SpacechatService.Peer) {
        if isGroup {
            if !members.contains(where: { $0.id == peer.id }) { members.append(peer) }
            return
        }
        working = true; error = nil
        Task {
            defer { working = false }
            do {
                switch mode {
                case .message:
                    if peer.isAgent { inbox.openFriend(peer) } else { try await inbox.open(username: peer.username) }
                case .invite(let chat): try await inbox.invite(peer, to: chat)
                case .group: break
                }
                finished()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func create() {
        guard !working else { return }
        working = true; error = nil
        Task {
            defer { working = false }
            do {
                try await inbox.createGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines), description: description, visibility: visibility, members: members)
                finished()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct SpacesProfileQR: View {
    let username: String
    @Environment(\.dismiss) private var dismiss
    private var qr: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("spacechat:user:\(username)".utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text("Let's connect.").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Scan this code in Spacechat to message me.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                    if let qr { Image(uiImage: qr).interpolation(.none).resizable().scaledToFit().padding(24).background(Color.white).frame(maxWidth: 290).accessibilityLabel("Spacechat profile QR code for \(username)") }
                    Text("@\(username)").font(.title3.weight(.semibold))
                    ShareLink(item: SpacechatService.profileURL(username), subject: Text("Find me on Spacechat"), message: Text("Let's chat on Spacechat.")) {
                        Label("Invite friends", systemImage: "square.and.arrow.up").fontWeight(.semibold).frame(maxWidth: .infinity).padding(16).background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 16))
                    }
                }.padding(26)
            }.background(Color.white).navigationTitle("My QR code").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(.black).preferredColorScheme(.light)
    }
}

private struct SpacesQRScanner: View {
    var found: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var allowed = false
    @State private var status = "Point the camera at a Spacechat profile QR code."
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if allowed { SpacesCameraPreview(found: found, failure: { status = $0 }).frame(maxHeight: 400).clipShape(RoundedRectangle(cornerRadius: 20)) }
                else {
                    Image(systemName: "qrcode.viewfinder").font(.system(size: 70)).padding(35)
                    Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                }
                Text(status).multilineTextAlignment(.center).foregroundColor(.secondary)
                Spacer()
            }.padding(24).navigationTitle("Scan QR code").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .task {
                    allowed = await AVCaptureDevice.requestAccess(for: .video)
                    if !allowed { status = "Allow camera access in Settings to scan a profile. You can also enter a username using New message." }
                }
        }.preferredColorScheme(.light)
    }
}

private struct SpacesCameraPreview: UIViewControllerRepresentable {
    var found: (String) -> Void
    var failure: (String) -> Void
    func makeUIViewController(context: Context) -> CameraController { CameraController(found: found, failure: failure) }
    func updateUIViewController(_ controller: CameraController, context: Context) {}
    static func dismantleUIViewController(_ controller: CameraController, coordinator: ()) { controller.stop() }

    final class CameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "spaces.qr.camera")
        private var layer: AVCaptureVideoPreviewLayer?
        private var completed = false
        private var found: (String) -> Void
        private var failure: (String) -> Void
        init(found: @escaping (String) -> Void, failure: @escaping (String) -> Void) { self.found = found; self.failure = failure; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func viewDidLoad() {
            super.viewDidLoad()
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                failure("The camera is unavailable. Enter a username using New message."); return
            }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { failure("QR scanning is unavailable on this device."); return }
            session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: session); preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview); layer = preview
            queue.async { [session] in session.startRunning() }
        }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); layer?.frame = view.bounds }
        func stop() { queue.async { [session] in session.stopRunning() } }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !completed, let raw = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            let username = SpacechatService.username(from: raw)
            guard !username.isEmpty else { failure("This is not a Spacechat profile QR code."); return }
            completed = true; stop(); found(username)
        }
    }
}
