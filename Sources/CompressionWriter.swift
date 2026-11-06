import Foundation
#if !os(Windows)
import CryptoKit
#endif

extension UtilityEngine {
    func compress(_ input: URL, folder: URL) throws -> URL {
        try control.check()
        let stamp = try FileStamp(input), layout = try ContainerLayout(input)
        guard ["nsp", "xci"].contains(input.pathExtension.lowercased()),
              !layout.entries.contains(where: { $0.name.lowercased().hasSuffix(".ncz") }) else {
            throw PatchError("Choose an uncompressed NSP or XCI file.")
        }
        guard let patcher else { throw TaskIssue(.keys, "Choose your prod.keys file to compress games.") }
        guard layout.fileSize <= 1 << 40 else { throw PatchError("This game file is too large to compress.") }
        try Self.requireSpace(folder, 2 * layout.fileSize + 32 * 1024 * 1024)
        let name = input.deletingPathExtension().lastPathComponent + " [Compressed]." + (layout.isCartridge ? "xcz" : "nsz")
        let destination = folder.appendingPathComponent(name)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw TaskIssue(.collision, "A file with this name already exists.") }
        let work = try PatchEngine.privateDirectory(in: folder)
        defer { try? fm.removeItem(at: work) }
        let keyWork = try PatchEngine.privateDirectory(in: fm.temporaryDirectory)
        defer { try? fm.removeItem(at: keyWork) }
        let keys = try patcher.prepareProductionKeys(in: keyWork)
        let titles = keyWork.appendingPathComponent("title.keys")
        let archive = try PFSArchive(input)
        try patcher.titleKeys(archives: [archive], ncas: [], at: titles)
        let probe = keyWork.appendingPathComponent("header.bin"), records = keyWork.appendingPathComponent("sections.bin")
        guard fm.createFile(atPath: records.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw PatchError("Couldn’t prepare the private compression workspace.")
        }

        var members: [ArchiveMember] = [], changed = false
        for (index, entry) in layout.entries.enumerated() {
            try control.check()
            let original = ArchiveMember(name: entry.name, spans: [FileSpan(url: input, offset: entry.offset, size: entry.size)])
            guard entry.name.lowercased().hasSuffix(".nca"), entry.size > 0x4000 else {
                members.append(original)
                continue
            }
            try archive.read(entry, limit: 0xC00).write(to: probe)
            let result = try patcher.run(["--switchbench-ncz", keys.path, titles.path, probe.path, records.path], working: keyWork)
            let status = result.components(separatedBy: .newlines).first { $0.hasPrefix("NCZ ") }
            switch status {
            case "NCZ SKIP":
                members.append(original)
                continue
            case "NCZ TITLE":
                throw TaskIssue(.extraKeys, "This game needs its matching title.keys file to compress.")
            case "NCZ HEADER", "NCZ KEYS":
                throw TaskIssue(.keys, "This game couldn’t be read with the selected prod.keys file. Choose the key file you use with your emulator.")
            default: break
            }
            guard status == "NCZ OK \(entry.size)" else { throw PatchError("The game contains an invalid content header.") }
            let sections = try CompressedContent.sections(from: Data(contentsOf: records), size: entry.size)
            let compressed = work.appendingPathComponent("content-\(index).ncz")
            if let size = try CompressedContent.encode(archive: input, entry: entry, sections: sections, to: compressed, control: control, progress: {
                self.event("Compressing and checking game data", 0.85 * (Double(index)+$0)/Double(layout.entries.count))
            }) {
                changed = true
                members.append(ArchiveMember(name: String(entry.name.dropLast()) + "z",
                                             spans: [FileSpan(url: compressed, offset: 0, size: size)]))
            } else {
                members.append(original)
            }
        }
        guard changed else { throw PatchError("This game has no supported content that would become smaller. No compressed copy was saved.") }
        let spans: [FileSpan]
        if let cartridge = layout.cartridge {
            spans = try compressedCartridge(input, cartridge: cartridge, members: members, work: work)
        } else {
            spans = try archiveSpans(members, headerURL: work.appendingPathComponent("pfs.bin"), hashed: false).spans
        }
        guard spans.reduce(UInt64(0), { $0 + $1.size }) < layout.fileSize else {
            throw PatchError("The compressed copy would not be smaller. No copy was saved.")
        }
        let staged = work.appendingPathComponent(name)
        let saver = UtilityEngine(patcher: nil, control: control) { stage, progress in
            self.event(stage, progress.map { 0.85 + 0.15 * $0 })
        }
        try saver.copyChecked(spans, to: staged, validateContainer: true)
        guard try FileStamp(input) == stamp else { throw PatchError("The original game changed while being compressed.") }
        try control.check()
        #if os(Windows)
        try publishWindowsFile(staged, to: destination)
        #else
        try fm.moveItem(at: staged, to: destination)
        #endif
        return destination
    }
}

private struct ArchiveMember {
    let name: String
    let spans: [FileSpan]
    var size: UInt64 { spans.reduce(0) { $0 + $1.size } }
}

