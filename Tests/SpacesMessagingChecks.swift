// Run with swiftc alongside Sources/AI/Auth/SpacechatService.swift.
// URLProtocol fixtures intercept all requests; no account or real message is used.
import Foundation
import SwiftUI

// Rendering is type-checked in the complete iOS app; these fixtures test design data.
enum WorldBackground {
    struct Palette { var background: Color; var line: Color; var isCosmic: Bool }
}

struct SpacechatAuth {
    static let baseURL = URL(string: "https://spaces-tests.invalid")!
    static var session: String? = "test-session"
    static func storedSession() -> String? { session }
}

final class FixtureProtocol: URLProtocol {
    static var handler: (URLRequest, [String: Any]) -> (Int, [String: Any]) = { _, _ in (200, ["ok": true]) }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "spaces-tests.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096); defer { buffer.deallocate() }
            while stream.hasBytesAvailable { let count = stream.read(buffer, maxLength: 4096); if count <= 0 { break }; data.append(buffer, count: count) }
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let (status, json) = Self.handler(request, body)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: json))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct SpacesMessagingChecks {
    @MainActor static func main() async throws {
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        URLProtocol.registerClass(FixtureProtocol.self)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); count += 1; print("PASS: \(label)")
        }
        check(SpacechatService.username(from: "spacechat:user:alice") == "alice", "QR username round trip")
        check(SpacechatService.username(from: "https://www.spacechat.app/alice") == "alice", "Profile link parsing")
        check(SpacechatService.username(from: "https://unrelated.invalid/alice").isEmpty, "Reject unrelated QR URLs")
        let row: [String: Any] = ["message": "hello", "clientMessageId": "m1", "at": 1_900_000_000_000.0]
        let message = SpacechatService.message(row)!
        check(message.incoming, "Pending delivery defaults to incoming")
        check(SpacechatService.message(row)?.id == message.id, "Message identity is stable")
        check(SpacechatService.merge([message], [message, message]).count == 1, "Pending/history duplicates collapse")
        check(SpacechatService.message(["text": "expired", "ephemeralExpiresAt": 1]) == nil, "Expired temporary message omitted")
        let store = SpacesInbox(storageDirectory: directory)
        store.configure(username: "alice")
        var chat = SpacechatService.Conversation(peer: .init(id: "bob-id", username: "bob", displayName: "Bob"))
        chat.messages = [message]
        store.upsert(chat, countUnread: true)
        store.upsert(chat, countUnread: true)
        check(store.conversations[0].unread == 1, "Duplicate delivery does not increment unread")
        store.archive([chat.id], value: true)
        store.mute(chat.id)
        store.drafts[chat.id] = "unfinished draft"
        store.filter = "Archive"
        let restored = SpacesInbox(storageDirectory: directory)
        restored.configure(username: "alice")
        check(restored.conversations.count == 1 && restored.conversations[0].messages.count == 1, "Relaunch restores history")
        check(restored.conversations[0].archived && restored.conversations[0].muted && restored.filter == "Archive", "Archive, mute and filter persist")
        check(restored.drafts[chat.id] == "unfinished draft", "Unsent draft survives relaunch")
        restored.configure(username: "carol")
        check(restored.conversations.isEmpty && restored.drafts.isEmpty, "Different account sees no previous history or drafts")
        restored.configure(username: "alice")
        check(restored.conversations.count == 1, "Switching back retains original history")
        restored.select(restored.conversations[0])
        check(restored.conversations[0].unread == 0, "Opening conversation marks read")
        restored.apply(["type": "message-received", "payload": ["id": "bob-id", "username": "bob", "message": "ack", "clientMessageId": "not-present"]])
        check(restored.conversations[0].messages.count == 1, "Delivery acknowledgements never become incoming messages")
        FixtureProtocol.handler = { request, body in
            checkHeader(request)
            return (200, ["ok": true, "found": true, "id": "bob-id", "username": "bob", "name": "Bob", "messages": [row], "pendingMessages": [row]])
        }
        let (_, deliveries) = try await SpacechatService.lookup("bob")
        check(deliveries.count == 1, "Lookup deduplicates duplicated pending response arrays")
        var sentIDs: [String] = []
        FixtureProtocol.handler = { request, body in
            if request.url!.path.hasSuffix("send-message") {
                sentIDs.append(body["clientMessageId"] as! String)
                precondition(body["username"] as? String == "bob")
                return (503, ["ok": false, "error": "Try again"])
            }
            return (200, ["ok": true])
        }
        await restored.send(text: "test draft", chat: chat)
        let failed = restored.conversations[0].messages.first { $0.text == "test draft" }!
        check(failed.text == "test draft" && failed.delivery.hasPrefix("Not sent"), "Failed send retains text and retry state")
        FixtureProtocol.handler = { _, body in sentIDs.append(body["clientMessageId"] as! String); return (200, ["ok": true, "delivered": true]) }
        await restored.send(text: failed.text, chat: chat, retry: failed)
        check(sentIDs.count == 2 && sentIDs[0] == sentIDs[1], "Retry reuses the original client message ID")
        check(restored.conversations[0].messages.filter { $0.id == failed.id }.count == 1, "Retry does not duplicate local message")
        check(restored.conversations[0].messages.first { $0.id == failed.id }?.delivery == "Delivered", "Successful acknowledgement updates delivery")
        FixtureProtocol.handler = { _, _ in (401, ["ok": false, "error": "expired"]) }
        do { _ = try await SpacechatService.post("poll"); preconditionFailure("Expected expired session") }
        catch { restored.report(error) }
        check(restored.needsSignIn, "401 exposes the sign-in recovery flow")
        restored.delete([chat.id])
        restored.upsert(chat)
        check(restored.conversations.isEmpty, "Deleted conversation is not reimported by stale snapshots")
        restored.upsert(chat, restore: true)
        check(restored.conversations.count == 1, "Explicit new conversation restores deleted peer")
        let groupRow: [String: Any] = ["id": "alice.test", "name": "Test", "ownerId": "alice-id", "joined": true,
                                       "messages": [["message": "mine", "senderUsername": "alice", "clientMessageId": "g1", "at": 1_900_000_000_000.0]]]
        let group = restored.group(groupRow)
        check(group.isGroup && group.messages[0].incoming == false, "Group messages resolve sender direction")
        let dotJSON = """
        {"name":"Polar","base":[0.1,0.4,0.9],"stickers":[{"symbol":"snowflake","x":2,"y":-2,"scale":5,"color":[1,1,1]}]}
        """
        let dot = try SpacesGeneratedDesign.parse(dotJSON).dot()
        check(dot.artwork.stickers.count == 1 && dot.artwork.stickers[0].scale == 0.65, "Generated dot geometry is bounded")
        check(dot.artwork.stickers[0].position.x == 0.65 && dot.artwork.stickers[0].position.y == -0.65, "Generated sticker stays inside dot")
        let universe = try SpacesGeneratedDesign.parse("{\"name\":\"Dawn\",\"background\":[0.9,0.8,0.7],\"grid\":[0.2,0.3,0.4],\"stars\":true}").universe()
        check(universe.stars && universe.background.r == 0.9, "Generated universe parses real palette")
        let roundTrip = try JSONDecoder().decode(CustomUniverse.self, from: JSONEncoder().encode(universe))
        check(roundTrip == universe, "Custom universe survives save round trip")
        do { _ = try SpacesGeneratedDesign.parse(dotJSON.replacingOccurrences(of: "snowflake", with: "unsupported-symbol")).dot(); preconditionFailure("Expected symbol validation") }
        catch { check(true, "Unsupported generated symbols rejected") }
        do { _ = try SpacesGeneratedDesign.parse(dotJSON.replacingOccurrences(of: "0.1,0.4,0.9", with: "2,0.4,0.9")).dot(); preconditionFailure("Expected color validation") }
        catch { check(true, "Out-of-range generated colors rejected") }
        do { _ = try SpacesGeneratedDesign.parse("An ordinary text answer"); preconditionFailure("Expected JSON validation") }
        catch { check(true, "Ordinary AI prose cannot silently change a design") }
        print("\(count) messaging and creation checks passed. No live network requests or messages.")
    }
    static func checkHeader(_ request: URLRequest) { precondition(request.value(forHTTPHeaderField: "x-spacechat-session") == "test-session") }
}
