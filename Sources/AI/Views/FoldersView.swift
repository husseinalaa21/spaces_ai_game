import SwiftUI
import UniformTypeIdentifiers

/// The Folders page: folders and files the person shares, which they (and
/// their agents) can read and edit. Everything an agent changes is listed and
/// can be undone.
struct FoldersView: View {
    @ObservedObject var folders: FolderStore
    @ObservedObject var agents: AgentsStore
    @ObservedObject var authState: AuthState
    let onLogin: () -> Void

    @State private var importing = false
    @State private var importKind: UTType = .folder
    @State private var opened: String?
    @State private var showNew = false
    @State private var newName = ""
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: GameHubView.bannerTopInset + 46)
            HStack {
                Text("Folders").font(.system(size: 32, weight: .bold))
                Spacer()
                Menu {
                    Button("Upload a folder", systemImage: "folder.badge.plus") { importKind = .folder; importing = true }
                    Button("Upload files", systemImage: "doc.badge.plus") { importKind = .item; importing = true }
                    Button("New empty folder", systemImage: "folder.fill.badge.plus") { newName = ""; showNew = true }
                } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
                        .frame(width: 40, height: 40).background(DotRenderer.defaultColor, in: Circle())
                }.accessibilityLabel("Add")
            }.padding(.horizontal, 20).padding(.vertical, 8)

            if folders.folders.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(folders.folders, id: \.self) { name in
                            Button { opened = name } label: { row(name) }.buttonStyle(.plain)
                                .contextMenu { Button("Remove from Space Dots and AI", systemImage: "trash", role: .destructive) { folders.deleteFolder(name) } }
                        }
                        Text("Folders are copied into Space Dots and AI. Changes happen to the copies, never to the originals.")
                            .font(.system(size: 12)).foregroundColor(.black.opacity(0.4)).multilineTextAlignment(.center).padding(.top, 8).padding(.horizontal, 20)
                    }.padding(.horizontal, 16).padding(.bottom, 120)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .preferredColorScheme(.light)
        .fileImporter(isPresented: $importing, allowedContentTypes: [importKind], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                do { let n = try folders.importItems(urls); message = n == 1 ? "1 file added." : "\(n) files added." }
                catch { message = "Couldn't add that: \(error.localizedDescription)" }
            case .failure: message = "Couldn't open that."
            }
        }
        .alert("New folder", isPresented: $showNew) {
            TextField("Name", text: $newName)
            Button("Create") { folders.createFolder(newName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK", role: .cancel) {} }
        .fullScreenCover(item: Binding(get: { opened.map { FolderRef(name: $0) } }, set: { opened = $0?.name })) { ref in
            FolderDetailView(folder: ref.name, folders: folders, agents: agents, authState: authState, onLogin: onLogin) { opened = nil }
        }
    }

    private struct FolderRef: Identifiable { let name: String; var id: String { name } }

    private func row(_ name: String) -> some View {
        let count = folders.files(name).count
        let changed = folders.changes(in: name).filter { !$0.undone }.count
        return HStack(spacing: 14) {
            Image(systemName: "folder.fill").font(.system(size: 26)).foregroundColor(DotRenderer.defaultColor).frame(width: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.system(size: 17, weight: .bold)).foregroundColor(.black)
                Text("\(count) file\(count == 1 ? "" : "s")" + (changed > 0 ? " · \(changed) change\(changed == 1 ? "" : "s")" : ""))
                    .font(.system(size: 13)).foregroundColor(.black.opacity(0.5))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundColor(.black.opacity(0.3))
        }
        .padding(14).background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.plus").font(.system(size: 44)).foregroundColor(.black.opacity(0.7))
            Text("No folders yet").font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Upload a folder or some files. Then you, or your agents, can read and edit them.")
                .font(.system(size: 13)).foregroundColor(.black.opacity(0.55)).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button { importKind = .folder; importing = true } label: {
                Text("Upload a folder").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
                    .padding(.horizontal, 26).frame(height: 48).background(DotRenderer.defaultColor, in: Capsule())
            }.buttonStyle(.plain).padding(.top, 6)
            Button("Upload files") { importKind = .item; importing = true }.font(.system(size: 14, weight: .semibold)).foregroundColor(.black.opacity(0.6))
            Spacer(); Spacer()
        }
    }
}

