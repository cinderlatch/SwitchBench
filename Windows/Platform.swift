import Foundation

@_silgen_name("sp_sha_create") private func createHash() -> UnsafeMutableRawPointer?
@_silgen_name("sp_sha_update") private func updateHash(_ ctx: UnsafeMutableRawPointer, _ bytes: UnsafeRawPointer?, _ count: Int)
@_silgen_name("sp_sha_digest") private func digestHash(_ ctx: UnsafeMutableRawPointer, _ out: UnsafeMutableRawPointer?)
@_silgen_name("sp_sha_free") private func freeHash(_ ctx: UnsafeMutableRawPointer)
@_silgen_name("sp_aes_ctr") func windowsAESCTR(_ key: UnsafeRawPointer?, _ counter: UnsafeRawPointer?, _ source: UnsafeRawPointer?, _ target: UnsafeMutableRawPointer?, _ count: Int) -> Int32
@_silgen_name("sp_inflate_raw") func windowsInflate(_ source: UnsafeRawPointer?, _ count: Int, _ target: UnsafeMutableRawPointer?, _ capacity: Int) -> Int
@_silgen_name("sp_publish") private func windowsMove(_ source: UnsafePointer<UInt16>, _ destination: UnsafePointer<UInt16>) -> UInt32

// Shared code uses this streaming interface. Windows uses the same Mbed TLS
// implementation already bundled with the processing helpers.
final class SHA256 {
    typealias Digest = [UInt8]
    private let context = createHash()!
    deinit { freeHash(context) }
    func update(data: Data) {
        if !data.isEmpty { data.withUnsafeBytes { updateHash(context, $0.baseAddress, $0.count) } }
    }
    func finalize() -> Digest {
        var result = Digest(repeating: 0, count: 32)
        result.withUnsafeMutableBytes { digestHash(context, $0.baseAddress) }
        return result
    }
    static func hash(data: Data) -> Digest {
        let hash = SHA256()
        hash.update(data: data)
        return hash.finalize()
    }
}

func autoreleasepool<T>(invoking work: () throws -> T) rethrows -> T { try work() }

func windowsPath(_ path: String) -> String {
    // Some Foundation URL forms represent drive paths with a leading slash.
    let bytes = Array(path.utf8.prefix(4))
    if bytes.count == 4, bytes[0] == 47, bytes[2] == 58, bytes[3] == 47 {
        return String(path.dropFirst()).replacingOccurrences(of: "/", with: "\\")
    }
    return path.replacingOccurrences(of: "/", with: "\\")
}

func publishWindowsFile(_ source: URL, to destination: URL) throws {
    let from = Array(windowsPath(source.path).utf16) + [0]
    let to = Array(windowsPath(destination.path).utf16) + [0]
    let error = from.withUnsafeBufferPointer { from in
        to.withUnsafeBufferPointer { to in windowsMove(from.baseAddress!, to.baseAddress!) }
    }
    switch error {
    case 0: return
    case 80, 183: throw TaskIssue(.collision, "A file with this name already exists. Your existing file is unchanged.")
    default: throw TaskIssue(.destination, "Windows couldn’t save the checked copy. Check the save folder and its permissions.", detail: "Windows error \(error)")
    }
}
