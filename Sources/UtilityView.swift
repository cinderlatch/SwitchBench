import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BenchStyle {
    // Semantic text colors carry meaning; the accent is reserved for controls and decoration.
    static let accent=Color.accentColor
    static let secondary=Color.primary.opacity(0.78)
}

struct RootView:View {
    @ObservedObject private var model=UtilityModel.shared
    @State private var recent=false
    @State private var settings=false
    var body:some View {
        GeometryReader { bounds in
        HSplitView {
            if model.sidebarVisible {
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:9) {
                    if let icon=NSImage(named:"AppIcon") { Image(nsImage:icon).resizable().frame(width:30,height:30).accessibilityHidden(true) }
                    Text("SwitchBench").font(.headline)
                }.padding(14)
                List(selection:Binding<UtilityTool?>(get:{model.activeTool},set:{if let tool=$0 { model.activate(tool) }})) {
                    ForEach(UtilityTool.tasks) { tool in Label(tool.title,systemImage:tool.symbol).tag(tool) }
                }.listStyle(.sidebar).frame(minHeight:0,maxHeight:.infinity).disabled(model.busy)
                VStack(alignment:.leading,spacing:10) {
                    Button { recent=true } label:{Label("Recent Results",systemImage:"clock")}.buttonStyle(.borderless).disabled(model.busy)
                    Button { settings=true } label:{Label("Settings…",systemImage:"gearshape")}.buttonStyle(.borderless).disabled(model.busy)
                    Text("Version "+(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")).font(.caption).foregroundStyle(BenchStyle.secondary)
                }.padding(14)
            }.frame(minWidth:185,idealWidth:205,maxWidth:250,maxHeight:.infinity)
            }
            TaskView(tool:model.activeTool).id(model.activeTool).frame(minWidth:610,maxWidth:.infinity,maxHeight:.infinity)
        }
        .frame(width:bounds.size.width,height:bounds.size.height,alignment:.topLeading)
        }
        .frame(minWidth:860,idealWidth:980,minHeight:610,idealHeight:740)
        .toolbar {
            ToolbarItem(placement:.navigation) {
                Button { model.sidebarVisible.toggle() } label:{Image(systemName:"sidebar.leading")}.accessibilityLabel(model.sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            }
        }
        .sheet(isPresented:$recent) { RecentResultsView(use:{url,tool in model.use(url,in:tool)},dismiss:{recent=false}) }
        .sheet(isPresented:$settings) { VStack { AppSettingsView();Button("Done") { settings=false }.keyboardShortcut(.defaultAction).padding(.bottom,18) } }
        .sheet(isPresented:$model.showHelp) { ToolHelpView(tool:model.activeTool) { model.showHelp=false } }
    }
}

struct KeyStatusView:View {
    @ObservedObject private var app=AppModel.shared
    @ObservedObject private var model=UtilityModel.shared
    var body:some View {
        if app.keys==nil {
            VStack(alignment:.leading,spacing:8) {
                Label("This tool needs your emulator’s key file",systemImage:"key").font(.headline)
                Text("Choose the prod.keys file you already use with your emulator. It’s read only on this Mac.").font(.callout).foregroundStyle(BenchStyle.secondary)
                Button("Choose Key File…",action:app.selectKeys)
            }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:10)).disabled(model.busy)
        }
        if let notice=app.keyIssue {
            HStack(alignment:.top) { Label(notice,systemImage:"exclamationmark.circle").fixedSize(horizontal:false,vertical:true);Spacer();Button("Dismiss") { app.keyIssue=nil }.buttonStyle(.borderless) }.font(.callout)
        }
    }
}

