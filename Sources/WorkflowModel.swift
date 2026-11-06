import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TaskRow:Identifiable {
    var plan:TaskPlan
    var state:RowState
    var message:String
    var issue:TaskIssue?
    var output:URL?
    var notes:[String]=[]
    var technical=""
    var id:String { plan.id }
    var finished:Bool { [.saved,.checked,.noChange].contains(state) }
    init(_ plan:TaskPlan) {
        self.plan=plan;issue=plan.issue
        if let problem=plan.issue { state = .attention;message=problem.message }
        else if let skip=plan.skipReason { state = .noChange;message=skip }
        else { state = .ready;message=plan.preview }
    }
}
struct TaskSession {
    var inputs:[URL]=[]
    var rows:[TaskRow]=[]
    var folder:URL?
    var names:[String:String]=[:]
    var notice:String?
    var report:URL?
    var details=""
    var needsPreparation=false
    var freeSpace:UInt64?
    var summary:String {
        if rows.isEmpty { return "Choose files to get started." }
        let states:[(RowState,String)]=[(.ready,"ready"),(.working,"working"),(.saved,"saved"),(.checked,"checked"),(.noChange,"need no change"),(.attention,"need attention"),(.stopped,"stopped")]
        return states.compactMap { state,label in let count=rows.filter { $0.state==state }.count;return count>0 ? "\(count) \(count==1 && state == .attention ? "needs attention" : count==1 && state == .noChange ? "needs no change" : label)" : nil }.joined(separator:" · ")
    }
}