// MARK: - One folder

struct FolderDetailView: View {
    let folder: String
    @ObservedObject var folders: FolderStore
    @ObservedObject var agents: AgentsStore
    @ObservedObject var authState: AuthState
    let onLogin: () -> Void
    @ObservedObject private var projects = ProjectStore.shared
    @ObservedObject private var workspaces = WorkspaceStore.shared
    private enum Cover: String, Identifiable { case team, space; var id: String { rawValue } }
    @State private var cover: Cover?
    /// The workspace (look) this folder's space was last in; a new space opens in the current one.
    private var spaceWorkspace: Workspace {
        let past = projects.projects.first { $0.linkedFolder == folder }
        return workspaces.all.first { $0.id == past?.workspaceID } ?? workspaces.current
    }
    let onClose: () -> Void

    @State private var editing: WorkspaceFile?
    @State private var showChanges = false
    @State private var importing = false

    var body: some View {
        let tree = folders.tree(folder)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).foregroundColor(.black)
                        .frame(width: 42, height: 42).background(Color.black.opacity(0.06), in: Circle())
                }.buttonStyle(.plain)
                Text(folder).font(.system(size: 20, weight: .bold)).lineLimit(1)
                Spacer()
                Button { importing = true } label: {
                    Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundColor(.black).frame(width: 42, height: 42).background(Color.black.opacity(0.06), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Add files")
                Button { showChanges = true } label: {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 16, weight: .bold)).foregroundColor(.black).frame(width: 42, height: 42).background(Color.black.opacity(0.06), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("Changes")
            }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)

            Button { cover = .team } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 15, weight: .bold))
                    Text("Ask agents to work on this folder").font(.system(size: 15, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(DotRenderer.defaultColor).padding(.horizontal, 16).frame(height: 50)
                .background(DotRenderer.defaultColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }.buttonStyle(.plain).padding(.horizontal, 14).padding(.bottom, 6)

            Button { cover = .space } label: {
                let past = projects.projects.first { $0.linkedFolder == folder }
                HStack(spacing: 10) {
                    Image(systemName: "circle.hexagongrid.fill").font(.system(size: 15, weight: .bold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Continue in the space").font(.system(size: 15, weight: .bold))
                        Text(past.map { "Its own dots and history · \($0.teamIDs.count) dot\($0.teamIDs.count == 1 ? "" : "s")" } ?? "Open this folder with its own dots and conversation").font(.system(size: 11.5, weight: .medium)).opacity(0.7)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white).padding(.horizontal, 16).frame(height: 54)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }.buttonStyle(.plain).padding(.horizontal, 14).padding(.bottom, 6)

            if tree.isEmpty {
                VStack(spacing: 8) { Spacer(); Text("This folder is empty").font(.system(size: 16, weight: .bold)); Text("Add files, or ask an agent to create some.").font(.system(size: 13)).foregroundColor(.black.opacity(0.5)); Spacer(); Spacer() }
            } else {
                List {
                    ForEach(tree) { item in
                        Button { if !item.isDirectory { editing = item } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.isDirectory ? "folder.fill" : icon(for: item.name)).font(.system(size: 16))
                                    .foregroundColor(item.isDirectory ? DotRenderer.defaultColor : .black.opacity(0.55)).frame(width: 24)
                                Text(item.name).font(.system(size: 15, weight: item.isDirectory ? .bold : .medium)).foregroundColor(.black).lineLimit(1)
                                Spacer()
                                if !item.isDirectory { Text(sizeText(item.size)).font(.system(size: 11, weight: .semibold)).foregroundColor(.black.opacity(0.35)) }
                            }
                            .padding(.leading, CGFloat(item.depth) * 18)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if !item.isDirectory {
                                Button(role: .destructive) { _ = try? folders.delete(folder, item.path, by: "You") } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }.listStyle(.plain)
            }
        }
        .background(Color.white)
        .preferredColorScheme(.light)
        .sheet(item: $editing) { file in FileEditorView(folder: folder, file: file, folders: folders) { editing = nil } }
        .sheet(isPresented: $showChanges) { ChangesView(folder: folder, folders: folders) { showChanges = false } }
        .fullScreenCover(item: $cover) { which in
            switch which {
            case .team: TeamRoomView(store: agents, folders: folders, preselected: folder) { cover = nil }
            case .space:
                TeamFlowView(agents: agents, folders: folders, projects: projects, authState: authState, workspace: spaceWorkspace, folderName: folder,
                             onLogin: { cover = nil; onLogin() }, onClose: { cover = nil })
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { _ = try? folders.importItems(urls, into: folder) }
        }
    }

    private func icon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "swift", "js", "ts", "py", "java", "c", "cpp", "h", "html", "css", "json", "rb", "go", "rs": return "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "gif", "heic": return "photo"
        case "md", "txt", "rtf": return "doc.text"
        default: return "doc"
        }
    }

    private func sizeText(_ bytes: Int) -> String {
        bytes < 1024 ? "\(bytes) B" : (bytes < 1_048_576 ? "\(bytes / 1024) KB" : String(format: "%.1f MB", Double(bytes) / 1_048_576))
    }
}

// MARK: - Editing a file by hand

struct FileEditorView: View {
    let folder: String
    let file: WorkspaceFile
    @ObservedObject var folders: FolderStore
    let onClose: () -> Void
    @State private var text = ""
    @State private var original = ""
    @State private var readable = true
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if readable {
                    TextEditor(text: $text).focused($focused).font(.system(size: 14, design: .monospaced))
                        .autocorrectionDisabled().textInputAutocapitalization(.never).padding(10)
                } else {
                    VStack(spacing: 8) { Spacer(); Image(systemName: "doc.fill").font(.system(size: 36)).foregroundColor(.black.opacity(0.4)); Text("This isn't a text file, or it is too large to edit here.").font(.system(size: 14)).foregroundColor(.black.opacity(0.55)).multilineTextAlignment(.center).padding(.horizontal, 30); Spacer() }
                }
            }
            .navigationTitle(file.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close", action: onClose) }
                ToolbarItemGroup(placement: .confirmationAction) {
                    if focused { Button { focused = false } label: { Image(systemName: "keyboard.chevron.compact.down") } }
                    Button("Save") {
                        do { if text != original { try folders.write(folder, file.path, content: text, by: "You") }; onClose() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(!readable || text == original)
                }
            }
            .alert(error ?? "", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} }
        }
        .tint(.black).preferredColorScheme(.light)
        .onAppear {
            if let content = folders.read(folder, file.path) { text = content; original = content } else { readable = false }
        }
    }
}

