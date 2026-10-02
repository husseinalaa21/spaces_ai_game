import Foundation

/// Spacechat AI conversations kept on this device, one file per account, the
/// way the Spacechat app keeps its own AI history.
struct SpacesAIMessage: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var role: String            // "user" | "assistant"
    var text: String
    var createdAt = Date().timeIntervalSince1970 * 1000
}

struct SpacesAIThread: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var messages: [SpacesAIMessage] = []
    var updatedAt = Date().timeIntervalSince1970 * 1000
    var title: String {
        let first = messages.first(where: { $0.role == "user" })?.text ?? "New conversation"
        let line = first.split(separator: "\n").first.map(String.init) ?? first
        return String(line.prefix(60))
    }
}

@MainActor
final class SpacesAIStore: ObservableObject {
    @Published private(set) var threads: [SpacesAIThread] = []
    private var account = ""
    private let directory: URL?

    init(directory: URL? = nil) {
        self.directory = directory
    }

    private var fileURL: URL? {
        guard !account.isEmpty else { return nil }
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SpacesAI", isDirectory: true)
        let safe = account.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return base?.appendingPathComponent(safe + ".json")
    }

    func configure(account: String?) {
        let next = (account ?? "").lowercased()
        guard next != self.account || threads.isEmpty else { return }
        self.account = next
        threads = []
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([SpacesAIThread].self, from: data) else { return }
        threads = saved
    }

    private func persist() {
        guard let url = fileURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(threads) { try? data.write(to: url, options: .atomic) }
    }

    func thread(_ id: String?) -> SpacesAIThread? { threads.first { $0.id == id } }

    func create() -> SpacesAIThread {
        let thread = SpacesAIThread()
        threads.insert(thread, at: 0)
        persist()
        return thread
    }

    func append(_ threadID: String, role: String, text: String) {
        guard let i = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[i].messages.append(SpacesAIMessage(role: role, text: text))
        threads[i].updatedAt = Date().timeIntervalSince1970 * 1000
        persist()
    }

    func delete(_ id: String) {
        threads.removeAll { $0.id == id }
        persist()
    }

    /// The last few turns, sent so the assistant reads them before it answers
    /// (the message being sent is the final entry and is dropped).
    func history(_ threadID: String) -> [[String: String]] {
        guard let thread = thread(threadID) else { return [] }
        return thread.messages.dropLast().suffix(6).map { ["role": $0.role, "text": String($0.text.prefix(500))] }
    }
}
