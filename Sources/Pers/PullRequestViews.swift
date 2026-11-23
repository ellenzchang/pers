import SwiftUI
import AppKit

struct PullRequestPanel: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: Session
    @ViewState private var selected = 0
    @FocusState private var focused: Bool

    private var prs: [PullRequest] { session.pullRequests }

    var body: some View {
        VStack(alignment: .leading, spacing: -8) {
            NamePlate(name: "PULL REQUESTS", color: Theme.gold, shadowColor: Theme.ocean)
                .padding(.horizontal, 18)
                .zIndex(1)
            content
                .padding(.top, 6)
                .padding(.bottom, 18)
                .panel(accent: Theme.gold, padding: 18, opacity: 1)
                .overlay(alignment: .bottomTrailing) {
                    KeyHints(hints: hints)
                        .padding(.horizontal, 10)
                        .background(Slant(amount: 6).fill(Theme.deep.opacity(0.9)))
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
        .onChange(of: prs.count) { selected = min(selected, max(prs.count - 1, 0)) }
    }

    @ViewBuilder
    private var content: some View {
        if prs.isEmpty {
            Text("Pull requests Claude opens in this session show here.")
                .font(Theme.body)
                .foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(prs.enumerated()), id: \.element.id) { index, pr in
                            row(pr, active: focused && selected == index)
                                .id(pr.id)
                                .onTapGesture {
                                    selected = index
                                    open(pr)
                                }
                        }
                    }
                }
                .onChange(of: selected) { proxy.scrollTo(prs[selected].id) }
            }
        }
    }

    private func row(_ pr: PullRequest, active: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(active ? "▶" : "○")
                .foregroundStyle(active ? Theme.gold : Theme.dim)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                PullRequestStatus(pr: pr).font(Theme.ui(12, weight: .bold))
                if let title = pr.title { Text(title).font(Theme.body).foregroundStyle(active ? Theme.gold : Theme.text) }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .activeShift(active, offset: 0)
    }

    private var hints: [(key: String, action: String)] {
        [(KeyAction.label(.down, .up), "select"), (KeyAction.select.label, "open"), (KeyAction.label(.back, .pullRequests), "close")]
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        switch press.action(in: .navigation) {
        case .back: store.showingPullRequests = false
        case .down: selected = min(selected + 1, max(prs.count - 1, 0))
        case .up: selected = max(selected - 1, 0)
        case .top: selected = 0
        case .bottom: selected = max(prs.count - 1, 0)
        case .select where press.phase == .down: if prs.indices.contains(selected) { open(prs[selected]) }
        default: return .ignored
        }
        return .handled
    }
}

struct PullRequestStatus: View {
    var pr: PullRequest

    var body: some View {
        HStack(spacing: 4) {
            Text("⇅ \(pr.label)").foregroundStyle(Theme.ice)
            if let state = pr.state { Text(state.rawValue.uppercased()).foregroundStyle(state.color) }
            if pr.state == .merged, pr.status != nil { Text(pr.baseBranch ?? "base").foregroundStyle(Theme.dim) }
            pr.status?.symbol
        }
    }
}

struct PullRequestBadge: View {
    var pr: PullRequest

    var body: some View {
        Button { open(pr) } label: { PullRequestStatus(pr: pr) }
            .buttonStyle(.plain)
            .hoverCard(accent: pr.state?.color ?? Theme.cyan) {
                if let title = pr.title { Text(title).foregroundStyle(Theme.ice) }
                Text(pr.url).font(Theme.code).foregroundStyle(Theme.dim)
            }
    }
}

struct PullRequestSummary: View {
    var prs: [PullRequest]

    var body: some View {
        HStack(spacing: 4) {
            Text("⇅ \(prs.count) PRs").foregroundStyle(Theme.ice)
            ForEach([PullRequest.Checks.failing, .running, .passing], id: \.self) { checks in
                let count = prs.filter { $0.status == checks }.count
                if count > 0 { checks.symbol + Text("\(count)").foregroundStyle(Theme.dim) }
            }
        }
        .hoverCard(accent: Theme.cyan) {
            ForEach(prs) { pr in
                Button { open(pr) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        PullRequestStatus(pr: pr)
                        if let title = pr.title { Text(title).font(Theme.ui(12, weight: .regular)).foregroundStyle(Theme.dim) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

func open(_ pr: PullRequest) {
    NSWorkspace.shared.open(URL(string: pr.url)!)
}

/// A card above the view on hover instead of `.help`: the tooltip never appeared in the status line, likely because the name plate
/// beside it redraws constantly.
private struct HoverCard<Card: View>: ViewModifier {
    var accent: Color
    @ViewBuilder var card: Card
    @ViewState private var overView = false
    @ViewState private var overCard = false

    func body(content: Content) -> some View {
        content
            .onHover { overView = $0 }
            .overlay(alignment: .bottomLeading) {
                if overView || overCard {
                    VStack(alignment: .leading, spacing: 6) { card }
                        .fixedSize()
                        .panel(accent: accent, dark: true, padding: 10, opacity: 1)
                        // Bridges the gap down to the view, so the pointer can reach the card's links without it closing.
                        .padding(.bottom, 12)
                        .contentShape(Rectangle())
                        .onHover { overCard = $0 }
                        .alignmentGuide(.bottom) { $0[.bottom] + 20 }
                }
            }
            .preference(key: HoverCardShown.self, value: overView || overCard)
    }
}

/// The message log is drawn above the input area, so the input area is lifted while one of its cards rises over the log.
struct HoverCardShown: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private extension View {
    func hoverCard<Card: View>(accent: Color, @ViewBuilder card: () -> Card) -> some View {
        modifier(HoverCard(accent: accent, card: card))
    }
}

extension PullRequest.State {
    var color: Color {
        switch self {
        case .draft: Theme.dim
        case .open: Theme.green
        case .merged: Theme.pink
        case .closed: Theme.red
        }
    }
}

extension PullRequest.Checks {
    var symbol: Text {
        switch self {
        case .passing: Text("✓").foregroundStyle(Theme.green)
        case .running: Text("●").foregroundStyle(Theme.gold)
        case .failing: Text("✗").foregroundStyle(Theme.red)
        }
    }
}
