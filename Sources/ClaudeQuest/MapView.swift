import SwiftUI

enum Page: CaseIterable {
    case sessions, apiTester

    var title: String {
        switch self {
        case .sessions: "Claude sessions"
        case .apiTester: "API tester"
        }
    }
}

struct MapView: View {
    @EnvironmentObject var store: AppStore
    @ViewState private var selected = Page.sessions
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: -8) {
            NamePlate(name: "MAP", color: Theme.gold, shadowColor: Theme.ocean)
                .padding(.horizontal, 18)
                .zIndex(1)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Page.allCases, id: \.self) { page in
                    Button { open(page) } label: { row(page) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 18)
            .panel(accent: Theme.gold, padding: 18, opacity: 1)
            .overlay(alignment: .bottomTrailing) {
                KeyHints(hints: [("↑↓ jk", "select"), ("⏎", "go"), ("ESC ⌃m", "back")])
                    .padding(.horizontal, 10)
                    .background(Slant(amount: 6).fill(Theme.deep.opacity(0.9)))
                    .padding(.trailing, 18)
                    .offset(y: 10)
            }
        }
        .frame(width: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat], action: handle)
        .onAppear {
            selected = store.page
            focused = true
        }
    }

    private func row(_ page: Page) -> some View {
        let active = page == selected
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(active ? "▶" : "○")
                .foregroundStyle(active ? Theme.gold : Theme.dim)
                .frame(width: 14)
            Text(page.title).foregroundStyle(active ? Theme.gold : Theme.ice)
        }
        .font(Theme.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .activeShift(active, offset: 0)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let pages = Page.allCases
        let index = pages.firstIndex(of: selected) ?? 0
        switch (press.key, press.characters) {
        case (.escape, _): store.showingMap = false
        case (.downArrow, _), (_, "j"): selected = pages[min(index + 1, pages.count - 1)]
        case (.upArrow, _), (_, "k"): selected = pages[max(index - 1, 0)]
        case (.return, _) where press.phase == .down: open(selected)
        default: return .ignored
        }
        return .handled
    }

    private func open(_ page: Page) {
        store.page = page
        store.showingMap = false
    }
}
