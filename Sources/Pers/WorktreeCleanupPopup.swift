import SwiftUI

struct WorktreeCleanupPopup: View {
    @EnvironmentObject var store: AppStore
    var pending: WorktreeClose

    var body: some View {
        Popup(title: "DELETE WORKTREE?", accent: Theme.red, dismiss: dismiss) {
            VStack(alignment: .leading, spacing: 0) {
                Text(pending.worktree.name).font(Theme.ui(14, weight: .bold)).foregroundStyle(Theme.ice)
                Text(pending.worktree.branch ?? "detached").font(Theme.ui(12)).foregroundStyle(Theme.dim)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let git = pending.git, git.changedFiles > 0 {
                    line("\(git.changedFiles) uncommitted \(git.changedFiles == 1 ? "file" : "files")", detail: git.unstaged + git.untracked > 0 ? "\(git.unstaged + git.untracked) unstaged" : nil)
                }
                if pending.unpushed > 0 {
                    line("\(pending.unpushed) unpushed \(pending.unpushed == 1 ? "commit" : "commits")", detail: "branch is kept")
                }
            }
            if let error = pending.error {
                Text(error).font(Theme.ui(12)).foregroundStyle(Theme.red)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(action: dismiss) { Chip(color: Theme.cyan) { Text("CANCEL") } }
                Button { store.closeAndDelete(pending) } label: { Chip(active: true, color: Theme.red) { Text("DELETE") } }
            }
            .buttonStyle(.plain)
        }
    }

    private func line(_ text: String, detail: String?) -> some View {
        HStack(spacing: 8) {
            Text(text).font(Theme.ui(13, weight: .bold)).foregroundStyle(Theme.gold)
            if let detail { Text(detail).font(Theme.ui(12)).foregroundStyle(Theme.dim) }
        }
    }

    private func dismiss() {
        store.pendingClose = nil
    }
}
