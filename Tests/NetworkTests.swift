import Foundation
@main struct NetworkTests {
 static func main() throws {
  let fm=FileManager.default,input=URL(fileURLWithPath:CommandLine.arguments[1]),parent=URL(fileURLWithPath:CommandLine.arguments[2])
  let root=try PatchEngine.privateDirectory(in:parent);defer { try? fm.removeItem(at:root) }
  let e=UtilityEngine(patcher:nil,control:WorkControl()) {_,_ in},prep=PreparationEngine(engine:e)
  let converted=try prep.execute(.convert,plan:prep.prepare(.convert,inputs:[input],folder:root)[0],folder:root)
  let trimmed=try prep.execute(.trim,plan:prep.prepare(.trim,inputs:[input],folder:root)[0],folder:root)
  let parts=try e.split(converted,folder:root,partSize:512*1024)
  let joined=try prep.execute(.join,plan:prep.prepare(.join,inputs:[parts],folder:root)[0],folder:root)
  guard try UtilityEngine.hash(converted,control:e.control)==UtilityEngine.hash(joined,control:e.control) else { throw PatchError("Network round trip mismatch") }
  guard try ContainerLayout(trimmed).isCartridge else { throw PatchError("Network trim invalid") }
  guard try fm.contentsOfDirectory(atPath:root.path).allSatisfy({ !$0.hasPrefix(".switchpatch-") }) else { throw PatchError("Network workspace was retained") }
  print("PASS: prepared conversion, trimming, joining, split checksums and readback on the actual network volume")
 }
}
