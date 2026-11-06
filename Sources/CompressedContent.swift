import Foundation
#if !os(Windows)
import CryptoKit
#endif
#if !os(Windows)
import CommonCrypto
#endif

#if os(Windows)
import SwitchBenchNative
private let zstdCreate = sp_zstd_create
private let zstdFree = sp_zstd_free
private let zstdDecode = sp_zstd_decode
let zstdEncode = sp_zstd_encode
#else
@_silgen_name("sp_zstd_create") private func zstdCreate() -> UnsafeMutableRawPointer?
@_silgen_name("sp_zstd_free") private func zstdFree(_ pointer: UnsafeMutableRawPointer)
@_silgen_name("sp_zstd_decode") private func zstdDecode(_ ctx: UnsafeMutableRawPointer, _ src: UnsafeRawPointer?, _ length: Int, _ consumed: UnsafeMutablePointer<Int>, _ dst: UnsafeMutableRawPointer?, _ capacity: Int, _ produced: UnsafeMutablePointer<Int>) -> Int
@_silgen_name("sp_zstd_encode") func zstdEncode(_ src: UnsafeRawPointer?, _ length: Int, _ dst: UnsafeMutableRawPointer?, _ capacity: Int, _ level: Int32) -> Int
#endif

struct CompressedContent {
    struct Section { let offset: UInt64; let size: UInt64; let type: UInt64; let key: Data; let counter: Data }
    let archive: URL
    let entry: PFSEntry
    let sections: [Section]
    let payload: UInt64
    let expandedSize: UInt64
    init(archive: URL, entry: PFSEntry) throws {
        self.archive = archive; self.entry = entry
        let h = try FileHandle(forReadingFrom: archive); defer { try? h.close() }
        guard entry.size >= 0x4010 else { throw PatchError("A compressed part of this game is incomplete.") }
        try h.seek(toOffset: entry.offset + 0x4000)
        let fixed = try h.read(upToCount: 16) ?? Data()
        guard fixed.count == 16, fixed.prefix(8) == Data("NCZSECTN".utf8) else { throw PatchError("The compressed game data has an invalid header.") }
        let count = try fixed.number(8, 8)
        guard count > 0, count <= 4096, count * 64 <= entry.size - 0x4010 else { throw PatchError("The compressed game’s contents list is invalid.") }
        let table = try h.read(upToCount: Int(count * 64)) ?? Data()
        guard table.count == count * 64 else { throw PatchError("The compressed game’s contents list is incomplete.") }
        var found: [Section] = [], next: UInt64 = 0x4000
        for i in 0..<Int(count) {
            let pos = i * 64, offset = try table.number(pos, 8), size = try table.number(pos + 8, 8), type = try table.number(pos + 16, 8)
            guard size > 0, offset <= 1 << 40, size <= (1 << 40) - offset, [UInt64(1), 3, 4].contains(type) else { throw PatchError("This compressed game uses an unsupported layout.") }
            if i == 0 && offset > next { found.append(Section(offset: next, size: offset-next, type: 1, key: Data(), counter: Data())) }
            guard (i == 0 || offset == next), offset + size > 0x4000 else { throw PatchError("The compressed game contains gaps or overlapping sections.") }
            found.append(Section(offset: offset, size: size, type: type, key: table.subdata(in: (pos+32)..<(pos+48)), counter: table.subdata(in: (pos+48)..<(pos+64))))
            next = offset + size
        }
        sections = found; expandedSize = next; payload = 0x4010 + count * 64
    }
    static func crypt(_ data: Data, section: Section, offset: UInt64) throws -> Data {
        if section.type == 1 { return data }
        var iv = section.counter
        for i in 0..<8 { iv[15-i] = UInt8(truncatingIfNeeded: (offset >> 4) >> (8*i)) }
        // CTR offset may fall inside a cipher block at a compression-block boundary.
        let prefix = Int(offset & 15)
        let input = Data(repeating: 0, count: prefix) + data
        #if os(Windows)
        if input.isEmpty { return input }
        var output = Data(count: input.count)
        let result = section.key.withUnsafeBytes { key in iv.withUnsafeBytes { counter in
            input.withUnsafeBytes { src in output.withUnsafeMutableBytes { dst in
                windowsAESCTR(key.baseAddress, counter.baseAddress, src.baseAddress, dst.baseAddress, src.count)
            }}
        }}
        guard result == 0 else { throw PatchError("Couldn’t restore the compressed game data.") }
        return Data(output.dropFirst(prefix))
        #else
        var cryptor: CCCryptorRef?
        let status = section.key.withUnsafeBytes { key in iv.withUnsafeBytes { counter in
            CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding), counter.baseAddress, key.baseAddress, 16, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
        }}
        guard status == kCCSuccess, let cryptor else { throw PatchError("Couldn’t read the compressed game’s encryption settings.") }
        defer { CCCryptorRelease(cryptor) }
        var output = Data(count: input.count + 16), written = 0
        let result = output.withUnsafeMutableBytes { dst in input.withUnsafeBytes { src in
            CCCryptorUpdate(cryptor, src.baseAddress, input.count, dst.baseAddress, dst.count, &written)
        }}
        guard result == kCCSuccess, written == input.count else { throw PatchError("Couldn’t restore the compressed game data.") }
        return output.subdata(in: prefix..<written)
        #endif
    }
    func extract(to target: URL, control: WorkControl, progress: (Double) -> Void) throws {
        _ = try process(to: target, control: control, progress: progress)
    }
    func digest(control: WorkControl, progress: (Double) -> Void) throws -> Data {
        try process(to: nil, control: control, progress: progress)
    }
    private func process(to target: URL?, control: WorkControl, progress: (Double) -> Void) throws -> Data {
        let fm = FileManager.default
        if let target {
            guard !fm.fileExists(atPath: target.path), fm.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw PatchError("The destination file already exists or can’t be created.") }
        }
        var success = false
        defer { if !success, let target { try? fm.removeItem(at: target) } }
        let input = try FileHandle(forReadingFrom: archive), output = try target.map { try FileHandle(forWritingTo: $0) }
        defer { try? input.close(); try? output?.close() }
        try input.seek(toOffset: entry.offset)
        let header = try input.read(upToCount: 0x4000) ?? Data()
        guard header.count == 0x4000 else { throw PatchError("The compressed game header is incomplete.") }
        try output?.write(contentsOf: header)
        var written: UInt64 = 0x4000, sectionIndex = 0, hasher = SHA256(); hasher.update(data: header)
        func consume(_ bytes: Data) throws {
            guard UInt64(bytes.count) <= expandedSize - written else { throw PatchError("The compressed game expands beyond its declared size.") }
            var pos = 0
            while pos < bytes.count {
                while sectionIndex < sections.count && written >= sections[sectionIndex].offset + sections[sectionIndex].size { sectionIndex += 1 }
                guard sectionIndex < sections.count else { throw PatchError("The compressed game has unexpected extra data.") }
                let section = sections[sectionIndex]
                guard written >= section.offset else { throw PatchError("The compressed game has a missing section.") }
                let count = min(bytes.count-pos, Int(section.offset + section.size-written))
                let restored = try Self.crypt(bytes.subdata(in: pos..<(pos+count)), section: section, offset: written)
                try output?.write(contentsOf: restored); hasher.update(data: restored); written += UInt64(count); pos += count
            }
            progress(Double(written) / Double(expandedSize))
        }
        var cursor = entry.offset + payload
        let end = entry.offset + entry.size
        func read(_ count: Int) throws -> Data {
            guard count >= 0, UInt64(count) <= end-cursor else { throw PatchError("The compressed game data is incomplete.") }
            try input.seek(toOffset: cursor)
            let d = try input.read(upToCount: count) ?? Data()
            guard d.count == count else { throw PatchError("The compressed game changed while reading.") }; cursor += UInt64(count); return d
        }
        func decode(_ length: UInt64, expected: UInt64) throws {
            guard let ctx = zstdCreate() else { throw PatchError("The decompressor couldn’t start.") }
            defer { zstdFree(ctx) }
            var left = length, producedTotal: UInt64 = 0, last = 1
            var buffer = Data(count: 1024 * 1024)
            while left > 0 {
                try autoreleasepool {
                    try control.check()
                    let chunk = try read(Int(min(left, 1024 * 1024))); left -= UInt64(chunk.count)
                    var pos = 0
                    while pos < chunk.count {
                        var used = 0, produced = 0
                        last = buffer.withUnsafeMutableBytes { dst in chunk.withUnsafeBytes { src in
                            zstdDecode(ctx, src.baseAddress?.advanced(by: pos), chunk.count-pos, &used, dst.baseAddress, dst.count, &produced)
                        }}
                        guard last != -1, used > 0 || produced > 0, UInt64(produced) <= expected-producedTotal else { throw PatchError("The compressed game data is damaged or exceeds its size limit.") }
                        pos += used; producedTotal += UInt64(produced)
                        if produced > 0 { try consume(Data(buffer.prefix(produced))) }
                        if last == 0 && (pos != chunk.count || left != 0) { throw PatchError("The compressed game contains unexpected trailing data.") }
                    }
                }
            }
            // A full output buffer may leave pending output after all input was consumed.
            while last != 0 {
                try control.check(); var used = 0, produced = 0
                last = buffer.withUnsafeMutableBytes { dst in zstdDecode(ctx, nil, 0, &used, dst.baseAddress, dst.count, &produced) }
                guard last != -1, produced > 0, UInt64(produced) <= expected-producedTotal else { throw PatchError("The compressed game data ended early.") }
                producedTotal += UInt64(produced); try consume(Data(buffer.prefix(produced)))
            }
            guard producedTotal == expected else { throw PatchError("The compressed game has an unexpected expanded size.") }
        }
        let start = cursor, magic = try read(8)
        if magic == Data("NCZBLOCK".utf8) {
            let h = try read(16), exponent = Int(h[3]), count = try h.number(4, 4), size = try h.number(8, 8)
            guard h[0] == 2, h[1] == 1, exponent >= 14, exponent <= 32, size == expandedSize - 0x4000 else { throw PatchError("This compressed game has an invalid block header.") }
            let blockSize = UInt64(1) << exponent
            guard count == (size + blockSize - 1) / blockSize, count <= 1_048_576, count * 4 <= end-cursor else { throw PatchError("The compressed game has an invalid block list.") }
            let table = try read(Int(count*4))
            var sizes: [UInt64] = [], total: UInt64 = 0
            for i in 0..<Int(count) {
                let bytes = try table.number(i*4, 4), expanded = min(blockSize, size - UInt64(i)*blockSize)
                guard bytes > 0, bytes <= expanded, bytes <= end-cursor-total else { throw PatchError("The compressed game contains an invalid block size.") }
                sizes.append(bytes); total += bytes
            }
            guard total == end-cursor else { throw PatchError("The compressed game is incomplete or has extra block data.") }
            for (i, bytes) in sizes.enumerated() {
                let expanded = min(blockSize, size - UInt64(i)*blockSize)
                if bytes == expanded {
                    var left = bytes
                    while left > 0 { try autoreleasepool { try control.check(); let d = try read(Int(min(left, 1024*1024))); try consume(d); left -= UInt64(d.count) } }
                } else { try decode(bytes, expected: expanded) }
            }
        } else {
            cursor = start; try decode(end-cursor, expected: expandedSize - 0x4000)
        }
        guard written == expandedSize else { throw PatchError("The compressed game could not be fully restored.") }
        let finalHash = Data(hasher.finalize())
        let digest = finalHash.hex
        let stem = URL(fileURLWithPath: entry.name).deletingPathExtension().lastPathComponent
        if stem.range(of: "^[0-9a-fA-F]{32}$", options: .regularExpression) != nil, !digest.hasPrefix(stem.lowercased()) {
            throw PatchError("The restored game content failed its original file-hash check.")
        }
        try output?.synchronize(); success = true
        return finalHash
    }
}

