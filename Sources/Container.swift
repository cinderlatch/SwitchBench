import Foundation
#if !os(Windows)
import CryptoKit
#endif

struct ContainerLayout {
    let entries: [PFSEntry]
    let isCartridge: Bool
    let usedSize: UInt64
    let fileSize: UInt64
    init(_ url: URL) throws {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        let size = try h.seekToEnd()
        func read(_ offset: UInt64, _ count: Int) throws -> Data {
            guard offset <= size, count >= 0, UInt64(count) <= size - offset else { throw PatchError("This game file is incomplete.") }
            try h.seek(toOffset: offset)
            let data = try h.read(upToCount: count) ?? Data()
            guard data.count == count else { throw PatchError("This game file changed while reading.") }; return data
        }
        func directory(_ offset: UInt64, _ length: UInt64, hashed: Bool) throws -> [PFSEntry] {
            guard length >= 16, offset <= size, length <= size - offset else { throw PatchError("The file’s contents extend beyond its end.") }
            let fixed = try read(offset, 16)
            guard fixed.prefix(4) == Data((hashed ? "HFS0" : "PFS0").utf8) else { throw PatchError("This isn’t a supported game-file container.") }
            let count = try fixed.number(4, 4), stringSize = try fixed.number(8, 4)
            guard count > 0, count <= 100_000, stringSize > 0, stringSize <= 16_777_216 else { throw PatchError("The game file’s contents list is invalid or too large.") }
            let stride: UInt64 = hashed ? 64 : 24
            let tableSize = count * stride, headerSize = 16 + tableSize + stringSize
            guard headerSize <= length else { throw PatchError("The game file’s contents list is incomplete.") }
            let table = try read(offset + 16, Int(tableSize)), strings = try read(offset + 16 + tableSize, Int(stringSize))
            var found: [PFSEntry] = [], names = Set<String>()
            for index in 0..<Int(count) {
                let pos = index * Int(stride), relative = try table.number(pos, 8), bytes = try table.number(pos + 8, 8), nameStart = Int(try table.number(pos + 16, 4))
                guard nameStart < strings.count, let end = strings[nameStart...].firstIndex(of: 0),
                      let name = String(data: strings.subdata(in: nameStart..<end), encoding: .utf8), !name.isEmpty,
                      name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
                      !name.unicodeScalars.contains(where: { $0.value < 32 }), names.insert(name.lowercased()).inserted else {
                    throw PatchError("A game file contains an unsafe or repeated filename.")
                }
                #if os(Windows)
                guard windowsSafeName(name) else { throw PatchError("This game package contains a filename Windows can’t safely open.") }
                #endif
                guard relative <= length - headerSize, bytes <= length - headerSize - relative else { throw PatchError("Part of this game file is missing.") }
                found.append(PFSEntry(name: name, offset: offset + headerSize + relative, size: bytes))
            }
            let sorted = found.filter { $0.size > 0 }.sorted { $0.offset < $1.offset }
            for i in 1..<max(1, sorted.count) where sorted[i-1].offset + sorted[i-1].size > sorted[i].offset {
                throw PatchError("Parts of this game file overlap.")
            }
            return found
        }
        if try read(0, 4) == Data("PFS0".utf8) {
            entries = try directory(0, size, hashed: false); isCartridge = false; usedSize = entries.map { $0.offset + $0.size }.max() ?? size
        } else {
            guard size >= 0x200, try read(0x100, 4) == Data("HEAD".utf8) else { throw PatchError("Choose an NSP, XCI, NSZ or XCZ game file.") }
            let header = try read(0, 0x200), rootOffset = try header.number(0x130, 8)
            guard rootOffset >= 0x200, rootOffset < size else { throw PatchError("The cartridge dump has an invalid contents location.") }
            let partitions = try directory(rootOffset, size - rootOffset, hashed: true)
            guard partitions.count <= 16, let secure = partitions.first(where: { $0.name == "secure" }) else { throw PatchError("This cartridge dump has no game-content partition.") }
            entries = try directory(secure.offset, secure.size, hashed: true); isCartridge = true
            let lastSector = try header.number(0x118, 8)
            guard lastSector < UInt64.max / 0x200 else { throw PatchError("The cartridge dump’s length is invalid.") }
            let declared = (lastSector + 1) * 0x200
            let partitionEnd = partitions.map { $0.offset + $0.size }.max() ?? size
            let compressed = entries.contains { $0.name.lowercased().hasSuffix(".ncz") }
            guard compressed || declared <= size else { throw PatchError("This cartridge dump is incomplete.") }
            usedSize = compressed ? partitionEnd : max(declared, partitionEnd)
        }
        fileSize = size
    }
}
