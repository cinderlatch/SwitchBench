import Foundation
#if !os(Windows)
import CryptoKit
#endif

struct FileSpan { let url: URL; let offset: UInt64; let size: UInt64 }
struct JoinPlan { let name: String; let spans: [FileSpan]; let expectedHash: String?; var size: UInt64 { spans.reduce(0) { $0+$1.size } } }
struct SplitPart: Codable { let name: String; let size: UInt64; let sha256: String }
struct SplitManifest: Codable { let version: Int; let originalName: String; let size: UInt64; let sha256: String; let parts: [SplitPart] }
extension UtilityEngine {
    @discardableResult func copyChecked(_ spans: [FileSpan], to destination: URL, expected: String? = nil, validateContainer: Bool = false) throws -> String {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path), !spans.isEmpty else { throw PatchError("An output with this name already exists. Choose a different save folder.") }
        let total = spans.reduce(UInt64(0)) { $0 + $1.size }
        try Self.requireSpace(destination.deletingLastPathComponent(), total + 16*1024*1024)
        let temp = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        guard fm.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw PatchError("Couldn’t create the new file in this folder.") }
        defer { try? fm.removeItem(at: temp) }
        let out = try FileHandle(forWritingTo: temp); defer { try? out.close() }
        var hasher = SHA256(), processed: UInt64 = 0
        for span in spans {
            let input = try FileHandle(forReadingFrom: span.url); defer { try? input.close() }
            let size = try input.seekToEnd()
            guard span.offset <= size, span.size <= size-span.offset else { throw PatchError("An input file is incomplete.") }
            try input.seek(toOffset: span.offset); var left = span.size
            while left > 0 {
                try autoreleasepool {
                    try control.check(); let n = Int(min(left,4*1024*1024)), data = try input.read(upToCount: n) ?? Data()
                    guard data.count == n else { throw PatchError("An input file changed while being copied.") }
                    try out.write(contentsOf: data); hasher.update(data: data); left -= UInt64(n); processed += UInt64(n)
                    event("Saving the new file", Double(processed)/Double(max(1,total))*0.6)
                }
            }
        }
        try out.synchronize(); try out.close()
        let hash = Data(hasher.finalize()).hex
        guard expected == nil || expected == hash else { throw PatchError("The joined file doesn’t match its original checksum. A part may be damaged.") }
        let readback = try Self.hash(temp, control: control) { self.event("Checking the saved file",0.6+$0*0.4) }.hex
        guard readback == hash else { throw PatchError("The saved copy failed its readback check.") }
        if validateContainer { _ = try ContainerLayout(temp) }
        try control.check()
        #if os(Windows)
        try publishWindowsFile(temp, to: destination)
        #else
        try fm.moveItem(at: temp, to: destination)
        #endif
        return hash
    }
    func trim(_ input: URL, folder: URL) throws -> URL {
        let layout = try ContainerLayout(input)
        guard layout.isCartridge, !layout.entries.contains(where: { $0.name.lowercased().hasSuffix(".ncz") }) else { throw PatchError("Choose an uncompressed XCI file to remove unused space. XCZ files already use compression.") }
        guard layout.usedSize < layout.fileSize else { throw PatchError("This XCI file is already trimmed. No unused space can be removed.") }
        let output = folder.appendingPathComponent(input.deletingPathExtension().lastPathComponent+" [Trimmed].xci")
        try copyChecked([FileSpan(url: input, offset: 0, size: layout.usedSize)], to: output, validateContainer: true)
        return output
    }
    func split(_ input: URL, folder: URL, partSize: UInt64 = 0xFFFF0000) throws -> URL {
        let fm = FileManager.default, size = (try fm.attributesOfItem(atPath: input.path)[.size] as! NSNumber).uint64Value
        _ = try ContainerLayout(input)
        guard partSize > 0, size > partSize else { throw PatchError("This file already fits in a single part. Splitting isn’t needed.") }
        guard (1+(size-1)/partSize) <= 10_000 else { throw PatchError("This file would create too many parts.") }
        try Self.requireSpace(folder, size+32*1024*1024)
        let output = folder.appendingPathComponent(input.deletingPathExtension().lastPathComponent+" [Split]")
        guard !fm.fileExists(atPath: output.path) else { throw PatchError("A split folder with this name already exists. Choose another save folder.") }
        let temp = try PatchEngine.privateDirectory(in: folder); defer { try? fm.removeItem(at: temp) }
        let h = try FileHandle(forReadingFrom: input); defer { try? h.close() }
        var parts: [SplitPart] = [], fullHash = SHA256(), offset: UInt64 = 0
        while offset < size {
            try control.check()
            let length = min(partSize, size-offset), name = input.lastPathComponent+String(format: ".%02d", parts.count), url = temp.appendingPathComponent(name)
            guard fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw PatchError("Couldn’t save a file part.") }
            let out = try FileHandle(forWritingTo: url); defer { try? out.close() }
            var left = length, partHash = SHA256()
            while left > 0 {
                try autoreleasepool {
                    try control.check(); let n = Int(min(left,4*1024*1024)), data = try h.read(upToCount: n) ?? Data()
                    guard data.count == n else { throw PatchError("The original file changed while being split.") }
                    try out.write(contentsOf: data); fullHash.update(data: data); partHash.update(data: data); left -= UInt64(n)
                    event("Saving part \(parts.count+1) of \(1+(size-1)/partSize)",(Double(offset)+Double(length-left)*0.6)/Double(size))
                }
            }
            try out.synchronize(); try out.close()
            let digest = Data(partHash.finalize()).hex
            guard try Self.hash(url, control: control, progress: { self.event("Checking part \(parts.count+1) of \(1+(size-1)/partSize)",(Double(offset)+Double(length)*(0.6+$0*0.4))/Double(size)) }).hex == digest else { throw PatchError("A saved part failed its content check.") }
            parts.append(SplitPart(name: name, size: length, sha256: digest)); offset += length
        }
        let manifest = SplitManifest(version: 1, originalName: input.lastPathComponent, size: size, sha256: Data(fullHash.finalize()).hex, parts: parts)
        try JSONEncoder().encode(manifest).write(to: temp.appendingPathComponent("SwitchBench Parts.json"))
        try control.check()
        #if os(Windows)
        try publishWindowsFile(temp, to: output)
        #else
        try fm.moveItem(at: temp, to: output)
        #endif
        return output
    }
    func joinPlan(_ selected: URL, verifyParts: Bool = false) throws -> JoinPlan {
        try control.check()
        let fm = FileManager.default
        let isDirectory = (try? selected.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let parent = isDirectory ? selected : selected.deletingLastPathComponent()
        let currentManifest = parent.appendingPathComponent("SwitchBench Parts.json")
        let manifestURL = fm.fileExists(atPath:currentManifest.path) ? currentManifest : parent.appendingPathComponent("SwitchPatch Parts.json")
        var spans: [FileSpan] = [], expected: String?, name: String
        func validName(_ name: String) -> Bool {
            #if os(Windows)
            return windowsSafeName(name)
            #else
            return !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.unicodeScalars.contains { $0.value < 32 }
            #endif
        }
        if fm.fileExists(atPath: manifestURL.path) {
            let attr = try fm.attributesOfItem(atPath: manifestURL.path)
            guard (attr[.size] as! NSNumber).uint64Value <= 4*1024*1024 else { throw PatchError("The parts list is too large.") }
            let manifest = try JSONDecoder().decode(SplitManifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.version == 1, validName(manifest.originalName), ["nsp","xci","nsz","xcz"].contains(URL(fileURLWithPath: manifest.originalName).pathExtension.lowercased()),
                  !manifest.parts.isEmpty, manifest.parts.count <= 10_000, manifest.sha256.range(of: "^[0-9a-f]{64}$",options:.regularExpression) != nil else { throw PatchError("The file’s parts list is invalid.") }
            guard isDirectory || selected.lastPathComponent == manifestURL.lastPathComponent || manifest.parts.contains(where: { $0.name == selected.lastPathComponent }) else {
                throw PatchError("This folder contains a parts list for a different file. Choose its folder or one of the listed parts.")
            }
            var total: UInt64 = 0
            for (index, part) in manifest.parts.enumerated() {
                guard part.name == manifest.originalName+String(format:".%02d",index), part.sha256.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil,
                      part.size > 0, part.size <= manifest.size, part.size <= manifest.size-total else { throw PatchError("The parts list contains an invalid filename or size.") }
                let url = parent.appendingPathComponent(part.name)
                guard fm.fileExists(atPath: url.path), (try fm.attributesOfItem(atPath: url.path)[.size] as! NSNumber).uint64Value == part.size else { throw PatchError("Part \(index+1) is missing or incomplete. Put all parts in the same folder.") }
                if verifyParts { guard try Self.hash(url, control: control, progress: { self.event("Checking original parts",(Double(index)+$0)/Double(manifest.parts.count)*0.3) }).hex == part.sha256 else { throw PatchError("Part \(index+1) failed its checksum check. Copy that part again before joining.") } }
                spans.append(FileSpan(url:url,offset:0,size:part.size));total += part.size
            }
            guard total == manifest.size else { throw PatchError("Some file parts are missing.") }
            name = manifest.originalName; expected = manifest.sha256
        } else {
            guard !isDirectory else { throw PatchError("Choose the first split part, or a folder made by SwitchBench.") }
            let leaf = selected.lastPathComponent
            let pattern = "(?i)^(.*\\.(?:nsp|xci|nsz|xcz))\\.([0-9]{2,6})$|^(.*)\\.(ns|xc)([0-9]{1,6})$|^([0-9]{2,6})$"
            let regex = try NSRegularExpression(pattern:pattern)
            func groups(_ text: String) -> [String?]? {
                guard let m = regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else { return nil }
                return (1..<m.numberOfRanges).map { Range(m.range(at:$0),in:text).map { String(text[$0]) } }
            }
            guard let selectedGroups = groups(leaf) else { throw PatchError("Choose a split part such as .nsp.00, .ns0 or .xc0.") }
            let prefix = selectedGroups[0] ?? selectedGroups[2], family = selectedGroups[3]?.lowercased()
            var candidates: [Int:URL] = [:]
            for url in try fm.contentsOfDirectory(at:parent,includingPropertiesForKeys:nil,options:[.skipsHiddenFiles]) {
                guard let g = groups(url.lastPathComponent), g[0] == selectedGroups[0], g[2] == selectedGroups[2], g[3]?.lowercased() == family else { continue }
                let number = g[1] ?? g[4] ?? g[5]!
                guard let index = Int(number), candidates[index] == nil, index < 10_000 else { throw PatchError("The folder has duplicate or invalid part numbers.") }
                candidates[index] = url
            }
            guard !candidates.isEmpty else { throw PatchError("No split parts were found.") }
            for index in 0..<candidates.count {
                guard let url = candidates[index] else { throw PatchError("Part \(index+1) is missing. Put every part in the same folder.") }
                let size = (try fm.attributesOfItem(atPath:url.path)[.size] as! NSNumber).uint64Value
                guard size > 0 else { throw PatchError("A file part is empty.") }; spans.append(FileSpan(url:url,offset:0,size:size))
            }
            if let prefix { name = selectedGroups[0] != nil ? prefix : prefix + (family == "xc" ? ".xci" : ".nsp") }
            else {
                let h = try FileHandle(forReadingFrom:spans[0].url); defer { try? h.close() }
                let magic = try h.read(upToCount:0x104) ?? Data()
                name = parent.deletingPathExtension().lastPathComponent + (magic.prefix(4) == Data("PFS0".utf8) ? ".nsp" : ".xci")
            }
        }
        guard validName(name) else { throw PatchError("The original filename is invalid.") }
        return JoinPlan(name:name,spans:spans,expectedHash:expected)
    }
    func join(_ selected: URL, folder: URL) throws -> URL {
        let plan = try joinPlan(selected,verifyParts:true)
        let original = URL(fileURLWithPath:plan.name), output = folder.appendingPathComponent(original.deletingPathExtension().lastPathComponent+" [Joined]."+original.pathExtension)
        let writer = UtilityEngine(patcher:patcher,control:control) { stage,progress in self.event(stage,progress.map { 0.3+$0*0.7 }) }
        try writer.copyChecked(plan.spans,to:output,expected:plan.expectedHash,validateContainer:true)
        return output
    }
}