struct TaskView:View {
    let tool:UtilityTool
    @ObservedObject private var model=UtilityModel.shared
    @ObservedObject private var app=AppModel.shared
    @State private var details=false
    @State private var dropTarget=false
    @FocusState private var focusedRow:String?
    @AccessibilityFocusState private var accessibleRow:String?
    var body:some View {
        VStack(spacing:0) {
            HStack(alignment:.top,spacing:12) {
                Image(systemName:tool.symbol).font(.system(size:25,weight:.medium)).foregroundStyle(BenchStyle.accent).frame(width:32).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:5) {
                    Text(tool.title).font(.system(size:25,weight:.bold,design:.rounded))
                    Text(tool.explanation).font(.callout).foregroundStyle(BenchStyle.secondary).fixedSize(horizontal:false,vertical:true)
                }
                Spacer(minLength:12)
                if tool.needsKeys,app.keys != nil {
                    Menu { Button("Change Key File…",action:app.selectKeys) } label:{Label("Keys ready",systemImage:"key.fill").font(.caption)}.menuStyle(.borderlessButton).fixedSize().disabled(model.busy).help("The key file is configured. Change it only if needed.")
                }
                Button { model.showHelp=true } label:{Image(systemName:"questionmark.circle")}.buttonStyle(.borderless).accessibilityLabel("Help for "+tool.title)
            }.padding(22)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        if tool.needsKeys { KeyStatusView() }
                        if let notice=model.task.notice {
                            HStack(alignment:.top) { Label(notice,systemImage:"info.circle").fixedSize(horizontal:false,vertical:true);Spacer();Button("Dismiss") { model.mutate(tool) { $0.notice=nil } }.buttonStyle(.borderless) }.font(.callout)
                        }
                        HStack {
                            Text(model.inputs.isEmpty ? "Your files" : "Your files · \(model.inputs.count)").font(.headline)
                            Spacer()
                            if !model.inputs.isEmpty {
                                Button("Add Files…",action:model.chooseFiles).disabled(model.busy)
                                if tool != .join { Menu("File Options") { Button("Choose a Folder…",action:model.chooseFolder);Button("Clear Selection",action:model.clearSelection) }.accessibilityLabel("File Options").disabled(model.busy) }
                            }
                        }
                        if model.inputs.isEmpty { emptyFiles }
                        else if model.rows.isEmpty && model.preparing { Text("Reading your files…").foregroundStyle(BenchStyle.secondary) }
                        else {
                            LazyVStack(spacing:12) {
                                ForEach(model.rows) { row in
                                    TaskRowView(row:row,tool:tool).id(row.id).focusable().focused($focusedRow,equals:row.id).accessibilityFocused($accessibleRow,equals:row.id)
                                }
                            }
                        }
                        if tool.writesFiles { destination }
                        DisclosureGroup("About this tool") {
                            VStack(alignment:.leading,spacing:9) {
                                Text(tool.guidance).fixedSize(horizontal:false,vertical:true)
                                if tool == .combine { Button("Use Update Games instead") { model.activate(.update) }.disabled(model.busy) }
                                if tool == .update { Button("Use Combine Files for a package with add-ons") { model.activate(.combine) }.disabled(model.busy) }
                            }.font(.callout).foregroundStyle(BenchStyle.secondary).padding(.top,7)
                        }.font(.callout)
                    }.padding(22).frame(maxWidth:1000,alignment:.leading).frame(maxWidth:.infinity)
                }
                .frame(minHeight:0,maxHeight:.infinity)
                .onChange(of:model.rows.map(\.id)) { ids in
                    if let first=ids.first,!model.busy { focusedRow=first;proxy.scrollTo(first,anchor:.top) }
                }
                .onChange(of:model.busy) { busy in
                    if !busy,let row=model.rows.first(where:{$0.state == .attention}) { focusedRow=row.id;accessibleRow=row.id;proxy.scrollTo(row.id,anchor:.top) }
                }
            }
            Divider()
            footer.fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
        .onDrop(of:[UTType.fileURL],isTargeted:$dropTarget,perform:drop)
        .sheet(isPresented:$details) {
            VStack(alignment:.leading,spacing:14) {
                Text("Technical Details").font(.title2.bold())
                Text("These details are optional. Each file’s result and recovery steps are shown in the main window.").foregroundStyle(BenchStyle.secondary)
                ScrollView { Text(model.supportText(tool)).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
                HStack {
                    Button("Copy Report") { NSPasteboard.general.clearContents();NSPasteboard.general.setString(model.supportText(tool),forType:.string) }
                    Button("Export Report…",action:model.exportReport).disabled(model.busy)
                    Spacer();Button("Done") { details=false }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width:680,height:440)
        }
    }
    private var emptyFiles:some View {
        VStack(spacing:10) {
            Image(systemName:"square.and.arrow.down").font(.system(size:28)).foregroundStyle(BenchStyle.accent).accessibilityHidden(true)
            Text(tool == .join ? "Drop a part or its folder here" : tool == .update ? "Drop games and their updates here" : "Drop game files here").font(.headline)
            Text(tool == .join ? "Choose any part; the others must be in the same folder." : tool == .trim ? "Uncompressed XCI files" : "NSP, XCI, NSZ and XCZ files").font(.callout).foregroundStyle(BenchStyle.secondary)
            HStack { Button(tool == .join ? "Choose Parts…" : "Choose Files…",action:model.chooseFiles);if tool != .join { Button("Choose a Folder…",action:model.chooseFolder) } }
            Text("Your originals stay unchanged.").font(.caption).foregroundStyle(BenchStyle.secondary)
        }.frame(maxWidth:.infinity).padding(.vertical,24).background(BenchStyle.accent.opacity(dropTarget ? 0.12 : 0.035),in:RoundedRectangle(cornerRadius:12))
        .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(BenchStyle.accent.opacity(0.35),style:StrokeStyle(lineWidth:1.5,dash:[5,4]))).disabled(model.busy)
    }
    private var destination:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:10) {
                Image(systemName:"folder").foregroundStyle(BenchStyle.accent).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4) {
                    Text("Save to").font(.caption).foregroundStyle(BenchStyle.secondary)
                    Text(model.output?.lastPathComponent ?? "Choose a folder for new copies").font(.callout.weight(.semibold))
                    if let output=model.output { Text(output.path).font(.caption).foregroundStyle(BenchStyle.secondary).lineLimit(1).truncationMode(.middle).help(output.path) }
                }
                Spacer();Button(model.output==nil ? "Choose Folder…" : "Change…",action:model.selectOutput).disabled(model.busy)
            }
            if let required=model.rows.filter({!$0.finished && $0.issue==nil}).map(\.plan.requiredSpace).max(),required>0 {
                Text("Largest task needs about \(FileLabels.bytes(required)) free, including temporary files. Finished copies also use space.").font(.caption).foregroundStyle(BenchStyle.secondary).fixedSize(horizontal:false,vertical:true)
            }
            if let free=model.task.freeSpace { Text(FileLabels.bytes(free)+" available in this location").font(.caption).foregroundStyle(BenchStyle.secondary) }
            Text("Used for this tool. Other tools keep their own save folders.").font(.caption).foregroundStyle(BenchStyle.secondary)
        }.padding(14).background(.quaternary.opacity(0.25),in:RoundedRectangle(cornerRadius:10))
    }
    private var footer:some View {
        VStack(alignment:.leading,spacing:10) {
            if model.busy {
                HStack { if !model.currentTitle.isEmpty { Text(model.position+" · "+model.currentTitle).font(.callout.weight(.semibold)).lineLimit(1) };Spacer();if let start=model.began { TimelineView(.periodic(from:start,by:1)) { context in Text("Elapsed "+elapsed(context.date.timeIntervalSince(start))).font(.caption).foregroundStyle(BenchStyle.secondary) } } }
                Text(model.phase).font(.callout).accessibilityLabel("Current task: "+model.phase)
                if let value=model.fraction { ProgressView(value:value).accessibilityLabel("Overall progress").accessibilityValue("\(Int(value*100)) percent") }
                else { ProgressView().progressViewStyle(.linear).accessibilityLabel("Processing") }
                Text("Stop discards unfinished work for the current file. Completed results are kept.").font(.caption).foregroundStyle(BenchStyle.secondary)
            } else { Text(model.task.summary).font(.callout).accessibilityLabel("Task summary: "+model.task.summary) }
            HStack {
                Menu("More") {
                    Button("Technical Details…") { details=true }
                    Button("Read Files Again") { model.prepare() }.disabled(model.busy || model.inputs.isEmpty)
                    Button("Export Support Report…",action:model.exportReport).disabled(model.busy)
                }.fixedSize()
                Spacer()
                if model.busy { Button(model.stopping ? "Stopping…" : "Stop",action:model.cancel).disabled(model.stopping).keyboardShortcut(.cancelAction) }
                else if tool.writesFiles && model.output==nil && model.readyCount>0 { Button("Choose Save Folder…",action:model.selectOutput).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
                else if tool.needsKeys && app.keys==nil && !model.inputs.isEmpty { Button("Choose Key File…",action:app.selectKeys).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
                else if model.canRun {
                    if !model.results.isEmpty { Button("Show Saved Files",action:model.revealResults) }
                    Button(tool.action(count:model.readyCount),action:model.runReady).buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                } else if model.canRetry {
                    if !model.results.isEmpty { Button("Show Saved Files",action:model.revealResults) }
                    Button("Retry Unfinished Files",action:model.retry).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else if !model.rows.isEmpty && model.unfinishedCount>0 { Button("Add Files…",action:model.chooseFiles) }
                else if !model.rows.isEmpty {
                    Button("Choose New Files…",action:model.newFiles)
                    if !model.results.isEmpty { Button("Show Saved Files",action:model.revealResults).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
                    else if tool == .inspect,model.completedCount>0 { Button("Check Again") { model.prepare(autoStart:true,force:Set(model.rows.map(\.id))) } }
                } else { Button(tool.action(count:1),action:model.runReady).buttonStyle(.borderedProminent).disabled(true) }
            }
        }.padding(.horizontal,22).padding(.vertical,14).background(.regularMaterial)
    }
    private func elapsed(_ seconds:TimeInterval)->String { let n=max(0,Int(seconds));return n<60 ? "\(n)s" : "\(n/60)m \(n%60)s" }
    private func drop(_ providers:[NSItemProvider])->Bool {
        guard !model.busy else { return false }
        let group=DispatchGroup(),lock=NSLock();var urls:[URL]=[]
        for provider in providers { group.enter();provider.loadDataRepresentation(forTypeIdentifier:UTType.fileURL.identifier) { data,_ in defer {group.leave()};if let data,let url=URL(dataRepresentation:data,relativeTo:nil) { lock.lock();urls.append(url);lock.unlock() } } }
        group.notify(queue:.main) { model.add(tool,urls:urls) };return true
    }
}

struct TaskRowView:View {
    let row:TaskRow
    let tool:UtilityTool
    @ObservedObject private var model=UtilityModel.shared
    @ObservedObject private var app=AppModel.shared
    var body:some View {
        VStack(alignment:.leading,spacing:11) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:4) {
                    Text(row.plan.title).font(.headline).textSelection(.enabled)
                    if !row.plan.subtitle.isEmpty { Text(row.plan.subtitle).font(.callout).foregroundStyle(BenchStyle.secondary) }
                }
                Spacer(minLength:8)
                Label(row.state.rawValue,systemImage:symbol).font(.caption.weight(.semibold)).foregroundStyle(row.state == .attention ? Color.primary : BenchStyle.secondary).fixedSize()
            }
            ForEach(row.plan.sources,id:\.url) { source in
                HStack(alignment:.top,spacing:8) {
                    VStack(alignment:.leading,spacing:3) {
                        if row.plan.sources.count>1 { Text(source.description).font(.caption.weight(.semibold)) }
                        Text(source.url.lastPathComponent).font(.caption).foregroundStyle(BenchStyle.secondary).lineLimit(2).truncationMode(.middle).help(source.url.path).textSelection(.enabled)
                    }
                    Spacer()
                    Button { model.remove(source.url) } label:{Image(systemName:"xmark.circle")}.buttonStyle(.borderless).help("Remove this input from the task; the file is kept.").accessibilityLabel("Remove "+source.url.lastPathComponent).disabled(model.busy)
                }
            }
            if let issue=row.issue {
                Label(issue.message,systemImage:"exclamationmark.circle").font(.callout).fixedSize(horizontal:false,vertical:true)
                recovery(issue)
            } else {
                if !row.message.isEmpty { Text(row.message).font(.callout).fixedSize(horizontal:false,vertical:true) }
                if row.state == .ready {
                    if let name=row.plan.outputName { LabeledContent("New file",value:name).font(.caption).textSelection(.enabled) }
                    if !row.plan.sizeEstimate.isEmpty { Text("Expected size: "+row.plan.sizeEstimate).font(.caption).foregroundStyle(BenchStyle.secondary) }
                    if tool == .combine { Button("Apply the update instead") { model.activate(.update);model.add(.update,urls:row.plan.sources.map(\.url)) }.buttonStyle(.borderless).disabled(model.busy) }
                }
                if let output=row.output {
                    Text("Saved to "+output.deletingLastPathComponent().path).font(.caption).foregroundStyle(BenchStyle.secondary).lineLimit(2).textSelection(.enabled)
                    HStack {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                        Menu("Use File In…") { ForEach(UtilityTool.destinations(for:output)) { next in Button(next.title) { model.use(output,in:next) } } }.fixedSize()
                        Button("Create Another Copy") { model.useSeparateName(row.id) }
                    }.font(.callout).disabled(model.busy)
                }
                if row.state == .stopped { Button("Retry",action:model.retry).disabled(model.busy) }
            }
            if row.state == .noChange,let original=row.plan.sources.first?.url { Button("Show File") { NSWorkspace.shared.activateFileViewerSelecting([original]) }.disabled(model.busy) }
            ForEach(row.notes,id:\.self) { Text($0).font(.callout).foregroundStyle(BenchStyle.secondary).fixedSize(horizontal:false,vertical:true) }
            if let info=row.plan.inspection {
                DisclosureGroup("File information") {
                    VStack(alignment:.leading,spacing:5) {
                        Text(info.format+" · "+FileLabels.bytes(info.bytes))
                        ForEach(Array(info.titles.enumerated()),id:\.offset) { _,title in
                            Text(title.role.rawValue+(title.displayVersion.map {" · Version "+$0} ?? ""))
                            Text(String(format:"Game identifier: %016llX · Revision %u",title.id,title.revision)).font(.caption).foregroundStyle(BenchStyle.secondary)
                        }
                        if let note=info.note { Text(note).foregroundStyle(BenchStyle.secondary) }
                        if row.state == .checked { Text("This checks stored data, not emulator gameplay.").foregroundStyle(BenchStyle.secondary) }
                    }.font(.callout).textSelection(.enabled).padding(.top,6)
                }.font(.caption)
            }
            if !(row.issue?.detail ?? row.technical).isEmpty {
                DisclosureGroup("Technical details") { ScrollView { Text(row.issue?.detail ?? row.technical).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:140) }.font(.caption)
            }
        }.padding(15).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12))
        .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(row.state == .attention ? Color.primary.opacity(0.35) : Color.primary.opacity(0.09)))
        .accessibilityElement(children:.contain)
    }
    private var symbol:String {
        switch row.state {case .saved,.checked:return "checkmark.circle.fill";case .noChange:return "checkmark.circle";case .attention:return "exclamationmark.circle.fill";case .working,.preparing:return "clock";case .stopped:return "stop.circle";case .ready:return "circle"}
    }
    @ViewBuilder private func recovery(_ issue:TaskIssue)->some View {
        HStack {
            switch issue.kind {
            case .keys:Button("Choose Key File…",action:app.selectKeys)
            case .extraKeys:Button("Choose Additional Key File…",action:app.selectTitleKeys)
            case .collision:
                if let folder=model.output,let name=row.plan.outputName { Button("Show Existing File") { NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent(name)]) } }
                Button("Use a Separate Name") { model.useSeparateName(row.id) }
                Button("Choose Folder…",action:model.selectOutput)
            case .space,.destination:Button("Choose Folder…",action:model.selectOutput)
            case .parts:
                if let url=row.plan.sources.first?.url { Button("Show Parts Folder") { let folder=(try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true ? url : url.deletingLastPathComponent();NSWorkspace.shared.open(folder) } }
                Button("Choose Parts…",action:model.chooseFiles)
            case .helper:Text("Quit and reopen the app, then retry.").font(.callout)
            case .input:
                Button("Choose Files…",action:model.chooseFiles)
                if tool == .update,row.plan.inspection?.titles.allSatisfy({$0.role == .addon})==true { Button("Use Combine Files") { model.activate(.combine);model.add(.combine,urls:row.plan.sources.map(\.url)) } }
            }
            if row.plan.issue != nil { Button("Read Again") { model.prepare() } }
        }.font(.callout).disabled(model.busy)
    }
}

struct ToolHelpView:View {
    let tool:UtilityTool
    let dismiss:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text(tool.title).font(.title2.bold())
            Text(tool.explanation)
            Text(tool.guidance).foregroundStyle(BenchStyle.secondary)
            Divider()
            Text("NSP is a game package. XCI is a cartridge backup. NSZ and XCZ are compressed versions of those formats. Converting expands compressed data; shrinking an XCI removes unused trailing space.").font(.callout)
            Text("Choose files or a folder, review the expected result, and choose where to save when a copy is created. Your original files are unchanged. Problems and recovery actions appear beside each file.").font(.callout)
            HStack { Spacer();Button("Done",action:dismiss).keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width:560)
    }
}
