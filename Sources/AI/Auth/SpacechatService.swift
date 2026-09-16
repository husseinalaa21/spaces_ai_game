import Foundation
import Combine
import CryptoKit

/// Spacechat's native API contracts. Polling is owned by one inbox store;
/// user-db drains pending deliveries and must never replace local history.
enum SpacechatService {
    struct Peer: Codable, Equatable, Identifiable {
        let id: String
        let username: String
        let displayName: String
        var picture: String = ""
    }

    struct Message: Codable, Identifiable, Equatable {
        let id: String
        let text: String
        let incoming: Bool
        var createdAt: Double
        var delivery: String = ""
        var senderName: String = ""
        var expiresAt: Double? = nil
        var timeLabel: String {
            Date(timeIntervalSince1970: createdAt / 1000).formatted(date: .omitted, time: .shortened)
        }
    }

    struct Conversation: Codable, Identifiable, Equatable {
        var peer: Peer
        var isGroup = false
        var messages: [Message] = []
        var unread = 0
        var archived = false
        var muted = false
        var isRequest = false
        var updatedAt: Double = 0
        var readAt: Double = 0
        var ownerID = ""
        var joined = true
        var id: String { (isGroup ? "group:" : "user:") + (peer.username.isEmpty ? peer.id : peer.username).lowercased() }
    }

    enum ServiceError: LocalizedError {
        case notSignedIn
        case unavailable(String)
        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Your Spacechat session has expired. Sign in with Spacechat to continue."
            case .unavailable(let message): return message.isEmpty ? "Couldn't reach Spacechat. Please try again." : message
            }
        }
    }

    static func post(_ path: String, body: [String: Any] = [:]) async throws -> [String: Any] {
        guard let session = SpacechatAuth.storedSession(), !session.isEmpty else { throw ServiceError.notSignedIn }
        var request = URLRequest(url: SpacechatAuth.baseURL.appendingPathComponent("api").appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(session, forHTTPHeaderField: "x-spacechat-session")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ServiceError.unavailable("") }
        if http.statusCode == 401 { throw ServiceError.notSignedIn }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.unavailable("Spacechat returned an invalid response. Please try again.")
        }
        guard (200..<300).contains(http.statusCode), json["ok"] as? Bool != false else {
            throw ServiceError.unavailable(json["error"] as? String ?? "")
        }
        return json
    }

    static func askSpacechatAI(_ text: String) async throws -> String {
        let json = try await post("guide/message", body: ["message": text, "clientMessageId": UUID().uuidString])
        guard let reply = json["reply"] as? String, !reply.isEmpty else { throw ServiceError.unavailable("") }
        return reply
    }

    static func username(from raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("spacechat:user:") { value = String(value.dropFirst(15)) }
        else if let url = URL(string: value), let host = url.host {
            guard ["spacechat.app", "www.spacechat.app"].contains(host.lowercased()) else { return "" }
            let parts = url.pathComponents.filter { $0 != "/" }
            if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "u" })?.value {
                value = query
            } else if parts.first == "user", parts.count > 1 { value = parts[1] }
            else { value = parts.first ?? "" }
        }
        if value.hasPrefix("@") { value.removeFirst() }
        guard !value.isEmpty, value.count <= 100,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !value.contains("/"), !value.contains(":") else { return "" }
        return value
    }

    static func profileURL(_ username: String) -> URL {
        SpacechatAuth.baseURL.appendingPathComponent(username)
    }

    static func peer(_ json: [String: Any], fallback: String = "") -> Peer {
        let username = string(json, "username", "user", fallback: fallback)
        return Peer(id: string(json, "id", "from", "userId", fallback: username), username: username,
                    displayName: string(json, "name", "displayName", fallback: username),
                    picture: string(json, "pic", "picture"))
    }

    static func string(_ json: [String: Any], _ keys: String..., fallback: String = "") -> String {
        for key in keys { if let value = json[key] as? String, !value.isEmpty { return value } }
        return fallback
    }

    static func timestamp(_ json: [String: Any]) -> Double {
        for key in ["createdAt", "at", "timestamp", "updatedAt"] {
            let value = (json[key] as? NSNumber)?.doubleValue ?? Double(json[key] as? String ?? "") ?? 0
            if value > 0 { return value < 20_000_000_000 ? value * 1000 : value }
        }
        return 0
    }

    static func message(_ json: [String: Any], incoming: Bool = true, group: Bool = false, ownID: String = "", ownUsername: String = "") -> Message? {
        let text = string(json, "text", "message", "body")
        guard !text.isEmpty else { return nil }
        let sender = string(json, "senderId", "from")
        let senderUsername = string(json, "senderUsername", "username")
        let direction = group ? !((!ownID.isEmpty && sender == ownID) || (!ownUsername.isEmpty && senderUsername.lowercased() == ownUsername.lowercased())) : (json["incoming"] as? Bool ?? incoming)
        let time = timestamp(json)
        let seed = "\(direction)|\(sender)|\(time)|\(text)"
        let fallbackID = SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
        let id = string(json, "clientMessageId", "messageId", fallback: fallbackID)
        let expiry = (json["ephemeralExpiresAt"] as? NSNumber)?.doubleValue
        if let expiry, expiry <= Date().timeIntervalSince1970 * 1000 { return nil }
        return Message(id: id, text: text, incoming: direction, createdAt: time,
                       delivery: direction ? "" : (json["delivered"] as? Bool == true ? "Delivered" : "Sent"),
                       senderName: string(json, "senderName", "name", fallback: senderUsername), expiresAt: expiry)
    }

    static func lookup(_ raw: String) async throws -> (Peer, [Message]) {
        let clean = username(from: raw)
        guard !clean.isEmpty else { throw ServiceError.unavailable("Enter a Spacechat username or profile link.") }
        let json = try await post("user-db", body: ["id": "", "username": clean])
        guard json["blocked"] as? Bool != true else { throw ServiceError.unavailable("This conversation is unavailable.") }
        guard json["found"] as? Bool == true else { throw ServiceError.unavailable("No Spacechat user found for @\(clean).") }
        let rows = (json["messages"] as? [[String: Any]] ?? []) + (json["pendingMessages"] as? [[String: Any]] ?? [])
        return (peer(json, fallback: clean), merge([], rows.compactMap { message($0) }))
    }

    static func merge(_ old: [Message], _ new: [Message]) -> [Message] {
        var byID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for item in new {
            var next = item
            if byID[item.id]?.delivery == "Delivered", next.delivery == "Sent" { next.delivery = "Delivered" }
            byID[item.id] = next
        }
        let now = Date().timeIntervalSince1970 * 1000
        return byID.values.filter { ($0.expiresAt ?? .greatestFiniteMagnitude) > now }.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
    }
}