extension CompressedContent {
    /// Keep bytes outside the filesystem sections as-is, including any sector padding.
    static func sections(from records: Data, size: UInt64) throws -> [Section] {
        guard !records.isEmpty, records.count <= 256, records.count % 64 == 0 else {
            throw PatchError("The game content has an invalid section table.")
        }
        var declared: [Section] = []
        for pos in stride(from: 0, to: records.count, by: 64) {
            let offset = try records.number(pos, 8)
            let size = try records.number(pos + 8, 8)
            let type = try records.number(pos + 16, 8)
            let key = records.subdata(in: (pos+32)..<(pos+48))
            let counter = records.subdata(in: (pos+48)..<(pos+64))
            declared.append(Section(offset: offset, size: size, type: type, key: key, counter: counter))
        }
        declared.sort { $0.offset < $1.offset }
        let zero = Data(count: 16)
        var found: [Section] = [], next: UInt64 = 0x4000, previousEnd: UInt64 = 0
        for section in declared {
            guard section.offset >= previousEnd, section.offset <= size, section.size > 0,
                  section.size <= size - section.offset, [UInt64(1), 3].contains(section.type) else {
                throw PatchError("The game content has invalid or overlapping sections.")
            }
            previousEnd = section.offset + section.size
            guard previousEnd > next else { continue }
            let start = max(next, section.offset)
            if start > next {
                found.append(Section(offset: next, size: start-next, type: 1, key: zero, counter: zero))
            }
            found.append(Section(offset: start, size: previousEnd-start, type: section.type,
                                 key: section.key, counter: section.counter))
            next = previousEnd
        }
        if next < size { found.append(Section(offset: next, size: size-next, type: 1, key: zero, counter: zero)) }
        return found
    }

