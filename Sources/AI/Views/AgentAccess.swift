import SwiftUI
import JavaScriptCore

// MARK: - What an agent may do

/// The access the person gives one agent, like the tool list each SpaceAILM
/// agent has. The server is told it and drops actions that are not allowed;
/// the app checks again before doing anything.
struct AgentAccess: Codable, Equatable {
    var read = true
    var write = true
    var run = false
    var notes = true

    init(read: Bool = true, write: Bool = true, run: Bool = false, notes: Bool = true) {
        self.read = read; self.write = write; self.run = run; self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        read = try c.decodeIfPresent(Bool.self, forKey: .read) ?? true
        write = try c.decodeIfPresent(Bool.self, forKey: .write) ?? true
        run = try c.decodeIfPresent(Bool.self, forKey: .run) ?? false
        notes = try c.decodeIfPresent(Bool.self, forKey: .notes) ?? true
    }

    var payload: [String: Bool] { ["read": read, "write": write, "run": run, "notes": notes] }
}

// MARK: - Approvals

enum ApprovalMode: String, CaseIterable, Identifiable, Codable {
    case ask, session, auto
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ask: return "Ask every time"
        case .session: return "Ask once per session"
        case .auto: return "Never ask"
        }
    }
}

/// Every kind of action that needs the person's say-so. Reading never asks;
/// anything that changes a file or runs code asks every time until told otherwise.
enum ApprovalKind: String, CaseIterable, Identifiable {
    case change, delete, run
    var id: String { rawValue }
    var title: String {
        switch self {
        case .change: return "Create and edit files"
        case .delete: return "Delete files"
        case .run: return "Run code"
        }
    }
    var detail: String {
        switch self {
        case .change: return "An agent writes a new file or changes an existing one. You see what changes first."
        case .delete: return "An agent removes a file from a folder."
        case .run: return "An agent runs a small sandboxed JavaScript program to test an idea."
        }
    }
    var defaultMode: ApprovalMode { .ask }
}

enum ApprovalDecision { case once, session, always, deny }

struct ApprovalRequest: Identifiable {
    let id = UUID()
    let kind: ApprovalKind
    let agent: String
    let summary: String
    let detail: String
}

@MainActor
final class ApprovalCenter: ObservableObject {
    static let shared = ApprovalCenter()

    @Published private(set) var queue: [ApprovalRequest] = []
    @Published private(set) var modes: [String: ApprovalMode] = [:]
    private var sessionGrants: Set<String> = []
    private var waiting: [UUID: CheckedContinuation<ApprovalDecision, Never>] = [:]
    private let defaults: UserDefaults
    private let key = "spaces.approvalModes"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for (k, v) in defaults.dictionary(forKey: key) as? [String: String] ?? [:] {
            if let mode = ApprovalMode(rawValue: v) { modes[k] = mode }
        }
    }

    var current: ApprovalRequest? { queue.first }
    func mode(for kind: ApprovalKind) -> ApprovalMode { modes[kind.id] ?? kind.defaultMode }

    func setMode(_ mode: ApprovalMode, for kind: ApprovalKind) {
        if mode == kind.defaultMode { modes.removeValue(forKey: kind.id) } else { modes[kind.id] = mode }
        if mode != .session { sessionGrants.remove(kind.id) }
        defaults.set(modes.mapValues(\.rawValue), forKey: key)
    }

    func resetToDefaults() {
        modes.removeAll(); sessionGrants.removeAll()
        defaults.removeObject(forKey: key)
    }

    /// True when the action may go ahead. Waits for the person unless this kind is set to never ask.
    func authorize(_ kind: ApprovalKind, agent: String, summary: String, detail: String = "") async -> Bool {
        switch mode(for: kind) {
        case .auto: return true
        case .session where sessionGrants.contains(kind.id): return true
        default: break
        }
        let request = ApprovalRequest(kind: kind, agent: agent, summary: summary, detail: detail)
        queue.append(request)
        let decision = await withCheckedContinuation { (continuation: CheckedContinuation<ApprovalDecision, Never>) in
            waiting[request.id] = continuation
        }
        switch decision {
        case .deny: return false
        case .once: return true
        case .session: sessionGrants.insert(kind.id); return true
        case .always: setMode(.auto, for: kind); return true
        }
    }

    func resolve(_ id: UUID, _ decision: ApprovalDecision) {
        guard let i = queue.firstIndex(where: { $0.id == id }) else { return }
        queue.remove(at: i)
        waiting.removeValue(forKey: id)?.resume(returning: decision)
    }

    /// Everything waiting is denied (the run was stopped or closed).
    func denyAll() { for request in queue { resolve(request.id, .deny) } }
}

// MARK: - Running code (develop and test algorithms)

/// A sandbox for small JavaScript programs: no network, no files, no timers; only
/// the language itself and `console.log`. Loops are fenced so that a runaway
/// program is stopped instead of freezing the app.
enum JSSandbox {
    static let maxOutput = 4000
    static let timeLimit: TimeInterval = 2.0
    static let loopLimit = 3_000_000

