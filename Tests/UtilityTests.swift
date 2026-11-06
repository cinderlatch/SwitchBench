import Foundation
#if !os(Windows)
import CryptoKit
import CommonCrypto
#endif

@main struct UtilityTests {
    static var passed = 0
    static func expect(_ ok: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try ok() else { throw PatchError("FAIL: "+name) };passed += 1;print("PASS: "+name)
    }
    static func rejects(_ name: String, _ f: () throws -> Void) throws {
        do { try f() } catch { passed += 1;print("PASS: "+name);return };throw PatchError("FAIL: "+name)
    }
    static func write(_ names:[String], _ parts:[Data], to url:URL, hashed:Bool = false) throws {
        try container(names,parts,hashed:hashed).write(to:url)
    }
    static func container(_ names:[String],_ parts:[Data],hashed:Bool = false) throws -> Data {
        var strings=Data(),table=Data(),payload=Data()
        for (index,name) in names.enumerated() {
            table.appendLE(UInt64(payload.count),bytes:8);table.appendLE(UInt64(parts[index].count),bytes:8);table.appendLE(UInt64(strings.count),bytes:4)
            if hashed {
                let n=min(parts[index].count,0x200);table.appendLE(UInt64(n),bytes:4);table.appendLE(0,bytes:8);table.append(Data(SHA256.hash(data:parts[index].prefix(n))))
            } else { table.appendLE(0,bytes:4) }
            strings.append(Data(name.utf8));strings.append(0);payload.append(parts[index])
        }
        let align=hashed ? 0x200:16
        strings.append(Data(repeating:0,count:(align-(16+table.count+strings.count)%align)%align))
        var out=Data((hashed ? "HFS0":"PFS0").utf8);out.appendLE(UInt64(parts.count),bytes:4);out.appendLE(UInt64(strings.count),bytes:4);out.appendLE(0,bytes:4)
        out.append(table);out.append(strings);out.append(payload);return out
    }
    static func header(size:Int,type:UInt8=0,title:UInt64=0x0100000000001000)->Data {
        var d=Data(repeating:0,count:0x4000);d.replaceSubrange(0x200..<0x204,with:Data("NCA3".utf8));d[0x205]=type
        var bytes=Data();bytes.appendLE(UInt64(size),bytes:8);d.replaceSubrange(0x208..<0x210,with:bytes)
        bytes=Data();bytes.appendLE(title,bytes:8);d.replaceSubrange(0x210..<0x218,with:bytes);return d
    }
    static func compress(_ data:Data)->Data {
        var result=Data(count:data.count+65536)
        let n=result.withUnsafeMutableBytes { dst in data.withUnsafeBytes { src in zstdEncode(src.baseAddress,data.count,dst.baseAddress,dst.count,3) } }
        precondition(n>0);return Data(result.prefix(n))
    }
    // Independent ECB counter construction checks CTR restoration, including nonaligned reads.
    static func ctrReference(_ data:Data,offset:UInt64,key:Data,counter:Data)->Data {
        let prefix=Int(offset&15),blocks=(prefix+data.count+15)/16
        var counters=Data()
        for i in 0..<blocks {
            counters.append(counter.prefix(8));let value=(offset>>4)+UInt64(i)
            for b in (0..<8).reversed() { counters.append(UInt8(truncatingIfNeeded:value>>(b*8))) }
        }
        #if os(Windows)
        let zero = Data(repeating: 0, count: 16)
        var stream = Data(count: counters.count)
        // Encrypt individually constructed counters to check the streaming CTR offsets.
        for block in 0..<blocks {
            let counter = counters.subdata(in: (block*16)..<((block+1)*16))
            let result = key.withUnsafeBytes { key in counter.withUnsafeBytes { counter in
                zero.withUnsafeBytes { input in stream.withUnsafeMutableBytes { output in
                    windowsAESCTR(key.baseAddress, counter.baseAddress, input.baseAddress,
                                  output.baseAddress?.advanced(by: block*16), 16)
                }}
            }}
            precondition(result == 0)
        }
        #else
        var stream=Data(count:counters.count+16);var written=0
        let status=stream.withUnsafeMutableBytes { dst in counters.withUnsafeBytes { src in key.withUnsafeBytes { k in
            CCCrypt(CCOperation(kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(kCCOptionECBMode),k.baseAddress,16,nil,src.baseAddress,counters.count,dst.baseAddress,dst.count,&written)
        }}}
        precondition(status==kCCSuccess)
        #endif
        return Data(data.enumerated().map { $0.element ^ stream[prefix+$0.offset] })
    }
    static func ncz(_ plain:Data,block:Bool,crypto:Bool,rawAlternate:Bool=false)->(Data,Data) {
        let key=Data((0..<16).map { UInt8($0) }),counter=Data(repeating:0x12,count:16),offset:UInt64=0x4000
        let hdr=header(size:0x4000+plain.count)
        let encrypted=crypto ? ctrReference(plain,offset:offset,key:key,counter:counter):plain
        let original=hdr+encrypted
        var data=hdr;data.append(Data("NCZSECTN".utf8));data.appendLE(1,bytes:8);data.appendLE(offset,bytes:8);data.appendLE(UInt64(plain.count),bytes:8)
        data.appendLE(crypto ? 3:1,bytes:8);data.appendLE(0,bytes:8);data.append(key);data.append(counter)
        if block {
            let blockSize=1<<14;var chunks:[Data]=[]
            for start in stride(from:0,to:plain.count,by:blockSize) {
                let d=plain.subdata(in:start..<min(plain.count,start+blockSize)),compressed=compress(d)
                chunks.append((rawAlternate && chunks.count%2==1)||compressed.count>=d.count ? d:compressed)
            }
            data.append(Data("NCZBLOCK".utf8));data.append(contentsOf:[2,1,0,14]);data.appendLE(UInt64(chunks.count),bytes:4);data.appendLE(UInt64(plain.count),bytes:8)
            chunks.forEach { data.appendLE(UInt64($0.count),bytes:4) };chunks.forEach { data.append($0) }
        } else { data.append(compress(plain)) }
        return (data,original)
    }
    static func cartridge(_ names:[String],_ data:[Data],padding:Int=4096,withOtherPartitions:Bool=false)->Data {
        let secure=try! container(names,data,hashed:true)
        let update=try! container(["notes.txt"],[Data("Cartridge update partition".utf8)],hashed:true)
        let normal=try! container(["notes.txt"],[Data("Cartridge normal partition".utf8)],hashed:true)
        let root=try! withOtherPartitions ? container(["normal","secure","update"],[normal,secure,update],hashed:true) : container(["secure"],[secure],hashed:true)
        var out=Data(repeating:0,count:0xF000);out.replaceSubrange(0x100..<0x104,with:Data("HEAD".utf8))
        func set(_ offset:Int,_ value:UInt64) { var d=Data();d.appendLE(value,bytes:8);out.replaceSubrange(offset..<(offset+8),with:d) }
        let used=((out.count+root.count+0x1FF)/0x200)*0x200
        set(0x130,0xF000);set(0x138,0x200);set(0x118,UInt64(used/0x200-1))
        out.replaceSubrange(0x140..<0x160,with:Data(SHA256.hash(data:root.prefix(0x200))))
        out.append(root);out.append(Data(repeating:0,count:used-out.count));out.append(Data(repeating:0xFF,count:padding));return out
    }
    static func main() throws {
        let fm=FileManager.default,root=try PatchEngine.privateDirectory(in:fm.temporaryDirectory);defer { try? fm.removeItem(at:root) }
        func folder(_ name:String) throws -> URL { let p=root.appendingPathComponent(name);try fm.createDirectory(at:p,withIntermediateDirectories:true);return p }
        let engine=UtilityEngine(patcher:nil,control:WorkControl()) { _,_ in }
        let zero=CompressedContent.Section(offset:0,size:16,type:3,key:Data(repeating:0,count:16),counter:Data(repeating:0,count:16))
        try expect(try CompressedContent.crypt(Data(repeating:0,count:16),section:zero,offset:0).hex=="66e94bd4ef8a2c3b884cfa59ca342b2e","CTR primitive matches the independent AES zero-key known-answer vector")
        let body=Data((0..<(2*1024*1024+123)).map { UInt8(truncatingIfNeeded:$0/37) })
        var compressedExample:URL!, originalExample:Data!
        for (index,mode) in [(false,false,false),(false,true,false),(true,true,false),(true,true,true)].enumerated() {
            let (compressed,original)=ncz(body,block:mode.0,crypto:mode.1,rawAlternate:mode.2),id=Data(SHA256.hash(data:original)).prefix(16).hex
            let input=root.appendingPathComponent("compressed-\(index).nsz")
            let meta=Data(header(size:0xC00,type:1).prefix(0xC00))
            try write([id+".ncz","meta.cnmt.nca"],[compressed,meta],to:input)
            let archive=try PFSArchive(input),entry=archive.entries[0],output=root.appendingPathComponent("restored-\(index).nca")
            let reader=try CompressedContent(archive:input,entry:entry)
            try reader.extract(to:output,control:engine.control) { _ in }
            try expect(try Data(contentsOf:output)==original,"NCZ mode \(index) restores exact original bytes across multiple buffers")
            try expect(try reader.digest(control:engine.control,progress:{ _ in })==Data(SHA256.hash(data:original)),"NCZ mode \(index) verifies without writing a temporary game copy")
            let converted=try engine.convert(input,folder:folder("converted-\(index)")),parsed=try PFSArchive(converted)
            try expect(parsed.entries[0].name==id+".nca" && (try parsed.read(parsed.entries[0],limit:original.count))==original,"NSZ conversion produces uncompressed content with its original name and bytes")
            if index==2 { compressedExample=input;originalExample=original }
        }
        // Real program NCZ files commonly cross multiple encrypted sections.
        let boundary=65549, keyA=Data(repeating:7,count:16), keyB=Data(repeating:11,count:16), ctrA=Data(repeating:0x13,count:16), ctrB=Data(repeating:0x27,count:16)
        let rawHeader=header(size:0x4000+body.count)
        let originalMulti=rawHeader+ctrReference(body.subdata(in:0..<boundary),offset:0x4000,key:keyA,counter:ctrA)+ctrReference(body.subdata(in:boundary..<body.count),offset:UInt64(0x4000+boundary),key:keyB,counter:ctrB)
        var multi=rawHeader;multi.append(Data("NCZSECTN".utf8));multi.appendLE(2,bytes:8)
        for (offset,size,type,key,counter) in [(UInt64(0x4000),boundary,UInt64(3),keyA,ctrA),(UInt64(0x4000+boundary),body.count-boundary,UInt64(4),keyB,ctrB)] {
            multi.appendLE(offset,bytes:8);multi.appendLE(UInt64(size),bytes:8);multi.appendLE(type,bytes:8);multi.appendLE(0,bytes:8);multi.append(key);multi.append(counter)
        }
        multi.append(compress(body))
        let multiURL=root.appendingPathComponent("multi.nsz"),multiName=Data(SHA256.hash(data:originalMulti)).prefix(16).hex+".ncz"
        try write([multiName],[multi],to:multiURL)
        let multiArchive=try PFSArchive(multiURL),multiOut=root.appendingPathComponent("multi.nca")
        try multiArchive.extract(multiArchive.entries[0],to:multiOut,control:engine.control) { _ in }
        try expect(try Data(contentsOf:multiOut)==originalMulti,"multiple NCZ encryption sections restore independently across unaligned boundaries")
        let (plainNCZ,plainOriginal)=ncz(body,block:false,crypto:false)
        var early=plainNCZ,earlyOffset=Data(),earlySize=Data();earlyOffset.appendLE(0xC00,bytes:8);earlySize.appendLE(UInt64(body.count+0x3400),bytes:8)
        early.replaceSubrange(0x4010..<0x4018,with:earlyOffset);early.replaceSubrange(0x4018..<0x4020,with:earlySize)
        let earlyURL=root.appendingPathComponent("early.nsz"),earlyName=Data(SHA256.hash(data:plainOriginal)).prefix(16).hex+".ncz"
        try write([earlyName],[early],to:earlyURL);let earlyArchive=try PFSArchive(earlyURL)
        try expect(try CompressedContent(archive:earlyURL,entry:earlyArchive.entries[0]).digest(control:engine.control,progress:{ _ in })==Data(SHA256.hash(data:plainOriginal)),"sections beginning inside the preserved 16 KB prefix restore without duplicated data")
        var overlap=multi,overlapOffset=Data();overlapOffset.appendLE(UInt64(0x4000+boundary-1),bytes:8)
        overlap.replaceSubrange(0x4050..<0x4058,with:overlapOffset)
        let overlapURL=root.appendingPathComponent("overlap.nsz");try write([multiName],[overlap],to:overlapURL);let overlapArchive=try PFSArchive(overlapURL)
        try rejects("overlapping NCZ sections are rejected before processing") { _=try CompressedContent(archive:overlapURL,entry:overlapArchive.entries[0]) }
        let input=compressedExample!,archive=try PFSArchive(input),entry=archive.entries[0]
        let all=try Data(contentsOf:input)
        var bad=all;bad[Int(entry.offset+0x4008)]=0xFF
        let invalid=root.appendingPathComponent("invalid.nsz");try bad.write(to:invalid)
        try rejects("oversized NCZ section list rejected") { _=try CompressedContent(archive:invalid,entry:entry) }
        bad=all;bad[Int(entry.offset+0x4010+16)]=2;try bad.write(to:invalid)
        try rejects("unsupported compressed encryption layout rejected") { _=try CompressedContent(archive:invalid,entry:entry) }
        bad=all;bad[Int(entry.offset+entry.size-2)] ^= 0x80;try bad.write(to:invalid)
        let broken=try CompressedContent(archive:invalid,entry:entry),brokenOutput=root.appendingPathComponent("broken.nca")
        try rejects("damaged compressed data fails restoration") { try broken.extract(to:brokenOutput,control:engine.control) { _ in } }
        try expect(!fm.fileExists(atPath:brokenOutput.path),"failed restoration removes its incomplete output")
        let cancelled=WorkControl();cancelled.cancel()
        try rejects("compressed restoration observes cancellation") { try CompressedContent(archive:input,entry:entry).extract(to:brokenOutput,control:cancelled) { _ in } }
        try expect(!fm.fileExists(atPath:brokenOutput.path),"cancelled restoration leaves no completed output")
        let sentinel=root.appendingPathComponent("existing.nca");try Data("keep".utf8).write(to:sentinel)
        try rejects("compressed restoration never overwrites an existing file") { try CompressedContent(archive:input,entry:entry).extract(to:sentinel,control:engine.control) { _ in } }
        try expect(try Data(contentsOf:sentinel)==Data("keep".utf8),"existing destination bytes remain untouched")
        // Cross-check the real header inspector against compressed and cartridge wrappers.
        let keys=root.appendingPathComponent("prod.keys");try Data(("header_key = "+String(repeating:"00",count:32)+"\n").utf8).write(to:keys)
        let patcher=PatchEngine(executable:URL(fileURLWithPath:CommandLine.arguments[1]),keys:keys,control:WorkControl()) {_,_ in}
        try expect(try patcher.inspect(input).program.declaredSize==originalExample.count,"update workflow imports compressed games using their original expanded sizes")
        let xci=root.appendingPathComponent("cartridge.xci"),meta=Data(header(size:0xC00,type:1).prefix(0xC00)),xciBytes=cartridge(["program.nca","meta.cnmt.nca"],[originalExample,meta])
        try xciBytes.write(to:xci)
        let layout=try ContainerLayout(xci)
        try expect(layout.isCartridge && layout.entries.count==2 && layout.usedSize<layout.fileSize,"XCI secure contents and removable padding are identified")
        try expect(try patcher.inspect(xci).program.declaredSize==originalExample.count,"update workflow imports cartridge dump content without a separate conversion")
        let xciConverted=try engine.convert(xci,folder:folder("xci-convert")),convertedArchive=try PFSArchive(xciConverted)
        try expect(try convertedArchive.read(convertedArchive.entries[0],limit:originalExample.count)==originalExample,"XCI to NSP conversion preserves stored game content")
        let trimmed=try engine.trim(xci,folder:folder("trim"))
        try expect(try Data(contentsOf:trimmed)==xciBytes.prefix(Int(layout.usedSize)),"trimming removes padding while keeping the entire used cartridge image identical")
        try rejects("already-trimmed images do not create another unnecessary copy") { _=try engine.trim(trimmed,folder:folder("trim-again")) }
        let xcz=root.appendingPathComponent("compressed.xcz"),comp=try archive.read(entry,limit:Int(entry.size))
        try cartridge([entry.name,"meta.cnmt.nca"],[comp,meta],padding:0).write(to:xcz)
        let xczOut=try engine.convert(xcz,folder:folder("xcz-convert")),xczParsed=try PFSArchive(xczOut)
        try expect(try xczParsed.read(xczParsed.entries[0],limit:originalExample.count)==originalExample,"XCZ conversion expands its compressed secure content")
        var invalidXCI=xciBytes;invalidXCI.replaceSubrange(0x130..<0x138,with:Data(repeating:0xFF,count:8));let badXCI=root.appendingPathComponent("bad.xci");try invalidXCI.write(to:badXCI)
        try rejects("overflowing cartridge directory offsets are rejected") { _=try ContainerLayout(badXCI) }
        try rejects("already-standard NSP files do not create unnecessary converted copies") { _=try engine.convert(xciConverted,folder:folder("unneeded-conversion")) }
        let splitFolder=try engine.split(xciConverted,folder:folder("split-output"),partSize:512*1024)
        let joined=try engine.join(splitFolder,folder:folder("join-output"))
        try expect(try UtilityEngine.hash(joined,control:engine.control)==UtilityEngine.hash(xciConverted,control:engine.control),"split and join round trip is byte-identical, including container headers")
        let manifest=try JSONDecoder().decode(SplitManifest.self,from:Data(contentsOf:splitFolder.appendingPathComponent("SwitchBench Parts.json")))
        try expect(manifest.parts.count>1 && manifest.parts.allSatisfy { $0.size<=512*1024 },"every split part respects the selected size limit")
        let legacy=try folder("legacy")
        for part in manifest.parts { try fm.copyItem(at:splitFolder.appendingPathComponent(part.name),to:legacy.appendingPathComponent(part.name)) }
        let legacyJoin=try engine.join(legacy.appendingPathComponent(manifest.parts.last!.name),folder:folder("legacy-out"))
        try expect(try UtilityEngine.hash(legacyJoin,control:engine.control)==UtilityEngine.hash(xciConverted,control:engine.control),"legacy numeric parts can be joined starting from any selected part")
        try fm.removeItem(at:legacy.appendingPathComponent(manifest.parts[1].name))
        try rejects("gaps in legacy part numbers are rejected") { _=try engine.join(legacy.appendingPathComponent(manifest.parts[0].name),folder:folder("gap-out")) }
        let changed=splitFolder.appendingPathComponent(manifest.parts[0].name);var changedData=try Data(contentsOf:changed);changedData[100] ^= 1;try changedData.write(to:changed)
        try rejects("damaged SwitchBench parts fail their saved checksums") { _=try engine.join(splitFolder,folder:folder("damaged-parts-out")) }
        let unsafe=SplitManifest(version:1,originalName:"../escape.nsp",size:10,sha256:String(repeating:"0",count:64),parts:manifest.parts)
        try JSONEncoder().encode(unsafe).write(to:splitFolder.appendingPathComponent("SwitchBench Parts.json"))
        try rejects("part manifests cannot escape their selected directory") { _=try engine.join(splitFolder,folder:folder("unsafe-out")) }
        try rejects("files that already fit do not need splitting") { _=try engine.split(xciConverted,folder:folder("small-split"),partSize:UInt64.max/2) }
        try expect(try Data(contentsOf:input)==all && Data(contentsOf:xci)==xciBytes,"all utility operations leave original game files unchanged")

        // QA regression and boundary matrix. Every output lives in a disposable private folder.
        let plainArchive=try PFSArchive(xciConverted),plainEntry=plainArchive.entries[0]
        let occupied=root.appendingPathComponent("occupied.nca");try Data("keep me".utf8).write(to:occupied)
        try rejects("uncompressed extraction refuses an existing destination") { try plainArchive.extract(plainEntry,to:occupied,control:engine.control) { _ in } }
        try expect(try Data(contentsOf:occupied)==Data("keep me".utf8),"uncompressed extraction preserves existing bytes")
        let stopped=WorkControl();stopped.cancel()
        let plainCancelled=root.appendingPathComponent("cancelled-plain.nca")
        try rejects("uncompressed extraction observes cancellation") { try plainArchive.extract(plainEntry,to:plainCancelled,control:stopped) { _ in } }
        try expect(!fm.fileExists(atPath:plainCancelled.path),"cancelled uncompressed extraction removes partial content")
        let noSpace=try folder("no-space")
        try rejects("insufficient free space produces a failure before writing") { try UtilityEngine.requireSpace(noSpace,UInt64.max) }
        try expect(try fm.contentsOfDirectory(atPath:noSpace.path).isEmpty,"space preflight leaves no temporary output")
        let notFolder=root.appendingPathComponent("not-a-folder");try Data([1]).write(to:notFolder)
        try rejects("invalid output location fails cleanly") { _=try engine.convert(xci,folder:notFolder) }
        let collide=try folder("collision"),collideURL=collide.appendingPathComponent("cartridge [Converted].nsp")
        try Data("sentinel".utf8).write(to:collideURL)
        try rejects("conversion detects output collisions") { _=try engine.convert(xci,folder:collide) }
        try expect(try Data(contentsOf:collideURL)==Data("sentinel".utf8),"conversion collisions preserve existing output")

        let intact=try engine.split(xciConverted,folder:folder("intact-parts"),partSize:512*1024)
        // The old branded manifest remains readable after the rename.
        try fm.moveItem(at:intact.appendingPathComponent("SwitchBench Parts.json"),to:intact.appendingPathComponent("SwitchPatch Parts.json"))
        let oldJoined=try engine.join(intact,folder:folder("old-manifest-output"))
        try expect(try UtilityEngine.hash(oldJoined,control:engine.control)==UtilityEngine.hash(xciConverted,control:engine.control),"old SwitchPatch manifests remain compatible with SwitchBench")
        let unrelated=intact.appendingPathComponent("unrelated.nsp.00");try Data([1]).write(to:unrelated)
        try rejects("selecting an unrelated part never silently joins another game") { _=try engine.join(unrelated,folder:folder("wrong-selection")) }
        let ownManifest=intact.appendingPathComponent("SwitchPatch Parts.json")
        let savedManifest=try Data(contentsOf:ownManifest)
        let dataManifest=try JSONDecoder().decode(SplitManifest.self,from:savedManifest)
        let missingPart=intact.appendingPathComponent(dataManifest.parts.last!.name)
        let savedPart=try Data(contentsOf:missingPart);try fm.removeItem(at:missingPart)
        try rejects("a missing final manifest part is detected") { _=try engine.join(intact,folder:folder("missing-final")) }
        try savedPart.write(to:missingPart)
        let versioned=SplitManifest(version:99,originalName:dataManifest.originalName,size:dataManifest.size,sha256:dataManifest.sha256,parts:dataManifest.parts)
        try JSONEncoder().encode(versioned).write(to:ownManifest)
        try rejects("unknown manifest versions are rejected") { _=try engine.join(intact,folder:folder("unknown-manifest")) }
        try Data("{broken json".utf8).write(to:ownManifest)
        try rejects("damaged manifest JSON is rejected") { _=try engine.join(intact,folder:folder("broken-manifest")) }
        try savedManifest.write(to:ownManifest)
        let joinedFolder=try folder("join-collision")
        let firstJoin=try engine.join(intact,folder:joinedFolder),firstBytes=try Data(contentsOf:firstJoin)
        try rejects("joining never overwrites an existing game") { _=try engine.join(intact,folder:joinedFolder) }
        try expect(try Data(contentsOf:firstJoin)==firstBytes,"join collision leaves the existing game unchanged")
        for operation in ["convert","split","join","trim"] {
            let c=WorkControl();c.cancel();let e=UtilityEngine(patcher:nil,control:c) {_,_ in},out=try folder("cancel-"+operation)
            try rejects(operation+" cancellation does not publish an output") {
                switch operation {
                case "convert": _=try e.convert(xci,folder:out)
                case "split": _=try e.split(xciConverted,folder:out,partSize:512*1024)
                case "join": _=try e.join(intact,folder:out)
                default: _=try e.trim(xci,folder:out)
                }
            }
            try expect(try fm.contentsOfDirectory(atPath:out.path).isEmpty,operation+" cancellation cleans all temporary files")
        }
        let unicode=root.appendingPathComponent("テスト — café 🧰.XCI");try xciBytes.write(to:unicode)
        let unicodeOutput=try engine.convert(unicode,folder:folder("unicode"))
        try expect(unicodeOutput.lastPathComponent=="テスト — café 🧰 [Converted].nsp","Unicode, spaces and uppercase extensions survive conversion")
        let noKeys=try engine.inspect(xciConverted)
        try expect(noKeys.titles.isEmpty && noKeys.note != nil,"inspection without keys explains how to obtain game information")
        try rejects("verification without keys cannot claim success") { _=try engine.verify(noKeys) }
        let unsafeNames=["../escape.nca","a/b.nca","a\\b.nca",".","..","bad\u{0001}.nca"]
        for (i,name) in unsafeNames.enumerated() {
            let f=root.appendingPathComponent("unsafe-container-\(i).nsp");try write([name],[Data([1])],to:f)
            try rejects("unsafe container filename \(i) is rejected") { _=try ContainerLayout(f) }
        }
        let duplicateNames=root.appendingPathComponent("duplicate-names.nsp")
        try write(["Game.nca","game.NCA"],[Data([1]),Data([2])],to:duplicateNames)
        try rejects("case-insensitive duplicate container names are rejected") { _=try ContainerLayout(duplicateNames) }
        let truncated=root.appendingPathComponent("truncated.nsp")
        for n in [0,1,3,4,15,16,31] {
            try Data(all.prefix(n)).write(to:truncated)
            try rejects("container truncation at byte \(n) is rejected") { _=try ContainerLayout(truncated) }
        }
        let race=try folder("publish-race"),raceDestination=race.appendingPathComponent("cartridge [Trimmed].xci")
        var created=false
        let raceEngine=UtilityEngine(patcher:nil,control:WorkControl()) { stage,_ in
            if stage=="Checking the saved file" && !created { created=true;try! Data("other writer".utf8).write(to:raceDestination) }
        }
        try rejects("another writer creating the output during verification is preserved") { _=try raceEngine.trim(xci,folder:race) }
        try expect(try Data(contentsOf:raceDestination)==Data("other writer".utf8),"publication race never overwrites the other writer")
        try expect(try fm.contentsOfDirectory(atPath:race.path)==[raceDestination.lastPathComponent],"publication failure removes its private partial file")
        // Deterministic structural mutations exercise parser boundaries; no game data is retained.
        var seed:UInt64=0x12345678
        func next() -> UInt64 { seed=seed &* 6364136223846793005 &+ 1;return seed }
        let fuzz=root.appendingPathComponent("parser-mutation.nsp"),small=try container(["one.nca","two.nca"],[Data(repeating:1,count:64),Data(repeating:2,count:32)])
        var rejected=0, boundsValid=true
        for _ in 0..<1000 {
            var bytes=small
            let pos=Int(next()%UInt64(min(80,bytes.count))),value=UInt8(truncatingIfNeeded:next()>>32)
            bytes[pos] ^= value
            try bytes.write(to:fuzz)
            do { let parsed=try ContainerLayout(fuzz);for entry in parsed.entries { boundsValid = boundsValid && entry.offset<=UInt64(bytes.count) && entry.size<=UInt64(bytes.count)-entry.offset } }
            catch { rejected += 1 }
        }
        try expect(boundsValid,"all accepted mutated entries remain inside the source file")
        try expect(rejected>500,"1,000 deterministic container mutations reject malformed layouts without crashes")

        for block in [false,true] {
            let sample=ncz(Data(repeating:0x55,count:64*1024),block:block,crypto:false)
            for trailing in [false,true] {
                let altered=trailing ? sample.0+Data([0x42]) : Data(sample.0.dropLast(1))
                let f=root.appendingPathComponent("frame-boundary.nsz");try write(["content.ncz"],[altered],to:f)
                let parsed=try PFSArchive(f)
                try rejects("\(block ? "block" : "solid") NCZ rejects \(trailing ? "trailing" : "truncated") frame data") { _=try CompressedContent(archive:f,entry:parsed.entries[0]).digest(control:engine.control,progress:{ _ in }) }
            }
        }
        let compressedMutation=root.appendingPathComponent("ncz-mutation.nsz")
        var compressedRejected=0
        let smallBody=Data(repeating:0x55,count:64*1024)
        let sample=ncz(smallBody,block:true,crypto:false)
        let sampleName=Data(SHA256.hash(data:sample.1)).prefix(16).hex+".ncz"
        for index in 0..<250 {
            var changed=sample.0
            let positions=[0x4000,0x4008,0x4010,0x4018,0x4020,0x4050,0x4058,0x405B,0x405C,0x4060,changed.count-1]
            let pos=positions[index%positions.count];changed[pos] ^= UInt8(1+(index%255))
            try write([sampleName],[changed],to:compressedMutation)
            let parsed=try PFSArchive(compressedMutation)
            do { _=try CompressedContent(archive:compressedMutation,entry:parsed.entries[0]).digest(control:engine.control,progress:{ _ in }) }
            catch { compressedRejected += 1 }
        }
        try expect(compressedRejected>150,"250 deterministic NCZ mutations are rejected without crashes or unbounded allocation")
        if let destination = ProcessInfo.processInfo.environment["QA_FIXTURES"] {
            let target=URL(fileURLWithPath:destination);try fm.createDirectory(at:target,withIntermediateDirectories:true)
            let output=target.appendingPathComponent("Sample Cartridge.xci")
            if fm.fileExists(atPath:output.path) { try fm.removeItem(at:output) }
            try fm.copyItem(at:xci,to:output)
            let game = try PFSArchive(target.appendingPathComponent("Sample Game.nsp"))
            let members = try game.entries.map { try game.read($0, limit: Int($0.size)) }
            try cartridge(game.entries.map(\.name), members, withOtherPartitions: true)
                .write(to: target.appendingPathComponent("Compressible Cartridge.xci"))
            let parts=target.appendingPathComponent("Sample Parts")
            if fm.fileExists(atPath:parts.path) { try fm.removeItem(at:parts) };try fm.copyItem(at:intact,to:parts)
        }
        var progressValues:[Double]=[]
        let progressEngine=UtilityEngine(patcher:nil,control:WorkControl()) {_,value in if let value { progressValues.append(value) } }
        _=try progressEngine.split(xciConverted,folder:folder("progress-split"),partSize:512*1024)
        try expect(zip(progressValues,progressValues.dropFirst()).allSatisfy { $0 <= $1 },"overall split progress never falls backward between parts")
        try expect(progressValues.last==1,"split progress reaches completion only after the last part is checked")
        print("\(passed) utility checks passed.")
    }
}
