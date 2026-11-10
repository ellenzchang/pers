import SwiftUI

struct NewWorktreePopup: View {
    @EnvironmentObject var store: AppStore
    @ViewState private var name = ""
    @ViewState private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        Popup(title: "NEW WORKTREE", dismiss: dismiss) {
            TextField("branch-name", text: $name)
                .textFieldStyle(.plain)
                .font(Theme.ui(14, weight: .bold))
                .foregroundStyle(Theme.ice)
                .focused($focused)
                .onSubmit(create)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Slant().fill(Theme.codeBackground))
                .overlay(Slant().stroke(Theme.cyan.opacity(0.55), lineWidth: 1.5))
            Text("Creates a directory in .claude/worktrees on a new branch and opens it in a new tab.")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.dim)
            if let error {
                Text(error).font(Theme.ui(12)).foregroundStyle(Theme.red)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(action: dismiss) { Chip(color: Theme.cyan) { Text("CANCEL") } }
                Button(action: create) { Chip(active: true, color: Theme.cyan) { Text("CREATE & OPEN TAB") } }
            }
            .buttonStyle(.plain)
        }
        .onAppear { focused = true }
    }

    private func dismiss() {
        store.creatingWorktree = false
    }

    private func create() {
        let name = name.trimmed
        guard !name.isEmpty, let directory = store.selected?.directory else { return }
        do {
            store.newTab(directory: try Git.addWorktree(named: name, from: directory))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
