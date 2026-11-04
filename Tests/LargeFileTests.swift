import Foundation
import CryptoKit
import Darwin

@main struct LargeFileTests {
    static func main() throws {
        let fm=FileManager.default,root=try PatchEngine.privateDirectory(in:fm.temporaryDirectory)
        defer { try? fm.removeItem(at:root) }
        let source=root.appendingPathComponent("Large Synthetic Game.nsp"),size:UInt64=0x1_0000_0000+123
        var strings=Data("payload.bin\0".utf8),table=Data()
        strings.append(Data(repeating:0,count:(16-(40+strings.count)%16)%16))
        let start=UInt64(40+strings.count)
        table.appendLE(0,bytes:8);table.appendLE(size-start,bytes:8);table.appendLE(0,bytes:4);table.appendLE(0,bytes:4)
        var header=Data("PFS0".utf8);header.appendLE(1,bytes:4);header.appendLE(UInt64(strings.count),bytes:4);header.appendLE(0,bytes:4);header.append(table);header.append(strings)
        try header.write(to:source)
        let handle=try FileHandle(forWritingTo:source);try handle.truncate(atOffset:size);try handle.seek(toOffset:size-16);try handle.write(contentsOf:Data(repeating:0xAB,count:16));try handle.close()
        let output=root.appendingPathComponent("output");try fm.createDirectory(at:output,withIntermediateDirectories:false)
        let control=WorkControl(),engine=UtilityEngine(patcher:nil,control:control) {_,_ in}
        let began=Date(),parts=try engine.split(source,folder:output)
        let manifest=try JSONDecoder().decode(SplitManifest.self,from:Data(contentsOf:parts.appendingPathComponent("SwitchBench Parts.json")))
        guard manifest.parts.count==2,manifest.parts[0].size==0xFFFF0000,manifest.parts.allSatisfy({$0.size<0x1_0000_0000}) else { throw PatchError("FAT32 split boundary failed") }
        let joined=try engine.join(parts,folder:output)
        let before=try UtilityEngine.hash(source,control:control),after=try UtilityEngine.hash(joined,control:control)
        guard before==after else { throw PatchError("Large split/join mismatch") }
        var usage=rusage();getrusage(RUSAGE_SELF,&usage)
        let report:[String:Any]=["sourceBytes":size,"partSizes":manifest.parts.map(\.size),"byteIdentical":true,"sha256":before.hex,"seconds":Date().timeIntervalSince(began),"peakResidentBytes":usage.ru_maxrss,"synthetic":true]
        let reportURL=URL(fileURLWithPath:CommandLine.arguments[1])
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:reportURL)
        print("PASS: a real >4 GiB file splits below FAT32’s limit and rejoins byte for byte")
        print("PASS: peak resident memory: \(usage.ru_maxrss) bytes")
    }
}