    /// Adds a guard call to every loop condition so an endless loop ends with an error.
    static func instrument(_ code: String) -> String {
        let chars = Array(code)
        var out = ""
        var i = 0

        func isIdent(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "$" }

        /// Index of the ")" that closes the "(" at `open`, skipping strings and comments.
        func closing(_ open: Int) -> Int? {
            var depth = 0, j = open
            while j < chars.count {
                let c = chars[j]
                if c == "\"" || c == "'" || c == "`" {
                    let q = c; j += 1
                    while j < chars.count, chars[j] != q { if chars[j] == "\\" { j += 1 }; j += 1 }
                } else if c == "/", j + 1 < chars.count, chars[j + 1] == "/" {
                    while j < chars.count, chars[j] != "\n" { j += 1 }
                } else if c == "/", j + 1 < chars.count, chars[j + 1] == "*" {
                    j += 2
                    while j + 1 < chars.count, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                    j += 1
                } else if c == "(" { depth += 1 }
                else if c == ")" { depth -= 1; if depth == 0 { return j } }
                j += 1
            }
            return nil
        }

        /// Splits at top-level semicolons.
        func parts(_ s: [Character]) -> [String] {
            var result: [String] = [], current = "", depth = 0, j = 0
            while j < s.count {
                let c = s[j]
                if c == "\"" || c == "'" || c == "`" {
                    let q = c; current.append(c); j += 1
                    while j < s.count, s[j] != q { if s[j] == "\\" { current.append(s[j]); j += 1 }; if j < s.count { current.append(s[j]) }; j += 1 }
                    if j < s.count { current.append(s[j]) }
                } else if "([{".contains(c) { depth += 1; current.append(c) }
                else if ")]}".contains(c) { depth -= 1; current.append(c) }
                else if c == ";", depth == 0 { result.append(current); current = "" }
                else { current.append(c) }
                j += 1
            }
            result.append(current)
            return result
        }

        while i < chars.count {
            let c = chars[i]
            // strings and comments are copied untouched
            if c == "\"" || c == "'" || c == "`" {
                let q = c; out.append(c); i += 1
                while i < chars.count, chars[i] != q { if chars[i] == "\\", i + 1 < chars.count { out.append(chars[i]); i += 1 }; out.append(chars[i]); i += 1 }
                if i < chars.count { out.append(chars[i]); i += 1 }
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { out.append(chars[i]); i += 1 }
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                out.append("/*"); i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { out.append(chars[i]); i += 1 }
                if i + 1 < chars.count { out.append("*/"); i += 2 }
                continue
            }
            for word in ["while", "for"] where c == word.first! {
                let w = Array(word)
                guard i + w.count < chars.count, Array(chars[i..<(i + w.count)]) == w,
                      i == 0 || !isIdent(chars[i - 1]), !isIdent(chars[i + w.count]) else { continue }
                var k = i + w.count
                while k < chars.count, chars[k].isWhitespace { k += 1 }
                guard k < chars.count, chars[k] == "(", let end = closing(k) else { continue }
                let inner = Array(chars[(k + 1)..<end])
                if word == "while" {
                    out += "while (__g(), (" + String(inner) + "))"
                    i = end + 1
                    return finish(chars: chars, from: &i, out: &out, instrument: instrument)
                }
                let p = parts(inner)
                if p.count == 3 {
                    let cond = p[1].trimmingCharacters(in: .whitespaces)
                    out += "for (" + p[0] + "; __g(), (" + (cond.isEmpty ? "true" : cond) + "); " + p[2] + ")"
                } else {
                    out += "for (" + String(inner) + ")"
                }
                i = end + 1
                return finish(chars: chars, from: &i, out: &out, instrument: instrument)
            }
            out.append(c); i += 1
        }
        return out
    }

    // After a loop header the rest of the program is instrumented the same way (recursively).
    private static func finish(chars: [Character], from i: inout Int, out: inout String, instrument: (String) -> String) -> String {
        out + instrument(String(chars[i...]))
    }

    /// Runs `code` and returns what it printed (or the value of its last expression).
    static func run(_ code: String) async -> (ok: Bool, output: String) {
        let source = instrument(code)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let context = JSContext() else { continuation.resume(returning: (false, "JavaScript isn't available.")); return }
                var lines: [String] = []
                var steps = 0
                let started = Date()
                var failure: String?

                let log: @convention(block) () -> Void = {
                    let args = JSContext.currentArguments() as? [JSValue] ?? []
                    let text = args.map { $0.isString ? ($0.toString() ?? "") : ((try? $0.toString()) ?? $0.toString() ?? "") }.joined(separator: " ")
                    if lines.joined(separator: "\n").count < maxOutput { lines.append(text) }
                }
                let guardCall: @convention(block) () -> Void = {
                    steps += 1
                    if steps > loopLimit || (steps % 2048 == 0 && Date().timeIntervalSince(started) > timeLimit) {
                        failure = "Stopped: the program ran too long (an endless loop?)."
                        if let ctx = JSContext.current() { ctx.exception = JSValue(newErrorFromMessage: failure, in: ctx) }
                    }
                }
                let console = JSValue(newObjectIn: context)
                console?.setObject(log, forKeyedSubscript: "log" as NSString)
                console?.setObject(log, forKeyedSubscript: "info" as NSString)
                console?.setObject(log, forKeyedSubscript: "warn" as NSString)
                console?.setObject(log, forKeyedSubscript: "error" as NSString)
                context.setObject(console, forKeyedSubscript: "console" as NSString)
                context.setObject(guardCall, forKeyedSubscript: "__g" as NSString)
                var thrown: String?
                context.exceptionHandler = { _, exception in thrown = exception?.toString() }
                let value = context.evaluateScript(source)

                var output = lines.joined(separator: "\n")
                if output.isEmpty, thrown == nil, let value, !value.isUndefined, !value.isNull { output = value.toString() ?? "" }
                if output.count > maxOutput { output = String(output.prefix(maxOutput)) + "\n…(output cut)" }
                if let error = failure ?? thrown {
                    continuation.resume(returning: (false, (output.isEmpty ? "" : output + "\n") + "Error: " + error))
                } else {
                    continuation.resume(returning: (true, output.isEmpty ? "(the program printed nothing)" : output))
                }
            }
        }
    }
}
