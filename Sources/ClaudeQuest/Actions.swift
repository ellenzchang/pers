import SwiftUI

/// A saved shell command for a repo, shared by all of its worktrees. Without a repo it's global and can run from any tab.
struct Action: Codable, Identifiable, Equatable {
    var id = UUID()
    var repo: String?
    var command = ""
    var nickname = ""
    /// `KEY=value` lines, exported before the command. Values go through the shell, so `$(secret …)` keeps secrets out of the save file.
    var environment = ""
    /// Output that means a long-running command, like a server, has finished starting.
    var readyMarker = ""

    var name: String { nickname.trimmed.isEmpty ? command : nickname.trimmed }

    var script: String {
        (variables.map { "export " + $0 } + [command]).joined(separator: "\n")
    }

    /// Variables named like credentials whose value is typed in rather than looked up, so they'd sit in plain text in the save file.
    var literalSecrets: [String] {
        variables.compactMap { line in
            let parts = line.split(separator: "=", maxSplits: 1).map(\.trimmed)
            guard parts.count == 2, !parts[1].isEmpty, !parts[1].hasPrefix("$"), !parts[1].hasPrefix("\"$"),
                  parts[0].range(of: "SECRET|PASSWORD|PASSWD|TOKEN|KEY|CREDENTIAL|PRIVATE|AUTH", options: [.regularExpression, .caseInsensitive]) != nil
            else { return nil }
            return parts[0]
        }
    }

    /// Google renders its AI Overview with JavaScript, so a headless Chrome fetches the page and Claude pulls the overview out of its text.
    static let googleAISummary = Action(command: """
        query=$(osascript -e 'text returned of (display dialog "Google query:" default answer "")') || exit 1
        url="https://www.google.com/search?q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote_plus(sys.argv[1]))' "$query")"
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --virtual-time-budget=10000 --dump-dom "$url" 2>/dev/null \
          | python3 -c 'import re, sys; print(re.sub(r"\\s+", " ", re.sub(r"<(script|style)[^>]*>.*?</\\1>|<[^>]+>", " ", sys.stdin.read(), flags=re.S)))' \
          | claude -p "This is the text of a Google results page for the query '$query'. Output only the AI Overview, or say there isn't one."
        """, nickname: "Google AI summary")

    private var variables: [String] {
        environment.split(separator: "\n").map(\.trimmed)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { $0.hasPrefix("export ") ? String($0.dropFirst(7)) : $0 }
    }
}

@MainActor
final class ActionRun: ObservableObject, Identifiable {
    enum State: Equatable { case running, ready, exited(Int32), stopped }

    let id = UUID()
    let action: Action
    let directory: String
    @Published private(set) var state = State.running
    @Published private(set) var output = ""
    private let process: Process

    init(action: Action, directory: String) {
        self.action = action
        self.directory = directory
        process = Session.shellProcess(action.script, in: directory)
    }

    var isActive: Bool { state == .running || state == .ready }

    func start() {
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        process.terminationHandler = { process in
            let status = process.terminationStatus
            Task { @MainActor in if self.state != .stopped { self.state = .exited(status) } }
        }
        do {
            try process.run()
        } catch {
            output = error.localizedDescription
            state = .exited(-1)
            return
        }
        Task {
            for await chunk in Session.chunks(of: out) { append(chunk) }
        }
    }

    /// Dev servers and Maven fork children that outlive the shell, so the whole tree is signalled.
    /// Returns the signalled processes so a restart can wait for them to let go of their ports.
    @discardableResult
    func stop() -> [pid_t] {
        guard isActive else { return [] }
        state = .stopped
        // Collected before signalling, since killed parents hand their children to launchd and `pgrep -P` loses them.
        let pids = [process.processIdentifier] + Self.descendants(of: process.processIdentifier)
        pids.forEach { kill($0, SIGTERM) }
        return pids
    }

    private func append(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        output = String((output + text).suffix(20_000))
        let marker = action.readyMarker.trimmed
        if state == .running, !marker.isEmpty, output.contains(marker) { state = .ready }
    }

    private static func descendants(of pid: pid_t) -> [pid_t] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", String(pid)]
        let out = Pipe()
        pgrep.standardOutput = out
        guard (try? pgrep.run()) != nil else { return [] }
        let children = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").compactMap { pid_t($0) }
        pgrep.waitUntilExit()
        return children + children.flatMap(descendants)
    }
}

