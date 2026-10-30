import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var scroller = LogScroller()

    var body: some View {
        VStack(spacing: 0) {
            TabBar()
            if let session = store.selected {
                StatusHUD(session: session)
                MessageLog(session: session, scroller: scroller)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                DialogueBox(session: session, scroller: scroller)
                    .id(session.id)
            }
        }
        .background(MoonlitBackground())
        .ignoresSafeArea(edges: .top)
        .preferredColorScheme(.dark)
        .frame(minWidth: 820, minHeight: 600)
    }
}

struct TabBar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.sessions) { session in
                        TabItem(session: session, selected: session.id == store.selectedId)
                            .onTapGesture { store.selectedId = session.id }
                    }
                }
                .padding(.vertical, 2)
            }
            Button { store.newTab() } label: { Chip(color: Theme.ice) { Text("+ NEW") } }
                .buttonStyle(.plain)
                .help("New tab (⌘T)")
        }
        .padding(.leading, 80)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Theme.deep.opacity(0.6))
    }
}

private struct TabItem: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: Session
    var selected: Bool

    var body: some View {
        Chip(active: selected, color: session.isBusy ? Theme.aqua : Theme.cyan) {
            HStack(spacing: 6) {
                Text(session.isBusy ? "◈" : "◆")
                Text(session.title).lineLimit(1)
                if let branch = session.git?.branch {
                    Text(branch).opacity(0.7).lineLimit(1)
                }
                Button { store.close(session) } label: { Text("×") }
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 260)
    }
}

struct StatusHUD: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: Session
    @ViewState private var newWorktreeName = ""
    @ViewState private var askingForWorktree = false
    @ViewState private var gitError: String?

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            DayPanel()
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) { locationRow }
                HStack(spacing: 8) { settingsRow }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(LinearGradient(colors: [Theme.deep.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
        .alert("New worktree", isPresented: $askingForWorktree) {
            TextField("branch-name", text: $newWorktreeName)
            Button("Create & open tab", action: createWorktree)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates a sibling directory on a new branch and opens it in a new tab.")
        }
        .alert("Git error", isPresented: Binding(get: { gitError != nil }, set: { if !$0 { gitError = nil } })) {
            Button("OK") {}
        } message: {
            Text(gitError ?? "")
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

        Chip(color: Theme.gold) { Text(String(format: "$%.3f", session.cost)) }
            .help("Total cost for this tab (USD)")
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
                Button("New worktree…") { newWorktreeName = ""; askingForWorktree = true }
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

    private func createWorktree() {
        let name = newWorktreeName.trimmed
        guard !name.isEmpty else { return }
        do {
            store.newTab(directory: try Git.addWorktree(named: name, from: session.directory))
        } catch {
            gitError = error.localizedDescription
        }
    }
}
