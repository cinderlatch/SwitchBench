import Foundation
import CryptoKit
import zlib

enum ContentRole: String { case game = "Game", update = "Update", addon = "Add-on pack", other = "Other content" }
struct ContentRecord { let hash: Data; let id: String; let size: UInt64; let type: UInt8 }
struct TitleContents: Identifiable {
    let id: UInt64
    let owner: UInt64
    let role: ContentRole
    let revision: UInt32
    let records: [ContentRecord]
    var name: String?
    var displayVersion: String?
}
struct FileInspection {
    let url: URL
    let format: String
    let bytes: UInt64
    let entries: Int
    let archive: PFSArchive
    let ncas: [NCAInfo]
    let titles: [TitleContents]
    let note: String?
}
struct VerificationResult {
    let checked: Int
    let bytes: UInt64
    let notes: [String]
    var summary: String { "Content checks passed. \(checked) stored \(checked == 1 ? "item matches" : "items match") the game’s contents list." }
}

// Immutable engine configuration; WorkControl synchronizes cancellation across queues.
final class UtilityEngine: @unchecked Sendable {
    let patcher: PatchEngine?
    let control: WorkControl
    let event: (String, Double?) -> Void
    init(patcher: PatchEngine?, control: WorkControl, event: @escaping (String, Double?) -> Void) {
        self.patcher = patcher; self.control = control; self.event = event
    }
    static func restoredName(_ name: String) -> String { name.lowercased().hasSuffix(".ncz") ? String(name.dropLast(1)) + "a" : name }
    static func requireSpace(_ folder: URL, _ bytes: UInt64) throws {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: folder.path)
        if let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value, free < bytes {
            throw PatchError("This operation needs about \(ByteCountFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))), countStyle: .file)) free in the chosen folder. Choose another folder or make room first.")
        }
    }
    static func hash(_ url: URL, offset: UInt64 = 0, size: UInt64? = nil, control: WorkControl, progress: (Double) -> Void = { _ in }) throws -> Data {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        let full = try h.seekToEnd()
        guard offset <= full, (size ?? full-offset) <= full-offset else { throw PatchError("The file is incomplete.") }
        let length = size ?? full-offset
        try h.seek(toOffset: offset); var left = length, hasher = SHA256()
        while left > 0 {
            try autoreleasepool {
                try control.check()
                let n = Int(min(left, 4*1024*1024)), d = try h.read(upToCount: n) ?? Data()
                guard d.count == n else { throw PatchError("The file changed while being checked.") }
                hasher.update(data: d); left -= UInt64(n); progress(Double(length-left)/Double(max(1,length)))
            }
        }
        return Data(hasher.finalize())
    }
    static func titleStrings(_ nacp: Data) throws -> (String?, String?) {
        guard nacp.count >= 0x4000 else { throw PatchError("The game-information file is incomplete.") }
        let version = String(data: nacp[0x3060..<0x3070].prefix { $0 != 0 }, encoding: .utf8)
        var names = nacp.subdata(in: 0..<0x3000)
        if nacp[0x3215] == 1 {
            let size = Int(try nacp.number(0, 2))
            guard size > 0, size <= 0x2FFE else { throw PatchError("The game’s compressed title information is invalid.") }
            let src = nacp.subdata(in: 2..<(2+size)); var out = Data(count: 32*0x300), stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw PatchError("Couldn’t read the game title.") }
            defer { inflateEnd(&stream) }
            let result = out.withUnsafeMutableBytes { dst in src.withUnsafeBytes { input -> Int32 in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress); stream.avail_in = uInt(src.count)
                stream.next_out = dst.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = uInt(dst.count)
                return inflate(&stream, Z_FINISH)
            }}
            guard result == Z_STREAM_END, stream.avail_in == 0, stream.total_out > 0, stream.total_out % 0x300 == 0 else { throw PatchError("The compressed game title couldn’t be read.") }
            names = Data(out.prefix(Int(stream.total_out)))
        } else if nacp[0x3215] != 0 { throw PatchError("This game uses a newer title-information format.") }
        for index in 0..<(names.count/0x300) {
            let text = names[(index*0x300)..<(index*0x300+0x200)].prefix { $0 != 0 }
            if !text.isEmpty, let title = String(data: Data(text), encoding: .utf8) { return (title, version) }
        }
        return (nil, version)
    }
    func inspect(_ url: URL) throws -> FileInspection {
        try control.check(); event("Reading file information", nil)
        let layout = try ContainerLayout(url), archive = try PFSArchive(url)
        let compressed = layout.entries.contains { $0.name.lowercased().hasSuffix(".ncz") }
        let format = layout.isCartridge ? (compressed ? "XCZ · Compressed cartridge dump" : "XCI · Cartridge dump") : (compressed ? "NSZ · Compressed game package" : "NSP · Game package")
        guard let patcher else { return FileInspection(url: url, format: format, bytes: layout.fileSize, entries: archive.entries.count, archive: archive, ncas: [], titles: [], note: "Choose your key file to read game names, versions and included updates.") }
        let (_, ncas) = try patcher.inspectContents(url)
        guard Set(ncas.map { Self.restoredName($0.entry.name).lowercased() }).count == ncas.count else {
            throw PatchError("This file contains duplicate names for the same content. Use a different copy of the game file.")
        }
        let fm = FileManager.default, temp = try PatchEngine.privateDirectory(in: fm.temporaryDirectory)
        defer { try? fm.removeItem(at: temp) }
        _ = try patcher.prepareProductionKeys(in: temp)
        let titleFile = temp.appendingPathComponent("title.keys")
        try patcher.titleKeys(archives: [archive], ncas: ncas, at: titleFile)
        var titles: [TitleContents] = [], notes: [String] = []
        for (index, metadata) in ncas.filter({ $0.contentType == 1 }).enumerated() {
            guard metadata.declaredSize <= 32*1024*1024 else { throw PatchError("The game’s contents list is unusually large.") }
            let dir = temp.appendingPathComponent("meta-\(index)"); try fm.createDirectory(at: dir, withIntermediateDirectories: false)
            let file = dir.appendingPathComponent("content.nca")
            try archive.extract(metadata.entry, to: file, control: control) { _ in }
            _ = try patcher.run(patcher.arguments(titles: titleFile) + ["--section0dir=\(dir.path)", file.path], working: dir, allowUnsigned: true)
            let tables = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "cnmt" }
            guard tables.count == 1 else { throw PatchError("A game file has a missing or ambiguous contents list.") }
            let data = try Data(contentsOf: tables[0])
            guard data.count >= 0x20 else { throw PatchError("The game’s contents list is incomplete.") }
            let id = try data.number(0, 8), revision = UInt32(try data.number(8, 4)), count = Int(try data.number(0x10, 2)), start = 0x20 + Int(try data.number(0xe, 2))
            guard id == metadata.titleID, start <= data.count, count <= (data.count-start)/0x38 else { throw PatchError("The game’s contents list is inconsistent or incomplete.") }
            let role: ContentRole = data[12] == 0x80 ? .game : data[12] == 0x81 ? .update : data[12] == 0x82 ? .addon : .other
            let owner: UInt64
            if role == .update || role == .addon {
                guard start >= 0x28 else { throw PatchError("The update or add-on pack has no matching game information.") }
                owner = try data.number(0x20, 8)
            } else { owner = id }
            var records: [ContentRecord] = []
            for i in 0..<count {
                let p = start + i*0x38
                records.append(ContentRecord(hash: data.subdata(in: p..<(p+0x20)), id: data.subdata(in: (p+0x20)..<(p+0x30)).hex, size: try data.number(p+0x30,6), type: data[p+0x36]))
            }
            var title = TitleContents(id: id, owner: owner, role: role, revision: revision, records: records, name: nil, displayVersion: nil)
            if let record = records.first(where: { $0.type == 3 }), let controlNCA = ncas.first(where: { Self.restoredName($0.entry.name).lowercased() == record.id + ".nca" }) {
                guard controlNCA.declaredSize <= 64*1024*1024 else { throw PatchError("The game-information archive is unusually large.") }
                let controls = dir.appendingPathComponent("control"); try fm.createDirectory(at: controls, withIntermediateDirectories: false)
                let source = dir.appendingPathComponent("control.nca")
                do {
                    try archive.extract(controlNCA.entry, to: source, control: control) { _ in }
                    _ = try patcher.run(patcher.arguments(titles: titleFile) + ["--romfsdir=\(controls.path)", source.path], working: dir, allowUnsigned: true)
                    let values = try Self.titleStrings(Data(contentsOf: controls.appendingPathComponent("control.nacp")))
                    title.name = values.0; title.displayVersion = values.1
                } catch { try control.check(); notes.append("Some title information couldn’t be read. Content checks are still available.") }
            }
            titles.append(title)
        }
        return FileInspection(url: url, format: format, bytes: layout.fileSize, entries: archive.entries.count, archive: archive, ncas: ncas, titles: titles.sorted { $0.id < $1.id }, note: notes.first)
    }
    func verify(_ info: FileInspection) throws -> VerificationResult {
        guard patcher != nil, !info.titles.isEmpty else { throw PatchError("Choose your key file so the game’s contents can be checked.") }
        var expected: [String: ContentRecord] = [:], notes: [String] = []
        for record in info.titles.flatMap(\.records) {
            if let existing = expected[record.id], existing.hash != record.hash || existing.size != record.size { throw PatchError("The contents lists disagree about a stored item.") }
            expected[record.id] = record
        }
        guard !expected.isEmpty else { throw PatchError("This file has no game content to check.") }
        let byName = Dictionary(uniqueKeysWithValues: info.ncas.map { (Self.restoredName($0.entry.name).lowercased(), $0) })
        var checked = 0, total: UInt64 = 0
        for (index, record) in expected.values.sorted(by: { $0.id < $1.id }).enumerated() {
            try control.check()
            guard let nca = byName[record.id + ".nca"] else {
                if record.type == 6 { notes.append("Optional download fragments are not included."); continue }
                throw PatchError("The game file is missing content listed in its contents table.")
            }
            guard nca.declaredSize == record.size else { throw PatchError("A stored item has a different size from the game’s contents list.") }
            event("Checking content \(index+1) of \(expected.count)", Double(index)/Double(expected.count))
            let progress: (Double) -> Void = { self.event("Checking content \(index+1) of \(expected.count)", (Double(index)+$0)/Double(expected.count)) }
            let hash: Data
            if nca.entry.name.lowercased().hasSuffix(".ncz") {
                hash = try CompressedContent(archive: info.url, entry: nca.entry).digest(control: control, progress: progress)
            } else { hash = try Self.hash(info.url, offset: nca.entry.offset, size: nca.entry.size, control: control, progress: progress) }
            guard hash == record.hash else { throw PatchError("A stored item failed its content check. The game file may be damaged or incomplete.") }
            checked += 1; total += record.size
        }
        guard checked > 0 else { throw PatchError("No complete game content was available to check. This file may contain only download fragments.") }
        // Check metadata file identities as well as their internal hash trees.
        for metadata in info.ncas where metadata.contentType == 1 {
            let stem = metadata.entry.name.components(separatedBy: ".")[0].lowercased()
            if stem.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil {
                let hash = metadata.entry.name.lowercased().hasSuffix(".ncz") ? try CompressedContent(archive: info.url, entry: metadata.entry).digest(control: control, progress: { _ in }) : try Self.hash(info.url, offset: metadata.entry.offset, size: metadata.entry.size, control: control)
                guard hash.hex.hasPrefix(stem) else { throw PatchError("The game’s contents-list archive failed its file-identity check.") }
            }
        }
        let extra = info.ncas.filter { nca in nca.contentType != 1 && !expected.keys.contains(Self.restoredName(nca.entry.name).components(separatedBy: ".")[0].lowercased()) }.count
        if extra > 0 { notes.append("\(extra) additional content items aren’t referenced by a contents list and weren’t verified.") }
        return VerificationResult(checked: checked, bytes: total, notes: Array(Set(notes)).sorted())
    }
    func convert(_ input: URL, folder: URL) throws -> URL {
        let archive = try PFSArchive(input)
        let layout = try ContainerLayout(input)
        guard layout.isCartridge || archive.entries.contains(where: { $0.name.lowercased().hasSuffix(".ncz") }) else {
            throw PatchError("This is already a standard NSP file. No conversion is needed. Use Check Files to inspect it.")
        }
        let output = folder.appendingPathComponent(input.deletingPathExtension().lastPathComponent + " [Converted].nsp")
        guard !FileManager.default.fileExists(atPath: output.path) else { throw PatchError("A converted file with this name already exists. Choose a different save folder.") }
        let size = try archive.entries.reduce(UInt64(0)) { sum, entry in
            sum + (entry.name.lowercased().hasSuffix(".ncz") ? try CompressedContent(archive: input, entry: entry).expandedSize : entry.size)
        }
        try Self.requireSpace(folder, size*2 + 32*1024*1024)
        let fm = FileManager.default, temp = try PatchEngine.privateDirectory(in: folder)
        defer { try? fm.removeItem(at: temp) }
        var files: [URL] = []
        for (i, entry) in archive.entries.enumerated() {
            let file = temp.appendingPathComponent(Self.restoredName(entry.name))
            guard !files.contains(where: { $0.lastPathComponent.lowercased() == file.lastPathComponent.lowercased() }) else { throw PatchError("Two stored items would have the same output name.") }
            try archive.extract(entry, to: file, control: control) { self.event("Preparing a standard game file", (Double(i)+$0)/Double(archive.entries.count)*0.6) }
            files.append(file)
        }
        try PatchEngine.pack(files, to: output, control: control) { self.event("Saving and checking the new file", 0.6+$0*0.4) }
        return output
    }
    func combine(_ inputs: [URL], folder: URL) throws -> URL {
        guard inputs.count >= 2 else { throw PatchError("Add the original game and at least one update or add-on pack.") }
        let infos = try inputs.map(inspect)
        let titles = infos.flatMap(\.titles), games = titles.filter { $0.role == .game }
        guard games.count == 1, let game = games.first, titles.allSatisfy({ $0.owner == game.id && $0.role != .other }) else { throw PatchError("Choose the original game and matching updates or add-on packs for one game.") }
        guard titles.filter({ $0.role == .update }).count <= 1, Set(titles.map(\.id)).count == titles.count else { throw PatchError("More than one version of the same content was added. Remove the extra update or add-on pack.") }
        let base = infos.first { $0.titles.contains { $0.role == .game } }!.url.deletingPathExtension().lastPathComponent
        let output = folder.appendingPathComponent(base + " [Combined].nsp")
        guard !FileManager.default.fileExists(atPath: output.path) else { throw PatchError("A combined file with this name already exists. Choose a different save folder.") }
        for info in infos { _ = try verify(info) }
        let bytes = infos.flatMap(\.ncas).reduce(UInt64(0)) { $0 + $1.declaredSize }
        try Self.requireSpace(folder, bytes*2 + 32*1024*1024)
        let fm = FileManager.default, temp = try PatchEngine.privateDirectory(in: folder)
        defer { try? fm.removeItem(at: temp) }
        var files: [String: URL] = [:]
        for (i, info) in infos.enumerated() {
            for entry in info.archive.entries {
                let name = Self.restoredName(entry.name)
                if let existing = files[name.lowercased()] {
                    let duplicate = temp.appendingPathComponent("duplicate-"+UUID().uuidString)
                    try info.archive.extract(entry, to: duplicate, control: control) { _ in }
                    guard try Self.hash(existing, control: control) == Self.hash(duplicate, control: control) else { throw PatchError("Two files contain different data with the same name.") }
                    try fm.removeItem(at: duplicate); continue
                }
                let file = temp.appendingPathComponent(name)
                try info.archive.extract(entry, to: file, control: control) { self.event("Bringing game content together", (Double(i)+$0)/Double(infos.count)*0.7) }
                files[name.lowercased()] = file
            }
        }
        try PatchEngine.pack(files.values.sorted { $0.lastPathComponent < $1.lastPathComponent }, to: output, control: control) { self.event("Saving and checking the combined file", 0.7+$0*0.3) }
        return output
    }
}