private func readSpan(_ url: URL, offset: UInt64, count: Int) throws -> Data {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    try file.seek(toOffset: offset)
    let data = try file.read(upToCount: count) ?? Data()
    guard data.count == count else { throw PatchError("A game file changed while preparing the compressed copy.") }
    return data
}

private func archiveSpans(_ members: [ArchiveMember], headerURL: URL, hashed: Bool,
                          suffix: Data = Data(), padding: URL? = nil) throws -> (header: Data, spans: [FileSpan], offsets: [UInt64]) {
    var rows = Data(), strings = Data(), body: [FileSpan] = [], offsets: [UInt64] = []
    var offset: UInt64 = 0
    for member in members {
        if let padding, offset % 0x200 != 0 {
            let length = 0x200 - offset % 0x200
            body.append(FileSpan(url: padding, offset: 0, size: length))
            offset += length
        }
        offsets.append(offset)
        rows.appendLE(offset, bytes: 8)
        rows.appendLE(member.size, bytes: 8)
        rows.appendLE(UInt64(strings.count), bytes: 4)
        strings.append(contentsOf: member.name.utf8)
        strings.append(0)
        if hashed {
            let hashSize = Int(min(0x200, member.size))
            rows.appendLE(UInt64(hashSize), bytes: 4)
            rows.appendLE(0, bytes: 8)
            var prefix = Data()
            for span in member.spans where prefix.count < hashSize {
                prefix.append(try readSpan(span.url, offset: span.offset, count: min(hashSize-prefix.count, Int(span.size))))
            }
            rows.append(Data(SHA256.hash(data: prefix + suffix)))
        } else {
            rows.appendLE(0, bytes: 4)
        }
        body.append(contentsOf: member.spans)
        offset += member.size
    }
    let alignment = hashed ? 0x200 : 16
    let remainder = (16 + rows.count + strings.count) % alignment
    if remainder != 0 { strings.append(Data(count: alignment-remainder)) }
    var header = Data((hashed ? "HFS0" : "PFS0").utf8)
    header.appendLE(UInt64(members.count), bytes: 4)
    header.appendLE(UInt64(strings.count), bytes: 4)
    header.appendLE(0, bytes: 4)
    header.append(rows)
    header.append(strings)
    try header.write(to: headerURL)
    return (header, [FileSpan(url: headerURL, offset: 0, size: UInt64(header.count))] + body, offsets)
}

private func compressedCartridge(_ input: URL, cartridge: ContainerLayout.Cartridge,
                                 members: [ArchiveMember], work: URL) throws -> [FileSpan] {
    let rootOffset = cartridge.rootOffset
    guard rootOffset % 0x200 == 0 else { throw PatchError("The cartridge has an unsupported partition alignment.") }
    var head = try readSpan(input, offset: 0, count: 0x200)
    let oldRootSize = try head.number(0x138, 8)
    let expectedHash = head.subdata(in: 0x140..<0x160)
    var suffix = Data()
    // China-region images append a region byte to HFS0 hashes.
    if oldRootSize > 0, oldRootSize <= 16 * 1024 * 1024,
       oldRootSize <= cartridge.partitions.map(\.offset).min()! - rootOffset {
        let originalRoot = try readSpan(input, offset: rootOffset, count: Int(oldRootSize))
        let region = Data([1])
        if Data(SHA256.hash(data: originalRoot + region)) == expectedHash { suffix = region }
    }
    let secure = try archiveSpans(members, headerURL: work.appendingPathComponent("secure.bin"), hashed: true, suffix: suffix)
    let partitions = cartridge.partitions.map { partition in
        ArchiveMember(name: partition.name, spans: partition.name == "secure" ? secure.spans :
            [FileSpan(url: input, offset: partition.offset, size: partition.size)])
    }
    let padding = work.appendingPathComponent("padding.bin")
    try Data(count: 0x200).write(to: padding)
    let root = try archiveSpans(partitions, headerURL: work.appendingPathComponent("root.bin"),
                                hashed: true, suffix: suffix, padding: padding)
    let secureIndex = partitions.firstIndex { $0.name == "secure" }!
    let secureOffset = rootOffset + UInt64(root.header.count) + root.offsets[secureIndex]
    guard secureOffset / 0x200 <= UInt64(UInt32.max) else { throw PatchError("The cartridge partition offset is too large.") }
    var location = Data(), rootSize = Data()
    location.appendLE(secureOffset / 0x200, bytes: 4)
    rootSize.appendLE(UInt64(root.header.count), bytes: 8)
    head.replaceSubrange(0x104..<0x108, with: location)
    head.replaceSubrange(0x138..<0x140, with: rootSize)
    head.replaceSubrange(0x140..<0x160, with: Data(SHA256.hash(data: root.header + suffix)))
    let headURL = work.appendingPathComponent("head.bin")
    try head.write(to: headURL)
    return [FileSpan(url: headURL, offset: 0, size: 0x200),
            FileSpan(url: input, offset: 0x200, size: rootOffset-0x200)] + root.spans
}
