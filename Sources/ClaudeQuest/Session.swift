import Foundation
import Combine

@MainActor
final class Session: ObservableObject, Identifiable {
    let id: UUID
    @Published var directory: String { didSet { if directory != oldValue { startNewSession(); refreshGit() } } }
    @Published var sessionId: String?
    @Published var model: ClaudeModel
    @Published var mode: PermissionMode
    @Published var effort: Effort?
    @Published var cost: Double
    @Published var messages: [ChatMessage]
    @Published var liveModel: String?
    @Published private(set) var outfit = Int.random(in: 0..<1000)
    @Published var git: GitInfo?
    @Published private(set) var isBusy = false
    @Published private(set) var typingId: UUID?
    @Published private(set) var revealed = 0
    @Published private(set) var prompt: PermissionPrompt?

    private var process: Process?
    private var input: FileHandle?
    private var typer: Timer?

    init(directory: String, model: ClaudeModel = .sonnet, mode: PermissionMode = .acceptEdits) {
        id = UUID()
        self.directory = directory
        self.model = model
        self.mode = mode
        cost = 0
        messages = []
        refreshGit()
    }

    init(snapshot: SessionSnapshot) {
        id = snapshot.id
        directory = snapshot.directory
        sessionId = snapshot.sessionId
        model = snapshot.model
        mode = snapshot.mode
        effort = snapshot.effort
        cost = snapshot.cost
        messages = snapshot.messages
        outfit = snapshot.outfit ?? outfit
        refreshGit()
    }

    var snapshot: SessionSnapshot {
        SessionSnapshot(id: id, directory: directory, sessionId: sessionId, model: model, mode: mode,
                        effort: effort, cost: cost, messages: messages, outfit: outfit)
    }

    var title: String { (directory as NSString).lastPathComponent }
    var isTalking: Bool { typingId != nil }

    func visibleText(of message: ChatMessage) -> String {
        message.id == typingId ? String(message.text.prefix(revealed)) : message.text
    }

    func refreshGit() {
        let directory = directory
        Task.detached {
            let info = Git.info(at: directory)
            await MainActor.run { self.git = info }
        }
    }

    func reset() {
        stop()
        messages = []
        cost = 0
        startNewSession()
    }

    /// Each Claude session gets one outfit for its whole lifetime.
    private func startNewSession() {
        sessionId = nil
        outfit = Int.random(in: 0..<1000)
    }

    func stop() {
        process?.terminate()
    }

    func skipTyping() {
        typer?.invalidate()
        typingId = nil
    }

    func send(_ text: String) {
        guard !isBusy, !text.trimmed.isEmpty else { return }
        messages.append(ChatMessage(speaker: .user, text: text))
        isBusy = true
        if text.hasPrefix("!") { return runShell(String(text.dropFirst())) }

        var args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                    "--permission-prompt-tool", "stdio", "--model", model.rawValue, "--permission-mode", mode.rawValue]
        if let effort { args += ["--effort", effort.rawValue] }
        if let sessionId { args += ["--resume", sessionId] }

