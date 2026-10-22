import Foundation

// Fixtures replace only the server and the surrounding UI's agent catalogue, not the runner, tools, approval system or folder store.
struct SpacesAgent { var id: String; var name: String; var role = "Research"; var prompt = "Be accurate"; var access = AgentAccess() }
struct AgentMessage {
    enum Kind { case user, agent, system, change }
    var kind: Kind; var from: String; var to: String? = nil; var text: String; var changeID: UUID? = nil
}
@MainActor final class AgentsStore {
    var all: [SpacesAgent]; var notes: [String] = []
    init(_ agent: SpacesAgent) { all = [agent] }
    func addNote(_ text: String, by: String) { notes.append(text) }
}
enum SpacechatService {
    enum ServiceError: LocalizedError { case missing, notSignedIn, unavailable(String) }
    @MainActor static var handler: ([String: Any]) async throws -> [String: Any] = { _ in [:] }
    @MainActor static func post(_ path: String, body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] { precondition(path == "spaces/agents"); precondition(timeout <= 60); return try await handler(body) }
}
@main struct SpacesAgentChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]); let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true); defer { try? fm.removeItem(at: root) }
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); count += 1; print("PASS: \(label)") }
        let folderStore = FolderStore(root: root.appendingPathComponent("folders")); let folder = folderStore.makeFolder("Research")!
        try folderStore.write(folder, "plan.txt", content: "Launch in June.\nProject identifier TS-999.\nKeep the first release small.", by: "Fixture")
        let sourceRoot = folderStore.researchRoot(folder)!
        let index = WorkspaceResearch()
        let result = try await index.search(root: sourceRoot, query: "TS-999")
        check(result.hits.first?.path == "plan.txt", "Ranked search retrieves an exact project identifier")
        check((result.hits.first?.firstLine ?? 99) <= 2 && (result.hits.first?.lastLine ?? 0) >= 2 && result.hits.first?.revision.count == 64, "Evidence carries line numbers and a full source digest")
        let cached = try await index.search(root: sourceRoot, query: "launch")
        check(cached.cacheHits == 1, "Unchanged files reuse their index")
        try folderStore.write(folder,"plan.txt",content:"Launch in July.\nProject identifier NEW-777.",by:"Fixture")
        let changed = try await index.search(root:sourceRoot,query:"NEW-777")
        check(changed.hits.first?.revision != result.hits.first?.revision, "Source edits invalidate cached evidence")
        let other = folderStore.makeFolder("Private")!; try folderStore.write(other,"secret.txt",content:"Confidential unrelated data",by:"Fixture")
        let isolated = try await index.search(root:sourceRoot,query:"Confidential")
        check(isolated.hits.isEmpty, "Search never crosses the selected folder")
        let outside=root.appendingPathComponent("outside.txt");try "linked-secret".write(to:outside,atomically:true,encoding:.utf8)
        try fm.createSymbolicLink(at:sourceRoot.appendingPathComponent("link.txt"),withDestinationURL:outside)
        check(folderStore.read(folder,"link.txt")==nil, "Folder reads refuse escaping symbolic links")
        let linked = try await index.search(root:sourceRoot,query:"linked-secret")
        check(linked.hits.isEmpty, "Index excludes symbolic links")
        try folderStore.write(folder,"long.txt",content:String(repeating:"padding ",count:500)+"UNIQUEENDTOKEN",by:"Fixture")
        let long = try await index.search(root:sourceRoot,query:"UNIQUEENDTOKEN")
        check(long.hits.first?.path == "long.txt", "Search includes the end of long unbroken source lines")
        var limits = WorkspaceResearch.Limits();limits.files=1
        let limited = try await WorkspaceResearch(limits:limits).search(root:sourceRoot,query:"launch")
        check(limited.truncated, "Bounded searches disclose partial coverage")
        do { try folderStore.write(folder,"plan.txt",content:"stale",by:"Agent",expected:.matching("Launch in June.")); preconditionFailure("Expected conflict") } catch FolderError.conflict { count+=1;print("PASS: Stale content cannot overwrite a newer file") }
        let before = folderStore.read(folder,"plan.txt")!
        try folderStore.write(folder,"plan.txt",content:before+"\nReviewed.",by:"Agent",expected:.matching(before))
        check(folderStore.read(folder,"plan.txt")!.contains("Reviewed."), "Matching source edits still succeed")
        func parse(_ json:[String:Any], write:Bool=true, copy:Bool=false) throws -> AgentResponseValidation.Turn { try AgentResponseValidation.parse(json,canRead:true,canWrite:write,canRun:false,canNote:true,copy:copy) }
        for (label,json) in [
            ("Reject path traversal",["actions":[["type":"write","path":"../escape","content":"no"]]] as [String:Any]),
            ("Reject unknown tools",["actions":[["type":"shell","code":"no"]]]),
            ("Reject nonintegral line numbers",["actions":[["type":"read","path":"plan.txt","start":1.5]]]),
            ("Reject excessive actions",["actions":Array(repeating:["type":"list"],count:5)]),
            ("Reject malformed action arrays",["actions":"not an array"])
        ] { do { _=try parse(json);preconditionFailure(label) } catch { count+=1; print("PASS: \(label)") } }
        do {_=try parse(["actions":[["type":"write","path":"plan.txt","content":"no"]]],write:false);preconditionFailure("Read-only write allowed")}catch{count+=1;print("PASS: Read-only access rejects changes before execution")}
        do {_=try parse(["actions":[["type":"spawn","tasks":["nested"]]]],copy:true);preconditionFailure("Recursive spawning allowed")}catch{count+=1;print("PASS: Copies cannot recursively create more copies")}
        let pendingSearch = try parse(["done":true,"actions":[["type":"search","query":"launch"]]])
        check(pendingSearch.done == false, "A pending search cannot be declared complete")
        let agent=SpacesAgent(id:"fixture",name:"Research Dot"),store=AgentsStore(SpacesAgent(id:"fixture",name:"Research Dot"))
        let defaults=UserDefaults(suiteName:"spaces-agent-checks-\(UUID().uuidString)")!;let approvals=ApprovalCenter(defaults:defaults)
        let runner=AgentRunner(folders:folderStore,approvals:approvals)
        var turn=0, receivedSearch=false
        SpacechatService.handler={body in turn+=1;if turn==1{return ["actions":[["type":"search","query":"NEW-777"]]]};let results=body["results"] as? [[String:String]] ?? [];receivedSearch=results.contains{($0["content"] ?? "").contains("sha256:")};return ["message":["text":"Found the current source."],"done":true]}
        let outcome=await runner.handOff(agent:agent,message:"Research the project identifier",store:store,folder:folder,canEdit:false)
        check(outcome.ok && receivedSearch, "Native runner hands verified cited search results to its next turn")
        // A real approval waits while the owner edits: the native tool must preserve the new contents.
        var steps=0
        SpacechatService.handler={_ in steps+=1;if steps==1{return ["actions":[["type":"read","path":"plan.txt"]]]};if steps==2{return ["actions":[["type":"write","path":"plan.txt","content":String(repeating:"new full text ",count:20)]]]};return ["message":["text":"Reviewed the result."],"done":true]}
        let pending=Task{await runner.handOff(agent:agent,message:"Update plan",store:store,folder:folder,canEdit:true)}
        for _ in 0..<300 where approvals.current == nil {try await Task.sleep(nanoseconds:1_000_000)}
        check(approvals.current != nil, "File mutation waits for a concrete approval")
        try folderStore.write(folder,"plan.txt",content:"Concurrent owner edit",by:"Owner")
        approvals.resolve(approvals.current!.id,.once);_=await pending.value
        check(folderStore.read(folder,"plan.txt")=="Concurrent owner edit", "Approval delay cannot overwrite a concurrent owner edit")
        // Repeat with Stop while the approval is pending.
        steps=0
        let stopped=Task{await runner.handOff(agent:agent,message:"Update again",store:store,folder:folder,canEdit:true)}
        for _ in 0..<300 where approvals.current == nil {try await Task.sleep(nanoseconds:1_000_000)}
        stopped.cancel();_=await stopped.value
        check(approvals.current == nil, "Task cancellation automatically dismisses its pending approval")
        check(folderStore.read(folder,"plan.txt")=="Concurrent owner edit", "Cancellation while awaiting approval leaves files intact")
        steps=0
        let revoked=Task{await runner.handOff(agent:agent,message:"Update with current access",store:store,folder:folder,canEdit:true)}
        for _ in 0..<300 where approvals.current == nil {try await Task.sleep(nanoseconds:1_000_000)}
        check(approvals.current != nil, "Permission revocation fixture reaches the real approval wait")
        store.all[0].access.write=false;approvals.resolve(approvals.current!.id,.once);_=await revoked.value
        check(folderStore.read(folder,"plan.txt")=="Concurrent owner edit", "Revoking access during approval prevents the write")
        store.all[0].access.write=true
        SpacechatService.handler={_ in ["actions":[["type":"write","path":"plan.txt","content":"forged replacement"]]]}
        let readOnly=await runner.handOff(agent:agent,message:"Read only",store:store,folder:folder,canEdit:false)
        check(!readOnly.ok && approvals.current == nil && folderStore.read(folder,"plan.txt")=="Concurrent owner edit", "Forged write actions cannot bypass native canEdit=false")
        let benchmarkRoot=root.appendingPathComponent("scale");try fm.createDirectory(at:benchmarkRoot,withIntermediateDirectories:true)
        for i in 0..<1_000 {try "Document \(i). General background text.\n\(i == 999 ? "FINAL-EXACT-9999" : "unrelated detail")".write(to:benchmarkRoot.appendingPathComponent(String(format:"file-%04d.txt",i)),atomically:true,encoding:.utf8)}
        let clock=Date(), benchmark=WorkspaceResearch();let measured=try await benchmark.search(root:benchmarkRoot,query:"FINAL-EXACT-9999")
        check(measured.files==1_000 && measured.hits.first?.path == "file-0999.txt", "1,000-file corpus finds a source beyond the old first-400 scan")
        print("BENCHMARK: 1000 files, \(measured.chunks) passages, cold query \(String(format:"%.1f",Date().timeIntervalSince(clock)*1000)) ms")
        print("\(count) native agent/research/validation checks passed.")
    }
}