/// Account-scoped local history, matching Spacechat's local-database behavior.
/// Never uploads a replacement account database: that would overwrite other devices.
@MainActor
final class SpacesInbox: ObservableObject {
    typealias Conversation = SpacechatService.Conversation
    typealias Message = SpacechatService.Message
    typealias Peer = SpacechatService.Peer
    @Published var conversations: [Conversation] = []
    @Published var error: String?
    @Published var loading = false
    @Published var needsSignIn = false
    @Published var activeID: String?
    @Published var drafts: [String: String] = [:]
    @Published var incomingAlertID: String?
    @Published var sendingIDs: Set<String> = []
    @Published var typingPeerID: String?
    @Published var filter = "All Messages" { didSet { persist() } }
    private(set) var account = ""
    private var ownID = ""
    private var blocked: Set<String> = []
    private var deleted: Set<String> = []
    private var directory: [Peer] = []
    private var refreshing = false
    private var polling = false
    private var generation = UUID()
    private var typingUntil = Date.distantPast
    private var lastTypingAt = Date.distantPast
    private var lastTypingValue = false
    private let storageDirectory: URL?
    init(storageDirectory: URL? = nil) { self.storageDirectory = storageDirectory }
    private var loadFailed = false
    private var configuring = false
    private var fileURL: URL? {
        guard !account.isEmpty else { return nil }
        let name = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("SpacesMessages", isDirectory: true)
        return directory?.appendingPathComponent(name + ".json")
    }
    private struct Saved: Codable {
        var conversations: [Conversation]
        var deleted: Set<String>
        var filter: String
        var drafts: [String: String]? = nil
    }