        let process = Process()
        // The login shell supplies .zprofile's environment; the binary path is resolved separately (see claudePath).
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec \"$0\" \"$@\"", Self.claudePath] + args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let out = Pipe(), err = Pipe(), stdin = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = stdin

        do {
            try process.run()
        } catch {
            finish(error: error.localizedDescription)
            return
        }
        self.process = process
        input = stdin.fileHandleForWriting
        write(["type": "user", "message": ["role": "user", "content": text]])

        Task {
            var gotResult = false
            do {
                for try await line in out.fileHandleForReading.bytes.lines {
                    if handle(line: line) { gotResult = true }
                }
            } catch {}
            process.waitUntilExit()
            let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmed
            if process.terminationReason == .uncaughtSignal {
                finish(error: "Interrupted.")
            } else if !gotResult {
                finish(error: stderr.isEmpty ? "claude exited with status \(process.terminationStatus)" : stderr)
            } else {
                finish(error: nil)
            }
        }
    }

    /// Mirrors the CLI's `!` mode, which `claude -p` doesn't support. The trailing marker reports the
    /// shell's final directory so a `cd` carries over to the tab.
    private func runShell(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "\(command)\nprintf '\\036%s' \"$PWD\""]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            finish(error: error.localizedDescription)
            return
        }
        self.process = process

        Task {
            let data = await Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
            process.waitUntilExit()
            var output = String(decoding: data, as: UTF8.self)
            if let marker = output.lastIndex(of: "\u{1E}") {
                let cwd = String(output[output.index(after: marker)...])
                output = String(output[..<marker])
                if cwd != directory { directory = cwd }
            }
            if !output.trimmed.isEmpty { messages.append(ChatMessage(speaker: .shell, text: output.trimmed)) }
            finish(error: process.terminationReason == .uncaughtSignal ? "Interrupted." : nil)
        }
    }

    /// Finder-launched apps get a minimal PATH, and login shells skip .zshrc where installers usually add
    /// `~/.local/bin`, so check the common install locations before asking an interactive shell.
    private static let claudePath: String = {
        let home = NSHomeDirectory()
        let known = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        if let path = known.first(where: FileManager.default.isExecutableFile(atPath:)) { return path }

        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lic", "command -v claude"]
        let out = Pipe()
        shell.standardOutput = out
        shell.standardError = FileHandle.nullDevice
        shell.standardInput = FileHandle.nullDevice
        try? shell.run()
        let output = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        shell.waitUntilExit()
        return output.split(separator: "\n").last.map { String($0).trimmed }.flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "claude"
    }()

    func answer(_ prompt: PermissionPrompt, allow: Bool, always: Bool = false) {
        guard self.prompt?.requestId == prompt.requestId else { return }
        self.prompt = nil
        respond(to: prompt, with: allow
            ? ["behavior": "allow", "updatedInput": prompt.input, "updatedPermissions": always ? prompt.suggestions : []]
            : ["behavior": "deny", "message": "The user denied this tool call."])
    }

    /// Answers the open AskUserQuestion step; the CLI gets every answer at once after the last question.
    func reply(_ text: String) {
        guard var prompt, let question = prompt.question else { return }
        messages.append(ChatMessage(speaker: .user, text: text))
        prompt.answers[question.text] = text
        guard prompt.question == nil else { return self.prompt = prompt }
        self.prompt = nil
        respond(to: prompt, with: ["behavior": "allow", "updatedInput": prompt.input.merging(["answers": prompt.answers]) { $1 }])
    }

    private func respond(to prompt: PermissionPrompt, with decision: [String: Any]) {
        write(["type": "control_response",
               "response": ["subtype": "success", "request_id": prompt.requestId, "response": decision]])
    }

    /// The CLI reads stream-json from stdin: the opening user message, then answers to permission requests.
    private func write(_ object: [String: Any]) {
        guard let input, var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        try? input.write(contentsOf: data)
    }

    private func finish(error: String?) {
        if let error { messages.append(ChatMessage(speaker: .system, text: error)) }
        try? input?.close()
        input = nil
        prompt = nil
        process = nil
        isBusy = false
        refreshGit()
    }

    /// Returns true when the line was the final `result` event.
    private func handle(line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }

        switch event["type"] as? String {
        case "system" where event["subtype"] as? String == "init":
            sessionId = event["session_id"] as? String
            liveModel = event["model"] as? String
        case "assistant":
            guard event["parent_tool_use_id"] is NSNull || event["parent_tool_use_id"] == nil,
                  let message = event["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { break }
            for block in blocks { append(block: block) }
        case "control_request":
            guard let id = event["request_id"] as? String,
                  let request = event["request"] as? [String: Any],
                  request["subtype"] as? String == "can_use_tool" else { break }
            let input = request["input"] as? [String: Any] ?? [:]
            let suggestions = (request["permission_suggestions"] as? [[String: Any]] ?? [])
                .filter { $0["type"] as? String != "setMode" }
            prompt = PermissionPrompt(requestId: id, tool: request["tool_name"] as? String ?? "tool",
                                      detail: Self.detail(of: input), input: input, suggestions: suggestions,
                                      questions: (input["questions"] as? [[String: Any]] ?? []).map(PermissionPrompt.Question.init))
        case "result":
            cost += event["total_cost_usd"] as? Double ?? 0
            // Closing stdin lets the CLI exit now that the turn is over.
            try? input?.close()
            input = nil
            if event["is_error"] as? Bool == true {
                messages.append(ChatMessage(speaker: .system, text: event["result"] as? String ?? "Unknown error"))
            }
            return true
        default:
            break
        }
        return false
    }

    private func append(block: [String: Any]) {
        switch block["type"] as? String {
        case "text":
            guard let text = (block["text"] as? String)?.trimmed, !text.isEmpty else { return }
            let message = ChatMessage(speaker: .claude, text: text)
            messages.append(message)
            startTyping(message)
        case "tool_use":
            let name = block["name"] as? String ?? "tool"
            let detail = Self.detail(of: block["input"] as? [String: Any] ?? [:])
            messages.append(ChatMessage(speaker: .tool, text: "\(name)\t\(detail)"))
        default:
            break
        }
    }

    private static func detail(of input: [String: Any]) -> String {
        ["command", "file_path", "pattern", "url", "query", "description", "skill", "prompt"]
            .lazy.compactMap { input[$0] as? String }.first ?? ""
    }

    private func startTyping(_ message: ChatMessage) {
        skipTyping()
        typingId = message.id
        revealed = 0
        let step = max(2, message.text.count / 90)
        typer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.revealed += step
                if self.revealed >= message.text.count { self.skipTyping() }
            }
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var selectedId: UUID?

    private var saveSubscription: AnyCancellable?
    private var sessionSubscriptions: AnyCancellable?

    private static let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeQuest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tabs.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.saveURL),
           let snapshots = try? JSONDecoder().decode([SessionSnapshot].self, from: data) {
            sessions = snapshots.map(Session.init(snapshot:))
        }
        if sessions.isEmpty { sessions = [Session(directory: NSHomeDirectory())] }
        selectedId = sessions.first?.id

        saveSubscription = $sessions.sink { [weak self] sessions in
            self?.sessionSubscriptions = Publishers.MergeMany(sessions.map(\.objectWillChange))
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
                .sink { [weak self] in self?.save() }
        }
    }

    var selected: Session? { sessions.first { $0.id == selectedId } }

    func newTab(directory: String? = nil) {
        let base = selected
        let session = Session(directory: directory ?? base?.directory ?? NSHomeDirectory(),
                              model: base?.model ?? .sonnet, mode: base?.mode ?? .acceptEdits)
        sessions.append(session)
        selectedId = session.id
    }

    func close(_ session: Session) {
        session.stop()
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions.remove(at: index)
        if sessions.isEmpty { sessions = [Session(directory: NSHomeDirectory())] }
        if selectedId == session.id { selectedId = sessions[min(index, sessions.count - 1)].id }
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(sessions.map(\.snapshot)) else { return }
        try? data.write(to: Self.saveURL, options: .atomic)
    }
}
