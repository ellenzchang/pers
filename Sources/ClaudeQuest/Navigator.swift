import SwiftUI

/// Vim-style keyboard cursor over the diff and the command menu, driven from the input field since it never loses focus.
@MainActor
final class Navigator: ObservableObject {
    enum Zone { case diff, menu }

    @Published var active = false
    @Published var zone = Zone.menu
    @Published var menuIndex = 0
    @Published var promptIndex = 0
    @Published var typingAnswer = false
    @Published var diffLine = 0
    @Published var diffPath: String? {
        didSet { diffLine = 0 }
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

    func moveFile(by delta: Int, in diff: [FileDiff]) {
        guard let index = diff.firstIndex(where: { $0.id == file(in: diff)?.id }) else { return }
        diffPath = diff[min(max(index + delta, 0), diff.count - 1)].id
    }

    func moveMenu(by delta: Int, count: Int) {
        menuIndex = min(max(min(menuIndex, count - 1) + delta, 0), count - 1)
    }
}
