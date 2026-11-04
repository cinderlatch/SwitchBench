import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    static let shared=AppModel()
    @Published var keys:URL?
    @Published var titleKeys:URL?
    @Published var keyIssue:String?
    @Published var settingsNotice:String?
    @Published var recent:[RecentResult]=[]
    @Published var notifications=false
    private var session:HelperSession?
    let defaults:UserDefaults
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        if let value=defaults.string(forKey:"keyFile"),FileManager.default.fileExists(atPath:value) { keys=URL(fileURLWithPath:value) }
        if let data=defaults.data(forKey:"recentResults"),let items=try? JSONDecoder().decode([RecentResult].self,from:data) { recent=Array(items.prefix(30)) }
        notifications=defaults.bool(forKey:"completionNotifications")
        session=try? HelperSession(executable:Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/hactool"))
    }
    func helpers() throws -> HelperSession {
        if let session { try session.validate();return session }
        let found=try HelperSession(executable:Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/hactool"));session=found;return found
    }
    func releaseHelpers() { session=nil }
    static func gameName(_ url:URL)->String { FileLabels.name(url) }
    func chooseFile(_ title:String,folder:Bool=false,multiple:Bool=false)->[URL] {
        let panel=NSOpenPanel();panel.title=title;panel.canChooseDirectories=folder;panel.canChooseFiles = !folder;panel.allowsMultipleSelection=multiple;panel.canCreateDirectories=folder;panel.prompt=folder ? "Choose Folder" : "Choose File"
        return panel.runModal() == .OK ? panel.urls : []
    }
    func selectKeys() {
        guard !UtilityModel.shared.busy else { return }
        keyIssue=nil
        guard let url=chooseFile("Choose your emulator’s prod.keys file").first else { return }
        do {
            let a=try FileManager.default.attributesOfItem(atPath:url.path)
            guard ((a[.size] as? NSNumber)?.uint64Value ?? UInt64.max) <= 16*1024*1024 else { throw PatchError("Choose the small prod.keys file, rather than a game file.") }
            _=try PatchEngine.productionKeyText(Data(contentsOf:url))
            keys=url;titleKeys=nil;defaults.set(url.path,forKey:"keyFile");UtilityModel.shared.keyChanged()
        } catch { keyIssue="This file couldn’t be used as prod.keys. Choose the key file you use with your emulator." }
    }
    func selectTitleKeys() {
        guard !UtilityModel.shared.busy else { return }
        keyIssue=nil
        guard let url=chooseFile("Choose the matching title.keys file").first else { return }
        do {
            let a=try FileManager.default.attributesOfItem(atPath:url.path)
            guard ((a[.size] as? NSNumber)?.uint64Value ?? UInt64.max) <= 16*1024*1024 else { throw PatchError("This file is too large.") }
            titleKeys=url;UtilityModel.shared.keyChanged()
        } catch { keyIssue="This additional key file couldn’t be read. Choose a small, readable title.keys file." }
    }
    func record(_ results:[RecentResult]) {
        recent=Array((results+recent).prefix(30))
        if let data=try? JSONEncoder().encode(recent) { defaults.set(data,forKey:"recentResults") }
    }
    func clearRecent() { recent=[];defaults.removeObject(forKey:"recentResults") }
    func setNotifications(_ enabled:Bool) {
        guard enabled else { notifications=false;defaults.set(false,forKey:"completionNotifications");return }
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert]) { allowed,error in
            DispatchQueue.main.async { self.notifications=allowed;self.defaults.set(allowed,forKey:"completionNotifications");if !allowed { self.settingsNotice="Completion notifications are off. You can enable them for SwitchBench in System Settings → Notifications." } }
        }
    }
    func finished(_ summary:String) {
        if let window=NSApp.mainWindow { NSAccessibility.post(element:window,notification:.announcementRequested,userInfo:[.announcement:summary,.priority:NSAccessibilityPriorityLevel.high.rawValue]) }
        guard !NSApp.isActive else { return }
        NSApp.dockTile.badgeLabel="✓"
        if notifications {
            let content=UNMutableNotificationContent();content.title="SwitchBench finished";content.body=summary
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:UUID().uuidString,content:content,trigger:nil))
        }
    }
}

struct RecentResult: Codable, Identifiable {
    var id=UUID()
    let date:Date
    let tool:UtilityTool
    let title:String
    let message:String
    let paths:[String]
    var urls:[URL] { paths.map { URL(fileURLWithPath:$0) } }
}

final class AppDelegate:NSObject,NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification:Notification) {
        #if QA_PREVIEW
        if let name=Bundle.main.object(forInfoDictionaryKey:"SwitchBenchQAAppearance") as? String { NSApp.appearance=NSAppearance(named:NSAppearance.Name(name)) }
        #endif
        NSApp.setActivationPolicy(.regular)
        if let icon=NSImage(named:"AppIcon") { NSApp.applicationIconImage=icon }
        NSApp.activate(ignoringOtherApps:true)
        DispatchQueue.main.async {
            if !UserDefaults.standard.bool(forKey:"compactWorkflowLayout060"),let window=NSApp.windows.first(where:{$0.canBecomeMain}) {
                window.setContentSize(NSSize(width:980,height:740));window.center()
                UserDefaults.standard.set(true,forKey:"compactWorkflowLayout060")
            }
        }
    }
    func applicationDidBecomeActive(_ notification:Notification) { NSApp.dockTile.badgeLabel=nil }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if UtilityModel.shared.busy { UtilityModel.shared.quitAfterCleanup=true;UtilityModel.shared.cancel();return .terminateCancel }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification:Notification) { AppModel.shared.releaseHelpers() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
}