extension AppStore {
    func run(of action: Action, in directory: String) -> ActionRun? {
        runs.last { $0.action.id == action.id && $0.directory == directory }
    }

    /// Running an action that's already running restarts it, once the old processes have exited.
    func run(_ action: Action, in directory: String) {
        let previous = run(of: action, in: directory)
        let pids = previous?.stop() ?? []
        Task {
            for _ in 0..<100 where pids.contains(where: { kill($0, 0) == 0 }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            let run = ActionRun(action: action, directory: directory)
            runs.removeAll { $0.id == previous?.id }
            runs.append(run)
            run.start()
        }
    }

    func dismiss(_ run: ActionRun) {
        run.stop()
        runs.removeAll { $0.id == run.id }
    }

    func upsert(_ action: Action) {
        if let index = actions.firstIndex(where: { $0.id == action.id }) { actions[index] = action } else { actions.append(action) }
    }

    func seedGlobalActions() {
        guard !UserDefaults.standard.bool(forKey: Self.seededGlobalKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.seededGlobalKey)
        actions.append(Action.googleAISummary)
    }

    func reloadActions() {
        guard let data = try? Data(contentsOf: Self.actionsURL),
              let saved = try? JSONDecoder().decode([Action].self, from: data),
              saved != actions else { return }
        actions = saved
    }

    /// Watches the directory rather than the file: saves are atomic, which replaces the file and would end a watch on it.
    func watchActions() {
        let descriptor = open(Self.actionsURL.deletingLastPathComponent().path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        watcher.setEventHandler { [weak self] in self?.reloadActions() }
        watcher.setCancelHandler { Darwin.close(descriptor) }
        watcher.resume()
        actionsWatcher = watcher
    }

    func saveActions() {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        try? data.write(to: Self.actionsURL, options: .atomic)
    }
}

extension ActionRun.State {
    func label(readyMarker: String) -> String {
        switch self {
        case .running: readyMarker.trimmed.isEmpty ? "RUNNING" : "STARTING"
        case .ready: "READY"
        case .exited(0): "DONE"
        case .exited(let status): "FAILED \(status)"
        case .stopped: "STOPPED"
        }
    }

    var color: Color {
        switch self {
        case .running: Theme.gold
        case .ready: Theme.green
        case .exited(0): Theme.aqua
        case .exited: Theme.red
        case .stopped: Theme.dim
        }
    }
}

struct ActionPanel: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: Session
    @ViewState private var editing: Action?
    @ViewState private var expanded: Action.ID?
    /// Index into `actions`, where one past the end is the new-action button.
    @ViewState private var selected = 0
    @ViewState private var deleteArmed = false
    @ViewState private var showingGlobal = false
    @FocusState private var focused: Bool

    private var actions: [Action] { store.actions.filter { $0.repo == (showingGlobal ? nil : session.repoPath) } }
    private var selectedAction: Action? { actions.indices.contains(selected) ? actions[selected] : nil }
    private static let newId = "new"

    var body: some View {
        VStack(alignment: .leading, spacing: -8) {
            HStack(spacing: 0) {
                NamePlate(name: "ACTIONS", color: Theme.gold, shadowColor: Theme.ocean)
                scopeTabs
            }
            .padding(.horizontal, 18)
            .zIndex(1)
            content
                .padding(.top, 6)
                .padding(.bottom, 18)
                .panel(accent: Theme.gold, padding: 18, opacity: 1)
                .overlay(alignment: .bottomTrailing) {
                    KeyHints(hints: hints, highlighted: deleteArmed ? "x" : nil)
                        .padding(.horizontal, 10)
                        .background(Slant(amount: 6).fill(Theme.deep.opacity(0.9)))
                        .padding(.leading, 30)
                        .padding(.trailing, 18)
                        .offset(y: 10)
                }
        }
        .frame(width: 380)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat], action: handle)
        .onAppear { focused = true }
        .onChange(of: editing) { if editing == nil { focused = true } }
        .onChange(of: selected) { deleteArmed = false }
        .onChange(of: showingGlobal) {
            editing = nil
            selected = 0
        }
        .onChange(of: actions.count) { selected = min(selected, actions.count) }
        .onChange(of: session.repoPath) {
            editing = nil
            selected = 0
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("runs in \(session.title)")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                            if editing?.id == action.id {
                                editor(for: action)
                            } else {
                                ActionRow(action: action, directory: session.directory,
                                          selected: focused && selected == index,
                                          expanded: expanded == action.id,
                                          select: { selected = index },
                                          toggle: { toggleOutput(of: action) },
                                          run: { run(action) },
                                          edit: { editing = action })
                                    .id(action.id.uuidString)
                            }
                        }
                        if let editing, !actions.contains(where: { $0.id == editing.id }) {
                            editor(for: editing)
                        } else if editing == nil {
                            Button(action: startNew) {
                                let active = focused && selected == actions.count
                                marker(active: active, text: "+ New action", color: Theme.cyan)
                            }
                            .buttonStyle(.plain)
                            .id(Self.newId)
                        }
                    }
                }
                .onChange(of: selected) {
                    proxy.scrollTo(selectedAction?.id.uuidString ?? Self.newId)
                }
            }
        }
    }

    private var scopeTabs: some View {
        HStack(spacing: 10) {
            scopeTab((session.repoPath as NSString).lastPathComponent.uppercased(), active: !showingGlobal) { showingGlobal = false }
            Text("│").foregroundStyle(Theme.dim)
            scopeTab("GLOBAL", active: showingGlobal) { showingGlobal = true }
        }
        .font(Theme.ui(12, weight: .bold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .background(Slant(amount: 6).fill(Theme.deep.opacity(0.9)))
    }

    private func scopeTab(_ title: String, active: Bool, select: @escaping () -> Void) -> some View {
        Button(action: select) { Text(title).foregroundStyle(active ? Theme.gold : Theme.dim) }
            .buttonStyle(.plain)
    }

    private func marker(active: Bool, text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(active ? "▶" : "○")
                .foregroundStyle(active ? Theme.gold : Theme.dim)
                .frame(width: 14)
            Text(text).foregroundStyle(active ? Theme.gold : color)
        }
        .font(Theme.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var hints: [(key: String, action: String)] {
        if editing != nil { return [("⏎", "save"), ("⇥", "next field"), ("⌥⏎", "new line"), ("ESC", "cancel")] }
        return [("↑↓ jk", "select"), ("⇥", showingGlobal ? "local" : "global"), ("⏎", "run"), ("s", "stop"), ("␣", "output"), ("e", "edit"), ("n", "new"),
                ("x", deleteArmed ? "again to delete" : "delete"), ("ESC ⇧⌘A", "close")]
    }

    private func editor(for action: Action) -> some View {
        ActionEditor(action: action, save: { store.upsert($0); editing = nil }, cancel: { editing = nil })
            .id(action.id)
    }

    /// Plain keys only, since the app's own shortcuts all use ⌘ and stay live while the panel has focus.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard editing == nil, press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        let action = selectedAction
        let run = action.flatMap { store.run(of: $0, in: session.directory) }
        switch (press.key, press.characters) {
        case (.escape, _): store.showingActions = false
        case (.tab, _) where press.phase == .down: showingGlobal.toggle()
        case (.downArrow, _), (_, "j"): selected = min(selected + 1, actions.count)
        case (.upArrow, _), (_, "k"): selected = max(selected - 1, 0)
        case (.return, _) where press.phase == .down: if let action { self.run(action) } else { startNew() }
        case (_, "s"): run?.stop()
        case (.space, _) where press.phase == .down: if let action { toggleOutput(of: action) }
        case (_, "e"): if let action { editing = action }
        case (_, "n"): startNew()
        case (_, "x") where press.phase == .down:
            guard let action, run?.isActive != true else { break }
            if deleteArmed { store.actions.removeAll { $0.id == action.id } }
            deleteArmed.toggle()
        default: return .ignored
        }
        return .handled
    }

    private func run(_ action: Action) {
        store.run(action, in: session.directory)
        expanded = action.id
    }

    private func toggleOutput(of action: Action) {
        expanded = expanded == action.id ? nil : action.id
    }

    private func startNew() {
        selected = actions.count
        editing = Action(repo: showingGlobal ? nil : session.repoPath)
    }
}

private struct ActionRow: View {
    @EnvironmentObject var store: AppStore
    var action: Action
    var directory: String
    var selected: Bool
    var expanded: Bool
    var select: () -> Void
    var toggle: () -> Void
    var run: () -> Void
    var edit: () -> Void

    var body: some View {
        let run = store.run(of: action, in: directory)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(selected ? "▶" : "○")
                    .foregroundStyle(selected ? Theme.gold : Theme.dim)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.name).foregroundStyle(selected ? Theme.gold : Theme.ice)
                    if !action.nickname.trimmed.isEmpty {
                        Text(action.command)
                            .font(Theme.code)
                            .foregroundStyle(Theme.dim)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if let run {
                    Text(run.state.label(readyMarker: action.readyMarker))
                        .font(Theme.ui(11, weight: .black))
                        .foregroundStyle(run.state.color)
                }
            }
            .font(Theme.body)
            .contentShape(Rectangle())
            .onTapGesture {
                select()
                if run != nil { toggle() }
            }
            if selected {
                HStack(spacing: 6) {
                    Button(action: self.run) { Chip(active: true, color: Theme.green) { Text(run?.isActive == true ? "RESTART" : "RUN") } }
                    if let run, run.isActive {
                        Button { run.stop() } label: { Chip(color: Theme.red) { Text("STOP") } }
                    }
                    Spacer(minLength: 0)
                    Button(action: edit) { Chip(color: Theme.cyan) { Text("EDIT") } }
                    Button { store.actions.removeAll { $0.id == action.id } } label: { Chip(color: Theme.red) { Text("×") } }
                        .disabled(run?.isActive == true)
                }
                .buttonStyle(.plain)
                .padding(.leading, 22)
            }
            if expanded, let run { RunOutput(run: run) }
        }
    }
}

