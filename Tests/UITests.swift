import Foundation
import SwiftUI

@main struct UIStateTests {
    @MainActor static func main() throws {
        var passed=0
        func expect(_ ok:@autoclosure ()->Bool,_ name:String) throws { guard ok() else { throw PatchError("FAIL: "+name) };passed += 1;print("PASS: "+name);fflush(stdout) }
        let suite="SwitchBench.QA."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let m=UtilityModel(defaults:defaults,automaticPreparation:false)
        let a=URL(fileURLWithPath:"/tmp/a.xci"),b=URL(fileURLWithPath:"/tmp/b.xci"),one=URL(fileURLWithPath:"/tmp/output-one"),two=URL(fileURLWithPath:"/tmp/output-two")
        try expect(UtilityTool.tasks.count==8 && Set(UtilityTool.tasks).count==8,"all eight tools have equal sidebar entries")
        try expect(m.activeTool == .inspect,"first launch defaults to Check Files")
        for tool in UtilityTool.tasks {
            try expect(!tool.title.isEmpty && !tool.explanation.isEmpty && !tool.guidance.isEmpty,"\(tool.title) has a purpose and contextual help")
            try expect(UtilityTool.restoredSelection(tool.rawValue)==tool,"\(tool.title) selection restores")
        }
        try expect(UtilityTool.restoredSelection("home") == .inspect && UtilityTool.restoredSelection("invalid") == .inspect,"obsolete and invalid selections fall back safely")
        m.activate(.convert);m.add(.convert,urls:[a,a,b])
        try expect(m.inputs==[a,b],"input selections are deduplicated")
        try expect(m.task.notice?.contains("duplicates") == true,"duplicate import is explained")
        var pa=TaskPlan.fallback([a]);pa.outputName="a [Converted].nsp";pa.preview="Create one NSP copy."
        let pb=TaskPlan.fallback([b])
        m.applyPreparation([pa,pb],tool:.convert,previous:[])
        try expect(!m.canRun,"write tasks require a destination")
        m.setOutput(one,persist:false)
        try expect(m.canRun,"prepared conversion needs no keys")
        m.mutate(.convert) { state in state.rows[0].state = .saved;state.rows[0].output=one.appendingPathComponent("saved.nsp");state.rows[0].message="Saved and checked." }
        m.activate(.trim);m.setOutput(two,persist:false);m.add(.trim,urls:[b])
        try expect(m.output==two,"each tool can choose its own destination")
        m.activate(.convert)
        try expect(m.output==one && m.rows[0].state == .saved && m.results.count==1,"switching tools preserves destination and completed outputs")
        m.setOutput(two,persist:false)
        try expect(m.rows[0].state == .saved && m.results.first?.deletingLastPathComponent().path==one.path,"changing destination never erases a previous saved outcome")
        m.applyPreparation([pa,pb],tool:.convert,previous:m.rows)
        try expect(m.rows[0].state == .saved,"preparing a new destination retains completed inputs")
        m.applyPreparation([pa,pb],tool:.convert,previous:m.rows,force:[pa.id])
        try expect(m.rows[0].state == .ready,"an explicit new-copy action can prepare a completed input again")
        m.activate(.join);m.add(.join,urls:[a,b])
        try expect(m.inputs.isEmpty && m.task.notice?.contains("one") == true,"joining explains a multiple-selection restriction without dropping files")
        m.add(.convert,urls:[a])
        try expect(m.inputs.isEmpty,"a delayed drop cannot change the wrong tool")
        m.activate(.inspect);m.add(.inspect,urls:[a,b])
        try expect(m.inputs.count==2,"Check Files supports multiple inputs")
        var checked=TaskRow(pa);checked.state = .checked;checked.message="No problems found in the checked game data."
        var noop=pb;noop.skipReason="Already a standard NSP."
        let skip=TaskRow(noop)
        try expect(skip.state == .noChange && skip.finished && skip.issue==nil,"unnecessary work is completed as No Change Needed rather than failure")
        var invalid=pa;invalid.issue=TaskIssue(.input,"Choose another update.")
        let problem=TaskRow(invalid)
        try expect(problem.state == .attention && !problem.finished,"input problems remain actionable and unfinished")
        m.mutate(.inspect) { $0.rows=[checked,skip,problem] }
        try expect(m.completedCount==2 && m.unfinishedCount==1 && !m.canRetry,"mixed results distinguish completed work from inputs that need resolving before retry")
        try expect(m.task.summary.contains("checked") && m.task.summary.contains("attention"),"the batch summary communicates meaningful outcomes")
        m.mutate(.inspect) { $0.rows[2].plan.issue=nil }
        try expect(m.canRetry,"a processing failure can retry unfinished work after preparation")
        m.mutate(.inspect) { $0.notice="Check-specific issue" };m.activate(.trim)
        try expect(m.task.notice != "Check-specific issue","errors are scoped to the tool that produced them")
        m.busy=true;let tool=m.activeTool;m.activate(.update);m.setOutput(one,persist:false)
        try expect(m.activeTool==tool && m.output==two,"active work cannot be replaced by navigation or folder changes")
        try expect(!m.canRun && !m.canRetry,"busy work cannot start another task")
        m.busy=false;m.clearSelection()
        try expect(m.inputs.isEmpty && m.rows.isEmpty && m.output==two,"clearing a task preserves its local destination")
        m.activate(.convert)
        let reopened=UtilityModel(defaults:defaults,automaticPreparation:false)
        try expect(reopened.activeTool == .convert,"the actual saved preference restores the last-used tool")
        try expect(UtilityTool.convert.action(count:3)=="Convert 3 Files" && UtilityTool.combine.action(count:5)=="Create Combined File","actions use meaningful counts and one combined output")
        try expect(UtilityTool.destinations(for:URL(fileURLWithPath:"/tmp/game.nsp")) == [.inspect,.update,.combine,.split,.compress],"NSP handoff offers only useful next tools")
        try expect(UtilityTool.destinations(for:URL(fileURLWithPath:"/tmp/game.nsp.00")) == [.join],"split parts hand off to Join instead of unsupported tools")
        m.activate(.convert);let previous=m.inputs
        m.add(.convert,urls:[URL(fileURLWithPath:"/tmp/unsupported.txt")],replacing:true)
        try expect(m.inputs==previous,"an unsupported replacement selection preserves the existing task")
        try expect(UtilityTool.update.progressText("Building application content table")=="Preparing game information","update progress describes game information without archive jargon")
        try expect(UtilityTool.inspect.progressText("Checking content 1 of 2")=="Checking game data","content-check progress describes the user’s data")
        let keysIssue=TaskIssue.from(PatchError("The processing helper failed.\nLoading prod.keys\nInvalid BKTR layout!"))
        try expect(keysIssue.kind == .input,"a helper log mentioning prod.keys does not falsely blame keys")
        try expect(TaskIssue.from(NSError(domain:NSCocoaErrorDomain,code:NSFileReadNoSuchFileError)).kind == .input,"an unavailable input offers input recovery rather than changing the output folder")
        try expect(TaskIssue.from(PatchError("Output already exists.")).kind == .collision,"collisions have a direct recovery category")
        try expect(TaskIssue.from(PatchError("A required title key is missing.")).kind == .extraKeys,"additional key recovery is contextual")
        let scrubbed=TaskIssue(.input,"Problem",detail:String(repeating:"ab",count:32))
        try expect(scrubbed.detail=="[redacted]","technical error details redact key-shaped values")
        let history=AppModel(defaults:defaults)
        history.record([RecentResult(date:Date(),tool:.convert,title:"Game",message:"Saved",paths:["/tmp/game.nsp"])])
        let restored=AppModel(defaults:defaults)
        try expect(restored.recent.count==1 && restored.recent[0].urls.first?.path=="/tmp/game.nsp","recent results survive relaunch without changing the files")
        restored.clearRecent()
        try expect(restored.recent.isEmpty,"clearing result history removes only history entries")
        try expect(!restored.notifications,"completion notifications require an explicit opt-in")
        print("\(passed) UI state checks passed.")
    }
}
