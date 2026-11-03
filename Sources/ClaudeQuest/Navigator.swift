import SwiftUI

/// Vim-style keyboard cursor over the diff and the message log, driven from the input field since it never loses focus.
@MainActor
final class Navigator: ObservableObject {
    @Published var active = false {
        didSet { if !active { disarm(); newMessage = false } }
    }
    @Published var messageId: ChatMessage.ID? {
        didSet { disarm() }
    }
    @Published var forkArmed = false
    @Published var yankArmed = false
    @Published var newMessage = false
    @Published var promptIndex = 0
    @Published var typingAnswer = false
    @Published var diffLine = 0 {
        didSet { disarm() }
    }
    @Published var commitIndex = 0
    @Published var diffPath: String? {
        didSet { diffLine = 0 }
    }

    var armedKey: String? {
        forkArmed ? "f" : yankArmed ? "y" : nil
    }

    func disarm() {
        forkArmed = false
        yankArmed = false
    }

    func file(in diff: [FileDiff]) -> FileDiff? {
        diff.first { $0.path == diffPath } ?? diff.first
    }

    func line(in diff: [FileDiff]) -> Int {
        min(diffLine, max((file(in: diff)?.lines.count ?? 1) - 1, 0))
    }

    func moveLine(by delta: Int, in diff: [FileDiff]) {
        setLine(line(in: diff) + delta, in: diff)
    }

    func setLine(_ line: Int, in diff: [FileDiff]) {
        let last = max((file(in: diff)?.lines.count ?? 1) - 1, 0)
        diffLine = min(max(line, 0), last)
    }

    /// Diff keys work both from the input field in NAVIGATE mode and from the focused diff itself.
    func navigateDiff(_ press: KeyPress, in session: Session) -> Bool {
        let diff = session.diff
        let file = file(in: diff)
        let row = file?.lines.indices.contains(line(in: diff)) == true ? file?.lines[line(in: diff)] : nil
        switch (press.key, press.characters) {
        case (.downArrow, _), (_, "j"): moveLine(by: 1, in: diff)
        case (.upArrow, _), (_, "k"): moveLine(by: -1, in: diff)
        case (_, "g"): setLine(0, in: diff)
        case (_, "G"): setLine(.max, in: diff)
        case (_, "J"): moveFile(by: 1, in: diff)
        case (_, "K"): moveFile(by: -1, in: diff)
        case (_, "y") where press.phase == .down:
            guard let row else { break }
            if yankArmed {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.text, forType: .string)
                disarm()
            } else {
                disarm()
                yankArmed = true
            }
        case (.return, _):
            if let file, let row { session.quote(row, in: file) }
        default: return false
        }
        return true
    }

    func commit(in commits: [Commit]) -> Int {
        min(commitIndex, max(commits.count - 1, 0))
    }

    func navigateLog(_ press: KeyPress, in commits: [Commit]) {
        switch (press.key, press.characters) {
        case (.downArrow, _), (_, "j"): commitIndex = min(commit(in: commits) + 1, max(commits.count - 1, 0))
        case (.upArrow, _), (_, "k"): commitIndex = max(commit(in: commits) - 1, 0)
        case (_, "g"): commitIndex = 0
        case (_, "G"): commitIndex = max(commits.count - 1, 0)
        default: break
        }
    }

    func moveFile(by delta: Int, in diff: [FileDiff]) {
        guard let index = diff.firstIndex(where: { $0.id == file(in: diff)?.id }) else { return }
        diffPath = diff[min(max(index + delta, 0), diff.count - 1)].id
    }

    func message(in messages: [ChatMessage]) -> ChatMessage? {
        messages.first { $0.id == messageId } ?? messages.last
    }

    func moveMessage(by delta: Int, in messages: [ChatMessage]) {
        guard let current = message(in: messages), let index = messages.firstIndex(of: current) else { return }
        messageId = messages[min(max(index + delta, 0), messages.count - 1)].id
    }

    func jumpToLatest(in messages: [ChatMessage]) {
        setMessage(.max, in: messages)
        newMessage = false
    }

    func setMessage(_ index: Int, in messages: [ChatMessage]) {
        messageId = messages.isEmpty ? nil : messages[min(max(index, 0), messages.count - 1)].id
    }
}

extension KeyPress {
    /// Arrow keys arrive flagged as numpad/function presses, so only real shortcut modifiers count; Shift+arrow is left for paging.
    var isPlain: Bool {
        let isArrow = [.upArrow, .downArrow, .leftArrow, .rightArrow].contains(key)
        return modifiers.isDisjoint(with: [.command, .control, .option]) && !(isArrow && modifiers.contains(.shift))
    }
}