private struct RunOutput: View {
    @ObservedObject var run: ActionRun

    var body: some View {
        ScrollView {
            Text(run.output.isEmpty ? "No output yet." : run.output)
                .font(Theme.code)
                .foregroundStyle(run.output.isEmpty ? Theme.dim : Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: 200)
        .background(Theme.codeBackground)
    }
}

private struct ActionEditor: View {
    @ViewState private var draft: Action
    @FocusState private var focusedField: String?
    var save: (Action) -> Void
    var cancel: () -> Void

    init(action: Action, save: @escaping (Action) -> Void, cancel: @escaping () -> Void) {
        _draft = ViewState(initialValue: action)
        self.save = save
        self.cancel = cancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("COMMAND", "npm run dev", text: $draft.command)
            field("NICKNAME", "local run finn prod", text: $draft.nickname)
            field("ENVIRONMENT", "DCONSTRETTO_TAGS=finn,dev\nDB_PASSWORD=$(secret get …)", text: $draft.environment, lines: 2...6)
            if !draft.literalSecrets.isEmpty {
                Text("\(draft.literalSecrets.joined(separator: ", ")) would be saved in plain text, where Claude's tools can read it. Look it up instead, e.g. $(secret get …) or $(security find-generic-password -s name -w).")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.gold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            field("READY WHEN OUTPUT CONTAINS", "Started Application", text: $draft.readyMarker)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(action: cancel) { Chip(color: Theme.cyan) { Text("CANCEL") } }
                Button(action: submit) { Chip(active: true, color: Theme.cyan) { Text("SAVE") } }
                    .disabled(draft.command.trimmed.isEmpty)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Slant(amount: 6).fill(Theme.navy.opacity(0.5)))
        .onAppear { focusedField = "COMMAND" }
        .onExitCommand(perform: cancel)
    }

