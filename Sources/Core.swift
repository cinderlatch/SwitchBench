import Foundation
#if !os(Windows)
import CryptoKit
#endif

struct PatchError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

final class WorkControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var process: Process?
    func cancel() {
        lock.lock(); stopped = true; let p = process; lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }
    func check() throws {
        lock.lock(); let flag = stopped; lock.unlock()
        if flag { throw PatchError("Cancelled. Original files were left untouched.") }
    }
    func setProcess(_ p: Process?) throws {
        lock.lock(); process = p; let flag = stopped; lock.unlock()
        if flag { if let p, p.isRunning { p.terminate() }; throw PatchError("Cancelled.") }
    }
}

extension Data {
    func number(_ offset: Int, _ count: Int) throws -> UInt64 {
        guard offset >= 0, count > 0, count <= 8, offset <= self.count - count else {
            throw PatchError("Truncated binary data.")
        }
        return (0..<count).reduce(0) { $0 | UInt64(self[offset + $1]) << ($1 * 8) }
    }
    mutating func appendLE(_ value: UInt64, bytes: Int) {
        for index in 0..<bytes { append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
    }
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

struct PFSEntry: Equatable {
    let name: String
    let offset: UInt64
    let size: UInt64
}

struct PFSArchive {
    let url: URL
    let entries: [PFSEntry]
    init(_ url: URL) throws {
        let layout = try ContainerLayout(url)
        self.url = url; self.entries = layout.entries
    }
    func read(_ entry: PFSEntry, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        try handle.seek(toOffset: entry.offset)
        let length = Int(min(entry.size, UInt64(limit)))
        let data = try handle.read(upToCount: length) ?? Data()
        guard data.count == length else { throw PatchError("An input changed or was truncated while reading.") }
        return data
    }
    func extract(_ entry: PFSEntry, to target: URL, control: WorkControl, progress: (Double) -> Void) throws {
        if entry.name.lowercased().hasSuffix(".ncz") {
            try CompressedContent(archive: url, entry: entry).extract(to: target, control: control, progress: progress)
            return
        }
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        guard !FileManager.default.fileExists(atPath:target.path), FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw PatchError("The destination already exists or cannot be created.") }
        var finished = false
        defer { if !finished { try? FileManager.default.removeItem(at:target) } }
        let output = try FileHandle(forWritingTo: target); defer { try? output.close() }
        try input.seek(toOffset: entry.offset)
        var remaining = entry.size
        while remaining > 0 {
            try autoreleasepool {
                try control.check()
                let length = Int(min(remaining, 4 * 1024 * 1024))
                let data = try input.read(upToCount: length) ?? Data()
                guard data.count == length else { throw PatchError("The input became incomplete while reading.") }
                try output.write(contentsOf: data); remaining -= UInt64(length)
                progress(entry.size == 0 ? 1 : Double(entry.size - remaining) / Double(entry.size))
            }
        }
        try output.synchronize(); try control.check(); finished = true
    }
}

struct NCAInfo {
    let entry: PFSEntry
    let contentType: Int
    let titleID: UInt64
    let rightsID: String
    let declaredSize: UInt64
    init(entry: PFSEntry, contentType: Int, titleID: UInt64, rightsID: String, declaredSize: UInt64? = nil) {
        self.entry = entry; self.contentType = contentType; self.titleID = titleID; self.rightsID = rightsID; self.declaredSize = declaredSize ?? entry.size
    }
}
struct InputPackage: Identifiable {
    let id = UUID()
    let url: URL
    let archive: PFSArchive
    let ncas: [NCAInfo]
    let program: NCAInfo
    var metadataID: UInt64 { ncas.first(where: { $0.contentType == 1 })!.titleID }
    var baseID: UInt64 { metadataID & ~UInt64(0x800) }
    var isUpdate: Bool { metadataID & 0x800 != 0 }
    var titleText: String { String(format: "%016llX", metadataID) }
}
struct PatchJob: Identifiable {
    var id: UInt64 { base.baseID }
    let base: InputPackage
    let update: InputPackage
    var name: String { base.url.deletingPathExtension().lastPathComponent }
}

struct HelperUnavailableError: LocalizedError {
    let url: URL
    var errorDescription: String? {
        "SwitchBench's local helper \(url.lastPathComponent) is unavailable. Quit and reopen the updated app before retrying. No completed output was overwritten."
    }
}

/// Keep executable resources independent of the app's original location for the entire session.
final class HelperSession: @unchecked Sendable {
    #if os(Windows)
    static let executableSuffix = ".exe"
    #else
    static let executableSuffix = ""
    #endif
    let directory: URL
    let executable: URL
    let packer: URL
    init(executable source: URL, packer sourcePacker: URL? = nil, parent: URL = FileManager.default.temporaryDirectory) throws {
        let fm = FileManager.default
        let sources = [source, sourcePacker ?? source.deletingLastPathComponent().appendingPathComponent("hacpack" + HelperSession.executableSuffix)]
        for file in sources where !fm.isExecutableFile(atPath: file.path) { throw HelperUnavailableError(url: file) }
        let directory = try PatchEngine.privateDirectory(in: parent)
        do {
            for (index, file) in sources.enumerated() {
                let target = directory.appendingPathComponent((index == 0 ? "hactool" : "hacpack") + Self.executableSuffix)
                try fm.copyItem(at: file.resolvingSymlinksInPath(), to: target)
                #if !os(Windows)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path)
                #endif
                guard fm.isExecutableFile(atPath: target.path) else { throw HelperUnavailableError(url: target) }
            }
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
        self.directory = directory
        executable = directory.appendingPathComponent("hactool" + Self.executableSuffix)
        packer = directory.appendingPathComponent("hacpack" + HelperSession.executableSuffix)
    }
    func validate() throws {
        for file in [executable, packer] where !FileManager.default.isExecutableFile(atPath: file.path) { throw HelperUnavailableError(url: file) }
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}

final class BatchReport {
    let url: URL
    init(folder: URL) throws {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        url = folder.appendingPathComponent("SwitchBench Batch \(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6)).log")
        guard FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
            throw PatchError("Cannot create a batch report in the output folder. Check that the folder is writable.")
        }
    }
    func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((PatchEngine.scrub(text) + "\n").utf8))
        try handle.synchronize()
    }
}