    func configure(username: String?) {
        let next = username?.lowercased() ?? ""
        guard next != account else { return }
        configuring = true
        defer { configuring = false }
        generation = UUID()
        account = next
        conversations = []; directory = []; deleted = []; blocked = []
        activeID = nil; drafts = [:]; ownID = ""; error = nil; needsSignIn = false
        sendingIDs = []; refreshing = false; polling = false; loading = false; loadFailed = false
        filter = "All Messages"
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: url))
            conversations = saved.conversations; deleted = saved.deleted; filter = saved.filter
            drafts = saved.drafts ?? [:]
            for i in conversations.indices {
                for j in conversations[i].messages.indices where conversations[i].messages[j].delivery == "Sending…" {
                    conversations[i].messages[j].delivery = "Not sent — tap to retry"
                }
            }
        } catch {
            loadFailed = true
            self.error = "Saved messages couldn't be opened. The existing file has been kept safe."
        }
    }

    func persist() {
        guard !configuring, !loadFailed, let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Saved(conversations: conversations, deleted: deleted, filter: filter, drafts: drafts))
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { self.error = "Messages couldn't be saved on this device. Check available storage." }
    }

    func report(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        if case SpacechatService.ServiceError.notSignedIn = error { needsSignIn = true }
        self.error = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Please try again."
    }

    func upsert(_ incoming: Conversation, countUnread: Bool = false, restore: Bool = false) {
        guard !blocked.contains(incoming.peer.id.lowercased()), !blocked.contains(incoming.peer.username.lowercased()) else { return }
        if restore { deleted.remove(incoming.id) }
        guard !deleted.contains(incoming.id) else { return }
        if let i = conversations.firstIndex(where: { $0.id == incoming.id }) {
            let old = conversations[i]
            let fresh = incoming.messages.filter { item in !old.messages.contains(where: { $0.id == item.id }) }
            conversations[i].peer = incoming.peer
            conversations[i].messages = SpacechatService.merge(old.messages, incoming.messages)
            conversations[i].updatedAt = max(old.updatedAt, incoming.updatedAt, incoming.messages.last?.createdAt ?? 0)
            if incoming.isGroup { conversations[i].ownerID = incoming.ownerID; conversations[i].joined = incoming.joined }
            if countUnread, activeID != incoming.id {
                let arrivals = fresh.filter { $0.incoming && $0.createdAt > old.readAt }
                conversations[i].unread += arrivals.count
                if !old.muted, let last = arrivals.last { incomingAlertID = last.id }
            }
        } else {
            var next = incoming
            if countUnread {
                next.unread = incoming.messages.filter(\.incoming).count
                if !next.muted { incomingAlertID = incoming.messages.last(where: \.incoming)?.id }
            }
            next.updatedAt = max(next.updatedAt, next.messages.last?.createdAt ?? 0)
            conversations.append(next)
        }
        if activeID == incoming.id { markRead([incoming.id]) }
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }

    func refresh() async {
        guard !account.isEmpty, !refreshing else { return }
        let token = generation
        refreshing = true; loading = conversations.isEmpty
        defer { if token == generation { refreshing = false; loading = false } }
        do {
            let json = try await SpacechatService.post("session/bootstrap")
            guard token == generation else { return }
            ownID = SpacechatService.string(json, "id")
            blocked = Set((json["blockedUsers"] as? [String] ?? []).map { $0.lowercased() })
            conversations.removeAll { blocked.contains($0.peer.id.lowercased()) || blocked.contains($0.peer.username.lowercased()) }
            if let database = json["prepaidDatabase"] as? [String: Any] {
                let requests = Set(database["requests"] as? [String] ?? [])
                let records = (database["conversations"] as? [String: [String: Any]] ?? [:])
                    .merging(database["messages"] as? [String: [String: Any]] ?? [:]) { first, _ in first }
                for (key, record) in records {
                    var chat = Conversation(peer: SpacechatService.peer(record, fallback: key))
                    chat.messages = (record["messages"] as? [[String: Any]] ?? []).compactMap { SpacechatService.message($0) }
                    chat.unread = (record["unread"] as? Int) ?? (record["unreadCount"] as? Int) ?? 0
                    chat.updatedAt = SpacechatService.timestamp(record)
                    chat.isRequest = requests.contains(key) || requests.contains(chat.peer.id)
                    upsert(chat, countUnread: true)
                }
            }
            error = nil; needsSignIn = false
            persist()
        } catch { if token == generation { report(error) } }
        await refreshGroups()
    }

    func refreshGroups() async {
        let token = generation
        do {
            let json = try await SpacechatService.post("group/list")
            guard token == generation else { return }
            for row in json["groups"] as? [[String: Any]] ?? [] { upsert(group(row)) }
            persist()
        } catch { if token == generation { report(error) } }
    }

    func group(_ row: [String: Any]) -> Conversation {
        let id = SpacechatService.string(row, "id", "groupId")
        var chat = Conversation(peer: Peer(id: id, username: id, displayName: SpacechatService.string(row, "name", fallback: id), picture: SpacechatService.string(row, "pic")), isGroup: true)
        chat.ownerID = SpacechatService.string(row, "ownerId")
        chat.joined = row["joined"] as? Bool ?? true
        chat.updatedAt = SpacechatService.timestamp(row)
        chat.messages = (row["messages"] as? [[String: Any]] ?? []).compactMap {
            SpacechatService.message($0, group: true, ownID: ownID, ownUsername: account)
        }
        return chat
    }

    func poll() async {
        guard !account.isEmpty, !polling, !needsSignIn else { return }
        polling = true
        let token = generation
        defer { if token == generation { polling = false } }
        let current = conversations.first { $0.id == activeID }
        var body: [String: Any] = [:]
        if let current, !current.isGroup { body["activeChat"] = ["id": current.peer.id, "username": current.peer.username] }
        do {
            let json = try await SpacechatService.post("poll", body: body)
            guard token == generation else { return }
            if let profile = json["activeChatProfile"] as? [String: Any], profile["blocked"] as? Bool != true,
               let current, !current.isGroup {
                var chat = current
                chat.peer = SpacechatService.peer(profile, fallback: current.peer.username)
                chat.messages = ((profile["messages"] as? [[String: Any]] ?? []) + (profile["pendingMessages"] as? [[String: Any]] ?? [])).compactMap { SpacechatService.message($0) }
                upsert(chat, countUnread: true)
            }
            for event in json["events"] as? [[String: Any]] ?? [] { apply(event) }
            if typingUntil < Date() { typingPeerID = nil }
            for i in conversations.indices { conversations[i].messages = SpacechatService.merge(conversations[i].messages, []) }
            persist()
            if let current, current.isGroup {
                let json = try await SpacechatService.post("group/get", body: ["groupId": current.peer.id, "includeMessages": true])
                guard token == generation else { return }
                if let row = json["group"] as? [String: Any] { upsert(group(row), countUnread: true); persist() }
            }
        } catch { if token == generation { report(error) } }
    }

    func apply(_ event: [String: Any]) {
        let kind = SpacechatService.string(event, "type", "name", "eventName", "event").lowercased()
        let payload = event["payload"] as? [String: Any] ?? [:]
        let row = payload["payload"] as? [String: Any] ?? payload["message"] as? [String: Any] ?? payload
        if kind == "message-received" {
            let id = SpacechatService.string(row, "clientMessageId")
            guard !id.isEmpty else { return }
            for i in conversations.indices {
                if let j = conversations[i].messages.firstIndex(where: { $0.id == id && !$0.incoming }) {
                    conversations[i].messages[j].delivery = "Delivered"
                }
            }
        } else if kind == "typing_on" {
            typingPeerID = row["c"] as? Bool == true ? SpacechatService.string(row, "id", "username") : nil
            typingUntil = Date().addingTimeInterval(6)
        } else if kind == "group-updated", let data = payload["group"] as? [String: Any] { upsert(group(data)) }
        else if kind.contains("group"), let index = conversations.firstIndex(where: { $0.isGroup && $0.peer.id == SpacechatService.string(payload, "groupId", "group_id") }) {
            if let item = SpacechatService.message(row, group: true, ownID: ownID, ownUsername: account) {
                var chat = conversations[index]; chat.messages = [item]; upsert(chat, countUnread: true)
            }
        } else if kind == "message", SpacechatService.string(row, "groupId", "group_id").isEmpty,
                  let item = SpacechatService.message(row) {
            let peer = SpacechatService.peer(row)
            guard !peer.id.isEmpty else { return }
            var chat = Conversation(peer: peer)
            chat.messages = [item]
            chat.isRequest = !conversations.contains { $0.id == chat.id }
            upsert(chat, countUnread: true)
        }
    }

    func search(_ query: String) async throws -> [Peer] {
        let clean = SpacechatService.username(from: query)
        guard clean.count >= 2 else { return [] }
        let token = generation
        if directory.isEmpty {
            let json = try await SpacechatService.post("user-directory", body: ["limit": 100])
            guard token == generation else { throw CancellationError() }
            directory = (json["users"] as? [[String: Any]] ?? []).map { SpacechatService.peer($0) }
        }
        var matches = directory.filter {
            $0.username.lowercased() != account && !blocked.contains($0.id.lowercased()) && !blocked.contains($0.username.lowercased()) &&
            ($0.username.localizedCaseInsensitiveContains(clean) || $0.displayName.localizedCaseInsensitiveContains(clean))
        }
        if matches.isEmpty {
            // Lookup consumes pending messages, so preserve them even during search.
            let (peer, messages) = try await SpacechatService.lookup(clean)
            guard token == generation else { throw CancellationError() }
            if peer.username.lowercased() != account, !blocked.contains(peer.id.lowercased()), !blocked.contains(peer.username.lowercased()) {
                if !messages.isEmpty { var chat = Conversation(peer: peer); chat.messages = messages; upsert(chat, countUnread: true); persist() }
                matches = [peer]
            }
        }
        try Task.checkCancellation()
        return Array(matches.prefix(12))
    }

    func open(username: String) async throws {
        let token = generation
        let (peer, messages) = try await SpacechatService.lookup(username)
        guard token == generation else { throw CancellationError() }
        guard peer.username.lowercased() != account else { throw SpacechatService.ServiceError.unavailable("Choose another user to start a conversation.") }
        var chat = Conversation(peer: peer); chat.messages = messages
        upsert(chat, countUnread: true, restore: true)
        activeID = chat.id; markRead([chat.id]); persist()
    }

    func select(_ chat: Conversation) { activeID = chat.id; markRead([chat.id]) }
    func close() { activeID = nil; typingPeerID = nil }

    func markRead(_ ids: Set<String>) {
        for i in conversations.indices where ids.contains(conversations[i].id) {
            conversations[i].unread = 0
            conversations[i].readAt = Date().timeIntervalSince1970 * 1000
        }
        persist()
    }

    func archive(_ ids: Set<String>, value: Bool) {
        for i in conversations.indices where ids.contains(conversations[i].id) { conversations[i].archived = value }
        persist()
    }
    func mute(_ id: String) {
        if let i = conversations.firstIndex(where: { $0.id == id }) { conversations[i].muted.toggle() }
        persist()
    }
    func accept(_ id: String) {
        if let i = conversations.firstIndex(where: { $0.id == id }) { conversations[i].isRequest = false }
        persist()
    }
    func delete(_ ids: Set<String>) {
        deleted.formUnion(ids); conversations.removeAll { ids.contains($0.id) }
        for id in ids { drafts.removeValue(forKey: id) }
        persist()
    }

    func send(text: String, chat: Conversation, retry: Message? = nil) async {
        guard !sendingIDs.contains(chat.id), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let token = generation
        sendingIDs.insert(chat.id)
        defer { if token == generation { sendingIDs.remove(chat.id) } }
        var message = retry ?? Message(id: "spaces_" + UUID().uuidString, text: text.trimmingCharacters(in: .whitespacesAndNewlines), incoming: false, createdAt: Date().timeIntervalSince1970 * 1000)
        message.delivery = "Sending…"
        var next = chat; next.messages = [message]; upsert(next); persist()
        do {
            let json: [String: Any]
            if chat.isGroup {
                json = try await SpacechatService.post("group/send", body: ["groupId": chat.peer.id, "message": message.text, "clientMessageId": message.id, "timestamp": message.createdAt])
            } else {
                json = try await SpacechatService.post("send-message", body: ["id": chat.peer.id, "to": chat.peer.id, "username": chat.peer.username, "text": message.text, "message": message.text, "clientMessageId": message.id, "timestamp": message.createdAt])
            }
            guard token == generation else { return }
            if SpacechatService.string(json, "reason") == "target-not-found" { throw SpacechatService.ServiceError.unavailable("This user could not be found.") }
            message.delivery = json["delivered"] as? Bool == true ? "Delivered" : "Sent"
            next.messages = [message]; upsert(next); error = nil
        } catch {
            guard token == generation else { return }
            message.delivery = "Not sent — tap to retry"
            next.messages = [message]; upsert(next); report(error)
        }
        persist()
    }

    func typing(_ value: Bool, chat: Conversation) async {
        guard !chat.isGroup, value != lastTypingValue || Date().timeIntervalSince(lastTypingAt) > 3 else { return }
        lastTypingAt = Date(); lastTypingValue = value
        _ = try? await SpacechatService.post("typing", body: ["id": chat.peer.id, "username": chat.peer.username, "c": value, "typing": value])
    }

    func createGroup(name: String, description: String, visibility: String, members: [Peer]) async throws {
        let token = generation
        let json = try await SpacechatService.post("group/create", body: ["name": name, "description": description, "visibility": visibility, "members": members.map(\.id), "allowMemberInvite": false, "background": "auto"])
        guard token == generation else { throw CancellationError() }
        guard let row = json["group"] as? [String: Any] else { throw SpacechatService.ServiceError.unavailable("The group could not be created.") }
        let chat = group(row); upsert(chat, restore: true); activeID = chat.id; persist()
    }

    func invite(_ peer: Peer, to chat: Conversation) async throws {
        let token = generation
        _ = try await SpacechatService.post("group/allow", body: ["groupId": chat.peer.id, "userId": peer.id])
        guard token == generation else { throw CancellationError() }
    }
    func canInvite(_ chat: Conversation) -> Bool { chat.isGroup && chat.ownerID == ownID }
}