    /// Write bounded Zstandard blocks and verify the restored ciphertext before keeping the result.
    static func encode(archive: URL, entry: PFSEntry, sections: [Section], to target: URL,
                       control: WorkControl, progress: (Double) -> Void) throws -> UInt64? {
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        let fm = FileManager.default
        guard fm.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw PatchError("Couldn’t create a temporary compressed file.")
        }
        var keep = false
        defer { if !keep { try? fm.removeItem(at: target) } }
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        func read(_ count: Int) throws -> Data {
            let bytes = try input.read(upToCount: count) ?? Data()
            guard bytes.count == count else { throw PatchError("A game file changed during compression.") }
            return bytes
        }
        try input.seek(toOffset: entry.offset)
        let header = try read(0x4000)
        var hash = SHA256()
        hash.update(data: header)
        try output.write(contentsOf: header)

        let exponent: UInt8 = 20
        let blockSize = 1 << exponent, body = entry.size - 0x4000
        let blockCount = Int(1 + (body-1)/UInt64(blockSize))
        var table = Data("NCZSECTN".utf8)
        table.appendLE(UInt64(sections.count), bytes: 8)
        for section in sections {
            table.appendLE(section.offset, bytes: 8)
            table.appendLE(section.size, bytes: 8)
            table.appendLE(section.type, bytes: 8)
            table.appendLE(0, bytes: 8)
            table.append(section.key)
            table.append(section.counter)
        }
        table.append(contentsOf: "NCZBLOCK".utf8)
        table.append(contentsOf: [2, 1, 0, exponent])
        table.appendLE(UInt64(blockCount), bytes: 4)
        table.appendLE(body, bytes: 8)
        try output.write(contentsOf: table)
        let blockTableOffset = try output.offset()
        try output.write(contentsOf: Data(count: blockCount * 4))

