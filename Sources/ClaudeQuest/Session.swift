import Foundation
import AppKit
import Combine

@MainActor
final class Session: ObservableObject, Identifiable {
    let id: UUID
    @Published var directory: String { didSet { if directory != oldValue { startNewSession(); refreshGit() } } }
    @Published var sessionId: String?
    @Published var model: ClaudeModel
    @Published var mode: PermissionMode
    @Published var effort: Effort?
    @Published var advising = false
    @Published var tokens: Int
    @Published private(set) var contextTokens: Int?
    @Published private(set) var contextWindow: Int?
    @Published var messages: [ChatMessage]
    @Published var draft = ""
    @Published var images: [Data] = []
    @Published private(set) var inputHistory: [String] = []
    @Published var liveModel: String?
    @Published private(set) var outfit = Int.random(in: 0..<1000)
    @Published var git: GitInfo?
    @Published var showingDiff = false
    @Published private(set) var diffBase = DiffBase.unstaged
    @Published private(set) var diff: [FileDiff] = []
    @Published private(set) var showingLog = false
    @Published private(set) var commits: [Commit] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isRunningShell = false
    @Published private(set) var typingId: UUID?
    @Published private(set) var revealed = 0
    @Published private(set) var prompt: PermissionPrompt?
    @Published private(set) var resets = 0
    @Published var hasUnread = false
    @Published var unseenAbove = false

    private(set) var forkedFrom: UUID?
    private var forkAt: String?
    private var process: Process?
    private var input: FileHandle?
    private var typer: Timer?
    private var fix: String?
    private var advisor: Process?
    private var pendingAdvice: [String] = []

    init(directory: String, model: ClaudeModel = .sonnet, mode: PermissionMode = .acceptEdits) {
        id = UUID()
        self.directory = directory
        self.model = model
        self.mode = mode
        tokens = 0
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
        advising = snapshot.advising ?? false
        tokens = snapshot.tokens ?? 0
        contextTokens = snapshot.contextTokens
        contextWindow = snapshot.contextWindow
        messages = snapshot.messages
        draft = snapshot.draft ?? ""
        inputHistory = snapshot.inputHistory ?? []
        forkedFrom = snapshot.forkedFrom
        forkAt = snapshot.forkAt
        outfit = snapshot.outfit ?? outfit
        refreshGit()
        checkTranscript()
    }

    /// Carries the parent's conversation up to `forkAt`; the CLI forks it into a session of its own on the first message.
    init(forking parent: Session, messages: [ChatMessage], forkAt: String?) {
        id = UUID()
        directory = parent.directory
        sessionId = forkAt == nil ? nil : parent.sessionId
        model = parent.model
        mode = parent.mode
        effort = parent.effort
        advising = parent.advising
        tokens = 0
        self.messages = messages
        forkedFrom = parent.id
        self.forkAt = forkAt
        refreshGit()
    }

    var snapshot: SessionSnapshot {
        SessionSnapshot(id: id, directory: directory, sessionId: sessionId, model: model, mode: mode,
                        effort: effort, advising: advising, tokens: tokens, contextTokens: contextTokens, contextWindow: contextWindow,
                        messages: messages, outfit: outfit, draft: draft, inputHistory: inputHistory,
                        forkedFrom: forkedFrom, forkAt: forkAt)
    }

    var title: String { (directory as NSString).lastPathComponent }
    var repoPath: String { git.map { $0.worktrees.first?.path ?? $0.root } ?? directory }
    var logIdentity: String { "\(id)-\(resets)" }
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

    func toggleLog() {
        showingLog.toggle()
        guard showingLog else { return }
        showingDiff = false
        let directory = directory
        Task.detached {
            let commits = Git.log(at: directory)
            await MainActor.run { self.commits = commits }
        }
    }

    func toggleDiff() {
        showingDiff.toggle()
        if showingDiff { showingLog = false }
        if showingDiff { loadDiff() }
    }

    func toggleDiffBase() {
        guard showingDiff else { return }
        diffBase = diffBase.toggled
        loadDiff()
    }

