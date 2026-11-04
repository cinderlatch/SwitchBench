import Foundation

/// Local command-line entry point for testing the same engine used by the Mac UI.
@main struct PatchCLI {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 7 else {
            fputs("Usage: PatchCLI engine prod.keys base.nsp update.nsp output-folder inspect|patch\n", stderr)
            exit(2)
        }
        var lastStage = "", lastPercent = -1
        let selectedEngine = URL(fileURLWithPath: args[1])
        let adjacentPacker = selectedEngine.deletingLastPathComponent().appendingPathComponent("hacpack")
        let selectedPacker = FileManager.default.isExecutableFile(atPath: adjacentPacker.path) ? adjacentPacker : selectedEngine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("hacPack/hacpack")
        let runtime: HelperSession
        do { runtime = try HelperSession(executable: selectedEngine, packer: selectedPacker) }
        catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
        defer { withExtendedLifetime(runtime) {} }
        let engine = PatchEngine(executable: runtime.executable, keys: URL(fileURLWithPath: args[2]), packer: runtime.packer, control: WorkControl()) { stage, value in
            let percent = value.map { Int($0 * 100) } ?? -1
            if stage != lastStage || percent >= lastPercent + 10 {
                print("\(stage)\(percent >= 0 ? " — \(percent)%" : "")")
                fflush(stdout); lastStage = stage; lastPercent = percent
            }
        }
        do {
            let base = try engine.inspect(URL(fileURLWithPath: args[3]))
            let update = try engine.inspect(URL(fileURLWithPath: args[4]))
            print("Base: \(base.titleText); update: \(update.titleText)")
            for (label, package) in [("Base", base), ("Update", update)] {
                for nca in package.ncas { print("\(label) NCA type \(nca.contentType), title \(String(format: "%016llX", nca.titleID)), bytes \(nca.entry.size)") }
            }
            print("Matched internal title IDs: \(base.baseID == update.baseID && !base.isUpdate && update.isUpdate)")
            fflush(stdout)
            if args[6] == "patch" {
                let output = try engine.patch(PatchJob(base: base, update: update), outputFolder: URL(fileURLWithPath: args[5]))
                print("Verified output: \(output.path)")
            } else if args[6] != "inspect" { throw PatchError("Unknown operation.") }
        } catch {
            fputs(PatchEngine.scrub(error.localizedDescription) + "\n", stderr); exit(1)
        }
    }
}
