import Foundation

@main struct WorkflowTests {
    static func main() throws {
        var passed=0
        func expect(_ ok:@autoclosure () throws -> Bool,_ name:String) throws { guard try ok() else { throw PatchError("FAIL: "+name) };passed += 1;print("PASS: "+name) }
        let fm=FileManager.default,fixtures=URL(fileURLWithPath:CommandLine.arguments[2]),helper=URL(fileURLWithPath:CommandLine.arguments[1])
        let root=try PatchEngine.privateDirectory(in:fm.temporaryDirectory);defer {try? fm.removeItem(at:root)}
        let keys=fixtures.appendingPathComponent("test-prod.keys"),game=fixtures.appendingPathComponent("Sample Game.nsp"),addon=fixtures.appendingPathComponent("Sample Add-on.nsp"),xci=fixtures.appendingPathComponent("Sample Cartridge.xci")
        let patcher=PatchEngine(executable:helper,keys:keys,packer:URL(fileURLWithPath:CommandLine.arguments[3]),control:WorkControl()) {_,_ in}
        let e=UtilityEngine(patcher:patcher,control:patcher.control) {_,_ in},prep=PreparationEngine(engine:e)
        let plain=UtilityEngine(patcher:nil,control:WorkControl()) {_,_ in},simple=PreparationEngine(engine:plain)
        let noop=try simple.prepare(.convert,inputs:[game],folder:root)[0]
        try expect(noop.skipReason != nil && noop.issue==nil,"preparation classifies an existing NSP as healthy no-op")
        let small=try simple.prepare(.split,inputs:[game],folder:root)[0]
        try expect(small.skipReason != nil && small.outputName==nil,"small files are skipped without creating a split folder")
        let trim=try simple.prepare(.trim,inputs:[xci],folder:root)[0],layout=try ContainerLayout(xci)
        try expect(trim.preview.contains("Save ") && trim.requiredSpace>=layout.usedSize,"shrink preview gives actual size savings and temporary-space requirement")
        let plan=try simple.prepare(.convert,inputs:[xci],folder:root)[0]
        try expect(plan.outputName=="Sample Cartridge [Converted].nsp" && plan.requiredSpace>0 && plan.issue==nil,"conversion previews exact filename and needed space")
        let converted=try simple.execute(.convert,plan:plan,folder:root)
        try expect(fm.fileExists(atPath:converted.path),"the prepared conversion publishes its checked result")
        let collision=try simple.prepare(.convert,inputs:[xci],folder:root)[0]
        try expect(collision.issue?.kind == .collision,"preparation identifies output collisions before copying")
        let renamed=try simple.prepare(.convert,inputs:[xci],folder:root,names:[plan.id:"Separate Copy.nsp"])[0]
        let separate=try simple.execute(.convert,plan:renamed,folder:root)
        try expect(try UtilityEngine.hash(separate,control:plain.control)==UtilityEngine.hash(converted,control:plain.control),"a separately named copy retains identical game bytes")
        let info=try prep.prepare(.inspect,inputs:[game,addon],folder:nil)
        try expect(info.count==2 && info[0].title=="Fixture" && info[0].subtitle.contains("1.2.3"),"batch inspection promotes actual game name and version")
        let combined=try prep.prepare(.combine,inputs:[game,addon],folder:root)[0]
        try expect(combined.issue==nil && combined.subtitle.contains("1 add-on") && combined.sources.count==2,"combination preview identifies matching game and add-on")
        let badCombo=try prep.prepare(.combine,inputs:[game,game],folder:root)[0]
        try expect(badCombo.issue?.kind == .input,"combination preview rejects duplicate original games")
        let lone=try prep.prepare(.update,inputs:[game],folder:root)[0]
        try expect(lone.issue?.message.contains("matching update")==true,"update preview explains a missing update")
        let keylessCompression = try simple.prepare(.compress, inputs: [game], folder: root)[0]
        try expect(keylessCompression.issue?.kind == .keys, "compression preview asks for a local key file")
        let cartridge = fixtures.appendingPathComponent("Compressible Cartridge.xci")
        let compression = try prep.prepare(.compress, inputs: [game, cartridge, addon], folder: root)
        try expect(compression.map { $0.outputName?.suffix(4) } == [".nsz", ".xcz", ".nsz"], "batch compression previews the format for each source")
        for (input, plan) in zip([game, cartridge, addon], compression) {
            let before = try UtilityEngine.hash(input, control: patcher.control)
            let output = try prep.execute(.compress, plan: plan, folder: root)
            let packed = try PFSArchive(output)
            try expect(packed.entries.contains { $0.name.hasSuffix(".ncz") } &&
                       (try FileStamp(output).size) < (try FileStamp(input).size), "compression publishes a smaller package with compressed game data")
            try expect(try UtilityEngine.hash(input, control: patcher.control) == before, "compression leaves the original unchanged")
            let restored = try simple.execute(.convert, plan: simple.prepare(.convert, inputs: [output], folder: root)[0], folder: root)
            let archive = try PFSArchive(input), copy = try PFSArchive(restored)
            try expect(archive.entries.map(\.name) == copy.entries.map(\.name), "conversion restores the original member names and order")
            for (original, member) in zip(archive.entries, copy.entries) {
                let data = try archive.read(original, limit: Int(original.size))
                try expect(original.size == member.size && (try copy.read(member, limit: Int(member.size))) == data,
                           "compression round trip preserves every member byte")
            }
            let info = try e.inspect(output)
            try expect(try e.verify(info).checked > 0, "the compressed copy passes the original game metadata checks")
            if input == cartridge {
                let report = try patcher.run(["-i", "-t", "xci", "--disablekeywarns", output.path], working: root, allowUnsigned: true)
                try expect(report.contains("update") && report.contains(".ncz"), "hactool independently reads the compressed cartridge partitions")
                let sourcePartitions = try ContainerLayout(input).cartridge!.partitions
                let copyPartitions = try ContainerLayout(output).cartridge!.partitions
                let sourceUpdate = sourcePartitions.first { $0.name == "update" }!
                let savedUpdate = copyPartitions.first { $0.name == "update" }!
                let source = try Data(contentsOf: input), saved = try Data(contentsOf: output)
                try expect(source.subdata(in: Int(sourceUpdate.offset)..<Int(sourceUpdate.offset + sourceUpdate.size)) ==
                           saved.subdata(in: Int(savedUpdate.offset)..<Int(savedUpdate.offset + savedUpdate.size)),
                           "compression preserves the entire non-game cartridge partition")
            }
            if input == addon {
                let member = packed.entries.first { $0.name.hasSuffix(".ncz") }!
                try expect(try CompressedContent(archive: output, entry: member).sections.contains { $0.type == 3 },
                           "encrypted game content is written using AES-CTR section records")
            }
        }
        let noSavings = try prep.prepare(.compress, inputs: [xci], folder: root)[0]
        do {
            _ = try prep.execute(.compress, plan: noSavings, folder: root)
            throw PatchError("Unexpected compression of unsupported content")
        } catch let error as PatchError {
            try expect(error.message.contains("become smaller") &&
                       !fm.fileExists(atPath: root.appendingPathComponent(noSavings.outputName!).path),
                       "unsupported content leaves no compressed output")
        }
        let cancelledCompression = WorkControl()
        let cancelPatcher = PatchEngine(executable: helper, keys: keys, control: cancelledCompression) { _, _ in }
        let cancelEngine = UtilityEngine(patcher: cancelPatcher, control: cancelledCompression) { stage, _ in
            if stage == "Compressing and checking game data" { cancelledCompression.cancel() }
        }
        let cancelFolder = root.appendingPathComponent("Cancelled")
        try fm.createDirectory(at: cancelFolder, withIntermediateDirectories: false)
        do {
            _ = try cancelEngine.compress(game, folder: cancelFolder)
            throw PatchError("Unexpected compression after cancellation")
        } catch let error as PatchError {
            try expect(error.message.contains("Cancelled") && (try fm.contentsOfDirectory(atPath: cancelFolder.path)).isEmpty,
                       "cancelling during compression cleans up all staged files")
        }
        let parts=fixtures.appendingPathComponent("Sample Parts")
        let join=try simple.prepare(.join,inputs:[parts],folder:root)[0]
        try expect(join.preview.contains("parts") && join.preview.contains("checksums") && join.requiredSpace>0,"join preview discovers part count and checksum availability without hashing all content")
        let joined=try simple.execute(.join,plan:join,folder:root)
        try expect(try ContainerLayout(joined).entries.count==2,"prepared legacy-manifest joining produces a complete container")
        let unavailable=try simple.prepare(.convert,inputs:[xci],folder:root.appendingPathComponent("missing-folder"))[0]
        try expect(unavailable.issue?.kind == .destination,"an unavailable destination has actionable preparation feedback")
        let keyless=try simple.prepare(.inspect,inputs:[game],folder:nil)[0]
        try expect(keyless.issue?.kind == .keys && keyless.inspection != nil,"keyless inspection shows basic format information with key recovery")
        let changed=root.appendingPathComponent("changed.xci");try fm.copyItem(at:xci,to:changed)
        let before=try simple.prepare(.trim,inputs:[changed],folder:root)[0]
        let handle=try FileHandle(forWritingTo:changed);try handle.truncate(atOffset:100);try handle.close()
        do { _=try simple.execute(.trim,plan:before,folder:root);throw PatchError("Input mutation was accepted") }
        catch let issue as TaskIssue { try expect(issue.kind == .input,"changed sources are rejected after preparation") }
        let stopped=WorkControl();stopped.cancel()
        let stoppedPrep=PreparationEngine(engine:UtilityEngine(patcher:nil,control:stopped) {_,_ in})
        do { _=try stoppedPrep.execute(.convert,plan:renamed,folder:root);throw PatchError("Cancellation ignored") }
        catch { try expect(!fm.fileExists(atPath:root.appendingPathComponent(".partial").path),"prepared execution observes cancellation without publishing a partial") }
        let noTemp=try fm.contentsOfDirectory(atPath:root.path).filter { $0.hasPrefix(".switchpatch-") || $0.hasSuffix(".partial") }
        try expect(noTemp.isEmpty,"prepared task workspaces are cleaned after success and failure")
        let importFolder=root.appendingPathComponent("Import");try fm.createDirectory(at:importFolder,withIntermediateDirectories:false)
        for name in ["one.nsp","two.xci","notes.txt"] { try Data([1]).write(to:importFolder.appendingPathComponent(name)) }
        let collection=try InputCollector.collect([importFolder,importFolder.appendingPathComponent("one.nsp")],tool:.inspect,known:[],control:WorkControl())
        try expect(collection.files.count==2 && collection.duplicates==1 && collection.ignored==1,"folder import counts supported files, duplicates and ignored items")
        let cancelCollection=WorkControl();cancelCollection.cancel()
        do { _=try InputCollector.collect([fixtures],tool:.inspect,known:[],control:cancelCollection);throw TaskIssue(.input,"Cancellation ignored") }
        catch let error as PatchError { try expect(error.message.contains("Cancelled"),"folder scanning observes cancellation before changing a selection") }
        let source=try patcher.inspect(game),updateFolder=root.appendingPathComponent("update");try fm.createDirectory(at:updateFolder,withIntermediateDirectories:false)
        var stored:[URL]=[]
        for nca in source.ncas where [0,2].contains(nca.contentType) {
            let file=root.appendingPathComponent(nca.entry.name);try source.archive.extract(nca.entry,to:file,control:patcher.control) { _ in };stored.append(file)
        }
        let controlFile=stored.first { $0.lastPathComponent==source.ncas.first(where:{$0.contentType==2})!.entry.name }!
        let romfs=root.appendingPathComponent("update-control");try fm.createDirectory(at:romfs,withIntermediateDirectories:false)
        _=try patcher.run(["-y","-k",keys.path,"--romfsdir=\(romfs.path)",controlFile.path],working:root,allowUnsigned:true)
        let nacp=romfs.appendingPathComponent("control.nacp");var nacpBytes=try Data(contentsOf:nacp);nacpBytes.replaceSubrange(0x3060..<0x3070,with:Data(repeating:0,count:16));nacpBytes.replaceSubrange(0x3060..<0x3065,with:Data("1.2.4".utf8));try nacpBytes.write(to:nacp)
        let args=["-k",keys.path,"--type","nca","--titleid","0100000000001800","--plaintext","--outdir",updateFolder.path,"--tempdir",updateFolder.appendingPathComponent("tmp").path,"--backupdir",updateFolder.appendingPathComponent("backup").path]
        _=try patcher.run(args+["--ncatype","control","--romfsdir",romfs.path],working:root,tool:patcher.packer)
        let newControl=try fm.contentsOfDirectory(at:updateFolder,includingPropertiesForKeys:nil).first { $0.pathExtension=="nca" }!
        let program=stored.first { $0 != controlFile }!
        var cnmt=Data(repeating:0,count:0x30)
        func set(_ offset:Int,_ value:UInt64,_ bytes:Int) { var d=Data();d.appendLE(value,bytes:bytes);cnmt.replaceSubrange(offset..<(offset+bytes),with:d) }
        set(0,0x0100000000001800,8);set(8,0x40000,4);cnmt[12]=0x81;set(14,0x10,2);set(16,2,2);set(0x20,0x0100000000001000,8)
        for (file,type) in [(program,UInt8(1)),(newControl,UInt8(3))] {
            let hash=try UtilityEngine.hash(file,control:patcher.control);cnmt.append(hash);cnmt.append(hash.prefix(16));cnmt.appendLE(try FileStamp(file).size,bytes:6);cnmt.append(type);cnmt.append(0)
        }
        cnmt.append(Data(repeating:0,count:32));let cnmtFile=root.appendingPathComponent("Patch.cnmt");try cnmt.write(to:cnmtFile)
        _=try patcher.run(args+["--ncatype","meta","--titletype","patch","--titleversion","00040000","--cnmt",cnmtFile.path],working:root,tool:patcher.packer)
        let meta=try fm.contentsOfDirectory(at:updateFolder,includingPropertiesForKeys:nil).first { $0.lastPathComponent.hasSuffix("cnmt.nca") }!
        let update=root.appendingPathComponent("Metadata Sample Update.nsp");try PatchEngine.pack([program,newControl,meta],to:update,control:patcher.control) { _ in }
        let pair=try prep.prepare(.update,inputs:[game,update],folder:root)[0]
        try expect(pair.job != nil && pair.subtitle.contains("1.2.4") && pair.outputName?.contains("1.2.4")==true,"update preview pairs real synthetic metadata and uses the selected update’s display version")
        let bundle=try prep.prepare(.combine,inputs:[game,update,addon],folder:root)[0]
        try expect(bundle.issue==nil && bundle.subtitle.contains("1 update") && bundle.subtitle.contains("1 add-on"),"combination preview retains the distinct game, update and add-on roles")
        let fullBundle=try prep.execute(.combine,plan:bundle,folder:root)
        try expect(try e.inspect(fullBundle).titles.count==3 && e.verify(e.inspect(fullBundle)).checked>0,"prepared combination with an update and add-on verifies all retained content")
        let mislabeled=root.appendingPathComponent("Mislabeled.nsz");try fm.copyItem(at:game,to:mislabeled)
        let correctedPlan=try simple.prepare(.convert,inputs:[mislabeled],folder:root)[0]
        let corrected=try simple.execute(.convert,plan:correctedPlan,folder:root)
        try expect(corrected.pathExtension=="nsp" && (try UtilityEngine.hash(corrected,control:plain.control))==UtilityEngine.hash(game,control:plain.control),"a standard NSP with a misleading extension gets a correctly named, identical copy")
        let raceURL=root.appendingPathComponent("Race.nsp");var competing=false
        let raceEngine=UtilityEngine(patcher:nil,control:WorkControl()) { stage,value in
            if stage=="Saving and checking the new file",(value ?? 0)>0.8,!competing { competing=true;fm.createFile(atPath:raceURL.path,contents:Data("other writer".utf8)) }
        }
        let racePrep=PreparationEngine(engine:raceEngine),racePlan=try racePrep.prepare(.convert,inputs:[xci],folder:root,names:[plan.id:"Race.nsp"])[0]
        do { _=try racePrep.execute(.convert,plan:racePlan,folder:root);throw PatchError("Publication race was accepted") }
        catch {
            try expect(competing && (try Data(contentsOf:raceURL))==Data("other writer".utf8),"prepared publication never replaces an output created by another writer")
            try expect(TaskIssue.from(error).kind == .collision,"a final-publication race offers filename recovery")
        }
        try expect(try fm.contentsOfDirectory(atPath:root.path).allSatisfy { !$0.hasPrefix(".switchpatch-") },"a failed final publication cleans its checked private workspace")
        let fixtureUpdate=fixtures.appendingPathComponent("Metadata Sample Update.nsp")
        if fm.fileExists(atPath:fixtureUpdate.path) { try fm.removeItem(at:fixtureUpdate) };try fm.copyItem(at:update,to:fixtureUpdate)
        print("\(passed) workflow checks passed.")
    }
}