    private func loadDiff() {
        let directory = directory, base = diffBase
        Task.detached {
            let diff = await Git.diff(base, at: directory)
            await MainActor.run { if self.diffBase == base { self.diff = diff } }
        }
    }

    func quote(_ row: DiffRow, in file: FileDiff) {
        guard !row.text.trimmed.isEmpty else { return }
        let location = file.reference(to: row).map { "\($0) " } ?? ""
        draft += (draft.isEmpty || draft.hasSuffix("\n") ? "" : "\n") + "\(location)`\(row.text.trimmed)`\n"
    }

    func isQuoted(_ row: DiffRow, in file: FileDiff) -> Bool {
        file.reference(to: row).map { draft.contains("\($0) `") } ?? false
    }

    func reset() {
        stop()
        messages = []
        tokens = 0
        resets += 1
        startNewSession()
    }

    /// Continues a CLI session in this tab, moving to the folder it ran in since `--resume` only finds
    /// sessions recorded under the current directory.
    func load(_ saved: SavedSession) {
        guard !isBusy else { return }
        if directory == saved.directory { startNewSession() } else { directory = saved.directory }
        sessionId = saved.id
        messages = SaveData.messages(in: saved.url)
        tokens = 0
    }

    /// Each Claude session gets one outfit for its whole lifetime.
    private func startNewSession() {
        sessionId = nil
        forkAt = nil
        contextTokens = nil
        outfit = Int.random(in: 0..<1000)
        advisor?.terminate()
        advisor = nil
        pendingAdvice = []
    }

    /// The CLI deletes transcripts after `cleanupPeriodDays`, which leaves a long-idle tab resuming a session that's gone.
    private func checkTranscript() {
        guard let sessionId, !Self.transcriptExists(sessionId) else { return }
        messages.append(ChatMessage(speaker: .system, text: "Claude has left the chat due to inactivity"))
        startNewSession()
    }

    /// Project folder names are an encoding of the working directory, so look in all of them. An unreadable
    /// projects folder counts as present rather than ending every tab's session.
    private static func transcriptExists(_ sessionId: String) -> Bool {
        guard let transcripts = SaveData.transcripts() else { return true }
        return transcripts.contains { $0.lastPathComponent == "\(sessionId).jsonl" }
    }

    func stop() {
        process?.terminate()
        resolveFix("Cancel")
    }

    func skipTyping() {
        typer?.invalidate()
        typingId = nil
    }

    /// Prefixes commands sent from terminal mode. Unlike `!` it can't be typed, so it never collides with a message.
    static let terminalMarker = "\u{1D}"

    func send(_ text: String) {
        guard !isBusy, !text.trimmed.isEmpty || !images.isEmpty else { return }
        checkTranscript()
        if !text.trimmed.isEmpty, inputHistory.last != text { inputHistory = Array((inputHistory + [text]).suffix(100)) }
        let attached = images
        images = []
        messages.append(ChatMessage(speaker: .user, text: text.trimmed, images: attached.isEmpty ? nil : attached))
        isBusy = true
        if text.hasPrefix("!") || text.hasPrefix(Self.terminalMarker) {
            isRunningShell = true
            let command = String(text.dropFirst())
            return command.trimmed == "fuck" ? fixLastCommand() : runShell(command)
        }

        var args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                    "--permission-prompt-tool", "stdio", "--model", model.rawValue, "--permission-mode", mode.rawValue]
        if let effort { args += ["--effort", effort.rawValue] }
        if let sessionId { args += ["--resume", sessionId] }
        if sessionId != nil, let forkAt { args += ["--fork-session", "--resume-session-at", forkAt] }

        let process = claudeProcess(args)
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
        let advice: [[String: Any]] = pendingAdvice.isEmpty ? [] : [["type": "text", "text": Self.advicePreamble + pendingAdvice.joined(separator: "\n\n")]]
        pendingAdvice = []
        let content: Any = attached.isEmpty && advice.isEmpty ? text : advice + attached.map { image in
            ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": image.base64EncodedString()]]
        } + (text.trimmed.isEmpty ? [] : [["type": "text", "text": text]])
        write(["type": "user", "message": ["role": "user", "content": content]])

