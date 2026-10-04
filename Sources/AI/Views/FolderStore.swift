import SwiftUI
import UniformTypeIdentifiers

/// One entry of a folder the person shared with their agents.
struct WorkspaceFile: Identifiable, Hashable {
    let path: String          // relative to the folder, "src/app.js"
    let isDirectory: Bool
    let size: Int
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var depth: Int { path.split(separator: "/").count - 1 }
}

/// A change made to a file, by the person or by an agent. Kept so it can be undone.
struct FileChange: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case created, edited, deleted }
    var id = UUID()
    let folder: String
    let path: String
    let kind: Kind
    let before: String?
    let after: String?
    let by: String
    var at = Date()
    var undone = false
}

enum FolderError: LocalizedError {
    case unsafePath, tooLarge, notText, missing, exists
    var errorDescription: String? {
        switch self {
        case .unsafePath: return "That path is outside the folder."
        case .tooLarge: return "That file is too large."
        case .notText: return "That file isn't text, so it can't be edited here."
        case .missing: return "That file or folder doesn't exist."
        case .exists: return "Something with that name is already there."
        }
    }
}

/// The folders and files shared with the agents. They are copied into the app
/// (an iOS app can't edit files in place in another app), and everything an
/// agent does to them goes through here: paths are checked, sizes are capped
/// and every edit keeps the old text so it can be undone.
@MainActor
final class FolderStore: ObservableObject {
    static let shared = FolderStore()

    @Published private(set) var folders: [String] = []
    @Published private(set) var changes: [FileChange] = []

    let root: URL
    private let fm = FileManager.default
    static let maxFileBytes = 400_000
    static let maxImportBytes = 25_000_000
    private static let skipped: Set<String> = [".git", "node_modules", ".build", "DerivedData", "Pods", ".DS_Store"]

