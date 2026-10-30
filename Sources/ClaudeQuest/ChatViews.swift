import SwiftUI

struct MessageLog: View {
    @ObservedObject var session: Session

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if session.messages.isEmpty { EmptyQuest() }
                    ForEach(session.messages) { message in
                        MessageRow(message: message, text: session.visibleText(of: message))
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: session.messages.count) { scrollDown(proxy) }
            .onChange(of: session.revealed) { scrollDown(proxy, animated: false) }
            .onAppear { scrollDown(proxy, animated: false) }
        }
    }

    private func scrollDown(_ proxy: ScrollViewProxy, animated: Bool = true) {
        withAnimation(animated ? .easeOut(duration: 0.2) : nil) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

private struct EmptyQuest: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("A NEW DAY BEGINS")
                .font(Theme.display(64))
                .foregroundStyle(Theme.ice)
                .shadow(color: Theme.cyan.opacity(0.7), radius: 0, x: 5, y: 5)
            Text("Claude has joined your party.")
                .font(Theme.ui(18, weight: .bold))
                .foregroundStyle(Theme.navy)
                .padding(.horizontal, 18)
                .padding(.vertical, 2)
                .background(Slant(amount: 10).fill(Theme.cyan))
        }
        .rotationEffect(.degrees(-4))
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }
}

struct MessageRow: View {
    var message: ChatMessage
    var text: String

    var body: some View {
        switch message.speaker {
        case .user:
            HStack {
                Spacer(minLength: 100)
                bubble(name: "YOU", plate: Theme.cyan, light: true, alignment: .trailing) {
                    Text(text)
                        .font(Theme.body)
                        .foregroundStyle(Theme.navy)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .claude:
            HStack {
                bubble(name: "CLAUDE", plate: Theme.ice, light: false, alignment: .leading) {
                    MarkdownView(text: text)
                }
                Spacer(minLength: 40)
            }
        case .tool:
            let parts = text.split(separator: "\t", maxSplits: 1).map(String.init)
            HStack(alignment: .center, spacing: 10) {
                Text(parts.first?.uppercased() ?? "TOOL")
                    .font(Theme.ui(13, weight: .black))
                    .foregroundStyle(Theme.navy)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                    .background(Slant(amount: 7).fill(Theme.cyan))
                if parts.count > 1 {
                    Text(parts[1])
                        .font(Theme.code)
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.leading, 18)
            .textSelection(.enabled)
        case .system:
            Text(text)
                .font(Theme.ui(13, weight: .bold))
                .foregroundStyle(Theme.ice)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Slant(amount: 8).fill(Theme.red.opacity(0.85)))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
        }
    }

    private func bubble<Content: View>(name: String, plate: Color, light: Bool, alignment: HorizontalAlignment,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: alignment, spacing: -8) {
            NamePlate(name: name, color: plate)
                .padding(.horizontal, 18)
                .zIndex(1)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .panel(light: light, padding: 18)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DialogueBox: View {
    @ObservedObject var session: Session
    @ViewState private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(spacing: -6) {
                // The bust is taller than its layout slot so it rises over the log, like a VN character.
                Portrait(mood: mood, outfit: session.outfit)
                    .frame(width: 210, height: 248)
                    .frame(width: 210, height: 150, alignment: .bottom)
                    .allowsHitTesting(false)
                NamePlate(name: "CLAUDE")
            }

            VStack(alignment: .leading, spacing: -8) {
                NamePlate(name: session.isBusy ? "CLAUDE IS THINKING…" : "WHAT WILL YOU DO?", color: Theme.cyan)
                    .padding(.horizontal, 18)
                    .zIndex(1)
                ZStack(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Speak to Claude…  (⏎ send · ⇧⏎ newline)")
                            .font(Theme.body)
                            .foregroundStyle(Theme.dim)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $draft)
                        .font(Theme.body)
                        .foregroundStyle(Theme.text)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.shift) { return .ignored }
                            send()
                            return .handled
                        }
                }
                .padding(.top, 8)
                .frame(height: 112)
                .panel(padding: 16)
            }

            CommandMenu(session: session, canSend: !draft.trimmed.isEmpty, send: send)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .padding(.top, 6)
        .background(LinearGradient(colors: [.clear, Theme.deep.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        .onAppear { focused = true }
        .onTapGesture { if session.isTalking { session.skipTyping() } }
    }

    private var mood: Mood {
        if session.isTalking { return .talking }
        if session.isBusy { return .thinking }
        return session.messages.last?.speaker == .system ? .worried : .idle
    }

    private func send() {
        guard !session.isBusy, !draft.trimmed.isEmpty else { return }
        session.send(draft)
        draft = ""
    }
}

private struct CommandMenu: View {
    @ObservedObject var session: Session
    var canSend: Bool
    var send: () -> Void
    @ViewState private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.isBusy {
                item("STOP", index: 0, color: Theme.red, shortcut: ".", action: session.stop)
            } else {
                item("SEND", index: 0, color: canSend ? Theme.ice : Theme.dim, action: send)
            }
            if session.isTalking {
                item("SKIP", index: 1, action: session.skipTyping)
            }
            item("NEW GAME", index: 2, action: session.reset)
                .help("Start a fresh conversation in this tab")
        }
        .frame(width: 150, alignment: .leading)
        .frame(minHeight: 128, alignment: .center)
    }

    /// Items step rightward down the list, and the hovered one flips to a solid bar that slides out.
    private func item(_ title: String, index: Int, color: Color = Theme.ice, shortcut: KeyEquivalent? = nil,
                      action: @escaping () -> Void) -> some View {
        let isHovered = hovered == title
        return Button(action: action) {
            Text(title)
                .font(Theme.display(26))
                .foregroundStyle(isHovered ? Theme.navy : color)
                .padding(.horizontal, 14)
                .background(Slant(amount: 10).fill(isHovered ? Theme.ice : .clear))
                .shadow(color: Theme.cyan.opacity(isHovered ? 0 : 0.5), radius: 0, x: 2, y: 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: CGFloat(index) * 10 + (isHovered ? 8 : 0))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { hovered = $0 ? title : (hovered == title ? nil : hovered) }
        .modifier(OptionalShortcut(key: shortcut))
    }
}

private struct OptionalShortcut: ViewModifier {
    var key: KeyEquivalent?
    func body(content: Content) -> some View {
        if let key { content.keyboardShortcut(key, modifiers: .command) } else { content }
    }
}
