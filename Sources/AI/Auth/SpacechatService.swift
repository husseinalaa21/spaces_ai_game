import Foundation

/// The handful of Spacechat endpoints the in-game Messages and Spacechat AI
/// pages use. Same server, same session header (`x-spacechat-session`) and
/// same request shapes as the Spacechat iOS client's `SpacechatAPI`.
///
/// Deliberately small: this game is not a chat client, so it implements
/// exactly the three calls its two pages need rather than mirroring the whole
/// API surface.
enum SpacechatService {

    struct Message: Identifiable, Equatable {
        let id: String
        let text: String
        let incoming: Bool
        let timeLabel: String
    }

    struct Peer: Equatable {
        let id: String
        let username: String
        let displayName: String
    }

    enum ServiceError: LocalizedError {
        case notSignedIn
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Sign in with a Spacechat phrase to use this."
            case .unavailable(let message):
                return message.isEmpty ? "Spacechat is unavailable right now." : message
            }
        }
    }

    // MARK: - Transport

    private static func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let session = SpacechatAuth.storedSession(), !session.isEmpty else {
            throw ServiceError.notSignedIn
        }
        var request = URLRequest(url: SpacechatAuth.baseURL
            .appendingPathComponent("api")
            .appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(session, forHTTPHeaderField: "x-spacechat-session")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw ServiceError.unavailable("")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if json["ok"] as? Bool == false {
            throw ServiceError.unavailable(json["error"] as? String ?? "")
        }
        return json
    }

    private static func clientMessageID() -> String {
        "game_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(8))"
    }

    // MARK: - Spacechat AI

    /// One turn with Spacechat AI. The server keeps the conversation history
    /// against the session, so only the new message is sent.
    static func askSpacechatAI(_ text: String) async throws -> String {
        let json = try await post("guide/message", body: [
            "message": text,
            "clientMessageId": clientMessageID()
        ])
        let reply = json["reply"] as? String ?? ""
        guard !reply.isEmpty else { throw ServiceError.unavailable("") }
        return reply
    }

    // MARK: - Messages

    /// Finds someone by username and returns them with the existing thread.
    static func openConversation(username: String) async throws -> (Peer, [Message]) {
        let cleaned = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
        guard !cleaned.isEmpty else { throw ServiceError.unavailable("Enter a username.") }

        let json = try await post("user-db", body: ["id": "", "username": cleaned])
        guard json["found"] as? Bool == true else {
            throw ServiceError.unavailable("No Spacechat account called @\(cleaned).")
        }
        let peer = Peer(
            id: json["id"] as? String ?? "",
            username: json["username"] as? String ?? cleaned,
            displayName: {
                let name = json["name"] as? String ?? ""
                return name.isEmpty ? (json["username"] as? String ?? cleaned) : name
            }()
        )
        return (peer, parseMessages(json))
    }

    /// Sends into a thread and returns the refreshed thread.
    static func send(_ text: String, to peer: Peer) async throws -> [Message] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        _ = try await post("send-message", body: [
            "to": peer.id,
            "id": peer.id,
            "username": peer.username,
            "text": trimmed,
            "message": trimmed,
            "clientMessageId": clientMessageID(),
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ])
        let (_, refreshed) = try await openConversation(username: peer.username)
        return refreshed
    }

    /// Message records vary in shape between endpoints and server versions
    /// (`text`/`message`/`body`, `timeLabel`/`time`), so every field is read
    /// tolerantly — one unexpected key should never empty a whole thread.
    private static func parseMessages(_ json: [String: Any]) -> [Message] {
        let raw = (json["messages"] as? [[String: Any]] ?? [])
            + (json["pendingMessages"] as? [[String: Any]] ?? [])
        return raw.compactMap { entry in
            let text = (entry["text"] as? String)
                ?? (entry["message"] as? String)
                ?? (entry["body"] as? String) ?? ""
            guard !text.isEmpty else { return nil }
            return Message(
                id: (entry["clientMessageId"] as? String) ?? UUID().uuidString,
                text: text,
                incoming: entry["incoming"] as? Bool ?? false,
                timeLabel: (entry["timeLabel"] as? String) ?? (entry["time"] as? String) ?? ""
            )
        }
    }
}