struct AppSettingsView:View {
    @ObservedObject private var app=AppModel.shared
    @ObservedObject private var model=UtilityModel.shared
    var body:some View {
        Form {
            Section {
                Text("Keys are used only on this Mac. Their contents are never saved in preferences.").fixedSize(horizontal:false,vertical:true)
                HStack { Text(app.keys?.lastPathComponent ?? "No key file selected");Spacer();Button("Choose Key File…",action:app.selectKeys) }
                if let keys=app.keys { Text(keys.path).font(.caption).textSelection(.enabled) }
                if let issue=app.keyIssue { Label(issue,systemImage:"exclamationmark.circle").fixedSize(horizontal:false,vertical:true) }
            } header:{Text("Game keys")}
            Section {
                Toggle("Notify me when work finishes in the background",isOn:Binding(get:{app.notifications},set:app.setNotifications))
                if let notice=app.settingsNotice { Text(notice).font(.callout) }
                Text("The Dock also shows a checkmark when a background task finishes.").font(.caption).foregroundStyle(BenchStyle.secondary)
            } header:{Text("Completion feedback")}
            Section {
                Text("Save folders are remembered separately for each tool. Completed copies remain in Recent Results.")
                Button("Show Local Reports") { if let folder=try? UtilityModel.reportsFolder() { NSWorkspace.shared.open(folder) } }
            } header:{Text("Files and reports")}
        }.formStyle(.grouped).padding(16).frame(width:530,height:420).disabled(model.busy)
    }
}

struct RecentResultsView:View {
    @ObservedObject private var app=AppModel.shared
    let use:(URL,UtilityTool)->Void
    let dismiss:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Recent Results").font(.title2.bold())
            Text("Previous results are kept here so you can find your files after reopening the app.").foregroundStyle(BenchStyle.secondary)
            if app.recent.isEmpty { Text("No completed results yet.").frame(maxWidth:.infinity,minHeight:150) }
            else {
                List(app.recent) { item in
                    VStack(alignment:.leading,spacing:6) {
                        Text(item.title).font(.headline)
                        Text(item.tool.title+" · "+item.message).font(.callout)
                        if let file=item.urls.first { Text(file.lastPathComponent).font(.caption).foregroundStyle(BenchStyle.secondary).lineLimit(1).truncationMode(.middle).help(file.path) }
                        HStack { Text(item.date,style:.date);Text(item.date,style:.time) }.font(.caption).foregroundStyle(BenchStyle.secondary)
                        if item.urls.allSatisfy({ !FileManager.default.fileExists(atPath:$0.path) }) { Label("File unavailable. Check that its drive is connected.",systemImage:"exclamationmark.circle").font(.caption) }
                        HStack {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(item.urls) }.disabled(item.urls.allSatisfy { !FileManager.default.fileExists(atPath:$0.path) })
                            if let first=item.urls.first {
                                Menu("Use File In…") { ForEach(UtilityTool.destinations(for:first)) { tool in Button(tool.title) { use(first,tool);dismiss() } } }
                            }
                        }
                    }.padding(.vertical,8)
                }
            }
            HStack { Button("Clear List",action:app.clearRecent).disabled(app.recent.isEmpty);Text("Files are kept.").font(.caption).foregroundStyle(BenchStyle.secondary);Spacer();Button("Done",action:dismiss).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:700,height:520)
    }
}

#if !QA_TESTING
@main struct SwitchBenchApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var model=UtilityModel.shared
    var body:some Scene {
        WindowGroup { RootView() }.defaultSize(width:980,height:740)
        .commands {
            CommandGroup(replacing:.newItem) {
                Button("Choose Files…") { model.chooseFiles() }.keyboardShortcut("o").disabled(model.busy)
                Button("Choose a Folder…") { model.chooseFolder() }.keyboardShortcut("o",modifiers:[.command,.shift]).disabled(model.busy || model.activeTool == .join)
                Divider()
                Button("Show Saved Files") { model.revealResults() }.keyboardShortcut("r").disabled(model.results.isEmpty)
                Button("Export Support Report…") { model.exportReport() }.keyboardShortcut("e",modifiers:[.command,.shift]).disabled(model.busy)
            }
            CommandGroup(after:.sidebar) {
                Button(model.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") { model.sidebarVisible.toggle() }.keyboardShortcut("s",modifiers:[.command,.control])
            }
            CommandMenu("Tools") {
                ForEach(Array(UtilityTool.tasks.enumerated()),id:\.element.id) { index,tool in
                    Button(tool.title) { model.activate(tool) }.keyboardShortcut(KeyEquivalent(Character(String(index+1)))).disabled(model.busy)
                }
            }
            CommandGroup(replacing:.help) { Button("SwitchBench Help") { model.showHelp=true } }
        }
        Settings { AppSettingsView() }
    }
}
#endif
