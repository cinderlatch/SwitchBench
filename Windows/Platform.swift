import Foundation

import SwitchBenchNative

let windowsAESCTR = sp_aes_ctr
let windowsInflate = sp_inflate_raw

// Shared code uses this streaming interface. Windows uses the same Mbed TLS
// implementation already bundled with the processing helpers.
final class SHA256 {
    typealias Digest = [UInt8]
    private let context = sp_sha_create()!
    deinit { sp_sha_free(context) }
    func update(data: Data) {
        if !data.isEmpty { data.withUnsafeBytes { sp_sha_update(context, $0.baseAddress, $0.count) } }
    }
    func finalize() -> Digest {
        var result = Digest(repeating: 0, count: 32)
        result.withUnsafeMutableBytes { sp_sha_digest(context, $0.baseAddress) }
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
        to.withUnsafeBufferPointer { to in sp_publish(from.baseAddress!, to.baseAddress!) }
    }
    switch error {
    case 0: return
    case 80, 183: throw TaskIssue(.collision, "A file with this name already exists. Your existing file is unchanged.")
    default: throw TaskIssue(.destination, "Windows couldn’t save the checked copy. Check the save folder and its permissions.", detail: "Windows error \(error)")
    }
}

func windowsSafeName(_ name: String) -> Bool {
    guard !name.isEmpty, !name.hasSuffix("."), !name.hasSuffix(" "),
          name.utf16.count <= 255,
          !name.unicodeScalars.contains(where: { $0.value < 32 || #"<>:"/\|?*"#.unicodeScalars.contains($0) })
    else { return false }
    let base = (name.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        .trimmingCharacters(in: .whitespaces).uppercased()
    if ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"].contains(base) { return false }
    if base.count == 4, (base.hasPrefix("COM") || base.hasPrefix("LPT")),
       let digit = base.last, "123456789¹²³".contains(digit) { return false }
    return true
}