    private func submit() {
        if !draft.command.trimmed.isEmpty { save(draft) }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.ui(11, weight: .black)).foregroundStyle(Theme.dim)
    }

    /// Vertical fields still submit on ⏎ and take ⌥⏎ for a new line, which keeps the whole form keyboard driven.
    private func field(_ title: String, _ placeholder: String, text: Binding<String>, lines: ClosedRange<Int> = 1...1) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label(title)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(lines)
                .focused($focusedField, equals: title)
                .onSubmit(submit)
                .textFieldStyle(.plain)
                .font(Theme.code)
                .foregroundStyle(Theme.ice)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.codeBackground)
        }
    }
}

/// A run in the overview, under each tab open in the directory it runs in.
struct RunLine: View {
    @EnvironmentObject var store: AppStore
    var run: ActionRun
    var highlighted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("▸ \(run.action.name)").lineLimit(1)
            Spacer(minLength: 0)
            Text(run.state.label(readyMarker: run.action.readyMarker))
                .foregroundStyle(highlighted ? Theme.navy : run.state.color)
            Button { if run.isActive { run.stop() } else { store.dismiss(run) } } label: { Text(run.isActive ? "■" : "×") }
                .buttonStyle(.plain)
                .help(run.isActive ? "Stop" : "Dismiss")
        }
        .font(Theme.ui(11, weight: .bold))
    }
}
