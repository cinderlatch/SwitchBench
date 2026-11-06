import Foundation

private struct Request: Decodable {
    let tool: UtilityTool
    let files: [String]
    let folder: String?
    let keys: String?
    let titleKeys: String?
    let previewOnly: Bool
}

private struct Event: Encodable {
    let kind: String
    var id: String?
    var title: String?
    var status: String?
    var message: String?
    var detail: String?
    var output: String?
    var issue: IssueKind?
    var progress: Double?
}

@main struct WindowsWorker {
    private static func send(_ event: Event) {
        if var line = try? JSONEncoder().encode(event) {
            line.append(10)
            try? FileHandle.standardOutput.write(contentsOf: line)
        }
    }

    static func main() {
        let control = WorkControl()
        do {
            guard let line = readLine(), line.utf8.count <= 4_000_000 else {
                throw PatchError("Choose your game files in SwitchBench.")
            }
            let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
            DispatchQueue.global().async {
                let command = readLine()
                if command == "stop" || command == nil { control.cancel() }
            }
            try perform(request, control: control)
        } catch {
            if (try? control.check()) == nil {
                send(Event(kind: "finished", message: "Stopped. Completed results were kept."))
                return
            }
            let issue = TaskIssue.from(error)
            send(Event(kind: "error", message: issue.message, detail: issue.detail, issue: issue.kind))
        }
    }

    private static func perform(_ request: Request, control: WorkControl) throws {
        let tool = request.tool
        let folder = request.folder.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let inputs = request.files.map { URL(fileURLWithPath: $0) }
        let collected = try InputCollector.collect(inputs, tool: tool, known: [], control: control)
        guard !collected.files.isEmpty else { throw TaskIssue(.input, "Choose at least one supported game file or parts folder.") }
        guard tool.allowsMultiple || collected.files.count == 1 else { throw TaskIssue(.parts, "Choose one split part or parts folder at a time.") }
        let helpers = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        var session: HelperSession?
        defer { withExtendedLifetime(session) {} }
        var patcher: PatchEngine?
        if tool.needsKeys, let keys = request.keys, !keys.isEmpty {
            let helperSession = try HelperSession(executable: helpers.appendingPathComponent("hactool.exe"))
            session = helperSession
            patcher = PatchEngine(executable: helperSession.executable, keys: URL(fileURLWithPath: keys),
                                  extraTitleKeys: request.titleKeys.map { URL(fileURLWithPath: $0) },
                                  packer: helperSession.packer, control: control) { stage, progress in
                send(Event(kind: "progress", message: tool.progressText(stage), progress: progress))
            }
        }
        let engine = UtilityEngine(patcher: patcher, control: control) { stage, progress in
            send(Event(kind: "progress", message: tool.progressText(stage), progress: progress))
        }
        let preparation = PreparationEngine(engine: engine)
        let plans = try preparation.prepare(tool, inputs: collected.files, folder: folder)
        for plan in plans {
            let issue = plan.issue
            let description = [plan.subtitle, issue?.message ?? plan.skipReason ?? plan.preview,
                               plan.outputName, plan.sizeEstimate].compactMap { $0 }.filter { !$0.isEmpty }
            send(Event(kind: "plan", id: plan.id, title: plan.title,
                       status: issue != nil ? "Needs attention" : plan.skipReason != nil ? "No change needed" : "Ready",
                       message: description.joined(separator: "\n"), detail: issue?.detail, issue: issue?.kind))
        }
        let ready = plans.filter { $0.issue == nil && $0.skipReason == nil }
        if request.previewOnly {
            send(Event(kind: "finished", message: "\(ready.count) ready. \(plans.count - ready.count) skipped or need attention."))
            return
        }
        var succeeded = 0, failed = 0
        for plan in ready {
            try control.check()
            send(Event(kind: "result", id: plan.id, title: plan.title, status: "Working"))
            do {
                if tool == .inspect, let info = plan.inspection {
                    let result = try engine.verify(info)
                    send(Event(kind: "result", id: plan.id, title: plan.title, status: "Checked", message: result.summary))
                } else if let folder {
                    let result = try preparation.execute(tool, plan: plan, folder: folder)
                    send(Event(kind: "result", id: plan.id, title: plan.title, status: "Saved",
                               message: result.lastPathComponent, output: windowsPath(result.path)))
                } else {
                    throw TaskIssue(.destination, "Choose a save folder.")
                }
                succeeded += 1
            } catch {
                if (try? control.check()) == nil {
                    send(Event(kind: "result", id: plan.id, title: plan.title, status: "Stopped"))
                    throw error
                }
                failed += 1
                let issue = TaskIssue.from(error)
                send(Event(kind: "result", id: plan.id, title: plan.title, status: "Needs attention",
                           message: issue.message, detail: issue.detail, issue: issue.kind))
            }
        }
        send(Event(kind: "finished", message: "\(succeeded) completed. \(failed) failed. \(plans.count - ready.count) skipped or need attention."))
    }
}
