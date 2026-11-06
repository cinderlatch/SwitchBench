import Foundation
#if !os(Windows)
import CryptoKit
import Darwin
#endif

@main struct CoreTests {
    static var passed = 0
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw PatchError("TEST FAILED: \(message)") }
        passed += 1; print("PASS: \(message)")
    }
    static func rejects(_ message: String, _ body: () throws -> Void) throws {
        do { try body() } catch { passed += 1; print("PASS: \(message)"); return }
        throw PatchError("TEST FAILED: expected rejection — \(message)")
    }
    static func bytes(_ value: UInt64, _ count: Int) -> Data { var d = Data(); d.appendLE(value, bytes: count); return d }
    static func archive(_ names: [String], _ data: [Data], to url: URL) throws {
        var strings = Data(), entries = Data(), offset: UInt64 = 0
        for (index, name) in names.enumerated() {
            entries.appendLE(offset, bytes: 8); entries.appendLE(UInt64(data[index].count), bytes: 8)
            entries.appendLE(UInt64(strings.count), bytes: 4); entries.appendLE(0, bytes: 4)
            strings.append(Data(name.utf8)); strings.append(0); offset += UInt64(data[index].count)
        }
        var out = Data("PFS0".utf8); out.appendLE(UInt64(names.count), bytes: 4); out.appendLE(UInt64(strings.count), bytes: 4); out.appendLE(0, bytes: 4)
        out.append(entries); out.append(strings); data.forEach { out.append($0) }; try out.write(to: url)
    }
    static func nca(_ title: UInt64, rights: Data = Data(repeating: 0, count: 16), contentType: UInt8 = 0) -> Data {
        var header = Data(repeating: 0, count: 0xC00)
        header.replaceSubrange(0x200..<0x204, with: Data("NCA3".utf8))
        header[0x205] = contentType
        header.replaceSubrange(0x208..<0x210, with: bytes(0xC00, 8))
        header.replaceSubrange(0x210..<0x218, with: bytes(title, 8))
        header.replaceSubrange(0x230..<0x240, with: rights)
        return header
    }
    static func ticket(rights: Data, personalized: Bool = false) -> Data {
        var d = Data(repeating: 0, count: 0x400)
        d.replaceSubrange(0..<4, with: Data([4, 0, 1, 0]))
        d.replaceSubrange(0x180..<0x190, with: Data(repeating: 0xAB, count: 16))
        d[0x281] = personalized ? 1 : 0
        d.replaceSubrange(0x2A0..<0x2B0, with: rights)
        return d
    }
    static func main() throws {
        let fm = FileManager.default
        let root = try PatchEngine.privateDirectory(in: fm.temporaryDirectory); defer { try? fm.removeItem(at: root) }
        let engineURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let keys = root.appendingPathComponent("prod.keys"); try Data(("header_key = " + String(repeating: "00", count: 32) + "\n").utf8).write(to: keys)
        let control = WorkControl(), engine = PatchEngine(executable: engineURL, keys: keys, control: WorkControl()) { _, _ in }
        let one = root.appendingPathComponent("main"), two = root.appendingPathComponent("game.romfs")
        let payload = Data((0..<(4 * 1024 * 1024 + 31)).map { UInt8(truncatingIfNeeded: $0) })
        try Data("NSO0sample".utf8).write(to: one); try payload.write(to: two)
        let output = root.appendingPathComponent("roundtrip.nsp")
        try PatchEngine.pack([one, two], to: output, control: control) { _ in }
        let parsed = try PFSArchive(output)
        try expect(parsed.entries.map(\.name) == ["main", "game.romfs"], "container names and order")
        try expect(try parsed.read(parsed.entries[1], limit: payload.count) == payload, "streaming payload crosses 4 MB boundary intact")
        let p = Process(), pipe = Pipe(); p.executableURL = engineURL; p.arguments = ["-t", "pfs0", "-i", output.path]; p.standardOutput = pipe; p.standardError = pipe
        try p.run(); let report = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self); p.waitUntilExit()
        try expect(p.terminationStatus == 0 && report.contains("game.romfs"), "upstream hactool independently reads generated PFS0")
        let selectedKeyReport = try engine.run(["-k", keys.path, "-t", "pfs0", "-i", output.path], working: root)
        try expect(!selectedKeyReport.contains("prod.keys does not exist"), "selected keys do not trigger a warning about an unused default key file")
        try rejects("missing explicitly selected key file fails instead of silently falling back") {
            _ = try engine.run(["-k", root.appendingPathComponent("missing.keys").path, "-t", "pfs0", "-i", output.path], working: root)
        }
        #if !os(Windows)
        var beforeMemory = rusage(); getrusage(0, &beforeMemory)
        let memoryCopy = root.appendingPathComponent("memory-test-copy")
        for _ in 0..<32 {
            try parsed.extract(parsed.entries[1], to: memoryCopy, control: control) { _ in }
            try fm.removeItem(at: memoryCopy)
        }
        var afterMemory = rusage(); getrusage(0, &afterMemory)
        try expect(afterMemory.ru_maxrss - beforeMemory.ru_maxrss < 64 * 1024 * 1024, "repeated streamed copies release temporary buffers instead of accumulating job data")
        #endif
        let originalHash = SHA256.hash(data: try Data(contentsOf: output))
        try rejects("existing output is never overwritten") { try PatchEngine.pack([one], to: output, control: control) { _ in } }
        try expect(SHA256.hash(data: try Data(contentsOf: output)) == originalHash, "existing output unchanged")
        let raced = root.appendingPathComponent("raced.nsp")
        let existing = Data("another writer's file".utf8)
        try rejects("destination created during verification is never replaced") {
            try PatchEngine.pack([one], to: raced, control: control) { progress in
                if progress >= 1 && !fm.fileExists(atPath: raced.path) { try! existing.write(to: raced) }
            }
        }
        try expect(try Data(contentsOf: raced) == existing, "move publication preserves a competing destination")
        let cancelled = WorkControl(); cancelled.cancel()
        let cancelledURL = root.appendingPathComponent("cancelled.nsp")
        try rejects("cancelled copy aborts") { try PatchEngine.pack([two], to: cancelledURL, control: cancelled) { _ in } }
        try expect(!fm.fileExists(atPath: cancelledURL.path), "cancellation leaves no completed output")
        let broken = root.appendingPathComponent("broken.nsp")
        try archive(["../escape"], [Data([1])], to: broken)
        try rejects("path traversal entry rejected") { _ = try PFSArchive(broken) }
        try archive(["a", "A"], [Data([1]), Data([2])], to: broken)
        try rejects("case-insensitive duplicate names rejected") { _ = try PFSArchive(broken) }
        try archive(["a"], [Data([1, 2, 3])], to: broken)
        var raw = try Data(contentsOf: broken); raw.removeLast(); try raw.write(to: broken)
        try rejects("truncated payload rejected") { _ = try PFSArchive(broken) }
        try archive(["a", "b"], [Data([1, 2]), Data([3, 4])], to: broken)
        raw = try Data(contentsOf: broken); raw.replaceSubrange(40..<48, with: bytes(0, 8)); try raw.write(to: broken)
        try rejects("overlapping payloads rejected") { _ = try PFSArchive(broken) }
        try archive(["a"], [Data([1])], to: broken)
        raw = try Data(contentsOf: broken); raw[41] = 65; try raw.write(to: broken)
        try rejects("unterminated string table rejected") { _ = try PFSArchive(broken) }
        let baseURL = root.appendingPathComponent("random-base-name.nsp"), updateURL = root.appendingPathComponent("unrelated-update-name.nsp")
        let rights = Data(repeating: 0x12, count: 16)
        try archive(["program.nca", "common.tik", "meta.cnmt.nca"], [nca(0x0100000000001000, rights: rights), ticket(rights: rights), nca(0x0100000000001000, contentType: 1)], to: baseURL)
        try archive(["program.nca", "common.tik", "meta.cnmt.nca"], [nca(0x0100000000001000, rights: rights), ticket(rights: rights), nca(0x0100000000001800, contentType: 1)], to: updateURL)
        let base = try engine.inspect(baseURL), update = try engine.inspect(updateURL)
        try expect(base.baseID == update.baseID && !base.isUpdate && update.isUpdate, "real engine reads title IDs independently of filenames")
        try expect(base.program.rightsID == rights.hex, "rights IDs survive metadata parsing")
        try expect(base.program.titleID == update.program.titleID && base.metadataID != update.metadataID, "update role comes from metadata even when program IDs are identical")
        let job = PatchJob(base: base, update: update), titles = root.appendingPathComponent("title.keys")
        try engine.titleKeys(for: job, at: titles)
        try expect(try String(contentsOf: titles, encoding: .utf8).contains(String(repeating: "ab", count: 16)), "common tickets supply encrypted title keys locally")
        #if !os(Windows)
        let permissions = try fm.attributesOfItem(atPath: titles.path)[.posixPermissions] as! NSNumber
        try expect(permissions.intValue == 0o600, "temporary title-key file is owner only")
        #endif
        let personalURL = root.appendingPathComponent("personal.nsp")
        try archive(["program.nca", "personal.tik", "meta.cnmt.nca"], [nca(0x0100000000001000, rights: rights), ticket(rights: rights, personalized: true), nca(0x0100000000001000, contentType: 1)], to: personalURL)
        let personal = try engine.inspect(personalURL)
        try rejects("personalized tickets without title.keys fail explicitly") { try engine.titleKeys(for: PatchJob(base: personal, update: personal), at: root.appendingPathComponent("missing.keys")) }
        let extraEngine = PatchEngine(executable: engineURL, keys: keys, extraTitleKeys: titles, control: WorkControl()) { _, _ in }
        try extraEngine.titleKeys(for: PatchJob(base: personal, update: personal), at: root.appendingPathComponent("from-extra.keys"))
        passed += 1; print("PASS: explicit title.keys supports personalized ticket inputs")
        try rejects("same-role and mismatched jobs rejected") { _ = try engine.patch(PatchJob(base: base, update: base), outputFolder: root) }
        try archive(["a.nca", "b.nca"], [nca(0x0100000000001000), nca(0x0100000000001001)], to: broken)
        try rejects("multi-program package rejected") { _ = try engine.inspect(broken) }
        try archive(["a.ncz"], [Data([1])], to: broken)
        try rejects("compressed package rejected") { _ = try engine.inspect(broken) }
        try expect(!PatchEngine.scrub("key: " + String(repeating: "ab", count: 16)).contains(String(repeating: "ab", count: 16)), "key-like data redacted from messages")
        // Reproduce the reported batch failure: the app's source folder vanishes after two jobs.
        let originalApp = root.appendingPathComponent("OriginalApp")
        let originalHelpers = originalApp.appendingPathComponent("Contents/Helpers")
        try fm.createDirectory(at: originalHelpers, withIntermediateDirectories: true)
        let originalEngine = originalHelpers.appendingPathComponent("hactool" + HelperSession.executableSuffix), originalPacker = originalHelpers.appendingPathComponent("hacpack" + HelperSession.executableSuffix)
        try fm.copyItem(at: engineURL, to: originalEngine)
        try fm.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[2]), to: originalPacker)
        let pinned = try HelperSession(executable: originalEngine, parent: root)
        let pinnedEngine = PatchEngine(executable: pinned.executable, keys: keys, packer: pinned.packer, control: WorkControl()) { _, _ in }
        var batchInspected = 0
        for index in 0..<9 {
            if index == 2 { try fm.moveItem(at: originalApp, to: root.appendingPathComponent("MovedApp")) }
            let inspected = try pinnedEngine.inspect(baseURL)
            if inspected.baseID == base.baseID { batchInspected += 1 }
        }
        try expect(batchInspected == 9, "all nine jobs retain working helpers after the app is moved after job two")
        try expect(!fm.fileExists(atPath: originalEngine.path) && !fm.fileExists(atPath: originalPacker.path), "regression fixture removes the original helper paths")
        try pinned.validate()
        #if !os(Windows)
        try expect((try fm.attributesOfItem(atPath: pinned.directory.path)[.posixPermissions] as! NSNumber).intValue == 0o700, "runtime helper directory is private")
        #endif
        try rejects("missing helper is caught before a batch can start") {
            _ = try HelperSession(executable: pinned.executable, packer: root.appendingPathComponent("missing-hacpack"), parent: root)
        }
        let reportFile: URL
        do {
            let report = try BatchReport(folder: root)
            reportFile = report.url
            try report.append("Started 9 games")
            try report.append("failure detail " + String(repeating: "ab", count: 16))
            try report.append("Batch finished: 9 succeeded, 0 failed, 0 not run.")
        }
        let reportText = try String(contentsOf: reportFile, encoding: .utf8)
        try expect(reportText.contains("9 succeeded") && reportText.contains("[redacted]"), "batch report persists results and redacts key-like text")
        #if !os(Windows)
        try expect((try fm.attributesOfItem(atPath: reportFile.path)[.posixPermissions] as! NSNumber).intValue == 0o600, "saved batch report is owner only")
        #endif
        // Build a real minimal NCA-based NSP using the actual packer and verify it with hactool.
        let rebuiltRoot = root.appendingPathComponent("rebuild")
        let rebuiltPayload = rebuiltRoot.appendingPathComponent("payload")
        try fm.createDirectory(at: rebuiltPayload, withIntermediateDirectories: true)
        let secretFolder = rebuiltRoot.appendingPathComponent("local-secrets")
        try fm.createDirectory(at: secretFolder, withIntermediateDirectories: false)
        let buildKeys = secretFolder.appendingPathComponent("prod.keys")
        try Data(("header_key = " + String(repeating: "01", count: 32) + "\nkey_area_key_application_00 = " + String(repeating: "02", count: 16) + "\n").utf8).write(to: buildKeys)
        try Data().write(to: secretFolder.appendingPathComponent("title.keys"))
        var npdm = Data(repeating: 0, count: 0x300)
        npdm.replaceSubrange(0..<4, with: Data("META".utf8))
        npdm.replaceSubrange(0x70..<0x74, with: bytes(0x80, 4)); npdm.replaceSubrange(0x74..<0x78, with: bytes(0x40, 4))
        npdm.replaceSubrange(0x78..<0x7C, with: bytes(0xC0, 4)); npdm.replaceSubrange(0x7C..<0x80, with: bytes(0x240, 4))
        npdm.replaceSubrange(0x80..<0x84, with: Data("ACI0".utf8)); npdm.replaceSubrange(0x90..<0x98, with: bytes(0x0100000000001000, 8))
        npdm.replaceSubrange(0x2C0..<0x2C4, with: Data("ACID".utf8)); npdm.replaceSubrange(0x2C4..<0x2C8, with: bytes(0x140, 4))
        npdm.replaceSubrange(0x2D0..<0x2D8, with: bytes(0x0100000000001000, 8)); npdm.replaceSubrange(0x2D8..<0x2E0, with: bytes(0x0100000000001000, 8))
        try npdm.write(to: rebuiltPayload.appendingPathComponent("main.npdm"))
        try Data("NSO0synthetic-test-module".utf8).write(to: rebuiltPayload.appendingPathComponent("main"))
        var romfs = Data()
        for value: UInt64 in [0x50,0x50,0xC,0x5C,0x18,0x74,0xC,0x80,0,0x200] { romfs.appendLE(value, bytes: 8) }
        for value: UInt64 in [0,0xFFFFFFFF,0xFFFFFFFF,0,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF,0,0xFFFFFFFF,0xFFFFFFFF,0xFFFFFFFF] { romfs.appendLE(value, bytes: 4) }
        romfs.append(Data(repeating: 0, count: 0x200-romfs.count))
        try romfs.write(to: rebuiltPayload.appendingPathComponent("game.romfs"))
        var controlData = Data(repeating: 0, count: 0x4000)
        controlData.replaceSubrange(0..<7, with: Data("Fixture".utf8)); controlData.replaceSubrange(0x200..<0x204, with: Data("Test".utf8))
        controlData.replaceSubrange(0x3060..<0x3065, with: Data("1.2.3".utf8))
        try controlData.write(to: rebuiltPayload.appendingPathComponent("control.nacp"))
        let realBuilder = PatchEngine(executable: pinned.executable, keys: buildKeys, packer: pinned.packer, control: WorkControl()) { _, _ in }
        let rebuilt = try realBuilder.rebuild(payload: rebuiltPayload, baseID: 0x0100000000001000, version: 0x30000, baseName: "Fixture", working: rebuiltRoot, outputFolder: root, keyFolder: secretFolder)
        try expect(!fm.fileExists(atPath: rebuiltRoot.appendingPathComponent("prod.keys").path) && !fm.fileExists(atPath: rebuiltRoot.appendingPathComponent("title.keys").path), "rebuild supports a separate local keys folder for network output")
        let rebuiltArchive = try PFSArchive(rebuilt)
        try expect(rebuiltArchive.entries.count == 3 && rebuiltArchive.entries.allSatisfy { $0.name.hasSuffix(".nca") }, "real packer produces normal NCA archives rather than extracted game files")
        let rebuiltInfo = try realBuilder.inspect(rebuilt)
        try expect(rebuiltInfo.ncas.filter { $0.contentType == 1 }.count == 1 && rebuiltInfo.ncas.filter { $0.contentType == 2 }.count == 1, "rebuilt NSP has one application metadata archive and one control archive")
        try expect(rebuiltInfo.baseID == 0x0100000000001000 && !rebuiltInfo.isUpdate, "rebuilt package is recognized as a base application")
        let meta = rebuiltInfo.ncas.first { $0.contentType == 1 }!
        let metaFile = rebuiltRoot.appendingPathComponent("check.cnmt.nca"), metaDir = rebuiltRoot.appendingPathComponent("check-cnmt")
        try rebuiltInfo.archive.extract(meta.entry, to: metaFile, control: realBuilder.control) { _ in }
        try fm.createDirectory(at: metaDir, withIntermediateDirectories: false)
        _ = try realBuilder.run(realBuilder.arguments(titles: secretFolder.appendingPathComponent("title.keys")) + ["--section0dir=\(metaDir.path)", metaFile.path], working: rebuiltRoot, allowUnsigned: true)
        let cnmtFile = try fm.contentsOfDirectory(at: metaDir, includingPropertiesForKeys: nil).first { $0.pathExtension == "cnmt" }!
        let cnmt = try Data(contentsOf: cnmtFile)
        try expect(try cnmt.number(8, 4) == 0x30000 && cnmt[12] == 0x80, "application CNMT retains the applied update revision")
        let count = Int(try cnmt.number(0x10, 2)), recordStart = 0x20 + Int(try cnmt.number(0xE, 2))
        for index in 0..<count {
            let start = recordStart + index*0x38
            let id = cnmt.subdata(in: (start+0x20)..<(start+0x30)).hex + ".nca"
            let entry = rebuiltArchive.entries.first { $0.name == id }!
            let data = try rebuiltArchive.read(entry, limit: Int(entry.size))
            try expect(Data(SHA256.hash(data: data)) == cnmt.subdata(in: start..<(start+0x20)), "CNMT content record independently matches its NCA SHA-256")
        }
        let utility = UtilityEngine(patcher: realBuilder, control: realBuilder.control) { _, _ in }
        let described = try utility.inspect(rebuilt)
        try expect(described.titles.count == 1 && described.titles[0].name == "Fixture" && described.titles[0].displayVersion == "1.2.3", "utility reads actual game name and version from rebuilt metadata")
        try expect(try utility.verify(described).checked == 2, "utility independently verifies every content hash in the application table")
        let corruptURL = root.appendingPathComponent("corrupt-game.nsp")
        var corruptData = try Data(contentsOf: rebuilt)
        let programInfo = described.ncas.first { $0.contentType == 0 }!
        corruptData[Int(programInfo.entry.offset + programInfo.entry.size - 1)] ^= 1
        try corruptData.write(to: corruptURL)
        let corruptInfo = try utility.inspect(corruptURL)
        try rejects("utility rejects changed content even when headers still read correctly") { _ = try utility.verify(corruptInfo) }
        let missingURL = root.appendingPathComponent("missing-content.nsp")
        let remaining = described.archive.entries.filter { $0 != programInfo.entry }
        var remainingFiles: [URL] = []
        let missingDir = root.appendingPathComponent("missing-parts"); try fm.createDirectory(at: missingDir, withIntermediateDirectories: false)
        for entry in remaining {
            let file = missingDir.appendingPathComponent(entry.name)
            try described.archive.extract(entry, to: file, control: realBuilder.control) { _ in }; remainingFiles.append(file)
        }
        try PatchEngine.pack(remainingFiles, to: missingURL, control: realBuilder.control) { _ in }
        let missingInfo = try utility.inspect(missingURL)
        try rejects("utility detects a missing game-content archive") { _ = try utility.verify(missingInfo) }
        // Build real add-on content through hacPack, then retain both contents tables in a combined NSP.
        let addonRoot = root.appendingPathComponent("addon"); try fm.createDirectory(at: addonRoot, withIntermediateDirectories: false)
        let addonID: UInt64 = 0x0100000000002001
        let addonArgs = ["-k", buildKeys.path, "--type", "nca", "--titleid", String(format: "%016llx", addonID), "--plaintext", "--outdir", addonRoot.path, "--tempdir", addonRoot.appendingPathComponent("temp").path, "--backupdir", addonRoot.appendingPathComponent("backup").path]
        _ = try realBuilder.run(addonArgs + ["--ncatype", "publicdata", "--romfsdir", rebuiltRoot.appendingPathComponent("payload/game.romfs").path], working: root, tool: realBuilder.packer)
        let publicData = try fm.contentsOfDirectory(at: addonRoot, includingPropertiesForKeys: nil).first { $0.pathExtension == "nca" }!
        _ = try realBuilder.run(addonArgs + ["--ncatype", "meta", "--titletype", "addon", "--publicdatanca", publicData.path], working: root, tool: realBuilder.packer)
        let addon = root.appendingPathComponent("addon.nsp")
        try PatchEngine.pack(fm.contentsOfDirectory(at: addonRoot, includingPropertiesForKeys: nil).filter { $0.pathExtension == "nca" }, to: addon, control: realBuilder.control) { _ in }
        let addonInfo = try utility.inspect(addon)
        try expect(addonInfo.titles.first?.role == .addon && addonInfo.titles.first?.owner == described.titles[0].id, "DLC is matched to its game by application metadata rather than filenames")
        let combinedFolder = root.appendingPathComponent("combined"); try fm.createDirectory(at: combinedFolder, withIntermediateDirectories: false)
        let combined = try utility.combine([rebuilt, addon], folder: combinedFolder)
        let combinedInfo = try utility.inspect(combined)
        try expect(combinedInfo.titles.count == 2 && combinedInfo.titles.contains { $0.role == .addon }, "combined package keeps original game and DLC as separate contents")
        try expect(try utility.verify(combinedInfo).checked == 3, "all game and DLC content hashes verify after combining")
        try rejects("combining duplicate content versions is rejected") { _ = try utility.combine([rebuilt, addon, addon], folder: combinedFolder) }
        if let destination = ProcessInfo.processInfo.environment["QA_FIXTURES"] {
            let target=URL(fileURLWithPath:destination);try fm.createDirectory(at:target,withIntermediateDirectories:true)
            for (source,name) in [(rebuilt,"Sample Game.nsp"),(addon,"Sample Add-on.nsp"),(buildKeys,"test-prod.keys")] {
                let output=target.appendingPathComponent(name);if fm.fileExists(atPath:output.path) { try fm.removeItem(at:output) };try fm.copyItem(at:source,to:output)
            }
        }
        let negativeFolder=root.appendingPathComponent("negative-combine");try fm.createDirectory(at:negativeFolder,withIntermediateDirectories:false)
        try rejects("combine rejects a single package") { _=try utility.combine([rebuilt],folder:negativeFolder) }
        try rejects("combine rejects add-ons without the original game") { _=try utility.combine([addon,addon],folder:negativeFolder) }
        try rejects("combine rejects two base games") { _=try utility.combine([rebuilt,rebuilt],folder:negativeFolder) }
        try rejects("combine refuses damaged game content before publishing") { _=try utility.combine([corruptURL,addon],folder:negativeFolder) }
        try rejects("combine refuses missing game content before publishing") { _=try utility.combine([missingURL,addon],folder:negativeFolder) }
        try expect(try fm.contentsOfDirectory(atPath:negativeFolder.path).isEmpty,"invalid combinations leave no outputs or temporary files")
        let combinedBefore=try Data(contentsOf:combined)
        try rejects("combine refuses existing output names") { _=try utility.combine([rebuilt,addon],folder:combinedFolder) }
        try expect(try Data(contentsOf:combined)==combinedBefore,"combine preserves the existing output on collision")
        let cancelledCombine=WorkControl();cancelledCombine.cancel()
        let cancelledUtility=UtilityEngine(patcher:realBuilder,control:cancelledCombine) {_,_ in}
        try rejects("combine cancellation stops before publication") { _=try cancelledUtility.combine([rebuilt,addon],folder:negativeFolder) }
        try expect(try fm.contentsOfDirectory(atPath:negativeFolder.path).isEmpty,"cancelled combine leaves no partial output")
        let onlyOptional=TitleContents(id:described.titles[0].id,owner:described.titles[0].id,role:.game,revision:0,records:[ContentRecord(hash:Data(repeating:0,count:32),id:String(repeating:"0",count:32),size:1,type:6)],name:nil,displayVersion:nil)
        let incomplete=FileInspection(url:described.url,format:described.format,bytes:described.bytes,entries:described.entries,archive:described.archive,ncas:described.ncas,titles:[onlyOptional],note:nil)
        try rejects("an optional-fragments-only package cannot receive a successful content check") { _=try utility.verify(incomplete) }
        let keyValue = String(repeating: "01", count: 32)
        let html = Data("<!doctype html><html><textarea>header_key = \(keyValue)</textarea><div>header_key = \(keyValue)</div></html>".utf8)
        let recovered = try PatchEngine.productionKeyText(html)
        try expect(String(decoding: recovered, as: UTF8.self) == "header_key = \(keyValue)\n", "saved HTML keyset recovered locally without duplicate assignments")
        var legacyPage = html; legacyPage.append(0xFF)
        try expect(try PatchEngine.productionKeyText(legacyPage) == recovered, "non-UTF-8 page decoration does not corrupt ASCII key recovery")
        var nacp = Data(repeating: 0, count: 0x4000)
        nacp.replaceSubrange(0x3060..<0x3067, with: Data("1.0.1_5".utf8))
        try expect(PatchEngine.outputFilename(baseName: "GAME [v0]", controlData: nacp) == "GAME [Patched 1.0.1_5].nsp", "output uses updated display version rather than a stale base version")
        try expect(PatchEngine.outputFilename(baseName: "GAME [v1.0.0]", controlData: nacp) == "GAME [Patched 1.0.1_5].nsp", "output removes dotted base-version labels before adding the applied version")
        try rejects("HTML without embedded keys rejected clearly") { _ = try PatchEngine.productionKeyText(Data("<!doctype html><html>Sign in</html>".utf8)) }
        try rejects("conflicting embedded keys rejected") { _ = try PatchEngine.productionKeyText(Data("<html>header_key = \(keyValue)\nheader_key = \(String(repeating: "02", count: 32))</html>".utf8)) }
        print("\n\(passed) checks passed. Real-game BKTR application and Eden boot are not verified by these synthetic tests.")
    }
}