    init(root: URL? = nil) {
        self.root = root ?? (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("SpacesFolders", isDirectory: true)
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
        reload()
        if let data = try? Data(contentsOf: changesURL), let saved = try? JSONDecoder().decode([FileChange].self, from: data) { changes = saved }
    }

    private var changesURL: URL { root.appendingPathComponent(".changes.json") }

    func reload() {
        let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        folders = names.filter { !$0.hasPrefix(".") && isDirectory(root.appendingPathComponent($0)) }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: Paths

    /// The real location of `path` inside `folder`, or nil when it would leave the folder.
    private func resolve(_ folder: String, _ path: String) -> URL? {
        guard !folder.isEmpty, !folder.contains("/"), !folder.hasPrefix(".") else { return nil }
        let base = root.appendingPathComponent(folder, isDirectory: true).standardizedFileURL
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(where: { $0 == ".." || $0.hasPrefix(".") }) else { return nil }
        let url = path.isEmpty ? base : base.appendingPathComponent(path).standardizedFileURL
        guard url.path == base.path || url.path.hasPrefix(base.path + "/") else { return nil }
        return url
    }

    // MARK: Adding

    /// Copies chosen folders and files in. Returns how many files arrived.
    @discardableResult
    func importItems(_ urls: [URL], into folder: String? = nil) throws -> Int {
        var count = 0
        var bytes = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if isDirectory(url) {
                let name = uniqueName(url.lastPathComponent, in: root)
                let target = root.appendingPathComponent(name, isDirectory: true)
                try copyDirectory(url, to: target, count: &count, bytes: &bytes)
            } else {
                // Loose files go into a folder of their own ("Files") unless one is given.
                let name = folder ?? "Files"
                let target = root.appendingPathComponent(name, isDirectory: true)
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= Self.maxFileBytes * 4, bytes + size <= Self.maxImportBytes else { continue }
                let dest = target.appendingPathComponent(uniqueName(url.lastPathComponent, in: target))
                try fm.copyItem(at: url, to: dest)
                count += 1; bytes += size
            }
        }
        reload()
        return count
    }

    private func copyDirectory(_ source: URL, to target: URL, count: inout Int, bytes: inout Int) throws {
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) {
            let name = item.lastPathComponent
            if name.hasPrefix(".") || Self.skipped.contains(name) { continue }
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                try copyDirectory(item, to: target.appendingPathComponent(name, isDirectory: true), count: &count, bytes: &bytes)
            } else {
                let size = values?.fileSize ?? 0
                guard size <= Self.maxFileBytes * 4, bytes + size <= Self.maxImportBytes else { continue }
                try fm.copyItem(at: item, to: target.appendingPathComponent(name))
                count += 1; bytes += size
            }
        }
    }

    private func uniqueName(_ name: String, in directory: URL) -> String {
        guard fm.fileExists(atPath: directory.appendingPathComponent(name).path) else { return name }
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        for i in 2...99 {
            let candidate = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            if !fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) { return candidate }
        }
        return UUID().uuidString
    }

    func createFolder(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, !clean.hasPrefix(".") else { return }
        try? fm.createDirectory(at: root.appendingPathComponent(uniqueName(clean, in: root), isDirectory: true), withIntermediateDirectories: true)
        reload()
    }

    /// Makes a folder and returns the name it really got (a number is added when the name is taken); nil when the name is not usable.
    @discardableResult
    func makeFolder(_ name: String) -> String? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, !clean.hasPrefix(".") else { return nil }
        let unique = uniqueName(String(clean.prefix(40)), in: root)
        guard (try? fm.createDirectory(at: root.appendingPathComponent(unique, isDirectory: true), withIntermediateDirectories: true)) != nil else { return nil }
        reload()
        return unique
    }

    func deleteFolder(_ folder: String) {
        guard let url = resolve(folder, "") else { return }
        try? fm.removeItem(at: url)
        changes.removeAll { $0.folder == folder }
        saveChanges(); reload()
    }

    // MARK: Organising (by the person)

    /// A new empty folder inside a project folder (`path` is "" for the top).
    func makeDirectory(_ folder: String, in parent: String, named name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, !clean.hasPrefix(".") else { throw FolderError.unsafePath }
        guard let base = resolve(folder, parent) else { throw FolderError.unsafePath }
        try fm.createDirectory(at: base.appendingPathComponent(uniqueName(clean, in: base), isDirectory: true), withIntermediateDirectories: true)
    }

    /// Renames a file or folder (same place, new name). Returns the new path.
    @discardableResult
    func rename(_ folder: String, _ path: String, to name: String) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, !clean.hasPrefix("."), let from = resolve(folder, path) else { throw FolderError.unsafePath }
        guard fm.fileExists(atPath: from.path) else { throw FolderError.missing }
        let parent = (path as NSString).deletingLastPathComponent
        let to = from.deletingLastPathComponent().appendingPathComponent(clean)
        guard !fm.fileExists(atPath: to.path) else { throw FolderError.exists }
        try fm.moveItem(at: from, to: to)
        return parent.isEmpty ? clean : parent + "/" + clean
    }

    /// Moves a file or folder into another folder of the same project (`parent` is "" for the top). Returns the new path.
    @discardableResult
    func move(_ folder: String, _ path: String, into parent: String) throws -> String {
        guard let from = resolve(folder, path), let dir = resolve(folder, parent) else { throw FolderError.unsafePath }
        guard fm.fileExists(atPath: from.path) else { throw FolderError.missing }
        // a folder cannot go inside itself
        if parent == path || parent.hasPrefix(path + "/") { throw FolderError.unsafePath }
        let name = from.lastPathComponent
        let to = dir.appendingPathComponent(name)
        guard !fm.fileExists(atPath: to.path) else { throw FolderError.exists }
        try fm.moveItem(at: from, to: to)
        return parent.isEmpty ? name : parent + "/" + name
    }

    /// Deletes a file (a text file can be undone from Changes) or a whole folder inside the project.
    func deleteItem(_ folder: String, _ item: WorkspaceFile, by: String) throws {
        guard !item.path.isEmpty, let url = resolve(folder, item.path) else { throw FolderError.unsafePath }
        if item.isDirectory { try fm.removeItem(at: url); return }
        if (try? delete(folder, item.path, by: by)) != nil { return }
        try fm.removeItem(at: url)
    }

    // MARK: Looking

    func tree(_ folder: String) -> [WorkspaceFile] {
        guard let base = resolve(folder, "") else { return [] }
        var out: [WorkspaceFile] = []
        func walk(_ dir: URL, prefix: String) {
            let items = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])) ?? [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            for item in items where out.count < 400 {
                let name = item.lastPathComponent
                if name.hasPrefix(".") || Self.skipped.contains(name) { continue }
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let path = prefix.isEmpty ? name : prefix + "/" + name
                if values?.isDirectory == true {
                    out.append(WorkspaceFile(path: path, isDirectory: true, size: 0))
                    walk(item, prefix: path)
                } else {
                    out.append(WorkspaceFile(path: path, isDirectory: false, size: values?.fileSize ?? 0))
                }
            }
        }
        walk(base, prefix: "")
        return out
    }

    func files(_ folder: String) -> [WorkspaceFile] { tree(folder).filter { !$0.isDirectory } }

    func read(_ folder: String, _ path: String) -> String? {
        guard let url = resolve(folder, path), let data = try? Data(contentsOf: url), data.count <= Self.maxFileBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func exists(_ folder: String, _ path: String) -> Bool {
        guard let url = resolve(folder, path) else { return false }
        return fm.fileExists(atPath: url.path)
    }

    // MARK: Changing (with undo)

    /// Creates or overwrites a text file. Returns the recorded change.
    @discardableResult
    func write(_ folder: String, _ path: String, content: String, by: String) throws -> FileChange {
        guard let url = resolve(folder, path), !path.isEmpty else { throw FolderError.unsafePath }
        guard content.utf8.count <= Self.maxFileBytes else { throw FolderError.tooLarge }
        let existed = fm.fileExists(atPath: url.path)
        var before: String? = nil
        if existed {
            guard let old = try? Data(contentsOf: url), old.count <= Self.maxFileBytes, let text = String(data: old, encoding: .utf8) else { throw FolderError.notText }
            before = text
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        let change = FileChange(folder: folder, path: path, kind: existed ? .edited : .created, before: before, after: content, by: by)
        record(change)
        return change
    }

    @discardableResult
    func delete(_ folder: String, _ path: String, by: String) throws -> FileChange {
        guard let url = resolve(folder, path), !path.isEmpty else { throw FolderError.unsafePath }
        guard fm.fileExists(atPath: url.path) else { throw FolderError.missing }
        let before = read(folder, path)
        try fm.removeItem(at: url)
        let change = FileChange(folder: folder, path: path, kind: .deleted, before: before, after: nil, by: by)
        record(change)
        return change
    }

    /// Puts a file back the way it was before `change`.
    func undo(_ change: FileChange) {
        guard let i = changes.firstIndex(where: { $0.id == change.id }), !changes[i].undone, let url = resolve(change.folder, change.path) else { return }
        switch change.kind {
        case .created: try? fm.removeItem(at: url)
        case .edited, .deleted:
            if let before = change.before {
                try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? before.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        changes[i].undone = true
        saveChanges()
    }

    func changes(in folder: String) -> [FileChange] { changes.filter { $0.folder == folder }.sorted { $0.at > $1.at } }

    private func record(_ change: FileChange) {
        changes.append(change)
        if changes.count > 300 { changes.removeFirst(changes.count - 300) }
        saveChanges()
    }

    private func saveChanges() {
        if let data = try? JSONEncoder().encode(changes) { try? data.write(to: changesURL, options: .atomic) }
    }
}
