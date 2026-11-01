import SwiftUI

struct SessionOverview: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            KeyHints(hints: [("⌘1 ⌘2", "tab"), ("⌘T", "new"), ("⇧⌘T", "worktree"), ("⌘W", "close")])
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(store.repos) { repo in
                        VStack(alignment: .leading, spacing: 4) {
                            NamePlate(name: repo.name.uppercased(), color: Theme.cyan)
                                .lineLimit(1)
                                .padding(.leading, 4)
                            ForEach(repo.sessions) { session in
                                OverviewRow(session: session, selected: session.id == store.selectedId)
                            }
                        }
                    }
                }
                .padding(.trailing, 14)
            }
        }
    }
}

private struct OverviewRow: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: Session
    var selected: Bool
    @ViewState private var hovered = false
    @ViewState private var tabTitle: String?
    private var highlighted: Bool { hovered || selected }

    var body: some View {
        HStack(spacing: 8) {
            Text(session.isBusy ? "◈" : "◆")
            VStack(alignment: .leading, spacing: 0) {
                Text(tabTitle ?? session.title)
                    .font(Theme.ui(15, weight: .bold))
                    .lineLimit(1)
                if let branch = session.git?.branch {
                    Text(branch)
                        .font(Theme.ui(12))
                        .opacity(0.7)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if session.hasUnread { tag("NEW") }
            if session.forkedFrom != nil { tag("FORK") }
            if hovered {
                Button { store.close(session) } label: { Text("×") }
                    .buttonStyle(.plain)
            }
        }
        .foregroundStyle(highlighted ? Theme.navy : session.isBusy ? Theme.aqua : Theme.ice)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Slant(amount: 8).fill(highlighted ? Theme.ice : .clear))
        .contentShape(Rectangle())
        .offset(x: highlighted ? 6 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: highlighted)
        .onHover { hovered = $0 }
        .task(id: "\(session.sessionId ?? "")\(session.isBusy)") {
            guard let sessionId = session.sessionId else { tabTitle = nil; return }
            tabTitle = await Task.detached { SaveData.title(ofSession: sessionId) }.value
        }
        .onTapGesture { store.selectedId = session.id }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(Theme.ui(10, weight: .black))
            .foregroundStyle(Theme.navy)
            .padding(.horizontal, 6)
            .background(Slant(amount: 4).fill(Theme.gold))
    }
}
