import Foundation
import CryptoKit

enum UtilityTool: String, CaseIterable, Identifiable, Codable {
    case update, inspect, combine, convert, split, join, trim
    var id: String { rawValue }
    static var tasks: [UtilityTool] { allCases }
    static func restoredSelection(_ value: String?) -> UtilityTool { value.flatMap(Self.init(rawValue:)) ?? .inspect }
    var title: String {
        switch self {
        case .update: return "Update Games"
        case .inspect: return "Check Files"
        case .combine: return "Combine Files"
        case .convert: return "Convert to NSP"
        case .split: return "Split Large Files"
        case .join: return "Join Split Files"
        case .trim: return "Shrink XCI Files"
        }
    }
    var symbol: String {
        switch self {
        case .update: return "arrow.up.doc"
        case .inspect: return "checkmark.shield"
        case .combine: return "square.stack.3d.up"
        case .convert: return "arrow.triangle.2.circlepath"
        case .split: return "square.split.2x2"
        case .join: return "square.grid.2x2"
        case .trim: return "scissors"
        }
    }
    var explanation: String {
        switch self {
        case .update: return "Apply an update and save an updated copy."
        case .inspect: return "See game names and versions, then check for missing or changed data."
        case .combine: return "Keep one game, its update and add-ons together in one NSP file."
        case .convert: return "Create NSP copies of XCI, NSZ or XCZ files."
        case .split: return "Create smaller parts for drives with a 4 GB file limit."
        case .join: return "Put file parts back together. Choose any part or its folder."
        case .trim: return "Remove unused space from XCI files. The game content stays the same."
        }
    }
    var guidance: String {
        switch self {
        case .update: return "Add the original game and its update. They’re matched automatically. Add-ons can be included with Combine Files."
        case .inspect: return "Reading names and versions is quick. A full check reads all listed game content and can take several minutes. It doesn’t test gameplay."
        case .combine: return "The update stays separate inside the package. To apply it to the game’s content, use Update Games. Emulator support for combined files varies."
        case .convert: return "Compressed content is expanded. Included updates remain separate; conversion doesn’t apply them to the game."
        case .split: return "Keep all parts and the included parts list together. Use Join Split Files to restore the complete file."
        case .join: return "SwitchBench parts have saved checksums. Older parts are checked for missing numbers and a complete game-file container."
        case .trim: return "Only unused space at the end is removed. This is different from compression and works with uncompressed XCI files."
        }
    }
    var button: String { action(count:1) }
    func action(count: Int) -> String {
        switch self {
        case .update: return count == 1 ? "Create Updated Copy" : "Update \(count) Games"
        case .inspect: return count == 1 ? "Check Contents" : "Check \(count) Files"
        case .combine: return "Create Combined File"
        case .convert: return count == 1 ? "Convert to NSP" : "Convert \(count) Files"
        case .split: return count == 1 ? "Split File" : "Split \(count) Files"
        case .join: return "Join Parts"
        case .trim: return count == 1 ? "Shrink XCI" : "Shrink \(count) Files"
        }
    }
    static func destinations(for url:URL) -> [UtilityTool] {
        if (try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true { return [.join] }
        switch url.pathExtension.lowercased() {
        case "nsp":return [.inspect,.update,.combine,.split]
        case "xci":return [.inspect,.update,.combine,.convert,.split,.trim]
        case "nsz","xcz":return [.inspect,.update,.combine,.convert,.split]
        default:return [.join]
        }
    }
    func progressText(_ raw:String)->String {
        let stage=raw.lowercased()
        if stage.contains("applying update") { return "Applying the update — this can take several minutes" }
        if stage.contains("metadata") || stage.contains("icon") || stage.contains("content table") { return "Preparing game information" }
        if stage.contains("verifying") || stage.contains("checking content") { return "Checking game data" }
        if stage.contains("building normal") { return "Saving updated game data" }
        if stage.contains("building compatible") { return "Creating the updated copy" }
        return raw
    }
    var needsKeys: Bool { [.update,.inspect,.combine].contains(self) }
    var writesFiles: Bool { self != .inspect }
    var allowsMultiple: Bool { self != .join }
    var extensions: Set<String> { self == .trim ? ["xci"] : ["nsp","xci","nsz","xcz"] }
}

enum IssueKind: String, Codable { case input, keys, extraKeys, destination, collision, space, parts, helper }
struct TaskIssue: Error, LocalizedError, Equatable {
    let kind: IssueKind
    let message: String
    let detail: String
    init(_ kind: IssueKind, _ message: String, detail: String = "") { self.kind=kind;self.message=message;self.detail=PatchEngine.scrub(detail) }
    var errorDescription: String? { message }
    static func from(_ error: Error) -> TaskIssue {
        if let issue=error as? TaskIssue { return issue }
        if error is HelperUnavailableError { return TaskIssue(.helper,"A processing component is unavailable. Quit and reopen SwitchBench.",detail:error.localizedDescription) }
        let raw=error.localizedDescription,first=raw.components(separatedBy:.newlines).first ?? raw,lower=first.lowercased()
        if lower.contains("title.keys") || lower.contains("title key") { return TaskIssue(.extraKeys,"This game needs a matching additional key file.",detail:raw) }
        if lower.contains("prod.keys") || lower.contains("key file") || lower.contains("decrypt an nca header") { return TaskIssue(.keys,"The key file couldn’t read this game. Choose the key file you use with your emulator.",detail:raw) }
        if lower.contains("already exists") || lower.contains("output with this name") || ((error as NSError).domain==NSCocoaErrorDomain && (error as NSError).code==NSFileWriteFileExistsError) { return TaskIssue(.collision,"A file with this name already exists. Your existing file is unchanged.",detail:raw) }
        if lower.contains("free") || lower.contains("space") || (error as NSError).code == NSFileWriteOutOfSpaceError { return TaskIssue(.space,"There isn’t enough free space for this task and its temporary files. Choose another folder.",detail:raw) }
        if lower.contains("part ") || lower.contains("parts") { return TaskIssue(.parts,PatchEngine.scrub(first),detail:raw) }
        if let cocoa=error as NSError?,cocoa.domain==NSCocoaErrorDomain {
            if [NSFileReadNoPermissionError,NSFileReadNoSuchFileError].contains(cocoa.code) { return TaskIssue(.input,"The input is unavailable. Check that its drive is connected, or choose the file again.",detail:raw) }
            if [NSFileWriteNoPermissionError,NSFileNoSuchFileError].contains(cocoa.code) { return TaskIssue(.destination,"The save folder is unavailable. Check that its drive is connected and writable.",detail:raw) }
        }
        if raw.contains("Invalid BKTR layout!") { return TaskIssue(.input,"The update’s patch data couldn’t be read. Try another copy; if it still fails, export a support report.",detail:raw) }
        if lower.contains("choose an nsp, xci, nsz or xcz") { return TaskIssue(.input,"This isn’t a readable game package. Choose another copy of the file.",detail:raw) }
        let message = raw.contains("\n") ? "This file couldn’t be processed. Choose another copy, or open Technical Details for the processing report." : PatchEngine.scrub(first)
        return TaskIssue(.input,message,detail:raw)
    }
}

enum RowState: String, Codable { case preparing="Reading files", ready="Ready", working="Working", saved="Saved", checked="Checked", noChange="No Change Needed", attention="Needs Attention", stopped="Stopped" }
struct SourceDescription {
    let url: URL
    var name: String
    var description: String
}
struct TaskPlan: Identifiable {
    let id: String
    var sources: [SourceDescription]
    var title: String
    var subtitle: String = ""
    var preview: String = ""
    var outputName: String?
    var requiredSpace: UInt64 = 0
    var sizeEstimate: String = ""
    var skipReason: String?
    var issue: TaskIssue?
    var inspection: FileInspection?
    var job: PatchJob?
    var sourceBytes: UInt64 = 0
    var sourceStamps: [URL:FileStamp] = [:]
    static func identifier(_ urls: [URL]) -> String { let data=try! JSONEncoder().encode(urls.map { $0.standardizedFileURL.path }.sorted());return Data(SHA256.hash(data:data)).hex }
    static func fallback(_ urls:[URL]) -> TaskPlan {
        TaskPlan(id:identifier(urls),sources:urls.map { SourceDescription(url:$0,name:FileLabels.name($0),description:$0.lastPathComponent) },title:urls.count==1 ? FileLabels.name(urls[0]) : "Selected game files")
    }
}
struct FileStamp: Equatable {
    let size: UInt64
    let modified: Date?
    init(_ url:URL) throws { let a=try FileManager.default.attributesOfItem(atPath:url.path);size=(a[.size] as? NSNumber)?.uint64Value ?? 0;modified=a[.modificationDate] as? Date }
}
enum FileLabels {
    static func name(_ url:URL) -> String {
        let raw=url.deletingPathExtension().lastPathComponent
        let clean=raw.replacingOccurrences(of:"\\[(?:[0-9a-fA-F]{16}|v[0-9][^\\]]*|USA|US|EUR|JPN|Base|Update|Patched[^\\]]*)\\]",with:"",options:[.regularExpression,.caseInsensitive]).trimmingCharacters(in:.whitespaces)
        return clean.isEmpty ? raw : clean
    }
    static func bytes(_ value:UInt64)->String { ByteCountFormatter.string(fromByteCount:Int64(min(UInt64(Int64.max),value)),countStyle:.file) }
}

/// Lightweight preparation. Full content hashes are checked only when work starts.
final class PreparationEngine {
    let engine: UtilityEngine
    var patcher: PatchEngine? { engine.patcher }
    init(engine:UtilityEngine) { self.engine=engine }
    func describe(_ info:FileInspection) -> SourceDescription {
        let game=info.titles.first(where:{$0.role == .game}) ?? info.titles.first
        let names=info.titles.map { $0.role.rawValue+($0.displayVersion.map { " · Version "+$0 } ?? "") }
        return SourceDescription(url:info.url,name:game?.name ?? FileLabels.name(info.url),description:names.isEmpty ? info.format : names.joined(separator:"; "))
    }
    func prepare(_ tool:UtilityTool,inputs:[URL],folder:URL?,names:[String:String]=[:]) throws -> [TaskPlan] {
        try engine.control.check()
        if tool == .update { return try prepareUpdates(inputs,folder:folder,names:names) }
        if tool == .combine { return [finish(prepareCombination(inputs),folder:folder,names:names)] }
        return try inputs.enumerated().map { index,url in
            try engine.control.check()
            engine.event("Preparing file \(index+1) of \(inputs.count) · \(FileLabels.name(url))",Double(index)/Double(inputs.count))
            var plan=TaskPlan.fallback([url])
            do {
                if tool == .join {
                    let parts=try engine.joinPlan(url)
                    plan.title=FileLabels.name(URL(fileURLWithPath:parts.name));plan.subtitle="\(parts.spans.count) parts · \(FileLabels.bytes(parts.size))"
                    let base=URL(fileURLWithPath:parts.name)
                    plan.outputName=base.deletingPathExtension().lastPathComponent+" [Joined]."+base.pathExtension
                    plan.preview="Join \(parts.spans.count) parts into one \(base.pathExtension.uppercased()) file. "+(parts.expectedHash == nil ? "No original checksum is available; the completed container will be checked." : "Each part and the complete file will be checked against saved checksums.")
                    plan.requiredSpace=parts.size+16*1024*1024;plan.sourceBytes=parts.size
                    for span in parts.spans { plan.sourceStamps[span.url]=try FileStamp(span.url) }
                } else {
                    let layout=try ContainerLayout(url)
                    plan.sourceBytes=layout.fileSize;plan.sourceStamps[url]=try FileStamp(url)
                    if tool == .inspect {
                        let info=try engine.inspect(url);plan.inspection=info;plan.sources=[describe(info)];plan.title=plan.sources[0].name
                        plan.subtitle=info.titles.compactMap { $0.displayVersion.map { "Version "+$0 } }.joined(separator:" · ")
                        plan.preview=info.note ?? "Names and versions are ready. A full content check hasn’t run yet."
                        if patcher == nil { plan.issue=TaskIssue(.keys,"Choose your prod.keys file to read game names, versions and check their content.") }
                        else if info.titles.isEmpty { plan.issue=TaskIssue(.input,"No supported game contents list was found. Choose a different file.") }
                    } else if tool == .convert {
                        let compressed=layout.entries.contains { $0.name.lowercased().hasSuffix(".ncz") }
                        plan.subtitle=(layout.isCartridge ? (compressed ? "XCZ" : "XCI") : (compressed ? "NSZ" : "NSP"))+" · "+FileLabels.bytes(layout.fileSize)
                        if !layout.isCartridge && !compressed && url.pathExtension.lowercased()=="nsp" { plan.skipReason="Already a standard NSP. No conversion is needed." }
                        else {
                            let restored=try layout.entries.reduce(UInt64(0)) { $0+($1.name.lowercased().hasSuffix(".ncz") ? try CompressedContent(archive:url,entry:$1).expandedSize : $1.size) }
                            plan.outputName=url.deletingPathExtension().lastPathComponent+" [Converted].nsp"
                            plan.requiredSpace=restored*2+32*1024*1024
                            plan.sizeEstimate="About "+FileLabels.bytes(restored)+" plus the package’s contents list"
                            plan.preview="Create one NSP copy. Included updates stay separate; they aren’t applied to the game."
                        }
                    } else if tool == .split {
                        let limit:UInt64=0xFFFF0000
                        if layout.fileSize<=limit { plan.skipReason="Already below the 4 GB file limit. No splitting is needed." }
                        else {
                            let count=1+(layout.fileSize-1)/limit
                            guard count<=10_000 else { throw TaskIssue(.input,"This file would create too many parts.") }
                            plan.outputName=url.deletingPathExtension().lastPathComponent+" [Split]"
                            plan.preview="Create \(count) parts that fit the drive’s file-size limit, plus a parts list. Keep them together for joining later."
                            plan.requiredSpace=layout.fileSize+32*1024*1024;plan.sizeEstimate=FileLabels.bytes(layout.fileSize)+" across \(count) parts"
                        }
                    } else if tool == .trim {
                        guard layout.isCartridge,!layout.entries.contains(where:{$0.name.lowercased().hasSuffix(".ncz")}) else { throw TaskIssue(.input,"Choose an uncompressed XCI file. XCZ files use compression instead.") }
                        if layout.usedSize>=layout.fileSize { plan.skipReason="Already trimmed. There’s no unused space to remove." }
                        else {
                            plan.outputName=url.deletingPathExtension().lastPathComponent+" [Trimmed].xci"
                            plan.requiredSpace=layout.usedSize+16*1024*1024
                            plan.preview=FileLabels.bytes(layout.fileSize)+" → "+FileLabels.bytes(layout.usedSize)+" · Save "+FileLabels.bytes(layout.fileSize-layout.usedSize)
                            plan.sizeEstimate=FileLabels.bytes(layout.usedSize)
                        }
                    }
                    if plan.subtitle.isEmpty { plan.subtitle=FileLabels.bytes(layout.fileSize) }
                }
            } catch { plan.issue=TaskIssue.from(error) }
            return finish(plan,folder:folder,names:names)
        }
    }
    func prepareCombination(_ inputs:[URL]) -> TaskPlan {
        var plan=TaskPlan.fallback(inputs)
        do {
            guard inputs.count>=2 else { throw TaskIssue(.input,"Add the original game and at least one matching update or add-on.") }
            guard patcher != nil else { throw TaskIssue(.keys,"Choose your prod.keys file so these game files can be matched.") }
            var infos:[FileInspection]=[]
            for (index,input) in inputs.enumerated() {
                try engine.control.check()
                engine.event("Preparing file \(index+1) of \(inputs.count) · \(FileLabels.name(input))",Double(index)/Double(inputs.count))
                do { infos.append(try engine.inspect(input)) }
                catch { throw TaskIssue.from(error) }
            }
            plan.sources=infos.map(describe)
            let titles=infos.flatMap(\.titles),games=titles.filter { $0.role == .game }
            guard games.count==1,let game=games.first else { throw TaskIssue(.input,"Choose one original game. Remove any extra original games, or add the missing original.") }
            let wrong=infos.filter { $0.titles.isEmpty || $0.titles.contains { $0.owner != game.id || $0.role == .other } }
            guard wrong.isEmpty else { throw TaskIssue(.input,"These files don’t match the original game: "+wrong.map { $0.url.lastPathComponent }.joined(separator:", ")) }
            guard titles.filter({$0.role == .update}).count<=1,Set(titles.map(\.id)).count==titles.count else { throw TaskIssue(.input,"More than one version of the same content was added. Remove the extra update or add-on.") }
            plan.title=game.name ?? plan.sources.first?.name ?? "Combined game"
            let updates=titles.filter { $0.role == .update },addons=titles.filter { $0.role == .addon }
            plan.subtitle="1 game · \(updates.count) update\(updates.count==1 ? "" : "s") · \(addons.count) add-on\(addons.count==1 ? "" : "s")"
            plan.preview="Create one NSP containing the game and its selected content. The update remains separate inside the file. All listed content is verified before combining."
            let base=infos.first { $0.titles.contains { $0.role == .game } }!.url
            plan.outputName=base.deletingPathExtension().lastPathComponent+" [Combined].nsp"
            let bytes=infos.flatMap(\.archive.entries).reduce(UInt64(0)) { $0+$1.size }
            let expanded=infos.flatMap(\.ncas).reduce(UInt64(0)) { $0+$1.declaredSize }
            plan.requiredSpace=max(bytes,expanded)*2+32*1024*1024;plan.sourceBytes=bytes;plan.sizeEstimate="Up to about "+FileLabels.bytes(max(bytes,expanded))
            for input in inputs { plan.sourceStamps[input]=try FileStamp(input) }
        } catch { plan.issue=TaskIssue.from(error) }
        return plan
    }
    func prepareUpdates(_ inputs:[URL],folder:URL?,names:[String:String]) throws -> [TaskPlan] {
        guard let patcher else { return inputs.map { url in var plan=TaskPlan.fallback([url]);plan.issue=TaskIssue(.keys,"Choose your prod.keys file so the games and updates can be matched.");return plan } }
        var packages:[InputPackage]=[],errors:[TaskPlan]=[],descriptions:[URL:SourceDescription]=[:],versions:[URL:String]=[:]
        for (index,url) in inputs.enumerated() {
            try engine.control.check()
            engine.event("Preparing file \(index+1) of \(inputs.count) · \(FileLabels.name(url))",Double(index)/Double(inputs.count))
            do {
                let info=try engine.inspect(url)
                if !info.titles.isEmpty,info.titles.allSatisfy({$0.role == .addon}) {
                    var plan=TaskPlan.fallback([url]);plan.sources=[describe(info)];plan.title=plan.sources[0].name;plan.inspection=info;plan.issue=TaskIssue(.input,"This is an add-on. Use Combine Files to keep it with your game.");errors.append(plan);continue
                }
                let package=try patcher.inspect(url)
                packages.append(package);descriptions[url]=describe(info);versions[url]=info.titles.first?.displayVersion
            } catch { var plan=TaskPlan.fallback([url]);plan.issue=TaskIssue.from(error);errors.append(plan) }
        }
        for group in Dictionary(grouping:packages,by:\.baseID).values {
            let sources=group.map(\.url),bases=group.filter { !$0.isUpdate },updates=group.filter(\.isUpdate)
            var plan=TaskPlan.fallback(sources)
            plan.sources=group.map { package in descriptions[package.url] ?? SourceDescription(url:package.url,name:FileLabels.name(package.url),description:package.isUpdate ? "Update" : "Original game") }
            plan.title=bases.first.flatMap { descriptions[$0.url]?.name } ?? FileLabels.name(sources[0])
            if bases.count != 1 || updates.count != 1 {
                let text=bases.isEmpty ? "Add the original game for this update." : updates.isEmpty ? "Add a matching update for this game." : bases.count>1 ? "More than one original game was added. Remove the extra file." : "More than one update was added. Remove the update you don’t want."
                plan.issue=TaskIssue(.input,text)
            } else {
                let job=PatchJob(base:bases[0],update:updates[0]);plan.job=job
                let version=versions[job.update.url] ?? versions[job.base.url]
                var data=Data(repeating:0,count:0x4000)
                if let version { data.replaceSubrange(0x3060..<(0x3060+min(16,version.utf8.count)),with:Data(version.utf8.prefix(16))) }
                plan.outputName=PatchEngine.outputFilename(baseName:job.name,controlData:data)
                plan.subtitle=version.map { "Updated copy · Version "+$0 } ?? "Game and update matched"
                plan.preview="Apply the matching update and create one new NSP. The original game and update stay unchanged."
                plan.requiredSpace=(job.base.program.declaredSize+job.update.program.declaredSize)*4+512*1024*1024
                plan.sourceBytes=job.base.program.declaredSize+job.update.program.declaredSize
                plan.sizeEstimate="Final size depends on the applied update"
                for url in sources { plan.sourceStamps[url]=try FileStamp(url) }
            }
            errors.append(finish(plan,folder:folder,names:names))
        }
        return errors.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func finish(_ original:TaskPlan,folder:URL?,names:[String:String]) -> TaskPlan {
        var plan=original
        if let name=names[plan.id] { plan.outputName=name }
        guard plan.issue==nil,plan.skipReason==nil,let name=plan.outputName,let folder else { return plan }
        do {
            guard (try? folder.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true,FileManager.default.isWritableFile(atPath:folder.path) else { throw TaskIssue(.destination,"The save folder is unavailable or not writable. Check the drive or choose another folder.") }
            guard !FileManager.default.fileExists(atPath:folder.appendingPathComponent(name).path) else { throw TaskIssue(.collision,"A file with this name already exists. Choose a separate name or another folder.") }
            try UtilityEngine.requireSpace(folder,plan.requiredSpace)
        } catch { plan.issue=TaskIssue.from(error) }
        return plan
    }
    /// Execute into a private folder, then publish the chosen name without replacing existing files.
    func execute(_ tool:UtilityTool,plan:TaskPlan,folder:URL) throws -> URL {
        try engine.control.check()
        guard let name=plan.outputName,!name.isEmpty,name != ".",name != "..",!name.contains("/"),!name.contains("\\") else { throw TaskIssue(.destination,"Choose a valid output filename.") }
        let destination=folder.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath:destination.path) else { throw TaskIssue(.collision,"A file with this name already exists. Choose another name or folder.") }
        for (url,stamp) in plan.sourceStamps { guard try FileStamp(url)==stamp else { throw TaskIssue(.input,"An input changed after it was added. Read the files again before continuing.") } }
        let workspace=try PatchEngine.privateDirectory(in:folder)
        defer { try? FileManager.default.removeItem(at:workspace) }
        let result:URL
        switch tool {
        case .update:
            guard let patcher,let job=plan.job else { throw TaskIssue(.input,"Add a matching game and update first.") }
            result=try patcher.patch(job,outputFolder:workspace)
        case .combine:result=try engine.combine(plan.sources.map(\.url),folder:workspace)
        case .convert:
            let input=plan.sources[0].url,layout=try ContainerLayout(input)
            if !layout.isCartridge && !layout.entries.contains(where:{$0.name.lowercased().hasSuffix(".ncz")}) {
                let file=workspace.appendingPathComponent(name)
                try engine.copyChecked([FileSpan(url:input,offset:0,size:layout.fileSize)],to:file,validateContainer:true);result=file
            } else { result=try engine.convert(input,folder:workspace) }
        case .split:result=try engine.split(plan.sources[0].url,folder:workspace)
        case .join:result=try engine.join(plan.sources[0].url,folder:workspace)
        case .trim:result=try engine.trim(plan.sources[0].url,folder:workspace)
        case .inspect:throw TaskIssue(.input,"Checking content doesn’t create a new file.")
        }
        try engine.control.check()
        try FileManager.default.moveItem(at:result,to:destination)
        return destination
    }
}

struct CollectedInputs {
    let files:[URL]
    let ignored:Int
    let duplicates:Int
}
enum InputCollector {
    static func collect(_ selections:[URL],tool:UtilityTool,known:Set<URL>,control:WorkControl,event:(Int)->Void={_ in}) throws -> CollectedInputs {
        let fm=FileManager.default
        var candidates:[URL]=[],ignored=0,visited=0
        for selected in selections {
            try control.check()
            if tool != .join,(try? selected.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true {
                var readError:Error?
                guard let entries=fm.enumerator(at:selected,includingPropertiesForKeys:[.isRegularFileKey],options:[.skipsHiddenFiles,.skipsPackageDescendants],errorHandler:{_,error in readError=error;return false}) else { throw TaskIssue(.input,"This folder couldn’t be read. Check that its drive is connected.") }
                for case let child as URL in entries {
                    try control.check();visited += 1
                    guard visited<=20000 else { throw TaskIssue(.input,"This folder contains too many items to scan at once. Choose a smaller folder.") }
                    if (try? child.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true {
                        if tool.extensions.contains(child.pathExtension.lowercased()) { candidates.append(child) } else { ignored += 1 }
                    }
                    if visited%100==0 { event(visited) }
                    guard candidates.count<=5000 else { throw TaskIssue(.input,"This folder contains more than 5,000 supported files. Choose a smaller folder.") }
                }
                if let error=readError { throw TaskIssue(.input,"This folder couldn’t be read completely. Check the drive or choose the files directly.",detail:error.localizedDescription) }
            } else if !selected.lastPathComponent.hasPrefix("._"),(tool == .join || tool.extensions.contains(selected.pathExtension.lowercased())) { candidates.append(selected) }
            else { ignored += 1 }
        }
        var normalized=Set<URL>()
        for input in candidates { try control.check();normalized.insert(input.resolvingSymlinksInPath().standardizedFileURL) }
        let duplicates=candidates.count-normalized.count+normalized.intersection(known).count
        return CollectedInputs(files:Array(normalized.subtracting(known)).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },ignored:ignored,duplicates:duplicates)
    }
}
