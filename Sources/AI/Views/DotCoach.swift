import SwiftUI

// AI outside the match: today's challenges and a coach's recap after it.
// Both come from the server (`POST /api/spaces/agents`, modes "challenge" and
// "recap") and both work without it: challenges fall back to a fixed set for
// the day, the recap to a plain summary of the numbers.

struct Challenge: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case eatPlayers, mass, survive, friends, combo }
    let id: String
    let type: Kind
    let target: Int
    let title: String
    let reward: Int
}

/// What a finished match counted for.
struct MatchStats {
    var eatenPlayers = 0
    var mass = 0
    var seconds = 0.0
    var bestCombo = 0
}

@MainActor
final class DailyChallenges: ObservableObject {
    static let shared = DailyChallenges()

    @Published private(set) var day = ""
    @Published private(set) var challenges: [Challenge] = []
    @Published private(set) var progress: [String: Int] = [:]
    private var claimed: Set<String> = []
    /// Called with the points to give when challenges are completed.
    var onReward: ((Int) -> Void)?

    private let defaults = UserDefaults.standard

    static func today() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Loads today's set: from this device if already fetched today, else from
    /// the server (one request a day), else a fixed fallback.
    func refresh() async {
        let today = Self.today()
        if day == today, !challenges.isEmpty { return }
        day = today
        progress = (defaults.dictionary(forKey: "spaces.challengeProgress.\(today)") as? [String: Int]) ?? [:]
        claimed = Set(defaults.stringArray(forKey: "spaces.challengeClaimed.\(today)") ?? [])
        if let data = defaults.data(forKey: "spaces.challenges.\(today)"), let saved = try? JSONDecoder().decode([Challenge].self, from: data), !saved.isEmpty {
            challenges = saved; return
        }
        var fetched: [Challenge] = []
        if let json = try? await SpacechatService.spacesAgents(["mode": "challenge"]),
           let rows = json["challenges"] as? [[String: Any]],
           let data = try? JSONSerialization.data(withJSONObject: rows),
           let decoded = try? JSONDecoder().decode([Challenge].self, from: data) {
            fetched = decoded
        }
        let set = fetched.count == 3 ? fetched : Self.fixedSet(for: today)
        challenges = set
        if fetched.count == 3, let data = try? JSONEncoder().encode(set) { defaults.set(data, forKey: "spaces.challenges.\(today)") }
    }

    /// The same three for the day without the server.
    static func fixedSet(for day: String) -> [Challenge] {
        let n = day.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 3
        return [
            Challenge(id: "\(day):0:eatPlayers", type: .eatPlayers, target: 1 + n, title: "Eat \(1 + n) other player\(n > 0 ? "s" : "")", reward: 30),
            Challenge(id: "\(day):1:mass", type: .mass, target: 100 + 20 * n, title: "Reach \(100 + 20 * n) mass in one match", reward: 25),
            Challenge(id: "\(day):2:survive", type: .survive, target: 2 + n, title: "Survive \(2 + n) minutes", reward: 25)
        ]
    }

    func value(for c: Challenge) -> Int { min(c.target, progress[c.id] ?? 0) }
    func isDone(_ c: Challenge) -> Bool { (progress[c.id] ?? 0) >= c.target }

    /// Counts a finished match. Returns the challenges this match completed.
    @discardableResult
    func record(_ stats: MatchStats) -> [Challenge] {
        var finished: [Challenge] = []
        for c in challenges {
            let before = isDone(c)
            switch c.type {
            case .eatPlayers: progress[c.id, default: 0] += stats.eatenPlayers
            case .mass: progress[c.id] = max(progress[c.id] ?? 0, stats.mass)
            case .survive: progress[c.id] = max(progress[c.id] ?? 0, Int(stats.seconds / 60))
            case .combo: progress[c.id] = max(progress[c.id] ?? 0, stats.bestCombo)
            case .friends: break
            }
            if !before && isDone(c) { finished.append(c) }
        }
        return settle(finished)
    }

    /// One more of something that happens outside a match (a friend added).
    func bump(_ kind: Challenge.Kind) {
        var finished: [Challenge] = []
        for c in challenges where c.type == kind {
            let before = isDone(c)
            progress[c.id, default: 0] += 1
            if !before && isDone(c) { finished.append(c) }
        }
        settle(finished)
    }

    @discardableResult
    private func settle(_ finished: [Challenge]) -> [Challenge] {
        defaults.set(progress, forKey: "spaces.challengeProgress.\(day)")
        let fresh = finished.filter { !claimed.contains($0.id) }
        for c in fresh { claimed.insert(c.id) }
        defaults.set(Array(claimed), forKey: "spaces.challengeClaimed.\(day)")
        let points = fresh.reduce(0) { $0 + $1.reward }
        if points > 0 { onReward?(points) }
        return fresh
    }
}

/// The coach's words after a match.
enum DotCoach {
    static func recap(_ result: GameResult) async -> (text: String, tip: String) {
        let you = result.rows.first(where: { $0.isYou })
        let body: [String: Any] = [
            "mode": "recap", "outcome": result.title,
            "you": ["mass": you?.mass ?? 0, "eaten": result.eatenCount, "rank": result.rank, "of": result.rows.count,
                    "seconds": Int(result.seconds), "eatenBy": result.eatenBy ?? ""],
            "biggestMass": result.rows.map(\.mass).max() ?? 0
        ]
        if let json = try? await SpacechatService.spacesAgents(body), let text = json["recap"] as? String, !text.isEmpty {
            return (text, (json["tip"] as? String) ?? "")
        }
        return localRecap(result)
    }

    /// A plain summary of the numbers, for when the server can't be reached.
    static func localRecap(_ result: GameResult) -> (text: String, tip: String) {
        let minutes = Int(result.seconds) / 60, secs = Int(result.seconds) % 60
        let time = minutes > 0 ? "\(minutes)m \(secs)s" : "\(secs)s"
        var text = "You lasted \(time) and finished \(result.rank) of \(result.rows.count)"
        if result.eatenCount > 0 { text += ", eating \(result.eatenCount) player\(result.eatenCount > 1 ? "s" : "")" }
        text += "."
        if let by = result.eatenBy { text += " \(by) got you in the end." }
        let tip = result.eatenBy != nil ? "Watch for smaller dots near you." : "Keep eating food between fights."
        return (text, tip)
    }
}
