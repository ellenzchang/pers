import SwiftUI

/// Lets the input field page the message log, since the log never has keyboard focus.
@MainActor
final class LogScroller: ObservableObject {
    @Published var position = ScrollPosition(edge: .bottom)
    // Not published: it changes on every scroll frame and only matters when paging.
    var geometry: ScrollGeometry?

    func page(_ direction: CGFloat) {
        guard let geometry else { return }
        let maxY = max(geometry.contentSize.height - geometry.containerSize.height, 0)
        let y = min(max(geometry.contentOffset.y + direction * geometry.containerSize.height / 2, 0), maxY)
        withAnimation(.easeOut(duration: 0.15)) { position.scrollTo(y: y) }
    }
}

struct MessageLog: View {
    @ObservedObject var session: Session
    @ObservedObject var scroller: LogScroller

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
            .scrollPosition($scroller.position)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { scroller.geometry = $1 }
            .onChange(of: session.messages.count) { scrollDown(proxy) }
            .onChange(of: session.revealed) { scrollDown(proxy, animated: false) }
            .onAppear { scrollDown(proxy, animated: false) }
        }
        .overlay(alignment: .trailing) {
            if let prompt = session.prompt {
                PermissionBox(session: session, prompt: prompt)
                    .id(prompt.step)
                    .padding(.trailing, 28)
                    .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: session.prompt?.step)
        .overlay {
            if session.showingRecap {
                RecapOverlay(session: session)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.showingRecap)
    }

    private func scrollDown(_ proxy: ScrollViewProxy, animated: Bool = true) {
        withAnimation(animated ? .easeOut(duration: 0.2) : nil) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

private struct RecapOverlay: View {
    @ObservedObject var session: Session

    var body: some View {
        ZStack {
            Theme.deep.opacity(0.82)
                .contentShape(Rectangle())
                .onTapGesture(perform: session.dismissRecap)
            VStack(alignment: .leading, spacing: -8) {
                NamePlate(name: "RECAP", color: Theme.cyan)
                    .padding(.horizontal, 18)
                    .zIndex(1)
                Group {
                    if let recap = session.recap {
                        Text(recap)
                            .font(Theme.body)
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                    } else {
                        Text("Recalling…")
                            .font(Theme.body)
                            .foregroundStyle(Theme.dim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .panel(padding: 18)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 620)
            .padding(24)
        }
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
        case .user where text.hasPrefix("!"):
            toolRow(name: "BASH", detail: text.dropFirst().trimmed, trailing: true)
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
            toolRow(name: parts.first?.uppercased() ?? "TOOL", detail: parts.count > 1 ? parts[1] : nil)
        case .shell:
            CodeBlock(language: "shell", code: text)
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

    private func toolRow(name: String, detail: String?, trailing: Bool = false) -> some View {
        let tag = Text(name)
            .font(Theme.ui(13, weight: .black))
            .foregroundStyle(Theme.navy)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(Slant(amount: 7).fill(Theme.cyan))
        let command = detail.map {
            Text($0)
                .font(Theme.code)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        return HStack(alignment: .center, spacing: 10) {
            if trailing {
                Spacer(minLength: 100)
                command
                tag
            } else {
                tag
                command
            }
        }
        .padding(trailing ? .trailing : .leading, 18)
        .textSelection(.enabled)
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
    var scroller: LogScroller
    @FocusState private var focused: Bool
    @ViewState private var historyIndex: Int?
    @ViewState private var stashedDraft = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(spacing: -6) {
                // The bust is taller than its layout slot so it rises over the log, like a VN character.
                Portrait(mood: mood, outfit: session.outfit)
                    .frame(width: 210, height: 248)
                    .frame(width: 210, height: 150, alignment: .bottom)
                    .allowsHitTesting(false)
                NamePlate(name: "CLAUDE", morphing: true)
            }

            VStack(alignment: .leading, spacing: -8) {
                NamePlate(name: heading,
                          color: isShell ? Theme.gold : Theme.cyan, shadowColor: Theme.ocean, morphing: true)
                    .padding(.horizontal, 18)
                    .zIndex(1)
                ZStack(alignment: .topLeading) {
                    if session.draft.isEmpty {
                        Text("Speak to Claude…  (⏎ send · ⇧⏎ newline · ! shell)")
                            .font(Theme.body)
                            .foregroundStyle(Theme.dim)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $session.draft)
                        .font(isShell ? .system(size: 14, design: .monospaced) : Theme.body)
                        .foregroundStyle(isShell ? Theme.gold : Theme.text)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.shift) { return .ignored }
                            send()
                            return .handled
                        }
                        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                            let up = press.key == .upArrow
                            if press.modifiers.contains(.shift) {
                                scroller.page(up ? -1 : 1)
                                return .handled
                            }
                            return up ? olderHistory() : newerHistory()
                        }
                        .onChange(of: session.draft) {
                            if let historyIndex, session.draft != session.inputHistory[historyIndex] { self.historyIndex = nil }
                        }
                }
                .padding(.top, 8)
                .frame(height: 112)
                .background(Theme.codeBackground.opacity(isShell ? 0.9 : 0))
                .panel(accent: isShell ? Theme.gold : Theme.cyan, padding: 16, morphing: true)
                .overlay(alignment: .bottomTrailing) { logButton.padding(10) }
                .animation(.easeOut(duration: 0.15), value: isShell)
            }

            CommandMenu(session: session, canSend: !session.draft.trimmed.isEmpty, send: send)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .padding(.top, 6)
        .background(LinearGradient(colors: [.clear, Theme.deep.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        .onAppear { focused = true }
        .onTapGesture { if session.isTalking { session.skipTyping() } }
    }

    private var logButton: some View {
        Button {
            session.showingRecap ? session.dismissRecap() : session.requestRecap()
        } label: {
            Chip(active: session.showingRecap) { Text("LOG") }
        }
        .buttonStyle(.plain)
        .disabled(session.messages.isEmpty || session.isBusy)
        .opacity(session.messages.isEmpty || session.isBusy ? 0.4 : 1)
        .help("Recap this session so far")
    }

    private var heading: String {
        if isAnswering { return "YOUR ANSWER" }
        if session.isBusy { return "CLAUDE IS THINKING…" }
        if let historyIndex { return "HISTORY \(historyIndex + 1)/\(session.inputHistory.count)" }
        return isShell ? "SHELL COMMAND" : "WHAT WILL YOU DO?"
    }

    /// Arrow keys only recall history while they'd have nowhere to move the cursor: a single-line draft,
    /// or an untouched recalled entry.
    private var canBrowseHistory: Bool {
        historyIndex != nil || !session.draft.contains("\n")
    }

    private func olderHistory() -> KeyPress.Result {
        let history = session.inputHistory
        guard canBrowseHistory, !history.isEmpty else { return .ignored }
        if let historyIndex {
            self.historyIndex = max(historyIndex - 1, 0)
        } else {
            stashedDraft = session.draft
            historyIndex = history.count - 1
        }
        session.draft = history[historyIndex!]
        return .handled
    }

    private func newerHistory() -> KeyPress.Result {
        guard let historyIndex else { return .ignored }
        if historyIndex < session.inputHistory.count - 1 {
            self.historyIndex = historyIndex + 1
            session.draft = session.inputHistory[historyIndex + 1]
        } else {
            self.historyIndex = nil
            session.draft = stashedDraft
        }
        return .handled
    }

    private var isShell: Bool { session.draft.hasPrefix("!") }
    private var isAnswering: Bool { session.prompt?.question != nil }

    private var mood: Mood {
        if session.isTalking { return .talking }
        if session.isBusy { return .thinking }
        return session.messages.last?.speaker == .system ? .worried : .idle
    }

    private func send() {
        guard !session.draft.trimmed.isEmpty else { return }
        if isAnswering {
            session.reply(session.draft.trimmed)
        } else if !session.isBusy {
            session.send(session.draft)
        } else {
            return
        }
        session.draft = ""
    }
}

private struct CommandMenu: View {
    @ObservedObject var session: Session
    var canSend: Bool
    var send: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !session.isBusy || session.prompt?.question != nil {
                MenuItem(title: "SEND", index: 0, color: canSend ? Theme.ice : Theme.dim, action: send)
            }
            if session.isBusy {
                MenuItem(title: "STOP", index: session.prompt?.question != nil ? 1 : 0, color: Theme.red, shortcut: ".", action: session.stop)
            }
            if session.isTalking {
                MenuItem(title: "SKIP", index: 1, action: session.skipTyping)
            }
            MenuItem(title: "NEW GAME", index: 2, action: session.reset)
                .help("Start a fresh conversation in this tab")
        }
        .frame(width: 150, alignment: .leading)
        .frame(minHeight: 128, alignment: .center)
    }
}

private struct PermissionBox: View {
    @ObservedObject var session: Session
    var prompt: PermissionPrompt

    var body: some View {
        VStack(alignment: .leading, spacing: -8) {
            NamePlate(name: title, color: Theme.gold, shadowColor: Theme.ocean)
                .padding(.horizontal, 18)
                .zIndex(1)
            VStack(alignment: .leading, spacing: 12) {
                if let question = prompt.question {
                    questionBody(question)
                } else {
                    permissionBody
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .panel(accent: Theme.gold, padding: 18)
        }
        .frame(width: 300)
    }

    private var title: String {
        guard let question = prompt.question else { return "USE \(prompt.tool.uppercased())?" }
        let progress = prompt.questions.count > 1 ? "  \(prompt.answers.count + 1)/\(prompt.questions.count)" : ""
        return (question.header.isEmpty ? "QUESTION" : question.header.uppercased()) + progress
    }

    @ViewBuilder
    private func questionBody(_ question: PermissionPrompt.Question) -> some View {
        Text(question.text)
            .font(Theme.body)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                MenuItem(title: option.label.uppercased(), index: index) { session.reply(option.label) }
                    .help(option.description)
            }
        }
        Text("…or type your own answer below")
            .font(Theme.ui(12, weight: .bold))
            .foregroundStyle(Theme.dim)
    }

    @ViewBuilder
    private var permissionBody: some View {
        if !prompt.detail.isEmpty {
            Text(prompt.detail)
                .font(Theme.code)
                .foregroundStyle(Theme.dim)
                .lineLimit(4)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        VStack(alignment: .leading, spacing: 6) {
            MenuItem(title: "ALLOW", index: 0) { session.answer(prompt, allow: true) }
            if !prompt.suggestions.isEmpty {
                MenuItem(title: "ALWAYS", index: 1, color: Theme.aqua) { session.answer(prompt, allow: true, always: true) }
                    .help("Allow and remember this rule")
            }
            MenuItem(title: "DENY", index: 2, color: Theme.red) { session.answer(prompt, allow: false) }
        }
    }
}

/// Items step rightward down the list, and the hovered one flips to a solid bar that slides out.
private struct MenuItem: View {
    var title: String
    var index: Int
    var color: Color = Theme.ice
    var shortcut: KeyEquivalent?
    var action: () -> Void
    @ViewState private var isHovered = false

    var body: some View {
        Button(action: action) {
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
        .onHover { isHovered = $0 }
        .modifier(OptionalShortcut(key: shortcut))
    }
}

private struct OptionalShortcut: ViewModifier {
    var key: KeyEquivalent?
    func body(content: Content) -> some View {
        if let key { content.keyboardShortcut(key, modifiers: .command) } else { content }
    }
}