        Task {
            var gotResult = false
            do {
                for try await line in out.fileHandleForReading.bytes.lines {
                    if handle(line: line) { gotResult = true }
                }
            } catch {}
            process.waitUntilExit()
            let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmed
            if process.terminationReason == .uncaughtSignal || process.terminationStatus == 143 {
                finish(error: "Claude was interrupted.")
            } else if !gotResult {
                finish(error: stderr.isEmpty ? "claude exited with status \(process.terminationStatus)" : stderr)
            } else {
                finish(error: nil)
                if advising { advise() }
            }
        }
    }

    private static let advicePreamble = "A second model reviewed your previous turn. Address its notes, or say why you disagree:\n\n"

    private static let advisorPrompt = """
        You are an advisor watching another Claude coding agent work. You are given its latest turn: the user's request, \
        the tools it called and what it said. Read files to check its work when that helps, but never change anything. \
        If the turn is fine, reply with exactly OK. Otherwise reply with one or two sentences starting with NOTE:, \
        CONCERN: or BLOCKER: about a real problem, such as a bug, a missed requirement, a wrong claim or a risky action.
        """

    /// A second model reviews the finished turn with read-only tools. Its note shows in the chat and reaches Claude with the next message.
    private func advise() {
        guard let request = messages.lastIndex(where: { $0.speaker == .user }),
              messages[request...].contains(where: { $0.speaker == .claude || $0.speaker == .tool }),
              messages.last?.speaker != .system else { return }
        let transcript = messages[request...].map { "\($0.speaker.rawValue.uppercased()): \($0.text)" }.joined(separator: "\n\n")
        // `--tools` takes a variadic list, so it goes last and the transcript is sent on stdin.
        let process = claudeProcess(["-p", "--output-format", "json", "--model", ClaudeModel.sonnet.rawValue,
                                     "--no-session-persistence", "--strict-mcp-config",
                                     "--append-system-prompt", Self.advisorPrompt, "--tools", "Read,Grep,Glob"])
        let out = Pipe(), stdin = Pipe()
        process.standardOutput = out
        process.standardInput = stdin
        process.standardError = FileHandle.nullDevice
        advisor?.terminate()
        guard (try? process.run()) != nil else { return }
        advisor = process

        Task {
            let data = await Task.detached {
                try? stdin.fileHandleForWriting.write(contentsOf: Data(transcript.utf8))
                try? stdin.fileHandleForWriting.close()
                return out.fileHandleForReading.readDataToEndOfFile()
            }.value
            guard advisor === process else { return }
            advisor = nil
            guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            tokens += Self.tokens(in: result)
            let note = (result["result"] as? String)?.trimmed ?? ""
            guard result["is_error"] as? Bool != true, !note.isEmpty, note != "OK" else { return }
            pendingAdvice.append(note)
            messages.append(ChatMessage(speaker: .advisor, text: note))
        }
    }

    private static func tokens(in result: [String: Any]) -> Int {
        let usage = result["usage"] as? [String: Any] ?? [:]
        return ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
            .reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
    }

    private func claudeProcess(_ args: [String]) -> Process {
        let process = Process()
        // The login shell supplies .zprofile's environment; the binary path is resolved separately (see claudePath).
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec \"$0\" \"$@\"", Self.claudePath] + args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        return process
    }

    /// Mirrors the CLI's `!` mode, which `claude -p` doesn't support. The trailing marker reports the
    /// shell's final directory so a `cd` carries over to the tab. Interactive (`-i`) so .zshrc's aliases,
    /// functions and PATH are available, like in the user's own terminal.
    private func runShell(_ command: String) {
        let process = Self.shellProcess("\(command)\nprintf '\\036%s' \"$PWD\"", in: directory)
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out

        do {
            try process.run()
        } catch {
            finish(error: error.localizedDescription)
            return
        }
        self.process = process

        Task {
            var data = Data()
            var messageId: UUID?
            for await chunk in Self.chunks(of: out) {
                data.append(chunk)
                let shown = Self.shellOutput(data).output.trimmed
                guard !shown.isEmpty else { continue }
                if let id = messageId, let index = messages.firstIndex(where: { $0.id == id }) {
                    messages[index].text = shown
                } else {
                    let message = ChatMessage(speaker: .shell, text: shown)
                    messageId = message.id
                    messages.append(message)
                }
            }
            process.waitUntilExit()
            if let cwd = Self.shellOutput(data).cwd, cwd != directory { directory = cwd }
            finish(error: process.terminationReason == .uncaughtSignal ? "Interrupted." : nil)
        }
    }

    static func shellProcess(_ script: String, _ args: [String] = [], in directory: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-ilc", script] + args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardInput = FileHandle.nullDevice
        return process
    }

    static func chunks(of pipe: Pipe) -> AsyncStream<Data> {
        AsyncStream { continuation in
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
        }
    }

    /// Every terminal command runs in a fresh shell with no history, so thefuck gets the tab's previous command
    /// through TF_HISTORY instead of `fc`. Its own confirmation needs a tty, so the correction is confirmed with a prompt.
    private func fixLastCommand() {
        let isCommand = { (text: String) in text.hasPrefix("!") || text.hasPrefix(Self.terminalMarker) }
        guard let previous = messages.dropLast().last(where: { $0.speaker == .user && isCommand($0.text) && $0.text.dropFirst().trimmed != "fuck" })?.text.dropFirst() else {
            return finish(error: "No fucks given.")
        }
        let process = Self.shellProcess("""
            TF_SHELL=zsh TF_ALIAS=fuck TF_SHELL_ALIASES=$(alias) TF_HISTORY=$1 \
            THEFUCK_REQUIRE_CONFIRMATION=false PYTHONIOENCODING=utf-8 thefuck THEFUCK_ARGUMENT_PLACEHOLDER
            """, ["fuck", String(previous)], in: directory)
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            finish(error: error.localizedDescription)
            return
        }
        self.process = process

        Task {
            var correction = ""
            do {
                for try await line in out.fileHandleForReading.bytes.lines where !line.trimmed.isEmpty { correction = line }
            } catch {}
            process.waitUntilExit()
            if process.terminationReason == .uncaughtSignal { return finish(error: "Interrupted.") }
            guard !correction.isEmpty else { return finish(error: "No fucks given.") }
            fix = correction
            let options = ["Run", "Cancel"].map { ["label": $0] }
            prompt = PermissionPrompt(requestId: "fuck", tool: "thefuck", detail: "", input: [:], suggestions: [],
                                      questions: [.init(json: ["question": correction, "header": "Fix", "options": options])])
        }
    }

    /// "Run" and "Cancel" are the offered options; any other text typed as the answer is run as the command instead.
    private func resolveFix(_ answer: String) {
        guard let fix else { return }
        self.fix = nil
        finish(error: nil)
        if answer != "Cancel" { send(Self.terminalMarker + (answer == "Run" ? fix : answer)) }
    }

    /// Splits off the trailing directory report so it never shows, even while the output is still streaming.
    private static func shellOutput(_ data: Data) -> (output: String, cwd: String?) {
        let text = String(decoding: data, as: UTF8.self)
        guard let marker = text.lastIndex(of: "\u{1E}") else { return (text, nil) }
        return (String(text[..<marker]), String(text[text.index(after: marker)...]))
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
        if fix != nil { return resolveFix(text) }
        messages.append(ChatMessage(speaker: .claude, text: question.markdown))
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
        isRunningShell = false
        refreshGit()
    }

    /// Returns true when the line was the final `result` event.
    private func handle(line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }

        switch event["type"] as? String {
        case "system" where event["subtype"] as? String == "init":
            sessionId = event["session_id"] as? String
            forkAt = nil
            liveModel = event["model"] as? String
        case "assistant":
            guard event["parent_tool_use_id"] is NSNull || event["parent_tool_use_id"] == nil,
                  let message = event["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]] else { break }
            for block in blocks { append(block: block) }
            if let usage = message["usage"] as? [String: Any] {
                contextTokens = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                    .reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
            }
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
            tokens += Self.tokens(in: event)
            // Subagents on other models are listed too, so prefer the entry for the model this session runs.
            let models = event["modelUsage"] as? [String: [String: Any]] ?? [:]
            let main = models.first { liveModel?.hasPrefix($0.key) == true }?.value ?? models.values.first
            contextWindow = main?["contextWindow"] as? Int ?? contextWindow
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
        guard let message = Self.message(from: block) else { return }
        messages.append(message)
        if message.speaker == .claude {
            startTyping(message)
            hasUnread = true
            NSApp.requestUserAttention(.criticalRequest)
        }
    }

    nonisolated static func message(from block: [String: Any]) -> ChatMessage? {
        switch block["type"] as? String {
        case "text":
            guard let text = (block["text"] as? String)?.trimmed, !text.isEmpty else { return nil }
            return ChatMessage(speaker: .claude, text: text)
        case "tool_use":
            let name = block["name"] as? String ?? "tool"
            let input = block["input"] as? [String: Any] ?? [:]
            return ChatMessage(speaker: .tool, text: "\(name)\t\(detail(of: input))", edits: edits(of: input))
        default:
            return nil
        }
    }

    nonisolated static func edits(of input: [String: Any]) -> [ChatMessage.Edit]? {
        if let content = input["content"] as? String { return [.init(old: "", new: content)] }
        let edits = input["edits"] as? [[String: Any]] ?? [input]
        let found = edits.compactMap { edit in
            (edit["new_string"] as? String).map { ChatMessage.Edit(old: edit["old_string"] as? String ?? "", new: $0) }
        }
        return found.isEmpty ? nil : found
    }

    nonisolated static func detail(of input: [String: Any]) -> String {
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
    @Published var selectedId: UUID? {
        didSet { UserDefaults.standard.set(selectedId?.uuidString, forKey: Self.selectedKey) }
    }
    @Published var pendingClose: WorktreeClose?
    @Published var creatingWorktree = false
    @Published var previewImage: NSImage?
    @Published var showingActions = false
    @Published var actions: [Action] = [] { didSet { saveActions() } }
    @Published var runs: [ActionRun] = []

    private var saveSubscription: AnyCancellable?
    private var sessionSubscriptions: AnyCancellable?
    private var layoutSubscription: AnyCancellable?
    private var unreadSubscription: AnyCancellable?
    private var runsSubscription: AnyCancellable?
    var actionsWatcher: DispatchSourceFileSystemObject?
    private var runStateSubscriptions: AnyCancellable?

    private static let selectedKey = "selectedSession"

    private static let supportDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeQuest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private static let saveURL = supportDirectory.appendingPathComponent("tabs.json")
    static let actionsURL = supportDirectory.appendingPathComponent("actions.json")

    init() {
        if let data = try? Data(contentsOf: Self.saveURL),
           let snapshots = try? JSONDecoder().decode([SessionSnapshot].self, from: data) {
            sessions = snapshots.map(Session.init(snapshot:))
        }
        if sessions.isEmpty { sessions = [Session(directory: NSHomeDirectory())] }
        let lastSelected = UserDefaults.standard.string(forKey: Self.selectedKey).flatMap(UUID.init)
        selectedId = sessions.first { $0.id == lastSelected }?.id ?? sessions.first?.id
        reloadActions()
        watchActions()
        // Output streams in constantly, so only state changes are forwarded to views observing the store.
        runsSubscription = $runs.sink { [weak self] runs in
            self?.runStateSubscriptions = Publishers.MergeMany(runs.map { $0.$state.map { _ in } })
                .sink { [weak self] in self?.objectWillChange.send() }
        }

        saveSubscription = $sessions.sink { [weak self] sessions in
            self?.sessionSubscriptions = Publishers.MergeMany(sessions.map(\.objectWillChange))
                .debounce(for: .seconds(1), scheduler: RunLoop.main)
                .sink { [weak self] in self?.save() }
            self?.layoutSubscription = Publishers.Merge(Publishers.MergeMany(sessions.map { $0.$git.map { _ in } }),
                             Publishers.MergeMany(sessions.map { $0.$directory.map { _ in } }))
                .sink { [weak self] in self?.objectWillChange.send() }
            guard let self else { return }
            let changes = sessions.flatMap { [$0.$hasUnread.map { _ in }.eraseToAnyPublisher(), $0.$unseenAbove.map { _ in }.eraseToAnyPublisher()] }
                + [self.$selectedId.map { _ in }.eraseToAnyPublisher(),
                   NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).map { _ in }.eraseToAnyPublisher()]
            self.unreadSubscription = Publishers.MergeMany(changes)
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.refreshDockBadge() }
        }
    }

    private func refreshDockBadge() {
        if NSApp.isActive, selected?.unseenAbove == false, selected?.hasUnread == true { selected?.hasUnread = false }
        let unread = sessions.filter(\.hasUnread).count
        NSApp.dockTile.badgeLabel = unread > 0 ? "\(unread)" : nil
    }

    var selected: Session? { sessions.first { $0.id == selectedId } }

    /// The overview's rows: sessions grouped by repo, in tab order.
    var repos: [RepoGroup] {
        let paths = sessions.map(\.repoPath).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return paths.map { path in RepoGroup(path: path, sessions: sessions.filter { $0.repoPath == path }) }
    }

    func newTab(directory: String? = nil) {
        let base = selected
        let session = Session(directory: directory ?? base?.directory ?? NSHomeDirectory(),
                              model: base?.model ?? .sonnet, mode: base?.mode ?? .acceptEdits)
        sessions.append(session)
        selectedId = session.id
    }

    /// Opens a tab continuing `session` from `message`. The transcript is read off the main thread since it can run to megabytes.
    func fork(_ session: Session, at message: ChatMessage) {
        guard let index = session.messages.firstIndex(of: message) else { return }
        var history = Array(session.messages[...index])
        let occurrence = history.filter { $0.speaker == message.speaker && $0.text == message.text }.count
        let parentSessionId = session.sessionId
        Task {
            let eventId = await Task.detached {
                parentSessionId.flatMap { SaveData.eventId(of: message, occurrence: occurrence, sessionId: $0) }
            }.value
            if eventId == nil && parentSessionId != nil {
                history.append(ChatMessage(speaker: .system, text: "That message isn't in Claude's transcript, so the fork starts without its memory."))
            }
            let fork = Session(forking: session, messages: history, forkAt: eventId)
            sessions.append(fork)
            selectedId = fork.id
        }
    }

    /// Closing the last tab of a worktree under `.claude/worktrees` also deletes it, after confirmation if work would be lost.
    func close(_ session: Session) {
        guard let worktree = deletableWorktree(of: session) else { return closeTab(session) }
        Task {
            let (git, unpushed) = await Task.detached { (Git.info(at: worktree.path), Git.unpushedCommits(at: worktree.path)) }.value
            let close = WorktreeClose(session: session, worktree: worktree, git: git, unpushed: unpushed)
            if let git, git.changedFiles > 0 || unpushed > 0 {
                pendingClose = close
            } else {
                closeAndDelete(close)
            }
        }
    }

    func closeAndDelete(_ close: WorktreeClose) {
        closeTab(close.session)
        do {
            try Git.removeWorktree(close.worktree, from: close.session.repoPath)
            pendingClose = nil
        } catch {
            var failed = close
            failed.error = error.localizedDescription
            pendingClose = failed
        }
        sessions.forEach { $0.refreshGit() }
    }

    private func deletableWorktree(of session: Session) -> Worktree? {
        let managedRoot = (session.repoPath as NSString).appendingPathComponent(".claude/worktrees/")
        let shared = sessions.contains { $0.id != session.id && $0.directory == session.directory }
        guard !shared, session.directory.hasPrefix(managedRoot) else { return nil }
        return session.git?.worktrees.first { $0.path == session.directory }
    }

    private func closeTab(_ session: Session) {
        session.stop()
        if !sessions.contains(where: { $0.id != session.id && $0.directory == session.directory }) {
            runs.filter { $0.directory == session.directory }.forEach(dismiss)
        }
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

struct RepoGroup: Identifiable {
    var path: String
    var sessions: [Session]
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

struct WorktreeClose {
    var session: Session
    var worktree: Worktree
    var git: GitInfo?
    var unpushed: Int
    var error: String?
}
