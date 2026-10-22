import Foundation
import CoreFoundation

/// The native app enforces its tool contract even if the remote model/server returns malformed actions.
enum AgentResponseValidation {
    enum Failure: LocalizedError {
        case malformed(String)
        var errorDescription: String? { if case .malformed(let reason) = self { return "The agent returned an invalid action: \(reason). No actions from this turn were applied." }; return nil }
    }
    struct Action {
        var type: String
        var path = "", content = "", find = "", replace = "", query = "", code = "", text = ""
        var tasks: [String] = []
        var start: Int?, end: Int?
    }
    struct Turn { var to: String?; var text: String?; var actions: [Action]; var done: Bool; var summary: String }
    static func pathIsSafe(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count <= 512 && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") && !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == ".." || $0.hasPrefix(".") }
    }
    static func parse(_ json: [String: Any], canRead: Bool, canWrite: Bool, canRun: Bool, canNote: Bool, copy: Bool) throws -> Turn {
        func fail(_ reason: String) -> Failure { .malformed(reason) }
        guard JSONSerialization.isValidJSONObject(json), let encoded = try? JSONSerialization.data(withJSONObject: json), encoded.count <= 2_000_000 else { throw fail("response too large or not JSON") }
        func string(_ row: [String: Any], _ key: String, _ max: Int, required: Bool = false) throws -> String {
            guard let value = row[key] else { if required { throw fail("missing \(key)") }; return "" }
            guard let text = value as? String, text.utf8.count <= max, !text.contains("\0") else { throw fail("invalid \(key)") }
            return text
        }
        func line(_ row: [String: Any], _ key: String) throws -> Int? {
            guard let value = row[key] else { return nil }
            guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue.rounded() == n.doubleValue, (1...1_000_000).contains(n.doubleValue) else { throw fail("invalid line number") }
            return n.intValue
        }
        let rows: [[String: Any]]
        if let raw = json["actions"] { guard let array = raw as? [[String: Any]], array.count <= 4 else { throw fail("at most four actions are allowed") }; rows = array } else { rows = [] }
        var actions: [Action] = []
        for row in rows {
            var action = Action(type: try string(row, "type", 16, required: true))
            switch action.type {
            case "list": guard canRead else { throw fail("file reading is not allowed") }
            case "read", "write", "create", "edit", "delete":
                guard canRead else { throw fail("file reading is not allowed") }
                if action.type != "read", !canWrite { throw fail("file changes are not allowed") }
                action.path = try string(row, "path", 512, required: true)
                guard pathIsSafe(action.path) else { throw fail("path is outside the shared folder") }
                if action.type == "read" { action.start = try line(row,"start"); action.end = try line(row,"end"); if let start = action.start, let end = action.end, start > end { throw fail("line range is reversed") } }
                if ["write","create"].contains(action.type) { action.content = try string(row,"content",400_000,required:true) }
                if action.type == "edit" { action.find = try string(row,"find",16_000,required:true); action.replace = try string(row,"replace",32_000,required:true); guard !action.find.isEmpty else { throw fail("find text is empty") } }
            case "search":
                guard canRead else { throw fail("file reading is not allowed") }
                action.query = try string(row,"query",500,required:true)
                guard !action.query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw fail("search query is empty") }
            case "run": guard canRun else { throw fail("code execution is not allowed") }; action.code = try string(row,"code",6_000,required:true)
            case "note": guard canNote else { throw fail("notes are not allowed") }; action.text = try string(row,"text",1_000,required:true)
            case "ask": action.text = try string(row,"text",2_000,required:true)
            case "spawn":
                guard !copy, let jobs = row["tasks"] as? [String], !jobs.isEmpty, jobs.count <= 10, jobs.allSatisfy({ !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.utf8.count <= 500 }) else { throw fail("invalid copy jobs") }
                action.tasks = jobs
            default: throw fail("unknown tool \(action.type)")
            }
            actions.append(action)
        }
        let message = json["message"] as? [String: Any] ?? [:]
        let text = try string(message,"text",8_000), to = try string(message,"to",120)
        let summary = try string(json,"summary",8_000)
        let waiting = actions.contains { ["read","list","search","run","spawn"].contains($0.type) }
        return Turn(to: to.isEmpty ? nil : to, text: text.isEmpty ? nil : text, actions: actions, done: json["done"] as? Bool == true && !waiting, summary: summary)
    }
}