final class PatchEngine: @unchecked Sendable {
    let executable: URL
    let keys: URL
    let packer: URL
    let extraTitleKeys: URL?
    let control: WorkControl
    let event: (String, Double?) -> Void
    init(executable: URL, keys: URL, extraTitleKeys: URL? = nil, packer: URL? = nil, control: WorkControl, event: @escaping (String, Double?) -> Void) {
        self.executable = executable; self.keys = keys; self.packer = packer ?? executable.deletingLastPathComponent().appendingPathComponent("hacpack" + HelperSession.executableSuffix); self.extraTitleKeys = extraTitleKeys; self.control = control; self.event = event
    }
    static func privateDirectory(in parent: URL) throws -> URL {
        let url = parent.appendingPathComponent(".switchpatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }
    static func scrub(_ text: String) -> String {
        text.replacingOccurrences(of: "(?i)[0-9a-f]{32,}", with: "[redacted]", options: .regularExpression)
    }
    func run(_ args: [String], working: URL, tool: URL? = nil, allowUnsigned: Bool = false) throws -> String {
        try control.check()
        let selectedTool = tool ?? executable
        guard FileManager.default.isExecutableFile(atPath: selectedTool.path) else { throw HelperUnavailableError(url: selectedTool) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: working.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PatchError("The temporary working folder disappeared. Restart this batch.")
        }
        let process = Process(), pipe = Pipe()
        process.executableURL = selectedTool
        #if os(Windows)
        process.arguments = args.map { argument in
            let components = argument.hasPrefix("--") ? argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false) : [argument[...]]
            let value = String(components.last ?? "")
            let drive = value.utf8.dropFirst(value.hasPrefix("/") ? 1 : 0).dropFirst().first == 58
            guard drive || value.hasPrefix("//") || value.hasPrefix("\\\\") else { return argument }
            return (components.count == 2 ? String(components[0]) + "=" : "") + windowsPath(value)
        }
        #else
        process.arguments = args
        #endif
        process.currentDirectoryURL = working
        process.standardOutput = pipe; process.standardError = pipe
        do { try process.run() } catch {
            if !FileManager.default.isExecutableFile(atPath: selectedTool.path) { throw HelperUnavailableError(url: selectedTool) }
            throw error
        }
        do { try control.setProcess(process) } catch { process.waitUntilExit(); throw error }
        defer { try? control.setProcess(nil) }
        // Drain while running so verbose output cannot deadlock the child.
        var tail = Data()
        while true {
            let finished = autoreleasepool { () -> Bool in
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { return true }
                tail.append(chunk)
                if tail.count > 256 * 1024 { tail = Data(tail.suffix(128 * 1024)) }
                return false
            }
            if finished { break }
        }
        process.waitUntilExit(); try control.check()
        let rawOutput = String(decoding: tail, as: UTF8.self)
        let output = Self.scrub(rawOutput)
        guard process.terminationStatus == 0 else {
            let detail: String
            if output.localizedCaseInsensitiveContains("BKTR") {
                detail = "The update’s patch data could not be read or verified. It may be damaged or use an unsupported layout."
            } else {
                detail = "The processing helper failed. The details below may identify an input, key, or format problem."
            }
            throw PatchError("\(detail)\n\(output.suffix(1800))")
        }
        // Upstream sometimes reports corrupt input but returns success.
        let errors = ["Invalid NCA header", "section seems to be corrupted", "is corrupted!", "Failed to", "Unable to match rights id", "Base NCA Title ID doesn't match", "(FAIL)"]
        let checkedOutput = allowUnsigned ? output.components(separatedBy: .newlines).filter {
            !$0.contains("Signature (FAIL)") && !$0.contains("Signature Key (FAIL)")
        }.joined(separator: "\n") : output
        if errors.contains(where: { checkedOutput.localizedCaseInsensitiveContains($0) }) {
            throw PatchError("The extraction engine could not read or verify this content. Check the keys and input files.\n\(output.suffix(1800))")
        }
        return args.first == "--switchpatch-header" ? rawOutput : output
    }
    static func productionKeyText(_ data: Data) throws -> Data {
        guard data.count <= 16 * 1024 * 1024 else {
            throw PatchError("The selected keys file must be smaller than 16 MB.")
        }
        let utf8 = String(data: data, encoding: .utf8)
        // Saved pages may contain non-UTF-8 decorative text; key assignments remain ASCII.
        let text = utf8 ?? String(decoding: data, as: UTF8.self)
        let html = text.prefix(2048).range(of: "(?i)<!doctype html|<html", options: .regularExpression) != nil
        if !html {
            guard utf8 != nil else { throw PatchError("The selected keyset must be UTF-8 text.") }
            guard !text.contains("<html"), !text.contains("<!DOCTYPE"),
                  text.range(of: "(?m)^\\s*[a-z][a-z0-9_]+\\s*=\\s*[0-9a-fA-F]{32,}\\s*$", options: .regularExpression) != nil else {
                throw PatchError("No key assignments found. Select a plain-text prod.keys file.")
            }
            return data
        }
        let pattern = try NSRegularExpression(pattern: "\\b([a-z][a-z0-9_]{2,64})\\s*=\\s*([0-9a-fA-F]{32,512})\\b")
        var found: [String: String] = [:]
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let kr = Range(match.range(at: 1), in: text), let vr = Range(match.range(at: 2), in: text) else { continue }
            let name = String(text[kr]), value = text[vr].lowercased()
            guard value.count % 2 == 0 else { continue }
            if let previous = found[name], previous != value { throw PatchError("The saved HTML page contains conflicting key values. Select the original plain-text keyset.") }
            found[name] = value
        }
        guard found["header_key"]?.count == 64 else {
            throw PatchError("This keys file is an HTML page, and no complete embedded keyset could be recovered. Select a plain-text prod.keys file.")
        }
        return Data(found.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)\n" }.joined().utf8)
    }
    func prepareProductionKeys(in folder: URL) throws -> URL {
        let text = try Self.productionKeyText(Data(contentsOf: keys))
        let target = folder.appendingPathComponent("prod.keys")
        guard FileManager.default.createFile(atPath: target.path, contents: text, attributes: [.posixPermissions: 0o600]) else { throw PatchError("Cannot create a private temporary keyset.") }
        return target
    }
    func inspectContents(_ url: URL) throws -> (PFSArchive, [NCAInfo]) {
        try control.check()
        guard ["nsp", "xci", "nsz", "xcz"].contains(url.pathExtension.lowercased()) else { throw PatchError("Choose an NSP, XCI, NSZ or XCZ game file.") }
        let archive = try PFSArchive(url)
        let temp = try Self.privateDirectory(in: FileManager.default.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: temp) }
        let normalizedKeys = try prepareProductionKeys(in: temp)
        let probe = temp.appendingPathComponent("header.bin")
        var infos: [NCAInfo] = []
        for entry in archive.entries where ["nca", "ncz"].contains(URL(fileURLWithPath: entry.name).pathExtension.lowercased()) {
            try control.check()
            guard entry.size >= 0xC00 else { throw PatchError("An NCA header is truncated.") }
            try archive.read(entry, limit: 0xC00).write(to: probe)
            let output = try run(["--switchpatch-header", normalizedKeys.path, probe.path], working: temp)
            guard let line = output.components(separatedBy: .newlines).first(where: { $0.hasPrefix("SWITCHPATCH ") }) else {
                throw PatchError("Could not decrypt an NCA header. Select the correct prod.keys.")
            }
            let parts = line.split(separator: " ")
            guard parts.count == 5, let type = Int(parts[1]), let title = UInt64(parts[2], radix: 16), let declared = UInt64(parts[3]), declared <= 1 << 40,
                  declared == (entry.name.lowercased().hasSuffix(".ncz") ? try CompressedContent(archive: url, entry: entry).expandedSize : entry.size) else {
                throw PatchError("An NCA header is invalid, or its declared size differs from the input.")
            }
            infos.append(NCAInfo(entry: entry, contentType: type, titleID: title, rightsID: String(parts[4]), declaredSize: declared))
        }
        return (archive, infos)
    }
    func inspect(_ url: URL) throws -> InputPackage {
        let (archive, infos) = try inspectContents(url)
        let programs = infos.filter { $0.contentType == 0 }
        guard programs.count == 1 else { throw PatchError("\(url.lastPathComponent): expected one program, found \(programs.count). DLC, multi-program and already-merged packages are unsupported.") }
        let metadata = infos.filter { $0.contentType == 1 }
        guard metadata.count == 1 else { throw PatchError("Expected one content-metadata archive. Merged or incomplete packages are unsupported.") }
        guard metadata[0].titleID & ~UInt64(0x800) == programs[0].titleID & ~UInt64(0x800) else {
            throw PatchError("Program and content metadata refer to different games.")
        }
        return InputPackage(url: url, archive: archive, ncas: infos, program: programs[0])
    }
    func arguments(titles: URL) -> [String] {
        ["-y", "-k", titles.deletingLastPathComponent().appendingPathComponent("prod.keys").path, "--switchpatch-titlekeys", titles.path, "--suppresskeys", "--disablekeywarns"]
    }
    func titleKeys(for job: PatchJob, at target: URL) throws {
        try titleKeys(archives: [job.base.archive, job.update.archive], ncas: job.base.ncas + job.update.ncas, at: target, requireContentKeys: true)
    }
    func titleKeys(archives: [PFSArchive], ncas: [NCAInfo], at target: URL, requireContentKeys: Bool = false) throws {
        var keys: [String: String] = [:]
        if let extraTitleKeys {
            let text = try String(contentsOf: extraTitleKeys, encoding: .utf8)
            for line in text.components(separatedBy: .newlines) {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                if parts.count == 2, parts[0].range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
                   parts[1].range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil { keys[parts[0]] = parts[1] }
            }
        }
        for archive in archives {
            for ticket in archive.entries where ticket.name.lowercased().hasSuffix(".tik") {
                let data = try archive.read(ticket, limit: 0x1000)
                guard data.count >= 4 else { throw PatchError("A ticket is truncated.") }
                let signature = UInt32(try data.number(0, 4))
                let start: Int
                switch signature {
                case 0x10000, 0x10003: start = 0x240
                case 0x10001, 0x10004: start = 0x140
                case 0x10002, 0x10005: start = 0x80
                case 0x10006: start = 0x40
                default: throw PatchError("Unsupported ticket signature format.")
                }
                guard data.count >= start + 0x170 else { throw PatchError("A ticket is truncated.") }
                if data[start + 0x141] == 0 {
                    let rights = data.subdata(in: (start + 0x160)..<(start + 0x170)).hex
                    let value = data.subdata(in: (start + 0x40)..<(start + 0x50)).hex
                    if let existing = keys[rights], existing != value { throw PatchError("Conflicting title keys in the selected inputs.") }
                    keys[rights] = value
                }
            }
        }
        for nca in ncas where requireContentKeys && [0, 2].contains(nca.contentType) {
            if nca.rightsID != String(repeating: "0", count: 32), keys[nca.rightsID] == nil {
                throw PatchError("A required title key is missing. prod.keys alone cannot decrypt this ticket. Select your matching title.keys in Setup.")
            }
        }
        let data = Data(keys.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)\n" }.joined().utf8)
        guard FileManager.default.createFile(atPath: target.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw PatchError("Cannot create private temporary title keys.") }
    }
    static func outputFilename(baseName: String, controlData: Data?) -> String {
        var name = baseName.replacingOccurrences(of: "(?i)\\[v[0-9]+(?:[._][0-9]+)*\\]", with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        var label = "Patched"
        if let data = controlData, data.count >= 0x3070,
           let version = String(data: Data(data[0x3060..<0x3070].prefix(while: { $0 != 0 })), encoding: .utf8),
           version.range(of: "^[a-zA-Z0-9._-]{1,16}$", options: .regularExpression) != nil {
            label += " \(version)"
        }
        return "\(name) [\(label)].nsp"
    }
    func patch(_ job: PatchJob, outputFolder: URL) throws -> URL {
        try control.check()
        guard job.base.baseID == job.update.baseID, !job.base.isUpdate, job.update.isUpdate else { throw PatchError("The base game and update have different internal title IDs.") }
        // Reinspect inputs immediately before work, rather than trusting an earlier import.
        let freshBase = try inspect(job.base.url), freshUpdate = try inspect(job.update.url)
        guard freshBase.program.entry == job.base.program.entry, freshUpdate.program.entry == job.update.program.entry,
              freshBase.metadataID == job.base.metadataID, freshUpdate.metadataID == job.update.metadataID else { throw PatchError("An input changed since it was added. Remove and add it again.") }
        let current = PatchJob(base: freshBase, update: freshUpdate)
        let fm = FileManager.default
        let baseSize = current.base.program.declaredSize, updateSize = current.update.program.declaredSize
        let estimate = (baseSize + updateSize) * 4 + 512 * 1024 * 1024
        let attributes = try fm.attributesOfFileSystem(forPath: outputFolder.path)
        if let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value, free < estimate {
            throw PatchError("Allow approximately \(ByteCountFormatter.string(fromByteCount: Int64(estimate), countStyle: .file)) free for extraction and output.")
        }
        let temp = try Self.privateDirectory(in: outputFolder)
        defer { try? fm.removeItem(at: temp) }
        let keyFolder = try Self.privateDirectory(in: fm.temporaryDirectory)
        defer { try? fm.removeItem(at: keyFolder) }
        let titleFile = keyFolder.appendingPathComponent("title.keys")
        _ = try prepareProductionKeys(in: keyFolder)
        try titleKeys(for: current, at: titleFile)
        let baseNCA = temp.appendingPathComponent("base.nca"), updateNCA = temp.appendingPathComponent("update.nca")
        event("Reading base game", 0)
        try current.base.archive.extract(current.base.program.entry, to: baseNCA, control: control) { event("Reading base game", $0 * 0.12) }
        try current.update.archive.extract(current.update.program.entry, to: updateNCA, control: control) { event("Reading update", 0.12 + $0 * 0.08) }
        let payload = temp.appendingPathComponent("payload")
        try fm.createDirectory(at: payload, withIntermediateDirectories: false)
        let romfs = payload.appendingPathComponent("game.romfs")
        event("Applying update to game data — this can take several minutes", nil)
        let report = try run(arguments(titles: titleFile) + ["--basenca=\(baseNCA.path)", "--exefsdir=\(payload.path)", "--romfs=\(romfs.path)", updateNCA.path], working: temp)
        guard report.contains("Patch RomFS"), fm.fileExists(atPath: romfs.path) else {
            throw PatchError("This update did not produce a patched RomFS. Its patch format is unsupported.")
        }
        for (name, magic) in [("main", "NSO0"), ("main.npdm", "META")] {
            let file = payload.appendingPathComponent(name)
            guard fm.fileExists(atPath: file.path) else { throw PatchError("The update did not produce \(name). This executable layout is unsupported.") }
            let h = try FileHandle(forReadingFrom: file); defer { try? h.close() }
            guard try h.read(upToCount: 4) == Data(magic.utf8) else { throw PatchError("Invalid patched executable metadata. Check the input and keys.") }
        }
        let npdm = try Data(contentsOf: payload.appendingPathComponent("main.npdm"))
        let aciOffset = Int(try npdm.number(0x70, 4))
        guard aciOffset >= 0x80, aciOffset <= npdm.count - 0x20,
              npdm.subdata(in: aciOffset..<(aciOffset + 4)) == Data("ACI0".utf8),
              try npdm.number(aciOffset + 0x10, 8) == current.base.baseID else {
            throw PatchError("The patched executable has an unexpected program ID or invalid permissions metadata.")
        }
        let rh = try FileHandle(forReadingFrom: romfs)
        let first = try rh.read(upToCount: 8) ?? Data(); try rh.close()
        guard try first.number(0, 8) == 0x50 else { throw PatchError("The patched RomFS is invalid.") }
        // A normal NSP must contain control and content metadata, as well as its program NCA.
        let controlPackage = current.update.ncas.contains(where: { $0.contentType == 2 }) ? current.update : current.base
        let controls = controlPackage.ncas.filter { $0.contentType == 2 && ($0.titleID & ~UInt64(0x800)) == current.base.baseID }
        guard controls.count == 1 else { throw PatchError("A single matching control archive is required to build an Eden-compatible NSP.") }
        event("Reading game metadata and icons", nil)
        let controlNCA = temp.appendingPathComponent("control.nca"), controlDir = temp.appendingPathComponent("control")
        try controlPackage.archive.extract(controls[0].entry, to: controlNCA, control: control) { _ in }
        try fm.createDirectory(at: controlDir, withIntermediateDirectories: false)
        _ = try run(arguments(titles: titleFile) + ["--romfsdir=\(controlDir.path)", controlNCA.path], working: temp)
        for file in try fm.contentsOfDirectory(at: controlDir, includingPropertiesForKeys: nil) where file.lastPathComponent == "control.nacp" || (file.lastPathComponent.hasPrefix("icon_") && file.pathExtension == "dat") {
            try fm.copyItem(at: file, to: payload.appendingPathComponent(file.lastPathComponent))
        }
        let version = try contentVersion(of: current.update, in: temp, titles: titleFile)
        // Reclaim large encrypted copies before creating the rebuilt archives.
        try fm.removeItem(at: baseNCA); try fm.removeItem(at: updateNCA)
        let output = try rebuild(payload: payload, baseID: current.base.baseID, version: version, baseName: job.name, working: temp, outputFolder: outputFolder, keyFolder: keyFolder)
        return output
    }
    func contentVersion(of package: InputPackage, in working: URL, titles: URL) throws -> UInt32 {
        let metadata = package.ncas.filter { $0.contentType == 1 }
        guard metadata.count == 1, metadata[0].entry.size <= 32 * 1024 * 1024 else { throw PatchError("Missing or oversized content metadata.") }
        let source = working.appendingPathComponent("source-meta.nca"), dir = working.appendingPathComponent("source-meta")
        try package.archive.extract(metadata[0].entry, to: source, control: control) { _ in }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        _ = try run(arguments(titles: titles) + ["--section0dir=\(dir.path)", source.path], working: working)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "cnmt" }
        guard files.count == 1 else { throw PatchError("Expected a single content-metadata table.") }
        let data = try Data(contentsOf: files[0])
        guard data.count >= 0x20, try data.number(0, 8) == package.metadataID,
              data[12] == (package.isUpdate ? 0x81 : 0x80) else { throw PatchError("Content metadata does not match the selected package.") }
        return UInt32(try data.number(8, 4))
    }
    /// Package materialized game files as normal program, control, and application metadata NCAs.
    func rebuild(payload: URL, baseID: UInt64, version: UInt32, baseName: String, working: URL, outputFolder: URL, keyFolder: URL? = nil) throws -> URL {
        let keyFolder = keyFolder ?? working
        let fm = FileManager.default, titleFile = keyFolder.appendingPathComponent("title.keys")
        let exefs = working.appendingPathComponent("rebuilt-exefs"), controlDir = working.appendingPathComponent("rebuilt-control"), ncas = working.appendingPathComponent("rebuilt-ncas")
        let packTemp = working.appendingPathComponent("packer-temp"), backup = working.appendingPathComponent("packer-backup")
        for dir in [exefs, controlDir, ncas, packTemp, backup] { try fm.createDirectory(at: dir, withIntermediateDirectories: false) }
        let controlData = try Data(contentsOf: payload.appendingPathComponent("control.nacp"))
        guard controlData.count >= 0x3070 else { throw PatchError("The game's control metadata is incomplete.") }
        let output = outputFolder.appendingPathComponent(Self.outputFilename(baseName: baseName, controlData: controlData))
        guard !fm.fileExists(atPath: output.path) else { throw PatchError("Output already exists: \(output.lastPathComponent). Choose a different output folder.") }
        let romfs = payload.appendingPathComponent("game.romfs")
        for file in try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil) {
            let name = file.lastPathComponent
            if name == "game.romfs" { continue }
            let target = name == "control.nacp" || name.hasPrefix("icon_") ? controlDir : exefs
            try fm.moveItem(at: file, to: target.appendingPathComponent(name))
        }
        let common = ["-k", keyFolder.appendingPathComponent("prod.keys").path, "--type", "nca", "--titleid", String(format: "%016llx", baseID), "--plaintext", "--outdir", ncas.path, "--tempdir", packTemp.path, "--backupdir", backup.path]
        event("Building normal game-content archive", nil)
        _ = try run(common + ["--ncatype", "program", "--noselfsignncasig2", "--exefsdir", exefs.path, "--romfsdir", romfs.path], working: working, tool: packer)
        func newNCA(excluding previous: Set<String>) throws -> URL {
            let files = try fm.contentsOfDirectory(at: ncas, includingPropertiesForKeys: nil).filter { $0.pathExtension == "nca" && !previous.contains($0.lastPathComponent) }
            guard files.count == 1 else { throw PatchError("The packer did not produce exactly one expected content archive.") }
            return files[0]
        }
        let program = try newNCA(excluding: [])
        event("Building game metadata and icon archive", nil)
        _ = try run(common + ["--ncatype", "control", "--romfsdir", controlDir.path], working: working, tool: packer)
        let controlNCA = try newNCA(excluding: [program.lastPathComponent])
        event("Building application content table", nil)
        _ = try run(common + ["--ncatype", "meta", "--titletype", "application", "--titleversion", String(format: "%08x", version), "--programnca", program.path, "--controlnca", controlNCA.path], working: working, tool: packer)
        let meta = try newNCA(excluding: [program.lastPathComponent, controlNCA.lastPathComponent])
        // Rebuilt files cannot carry Nintendo's signatures. Verify their content hashes independently.
        for file in [program, controlNCA, meta] {
            event("Verifying rebuilt content hashes", nil)
            _ = try run(arguments(titles: titleFile) + [file.path], working: working, allowUnsigned: true)
        }
        let files = try fm.contentsOfDirectory(at: ncas, includingPropertiesForKeys: nil).filter { $0.pathExtension == "nca" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard files.count == 3, files.contains(where: { $0.lastPathComponent.hasSuffix(".cnmt.nca") }) else { throw PatchError("The rebuilt NSP is missing its application metadata.") }
        event("Building compatible NSP", 0.65)
        try Self.pack(files, to: output, control: control) { value in self.event(value < 0.5 ? "Building compatible NSP" : "Verifying output bytes", 0.65 + value * 0.35) }
        return output
    }
    /// Write beside destination, verify every payload with SHA-256, then publish without overwriting.
    static func pack(_ files: [URL], to destination: URL, control: WorkControl, progress: (Double) -> Void) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw PatchError("Output already exists: \(destination.lastPathComponent). Choose another output folder or move that file.") }
        guard !files.isEmpty, files.count <= 100_000 else { throw PatchError("Invalid output file count.") }
        var sizes: [UInt64] = [], strings = Data(), table = Data(), offset: UInt64 = 0
        var seen = Set<String>()
        for file in files {
            let name = file.lastPathComponent
            guard seen.insert(name.lowercased()).inserted, !name.contains("/"), !name.contains("\\"), !name.isEmpty else { throw PatchError("Invalid output filename.") }
            let size = (try fm.attributesOfItem(atPath: file.path)[.size] as! NSNumber).uint64Value
            table.appendLE(offset, bytes: 8); table.appendLE(size, bytes: 8)
            table.appendLE(UInt64(strings.count), bytes: 4); table.appendLE(0, bytes: 4)
            strings.append(contentsOf: name.utf8); strings.append(0); sizes.append(size); offset += size
        }
        let padding = (16 - ((16 + table.count + strings.count) % 16)) % 16
        strings.append(Data(repeating: 0, count: padding))
        var header = Data("PFS0".utf8)
        header.appendLE(UInt64(files.count), bytes: 4); header.appendLE(UInt64(strings.count), bytes: 4); header.appendLE(0, bytes: 4)
        header.append(table); header.append(strings)
        let temp = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        guard fm.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw PatchError("Cannot create output file.") }
        defer { try? fm.removeItem(at: temp) }
        let output = try FileHandle(forWritingTo: temp); defer { try? output.close() }
        try output.write(contentsOf: header)
        var hashes: [SHA256.Digest] = [], processed: UInt64 = 0
        for (index, file) in files.enumerated() {
            let input = try FileHandle(forReadingFrom: file); defer { try? input.close() }
            var hasher = SHA256(), left = sizes[index]
            while left > 0 {
                try autoreleasepool {
                    try control.check()
                    let length = Int(min(left, 4 * 1024 * 1024)), data = try input.read(upToCount: Int(min(left, 4 * 1024 * 1024))) ?? Data()
                    guard data.count == length else { throw PatchError("A source file changed during packaging.") }
                    try output.write(contentsOf: data); hasher.update(data: data); left -= UInt64(length); processed += UInt64(length)
                    progress(Double(processed) / Double(max(1, offset)) * 0.5)
                }
            }
            hashes.append(hasher.finalize())
        }
        try output.synchronize(); try output.close()
        let check = try PFSArchive(temp), input = try FileHandle(forReadingFrom: temp); defer { try? input.close() }
        guard check.entries.map(\.name) == files.map(\.lastPathComponent), check.entries.map(\.size) == sizes else { throw PatchError("Output directory verification failed.") }
        for (index, entry) in check.entries.enumerated() {
            try input.seek(toOffset: entry.offset)
            var hasher = SHA256(), left = entry.size
            while left > 0 {
                try autoreleasepool {
                    try control.check()
                    let length = Int(min(left, 4 * 1024 * 1024)), data = try input.read(upToCount: Int(min(left, 4 * 1024 * 1024))) ?? Data()
                    guard data.count == length else { throw PatchError("Output verification failed: truncated file.") }
                    hasher.update(data: data); left -= UInt64(length); processed += UInt64(length)
                    progress(Double(processed) / Double(max(1, offset)) * 0.5)
                }
            }
            guard hasher.finalize() == hashes[index] else { throw PatchError("Output verification failed: checksum mismatch.") }
        }
        try input.close()
        try control.check()
        // A same-directory move publishes the verified file without requiring hard-link support.
        // FileManager refuses an existing destination, including one created during verification.
        #if os(Windows)
        try publishWindowsFile(temp, to: destination)
        #else
        try fm.moveItem(at: temp, to: destination)
        #endif
        progress(1)
    }
}