        var blockTable = Data(), packed = Data(count: blockSize + 8192), cursor: UInt64 = 0x4000
        var sectionIndex = 0, storedSize = blockTableOffset + UInt64(blockCount * 4)
        while cursor < entry.size {
            try autoreleasepool {
                try control.check()
                let count = Int(min(UInt64(blockSize), entry.size-cursor))
                let raw = try read(count)
                hash.update(data: raw)
                var plaintext = Data()
                plaintext.reserveCapacity(count)
                var pos = 0
                while pos < count {
                    let offset = cursor + UInt64(pos)
                    let section = sections[sectionIndex]
                    let end = section.offset + section.size
                    let length = min(count-pos, Int(end-offset))
                    plaintext.append(try crypt(raw.subdata(in: pos..<(pos+length)), section: section, offset: offset))
                    pos += length
                    if offset + UInt64(length) == end { sectionIndex += 1 }
                }
                let compressed = packed.withUnsafeMutableBytes { dst in
                    plaintext.withUnsafeBytes { src in
                        zstdEncode(src.baseAddress, src.count, dst.baseAddress, dst.count, 6)
                    }
                }
                let bytes = compressed > 0 && compressed < count ? Data(packed.prefix(compressed)) : plaintext
                try output.write(contentsOf: bytes)
                blockTable.appendLE(UInt64(bytes.count), bytes: 4)
                storedSize += UInt64(bytes.count)
                cursor += UInt64(count)
                progress(0.55 * Double(cursor) / Double(entry.size))
            }
        }
        guard storedSize < entry.size else { return nil }
        try output.seek(toOffset: blockTableOffset)
        try output.write(contentsOf: blockTable)
        try output.close()
        let member = PFSEntry(name: String(entry.name.dropLast()) + "z", offset: 0, size: storedSize)
        let restored = try Self(archive: target, entry: member).digest(control: control) { progress(0.55 + 0.45*$0) }
        guard restored == Data(hash.finalize()) else { throw PatchError("The compressed copy failed its restore check.") }
        keep = true
        return storedSize
    }
}