@MainActor final class UtilityModel:ObservableObject {
    static let shared=UtilityModel()
    @Published private(set) var activeTool:UtilityTool
    @Published private(set) var sessions:[UtilityTool:TaskSession]=[:]
    @Published var busy=false
    @Published var preparing=false
    @Published var stopping=false
    @Published var fraction:Double?
    @Published var currentTitle=""
    @Published var position=""
    @Published var phase=""
    @Published var began:Date?
    @Published var showHelp=false
    @Published var sidebarVisible=true
    var quitAfterCleanup=false
    let defaults:UserDefaults
    let automaticPreparation:Bool
    private var control:WorkControl?
    private var highWater:Double=0
    init(defaults:UserDefaults = .standard,automaticPreparation:Bool=true) {
        self.defaults=defaults;self.automaticPreparation=automaticPreparation
        activeTool=UtilityTool.restoredSelection(defaults.string(forKey:"lastTool"))
        for tool in UtilityTool.tasks {
            var state=TaskSession()
            if let path=defaults.string(forKey:"saveFolder."+tool.rawValue) ?? defaults.string(forKey:"saveFolder") { state.folder=URL(fileURLWithPath:path) }
            sessions[tool]=state
        }
    }
    var task:TaskSession { sessions[activeTool] ?? TaskSession() }
    var rows:[TaskRow] { task.rows }
    var inputs:[URL] { task.inputs }
    var output:URL? { task.folder }
    var results:[URL] { rows.compactMap(\.output) }
    var readyCount:Int { rows.filter { $0.state == .ready }.count }
    var unfinishedCount:Int { rows.filter { !$0.finished }.count }
    var completedCount:Int { rows.filter(\.finished).count }
    var canRun:Bool { !busy && readyCount>0 && (!activeTool.writesFiles || output != nil) }
    var canRetry:Bool { !busy && rows.contains { $0.state == .stopped || ($0.state == .attention && $0.plan.issue == nil) } }
    func mutate(_ tool:UtilityTool,_ change:(inout TaskSession)->Void) { var state=sessions[tool] ?? TaskSession();change(&state);sessions[tool]=state }
    func activate(_ tool:UtilityTool) {
        guard !busy,tool != activeTool else { return }
        activeTool=tool;defaults.set(tool.rawValue,forKey:"lastTool");phase="";fraction=nil
        if task.needsPreparation && automaticPreparation { prepare() }
    }
    func setOutput(_ url:URL,persist:Bool=true) {
        guard !busy else { return }
        let tool=activeTool
        mutate(tool) { $0.folder=url;$0.notice=nil;$0.freeSpace=nil }
        if persist { defaults.set(url.path,forKey:"saveFolder."+tool.rawValue) }
        if automaticPreparation && !inputs.isEmpty { prepare() }
    }
    func selectOutput() {
        guard !busy,let url=AppModel.shared.chooseFile("Choose where to save these copies",folder:true).first else { return };setOutput(url)
    }
    private func fileSelection()->[URL]? {
        let p=NSOpenPanel();p.title=activeTool == .join ? "Choose any split part or its parts folder" : "Choose game files";p.canChooseFiles=true;p.canChooseDirectories=activeTool == .join;p.allowsMultipleSelection=activeTool.allowsMultiple
        if activeTool != .join { p.allowedContentTypes=activeTool.extensions.sorted().map { UTType(filenameExtension:$0) ?? .data } }
        return p.runModal() == .OK ? p.urls : nil
    }
    func chooseFiles() { guard !busy,let urls=fileSelection() else { return };add(activeTool,urls:urls) }
    func chooseFolder() {
        guard !busy,activeTool != .join,let url=AppModel.shared.chooseFile("Choose a folder of game files",folder:true).first else { return };add(activeTool,urls:[url])
    }
    func add(_ tool:UtilityTool,urls:[URL],replacing:Bool=false) {
        guard !busy,tool==activeTool,!urls.isEmpty else { return }
        if tool == .join && urls.count != 1 { mutate(tool) { $0.notice="Choose one parts folder or one part at a time. Your current selection is unchanged." };return }
        let known=replacing ? Set<URL>() : Set(inputs)
        if !automaticPreparation {
            do { finishImport(try InputCollector.collect(urls,tool:tool,known:known,control:WorkControl()),tool:tool,replacing:replacing) }
            catch { mutate(tool) { $0.notice=TaskIssue.from(error).message } }
            return
        }
        let token=WorkControl();control=token;busy=true;preparing=true;stopping=false;phase="Finding game files…";fraction=nil;began=Date()
        DispatchQueue.global(qos:.userInitiated).async {
            let result:Result<CollectedInputs,Error>
            do { result = .success(try InputCollector.collect(urls,tool:tool,known:known,control:token) { count in DispatchQueue.main.async { if !self.stopping { self.phase="Looking for game files · \(count) items read" } } }) }
            catch { result = .failure(error) }
            let cancelled=(try? token.check())==nil
            DispatchQueue.main.async {
                self.busy=false;self.preparing=false;self.stopping=false;self.began=nil;self.control=nil;self.phase=""
                if self.quitAfterCleanup { NSApp.terminate(nil);return }
                if cancelled { self.mutate(tool) { $0.notice="Stopped finding files. Your previous selection is unchanged." } }
                else {
                    switch result {
                    case .success(let collected):self.finishImport(collected,tool:tool,replacing:replacing)
                    case .failure(let error):self.mutate(tool) { $0.notice=TaskIssue.from(error).message }
                    }
                }
            }
        }
    }
    private func finishImport(_ collected:CollectedInputs,tool:UtilityTool,replacing:Bool=false) {
        guard !collected.files.isEmpty else {
            mutate(tool) { $0.notice=collected.ignored>0 ? "No supported files added. \(collected.ignored) unsupported items were ignored." : collected.duplicates>0 ? "These files are already in the list." : "No supported game files were found. Choose files or another folder." };return
        }
        mutate(tool) { state in
            if replacing { let folder=state.folder;state=TaskSession();state.folder=folder }
            state.inputs=(tool == .join ? collected.files : Array(Set(state.inputs+collected.files))).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            state.needsPreparation=true
            state.notice=(collected.ignored>0 || collected.duplicates>0) ? "\(collected.files.count) added · \(collected.duplicates) duplicates skipped · \(collected.ignored) unsupported items ignored" : nil
        }
        if automaticPreparation { prepare() }
    }
    func remove(_ url:URL) {
        guard !busy else { return }
        mutate(activeTool) { state in state.inputs.removeAll { $0==url };state.rows.removeAll { $0.plan.sources.contains { $0.url==url } };state.notice=nil;state.needsPreparation=true }
        if automaticPreparation && !inputs.isEmpty { prepare() }
    }
    func newFiles() {
        guard !busy,let urls=fileSelection() else { return }
        add(activeTool,urls:urls,replacing:true)
    }
    func clearSelection() { guard !busy else { return };mutate(activeTool) { state in let folder=state.folder;state=TaskSession();state.folder=folder } }
    func keyChanged() {
        for tool in UtilityTool.tasks where tool.needsKeys { mutate(tool) { $0.needsPreparation=true } }
        if !busy,activeTool.needsKeys,!inputs.isEmpty,automaticPreparation { prepare() }
    }
    func cancel() { guard busy else { return };stopping=true;phase="Stopping safely…";control?.cancel() }
    func makeRuntime(_ tool:UtilityTool,control:WorkControl,event:@escaping(String,Double?)->Void) throws -> (UtilityEngine,HelperSession?) {
        let app=AppModel.shared
        let runtime=tool.needsKeys && app.keys != nil ? try app.helpers() : nil
        let patcher=app.keys.flatMap { key in runtime.map { PatchEngine(executable:$0.executable,keys:key,extraTitleKeys:app.titleKeys,packer:$0.packer,control:control,event:event) } }
        return (UtilityEngine(patcher:patcher,control:control,event:event),runtime)
    }
    func prepare(autoStart:Bool=false,force:Set<String>=[]) {
        guard !busy,!inputs.isEmpty else { return }
        let tool=activeTool,selected=inputs,folder=output,names=task.names,old=rows,taskControl=WorkControl()
        let runtime: (UtilityEngine,HelperSession?)
        do { runtime=try makeRuntime(tool,control:taskControl) { stage,value in
            guard stage.hasPrefix("Preparing file ") else { return }
            DispatchQueue.main.async { if !self.stopping { self.phase=stage;self.fraction=value } }
        } }
        catch { let issue=TaskIssue.from(error);mutate(tool) { state in state.rows=selected.map { var p=TaskPlan.fallback([$0]);p.issue=issue;return TaskRow(p) };state.needsPreparation=false };return }
        control=taskControl;busy=true;preparing=true;stopping=false;fraction=nil;phase="Reading files and preparing your task…";currentTitle="";position="";began=Date()
        DispatchQueue.global(qos:.userInitiated).async {
            defer { withExtendedLifetime(runtime.1) {} }
            let plans: [TaskPlan]
            do { plans=try PreparationEngine(engine:runtime.0).prepare(tool,inputs:selected,folder:folder,names:names) }
            catch { plans=selected.map { var p=TaskPlan.fallback([$0]);p.issue=TaskIssue.from(error);return p } }
            let cancelled=(try? taskControl.check())==nil
            let free=folder.flatMap { (try? FileManager.default.attributesOfFileSystem(forPath:$0.path)[.systemFreeSize] as? NSNumber)?.uint64Value }
            DispatchQueue.main.async {
                self.applyPreparation(plans,tool:tool,previous:old,force:force,cancelled:cancelled)
                self.mutate(tool) { $0.freeSpace=free }
                self.busy=false;self.preparing=false;self.stopping=false;self.began=nil;self.phase="";self.control=nil
                if self.quitAfterCleanup { NSApp.terminate(nil);return }
                if autoStart && !cancelled { self.runReady() }
            }
        }
    }
    func applyPreparation(_ plans:[TaskPlan],tool:UtilityTool,previous:[TaskRow],force:Set<String>=[],cancelled:Bool=false) {
        let existing=Dictionary(uniqueKeysWithValues:previous.map { ($0.id,$0) })
        mutate(tool) { state in
            state.rows=plans.map { plan in
                if let old=existing[plan.id],old.finished,old.plan.sourceStamps==plan.sourceStamps,!force.contains(plan.id) { return old }
                var row=TaskRow(plan)
                if cancelled { row.state = .stopped;row.issue=nil;row.message="Stopped reading this file. Retry when you’re ready." }
                return row
            }
            state.needsPreparation=false
        }
    }
    func useSeparateName(_ id:String) {
        guard !busy,let row=rows.first(where:{$0.id==id}),let folder=output,let original=row.plan.outputName else { return }
        let file=URL(fileURLWithPath:original),ext=activeTool == .split ? "" : file.pathExtension,base=(ext.isEmpty ? original : file.deletingPathExtension().lastPathComponent).replacingOccurrences(of:#"\] [0-9]+$"#,with:"]",options:.regularExpression)
        for index in 2...10000 {
            let candidate=base+" \(index)"+(ext.isEmpty ? "" : "."+ext)
            if !FileManager.default.fileExists(atPath:folder.appendingPathComponent(candidate).path) {
                mutate(activeTool) { $0.names[id]=candidate }
                if automaticPreparation { prepare(force:[id]) }
                return
            }
        }
        mutate(activeTool) { $0.notice="Choose another save folder; there are too many copies with this name." }
    }
    func retry() { prepare(autoStart:true) }
    func runReady() {
        guard canRun else { return }
        let tool=activeTool,work=rows.filter { $0.state == .ready },folder=output,taskControl=WorkControl()
        let runtime: (UtilityEngine,HelperSession?)
        // The engines for each row are created below, with their own progress context.
        do { runtime=try makeRuntime(tool,control:taskControl) {_,_ in} }
        catch { let issue=TaskIssue.from(error);mutate(tool) { state in for index in state.rows.indices where state.rows[index].state == .ready { state.rows[index].state = .attention;state.rows[index].issue=issue;state.rows[index].message=issue.message } };return }
        let keys=AppModel.shared.keys,extra=AppModel.shared.titleKeys
        control=taskControl;busy=true;preparing=false;stopping=false;began=Date();highWater=0;fraction=0
        mutate(tool) { $0.notice=nil;$0.details="SwitchBench \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development") · \(tool.title)\nOriginal files are unchanged.\n" }
        DispatchQueue.global(qos:.userInitiated).async {
            defer { withExtendedLifetime(runtime.1) {} }
            var outcomes:[String:TaskRow]=[:]
            for (index,original) in work.enumerated() {
                guard (try? taskControl.check()) != nil else { break }
                var row=original;row.state = .working
                let title=row.plan.title,id=row.id
                DispatchQueue.main.async {
                    self.currentTitle=title;self.position="\(index+1) of \(work.count)";self.phase="Starting…"
                    self.mutate(tool) { state in if let i=state.rows.firstIndex(where:{$0.id==id}) { state.rows[i].state = .working } }
                }
                let event:(String,Double?)->Void = { stage,value in
                    DispatchQueue.main.async {
                        guard !self.stopping else { return }
                        self.phase=tool.progressText(stage)
                        if let value {
                            self.highWater=max(self.highWater,(Double(index)+min(1,max(0,value)))/Double(work.count));self.fraction=self.highWater
                        } else { self.fraction=nil }
                    }
                }
                let patcher=keys.flatMap { key in runtime.1.map { PatchEngine(executable:$0.executable,keys:key,extraTitleKeys:extra,packer:$0.packer,control:taskControl,event:event) } }
                let engine=UtilityEngine(patcher:patcher,control:taskControl,event:event)
                do {
                    try autoreleasepool {
                        if tool == .inspect {
                            let info=try engine.inspect(row.plan.sources[0].url),checked=try engine.verify(info)
                            row.plan.inspection=info;row.plan.sources=[PreparationEngine(engine:engine).describe(info)];row.plan.title=row.plan.sources[0].name
                            row.state = .checked;row.message=checked.notes.isEmpty ? "No problems found in the checked game data." : "Listed game data passed. Review the notes below."
                            row.notes=checked.notes;row.technical="\(checked.checked) content archives matched their listed hashes.\n"+checked.notes.joined(separator:"\n")
                        } else {
                            row.output=try PreparationEngine(engine:engine).execute(tool,plan:row.plan,folder:folder!)
                            row.state = .saved
                            switch tool {
                            case .update:row.message="Updated copy saved and its data checked."
                            case .combine:row.message="Combined file saved and checked."
                            case .convert:row.message="NSP copy saved and checked."
                            case .split:row.message="Parts saved and checked. Keep the parts list with them."
                            case .join:row.message="Complete file saved and checked.";if row.plan.preview.contains("No original checksum") { row.notes=["No original checksum was available. Part numbers and the final container were checked."] }
                            case .trim:row.message="Smaller XCI saved and checked."
                            case .compress:row.message="Smaller copy saved and checked."
                            case .inspect:break
                            }
                        }
                    }
                } catch {
                    if (try? taskControl.check())==nil { row.state = .stopped;row.message="Stopped. No unfinished copy was kept.";row.issue=nil }
                    else { row.state = .attention;row.issue=TaskIssue.from(error);row.message=row.issue!.message;row.technical=PatchEngine.scrub(error.localizedDescription) }
                }
                outcomes[id]=row
                let result=row
                DispatchQueue.main.async {
                    self.mutate(tool) { state in
                        if let i=state.rows.firstIndex(where:{$0.id==result.id}) { state.rows[i]=result }
                        state.details += "\n\(result.plan.title): \(result.state.rawValue) · \(result.message)\n"+(result.output?.path ?? "")+"\n"+result.technical
                    }
                }
                if row.issue?.kind == .helper { break }
            }
            let cancelled=(try? taskControl.check())==nil,final=outcomes
            let finalFree=folder.flatMap { (try? FileManager.default.attributesOfFileSystem(forPath:$0.path)[.systemFreeSize] as? NSNumber)?.uint64Value }
            DispatchQueue.main.async {
                self.mutate(tool) { state in
                    state.freeSpace=finalFree
                    for i in state.rows.indices where work.contains(where:{$0.id==state.rows[i].id}) && final[state.rows[i].id]==nil {
                        state.rows[i].state = .stopped;state.rows[i].message=cancelled ? "Not started because the task was stopped." : "Not started. Retry after resolving the processing-component problem."
                    }
                }
                self.busy=false;self.stopping=false;self.fraction=nil;self.currentTitle="";self.position="";self.phase="";self.began=nil;self.control=nil
                let finished=Array(final.values).filter { [.saved,.checked].contains($0.state) }
                AppModel.shared.record(finished.map { row in RecentResult(date:Date(),tool:tool,title:row.plan.title,message:row.message,paths:(row.output.map { [$0] } ?? row.plan.sources.map(\.url)).map(\.path)) })
                self.saveLocalReport(tool)
                AppModel.shared.finished(self.sessions[tool]?.summary ?? "Task finished.")
                if self.quitAfterCleanup { NSApp.terminate(nil) }
            }
        }
    }
    func revealResults() { if !results.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(results) } }
    func use(_ url:URL,in tool:UtilityTool) { guard !busy else { return };activate(tool);add(tool,urls:[url]) }
    static func reportsFolder() throws -> URL {
        let fm=FileManager.default,base=try fm.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true),folder=base.appendingPathComponent("SwitchBench/Reports")
        try fm.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);return folder
    }
    func supportText(_ tool:UtilityTool)->String {
        let state=sessions[tool] ?? TaskSession()
        let rows=state.rows.map { row in "\n\(row.plan.title) — \(row.state.rawValue)\n\(row.plan.sources.map { $0.url.path }.joined(separator:"\n"))\n\(row.message)\n\(row.issue?.detail ?? "")\n\(row.technical)\nOutput: \(row.output?.path ?? "none")" }.joined()
        return PatchEngine.scrub("SwitchBench \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development") · \(tool.title)\n\(state.summary)\n"+rows+"\n"+state.details)
    }
    func saveLocalReport(_ tool:UtilityTool) {
        do {
            let folder=try Self.reportsFolder(),url=folder.appendingPathComponent("\(tool.rawValue)-\(UUID().uuidString.prefix(8)).log")
            try Data(supportText(tool).utf8).write(to:url,options:.withoutOverwriting);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
            mutate(tool) { $0.report=url }
            // Bounded local diagnostics, kept separate from game outputs.
            let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.creationDateKey]).filter { $0.pathExtension=="log" }.sorted { ((try? $0.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast) }
            for old in files.dropFirst(30) { try? FileManager.default.removeItem(at:old) }
        } catch { mutate(tool) { $0.notice="The task finished, but its local report couldn’t be saved. You can export a report from Technical Details." } }
    }
    func exportReport() {
        guard !busy else { return }
        let panel=NSSavePanel();panel.title="Export a support report";panel.nameFieldStringValue="SwitchBench Support Report.txt"
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do { try Data(supportText(activeTool).utf8).write(to:url,options:.withoutOverwriting);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path) }
        catch { mutate(activeTool) { $0.notice="The report couldn’t be exported. Choose a new filename in a writable folder." } }
    }
}
