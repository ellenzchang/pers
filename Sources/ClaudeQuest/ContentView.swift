import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var scroller = LogScroller()
    @StateObject private var navigator = Navigator()
    @AppStorage(DialogueBox.showSpriteKey) private var showSprite = false

    var body: some View {
        VStack(spacing: 0) {
            if let session = store.selected {
                StatusHUD(session: session)
                MainPanel(session: session, scroller: scroller, navigator: navigator)
                    .zIndex(1)
                DialogueBox(session: session, scroller: scroller, navigator: navigator)
                    .id(session.id)
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 14) {
                DayPanel()
                SessionOverview()
            }
            .frame(width: 232, alignment: .topLeading)
            .padding(.top, 34)
            .padding(.leading, 18)
            .padding(.bottom, 250)
        }
        .overlay {
            if let pending = store.pendingClose { WorktreeCleanupPopup(pending: pending) }
            if store.creatingWorktree { NewWorktreePopup() }
        }
        .background(MoonlitBackground())
        .background {
            Button("") { showSprite.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .opacity(0)
                .allowsHitTesting(false)
            Button("") { openDiffFileInIntelliJ() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .opacity(0)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea(edges: .top)
        .preferredColorScheme(.dark)
        .frame(minWidth: 820, minHeight: 600)
    }

    private func openDiffFileInIntelliJ() {
        guard let session = store.selected, session.showingDiff, let root = session.git?.root,
              let file = navigator.file(in: session.diff),
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.jetbrains.intellij") else { return }
        let process = Process()
        process.executableURL = app.appendingPathComponent("Contents/MacOS/idea")
        process.arguments = [root, (root as NSString).appendingPathComponent(file.path)]
        try? process.run()
    }
}

private struct MainPanel: View {
    @ObservedObject var session: Session
    var scroller: LogScroller
    var navigator: Navigator

    var body: some View {
        if session.showingDiff {
            DiffView(session: session, scroller: scroller, navigator: navigator)
        } else {
            MessageLog(session: session, scroller: scroller, navigator: navigator)
                .id(session.logIdentity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct StatusHUD: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: Session

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) { locationRow }
                HStack(spacing: 8) { settingsRow }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(LinearGradient(colors: [Theme.deep.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
        .background {
            Button("") { promptForWorktree() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .opacity(0)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var locationRow: some View {
        Button(action: chooseDirectory) {
            Chip(color: Theme.ice) { Text("▸ \(abbreviated(session.directory))").lineLimit(1).truncationMode(.head) }
        }
        .buttonStyle(.plain)
        .help(session.directory)

        gitSection
    }

    @ViewBuilder
    private var settingsRow: some View {
        HStack(spacing: 2) {
            ForEach(ClaudeModel.allCases) { model in
                Button { session.model = model } label: { Chip(active: session.model == model, color: Theme.ice) { Text(model.label) } }
                    .buttonStyle(.plain)
            }
        }
        .help(session.liveModel.map { "Last run: \($0)" } ?? "Model for the next message")

        Menu {
            Picker("Mode", selection: $session.mode) {
                ForEach(PermissionMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Chip(color: modeColor) { Text("MODE \(session.mode.label)") }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()

        Menu {
            Picker("Effort", selection: $session.effort) {
                Text("DEFAULT").tag(Effort?.none)
                ForEach(Effort.allCases) { Text($0.label).tag(Effort?.some($0)) }
            }
            .pickerStyle(.inline)
        } label: {
            Chip(color: Theme.cyan) { Text("EFFORT \(session.effort?.label ?? "DEFAULT")") }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()

        Chip(color: Theme.gold) { Text(Self.compact(session.tokens)) }
            .help("Tokens used in this session (input, output and cache)")
    }

    private static func compact(_ tokens: Int) -> String {
        tokens < 1000 ? "\(tokens) TOKENS" : String(format: "%.1fk TOKENS", Double(tokens) / 1000)
    }

    @ViewBuilder
    private var gitSection: some View {
        if let git = session.git {
            Menu {
                Section("Worktrees") {
                    ForEach(git.worktrees) { worktree in
                        Menu("\(worktree.path == session.directory ? "▶ " : "")\(worktree.name)  [\(worktree.branch ?? "detached")]") {
                            Button("Switch this tab") { session.directory = worktree.path }
                            Button("Open in new tab") { store.newTab(directory: worktree.path) }
                        }
                    }
                }
                Divider()
                Button("New worktree…", action: promptForWorktree)
                Button("Refresh") { session.refreshGit() }
            } label: {
                Chip(color: Theme.aqua) {
                    HStack(spacing: 6) {
                        Text("⎇ \(git.branch)")
                        if git.changedFiles > 0 { Text("●\(git.changedFiles)").foregroundStyle(Theme.gold) }
                        if git.ahead > 0 { Text("↑\(git.ahead)") }
                        if git.behind > 0 { Text("↓\(git.behind)") }
                        if git.worktrees.count > 1 { Text("🌳\(git.worktrees.count)") }
                    }
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
        } else {
            Chip(color: Theme.dim) { Text("no git") }
        }
    }

    private var modeColor: Color {
        switch session.mode {
        case .bypassPermissions, .dontAsk: Theme.red
        case .plan: Theme.cyan
        case .auto, .acceptEdits: Theme.aqua
        case .manual: Theme.text
        }
    }

    private func abbreviated(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: session.directory)
        if panel.runModal() == .OK, let url = panel.url { session.directory = url.path }
    }

    private func promptForWorktree() {
        guard session.git != nil else { return }
        store.creatingWorktree = true
    }
}
