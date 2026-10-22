import Foundation
import CryptoKit

/// Local-only evidence retrieval. File I/O and ranking are isolated from SwiftUI's main actor.
actor WorkspaceResearch {
    static let shared = WorkspaceResearch()
    struct Hit: Sendable {
        let path: String
        let firstLine: Int
        let lastLine: Int
        let text: String
        let revision: String
        let score: Double
        var citation: String { "\(path):\(firstLine)-\(lastLine) [sha256:\(revision.prefix(12))]" }
    }
    struct Report: Sendable {
        let hits: [Hit]
        let files: Int
        let chunks: Int
        let truncated: Bool
        let cacheHits: Int
        var text: String {
            let result = hits.isEmpty ? "No supporting passages found." : hits.map { "\($0.citation)\n\($0.text)" }.joined(separator: "\n\n")
            return result + (truncated ? "\nIndex limit reached; results cover only the indexed files." : "")
        }
    }
    struct Limits: Sendable {
        var files = 2_000
        var bytes = 16_000_000
        var fileBytes = 400_000
        var chunks = 12_000
        var results = 12
    }
    private struct Passage { let path: String; let start: Int; let end: Int; let text: String; let revision: String; let terms: [String: Int]; let length: Int }
    private struct CachedFile { let size: Int; let modified: Date?; let passages: [Passage] }
    private var cache: [String: CachedFile] = [:]
    private var cachedRoot: String?
    private let limits: Limits
    init(limits: Limits = Limits()) { self.limits = limits }
    nonisolated static func revision(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    func search(root: URL, query: String) throws -> Report {
        try Task.checkCancellation()
        let query = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        let wanted = Array(Set(Self.tokens(query))).sorted()
        guard !wanted.isEmpty else { return Report(hits: [], files: 0, chunks: 0, truncated: false, cacheHits: 0) }
        let base = root.standardizedFileURL
        let resolved = base.resolvingSymlinksInPath()
        guard resolved.path == base.path else { throw CocoaError(.fileReadNoPermission) }
        if cachedRoot != base.path { cache = [:]; cachedRoot = base.path }
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { throw CocoaError(.fileReadNoSuchFile) }
        let skipped: Set<String> = ["node_modules", "Pods", "DerivedData", ".git", ".build"]
        var passages: [Passage] = [], seen: Set<String> = [], count = 0, bytes = 0, reused = 0, truncated = false
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isDirectory == true { if skipped.contains(url.lastPathComponent) { enumerator.skipDescendants() }; continue }
            guard values.isRegularFile == true, let size = values.fileSize, size <= limits.fileBytes else { continue }
            if count >= limits.files || bytes + size > limits.bytes || passages.count >= limits.chunks { truncated = true; break }
            let realURL = url.resolvingSymlinksInPath()
            guard realURL.path.hasPrefix(resolved.path + "/") else { continue }
            let path = String(realURL.path.dropFirst(resolved.path.count + 1))
            seen.insert(path); bytes += size; count += 1
            let entry: CachedFile
            if let old = cache[path], old.size == size, old.modified == values.contentModificationDate { entry = old; reused += 1 }
            else {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                guard let data = try handle.read(upToCount: limits.fileBytes + 1), data.count <= limits.fileBytes, let text = String(data: data, encoding: .utf8), !text.contains("\0") else { continue }
                let digest = Self.revision(text)
                let lines = text.components(separatedBy: "\n")
                var pieces: [Passage] = [], start = 0
                while start < lines.count && pieces.count < limits.chunks {
                    var end = start, characters = 0
                    while end < lines.count && end - start < 12 && characters < 1_200 { characters += lines[end].count; end += 1 }
                    if end == start + 1 && lines[start].count > 2_000 {
                        let line = lines[start]; var cursor = line.startIndex
                        while cursor < line.endIndex && pieces.count < limits.chunks {
                            let next = line.index(cursor, offsetBy: 1_200, limitedBy: line.endIndex) ?? line.endIndex
                            let piece = String(line[cursor..<next]), terms = Self.tokens(path + " " + piece)
                            pieces.append(Passage(path: path, start: start + 1, end: start + 1, text: piece, revision: digest, terms: Dictionary(terms.map { ($0, 1) }, uniquingKeysWith: +), length: terms.count)); cursor = next
                        }
                        start = end; continue
                    }
                    let text = String(lines[start..<end].joined(separator: "\n").prefix(2_000))
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { start = max(start + 1, end - 2); continue }
                    let terms = Self.tokens(path + " " + text)
                    pieces.append(Passage(path: path, start: start + 1, end: end, text: text, revision: digest, terms: Dictionary(terms.map { ($0, 1) }, uniquingKeysWith: +), length: terms.count))
                    start = max(start + 1, end - 2)
                }
                entry = CachedFile(size: size, modified: values.contentModificationDate, passages: pieces)
                cache[path] = entry
            }
            let room = limits.chunks - passages.count
            if entry.passages.count >= room { truncated = true }
            passages += entry.passages.prefix(room)
        }
        cache = cache.filter { seen.contains($0.key) }
        let average = max(1, Double(passages.reduce(0) { $0 + $1.length }) / Double(max(1, passages.count)))
        var frequencies: [String: Int] = [:]
        for row in passages { for word in wanted where row.terms[word] != nil { frequencies[word, default: 0] += 1 } }
        let hits = try passages.enumerated().compactMap { index, row -> Hit? in
            if index % 128 == 0 { try Task.checkCancellation() }
            var score = 0.0
            for word in wanted {
                guard let frequency = row.terms[word] else { continue }
                let idf = log(1 + (Double(passages.count - (frequencies[word] ?? 0)) + 0.5) / (Double(frequencies[word] ?? 0) + 0.5))
                let f = Double(frequency)
                score += idf * f * 2.4 / (f + 1.4 * (0.25 + 0.75 * Double(row.length) / average))
            }
            guard score > 0 else { return nil }
            if row.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil { score += 3 }
            if row.path.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil { score += 2 }
            return Hit(path: row.path, firstLine: row.start, lastLine: row.end, text: row.text, revision: row.revision, score: score)
        }.sorted { $0.score == $1.score ? ($0.path == $1.path ? $0.firstLine < $1.firstLine : $0.path < $1.path) : $0.score > $1.score }
        var selected: [Hit] = []
        for hit in hits {
            guard selected.filter({ $0.path == hit.path }).count < 3,
                  !selected.contains(where: { $0.path == hit.path && $0.firstLine <= hit.lastLine && hit.firstLine <= $0.lastLine && $0.text.contains(hit.text) }) else { continue }
            selected.append(hit)
            if selected.count >= limits.results { break }
        }
        return Report(hits: selected, files: count, chunks: passages.count, truncated: truncated, cacheHits: reused)
    }
}
