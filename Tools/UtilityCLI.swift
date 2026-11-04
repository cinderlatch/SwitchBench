import Foundation
@main struct UtilityCLI {
    static func main() {
        let a=CommandLine.arguments
        guard a.count>=6 else { fputs("Usage: UtilityCLI helpers-folder prod.keys|- operation output-folder input...\n",stderr);exit(2) }
        let folder=URL(fileURLWithPath:a[1]), control=WorkControl()
        var stage="",lastPercent = -1
        do {
            let session=try HelperSession(executable:folder.appendingPathComponent("hactool"))
            defer { withExtendedLifetime(session) {} }
            let patcher = a[2]=="-" ? nil:PatchEngine(executable:session.executable,keys:URL(fileURLWithPath:a[2]),packer:session.packer,control:control) {_,_ in}
            let utility=UtilityEngine(patcher:patcher,control:control) { s,p in
                let n=p.map { Int($0*100) } ?? -1
                if s != stage || n>=lastPercent+20 { print(s+(n>=0 ? " — \(n)%":""));fflush(stdout);stage=s;lastPercent=n }
            }
            let inputs=a.dropFirst(5).map { URL(fileURLWithPath:$0) }, output=URL(fileURLWithPath:a[4])
            if a[3]=="inspect" || a[3]=="verify" {
                for input in inputs {
                    let info=try utility.inspect(input)
                    print("FILE \(input.lastPathComponent) — \(info.format)")
                    for title in info.titles { print("CONTENT \(title.role.rawValue) · \(title.name ?? "Name unavailable") · \(title.displayVersion ?? "no display version") · revision \(title.revision)") }
                    if a[3]=="verify" { print(try utility.verify(info).summary) }
                }
            } else if a[3]=="combine" { print("SAVED "+(try utility.combine(inputs,folder:output)).path) }
            else {
                for input in inputs {
                    let result:URL
                    switch a[3] {
                    case "convert":result=try utility.convert(input,folder:output)
                    case "split":result=try utility.split(input,folder:output)
                    case "join":result=try utility.join(input,folder:output)
                    case "trim":result=try utility.trim(input,folder:output)
                    default:throw PatchError("Unknown operation.")
                    }
                    print("SAVED "+result.path)
                }
            }
        } catch { fputs(PatchEngine.scrub(error.localizedDescription)+"\n",stderr);exit(1) }
    }
}