// MARK: - What changed

struct ChangesView: View {
    let folder: String
    @ObservedObject var folders: FolderStore
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            let list = folders.changes(in: folder)
            Group {
                if list.isEmpty {
                    VStack(spacing: 8) { Spacer(); Text("No changes yet").font(.system(size: 16, weight: .bold)); Text("Edits made by you or your agents show up here, and can be undone.").font(.system(size: 13)).foregroundColor(.black.opacity(0.5)).multilineTextAlignment(.center).padding(.horizontal, 30); Spacer() }
                } else {
                    List(list) { change in
                        HStack(spacing: 10) {
                            Image(systemName: change.kind == .created ? "plus.circle.fill" : (change.kind == .deleted ? "trash.circle.fill" : "pencil.circle.fill"))
                                .font(.system(size: 22)).foregroundColor(change.undone ? .black.opacity(0.2) : DotRenderer.defaultColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(change.kind.rawValue.capitalized) \(change.path)").font(.system(size: 14, weight: .semibold)).foregroundColor(.black).lineLimit(1)
                                Text("by \(change.by) · \(change.at.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundColor(.black.opacity(0.45))
                            }
                            Spacer()
                            if change.undone { Text("Undone").font(.system(size: 12, weight: .semibold)).foregroundColor(.black.opacity(0.35)) }
                            else { Button("Undo") { folders.undo(change) }.font(.system(size: 13, weight: .bold)).buttonStyle(.borderless).foregroundColor(DotRenderer.defaultColor) }
                        }
                    }.listStyle(.plain)
                }
            }
            .navigationTitle("Changes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) } }
        }.tint(.black).preferredColorScheme(.light)
    }
}
