import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var scroller = LogScroller()
    @StateObject private var navigator = Navigator()
    @AppStorage(Theme.styleKey) private var style = ThemeStyle.neutral
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
                if Theme.isQuest { DayPanel() }
                SessionOverview()
            }
            .frame(width: SessionOverview.width, alignment: .topLeading)
            .padding(.top, 34)
            .padding(.leading, SessionOverview.leadingInset)
            .padding(.bottom, 250)
        }
        .overlay(alignment: .topTrailing) {
            if store.showingActions, let session = store.selected {
                ActionPanel(session: session)
                    .padding(.top, 90)
                    .padding(.trailing, 18)
                    .padding(.bottom, 250)
            }
        }
        .overlay {
            if let pending = store.pendingClose { WorktreeCleanupPopup(pending: pending) }
            if store.creatingWorktree { NewWorktreePopup() }
            if let image = store.previewImage {
                Popup(title: "IMAGE", width: 720, dismiss: { store.previewImage = nil }) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 480)
                }
            }
        }
        .background {
            if Theme.isQuest { MoonlitBackground() } else { Theme.deep }
        }
        .background {
            Button("") { showSprite.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .opacity(0)
                .allowsHitTesting(false)
            Button("") { store.showingActions.toggle() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
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
        .id(style)
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
        if session.showingLog {
            CommitLog(commits: session.commits)
        } else if session.showingDiff {
            DiffView(session: session, scroller: scroller, navigator: navigator)
        } else {
            MessageLog(session: session, scroller: scroller, navigator: navigator)
                .id(session.logIdentity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CommitLog: View {
    var commits: [Commit]

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: SessionOverview.reservedWidth)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(commits) { commit in
                        HStack(spacing: 12) {
                            Text(commit.id).foregroundStyle(Theme.gold)
                            Text(commit.subject).foregroundStyle(Theme.text).lineLimit(1)
                            Spacer(minLength: 12)
                            Text("\(commit.author) · \(commit.age)").foregroundStyle(Theme.dim)
                        }
                        .font(Theme.code)
                        .padding(.vertical, 3)
                    }
                }
                .padding(12)
            }
            .defaultScrollAnchor(.top)
            .background(Theme.codeBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StatusHUD: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: Session
    @AppStorage(Theme.styleKey) private var style = ThemeStyle.neutral

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Spacer(minLength: 8)
            HStack(spacing: 8) { settingsRow }
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
    private var settingsRow: some View {
        Button { session.advising.toggle() } label: { Chip(active: session.advising, color: Theme.gold) { Text("ADVISOR") } }
            .buttonStyle(.plain)
            .help("A second model (Sonnet) reviews each finished turn; its notes go to Claude with your next message")

        Menu {
            Picker("Theme", selection: $style) {
                ForEach(ThemeStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Chip(color: Theme.ice) { Text("THEME") }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }

    static func compact(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.1fM", Double(tokens) / 1_000_000).replacingOccurrences(of: ".0M", with: "M") }
        return tokens < 1000 ? "\(tokens)" : String(format: "%.1fk", Double(tokens) / 1000)
    }

    private func promptForWorktree() {
        guard session.git != nil else { return }
        store.creatingWorktree = true
    }
}

/// The session at a glance beside the input: model and effort, mode, git state and how full the context window is.
struct StatusLine: View {
    @ObservedObject var session: Session

    var body: some View {
        HStack(spacing: 10) {
            Text(session.model.label + (session.effort.map { " · \($0.label)" } ?? "")).foregroundStyle(Theme.ice)
            separator
            Text(session.mode.label).foregroundStyle(session.mode.color)
            if let git = session.git {
                separator
                gitStatus(git)
            }
            if let used = session.contextTokens {
                separator
                context(used)
            }
        }
        .font(Theme.ui(12, weight: .bold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .background(Slant(amount: 6).fill(Theme.deep.opacity(0.9)))
    }

    private var separator: some View { Text("│").foregroundStyle(Theme.dim) }

    private func gitStatus(_ git: GitInfo) -> some View {
        HStack(spacing: 6) {
            Text("⎇ \(git.branch)").foregroundStyle(git.changedFiles > 0 ? Theme.gold : Theme.green)
            if git.unstaged > 0 { Text("*\(git.unstaged)").foregroundStyle(Theme.gold) }
            if git.staged > 0 { Text("+\(git.staged)").foregroundStyle(Theme.green) }
            if git.untracked > 0 { Text("?\(git.untracked)").foregroundStyle(Theme.pink) }
            if git.ahead > 0 { Text("↑\(git.ahead)").foregroundStyle(Theme.cyan) }
            if git.behind > 0 { Text("↓\(git.behind)").foregroundStyle(Theme.cyan) }
        }
        .help("* unstaged  + staged  ? untracked  ↑ ahead  ↓ behind")
    }

    @ViewBuilder
    private func context(_ used: Int) -> some View {
        if let window = session.contextWindow, window > 0 {
            let percent = used * 100 / window
            HStack(spacing: 4) {
                Text("◔ \(percent)%").foregroundStyle(percent >= 80 ? Theme.red : percent >= 50 ? Theme.gold : Theme.green)
                Text("of \(StatusHUD.compact(window))").foregroundStyle(Theme.dim)
            }
            .help("\(StatusHUD.compact(used)) of \(StatusHUD.compact(window)) context tokens used")
        } else {
            Text("◔ \(StatusHUD.compact(used))").foregroundStyle(Theme.dim)
                .help("Context tokens used; the window size shows after the next reply")
        }
    }
}

extension PermissionMode {
    var color: Color {
        switch self {
        case .bypassPermissions, .dontAsk: Theme.red
        case .plan: Theme.cyan
        case .auto, .acceptEdits: Theme.aqua
        case .manual: Theme.text
        }
    }
}
