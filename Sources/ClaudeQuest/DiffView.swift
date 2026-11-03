import SwiftUI

struct DiffView: View {
    @ObservedObject var session: Session
    @ObservedObject var scroller: LogScroller
    @ObservedObject var navigator: Navigator
    @ViewState private var viewportWidth: CGFloat = 0
    @FocusState private var focused: Bool

    private var current: FileDiff? { navigator.file(in: session.diff) }
    private var cursor: Int? { navigator.active || focused ? navigator.line(in: session.diff) : nil }

    private var lineHints: [(key: String, action: String)] {
        [("j k", "line"), ("g G", "top/end"), ("⏎", "quote"), ("y", navigator.yankArmed ? "again to copy this line" : "copy")]
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: SessionOverview.reservedWidth)
            Group {
                if let current {
                    VStack(spacing: 0) {
                        DiffHeader(file: current)
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(current.lines.enumerated()), id: \.offset) { index, line in
                                    DiffLine(row: line, selected: index == cursor, pinned: session.isQuoted(line, in: current),
                                             hints: index == cursor ? lineHints : [], armedKey: navigator.armedKey) {
                                        focused = true
                                        navigator.setLine(index, in: session.diff)
                                        session.quote(line, in: current)
                                    }
                                }
                            }
                            .scrollTargetLayout()
                            .frame(minWidth: viewportWidth - 24, alignment: .leading)
                            .padding(12)
                        }
                        .onScrollGeometryChange(for: CGFloat.self, of: { $0.containerSize.width }) { viewportWidth = $1 }
                        .scrollPosition($scroller.position)
                        .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { scroller.geometry = $1 }
                        .id(current.id)
                    }
                } else {
                    Text("No changes").font(Theme.ui(14)).foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.codeBackground)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(phases: [.down, .repeat]) { press in
                press.isPlain && navigator.navigateDiff(press, in: session) ? .handled : .ignored
            }
            .onAppear { scroller.position.scrollTo(x: 0, y: 0) }
            .onChange(of: current?.id) { scroller.position.scrollTo(x: 0, y: 0) }
            .onChange(of: navigator.diffLine) { scroller.position.scrollTo(id: navigator.line(in: session.diff)) }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(session.diff) { file in
                        Button { navigator.diffPath = file.id } label: {
                            Chip(active: file.id == current?.id, color: Theme.cyan) {
                                Text((file.path as NSString).lastPathComponent).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(file.path)
                    }
                }
                .padding(8)
                .padding(.bottom, 24)
            }
            .frame(width: 240)
            .background(Theme.deep.opacity(0.6))
            .overlay(alignment: .bottomTrailing) {
                if cursor != nil {
                    KeyHints(hints: [("J K", "file"), ("⌘O", "IntelliJ")])
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Slant(amount: 6).fill(Theme.deep.opacity(0.9)))
                        .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiffHeader: View {
    var file: FileDiff

    var body: some View {
        let directory = (file.path as NSString).deletingLastPathComponent
        HStack(spacing: 0) {
            Text(directory.isEmpty ? "" : directory + "/").foregroundStyle(Theme.dim)
            Text((file.path as NSString).lastPathComponent).foregroundStyle(Theme.text)
            Spacer()
            Text("+\(file.added)").foregroundStyle(Theme.green)
            Text("  \u{2212}\(file.removed)").foregroundStyle(Theme.red)
        }
        .font(Theme.code)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.deep.opacity(0.6))
    }
}

struct DiffLine: View {
    var row: DiffRow
    var numbered = true
    var selected: Bool
    var pinned: Bool
    var hints: [(key: String, action: String)] = []
    var armedKey: String?
    var onTap: () -> Void
    @ViewState private var hovering = false

    private static let hunkColor = Color(hex: 0x5C8DFF)

    private var tint: Color? {
        switch row.kind {
        case .added: Theme.green
        case .removed: Theme.red
        case .modified: Theme.gold
        case .hunk: Self.hunkColor
        case .context: nil
        }
    }

    private var code: AttributedString {
        var text = switch row.kind {
        case .hunk: AttributedString(row.text)
        default: row.highlighted ?? SyntaxHighlighter.highlight(row.text)
        }
        if row.text.isEmpty { text = AttributedString(" ") }
        text.font = Theme.code
        if row.kind == .hunk { text.foregroundColor = Self.hunkColor }
        let wordTint = row.kind == .modified ? Theme.green : tint
        if let wordTint {
            for changed in row.changed {
                let start = text.index(text.startIndex, offsetByCharacters: changed.lowerBound)
                let end = text.index(start, offsetByCharacters: changed.count)
                text[start..<end].backgroundColor = wordTint.opacity(0.4)
            }
        }
        return row.kind == .modified ? withRemovals(in: text) : text
    }

    private func withRemovals(in text: AttributedString) -> AttributedString {
        func slice(_ range: Range<Int>) -> AttributedString {
            let start = text.index(text.startIndex, offsetByCharacters: range.lowerBound)
            return AttributedString(text[start..<text.index(start, offsetByCharacters: range.count)])
        }
        var result = AttributedString()
        var position = 0
        for removal in row.removals {
            var removed = AttributedString(removal.text)
            removed.font = Theme.code
            removed.foregroundColor = Theme.red
            removed.backgroundColor = Theme.red.opacity(0.4)
            removed.strikethroughStyle = .single
            result += slice(position..<removal.offset) + removed
            position = removal.offset
        }
        return result + slice(position..<text.characters.count)
    }

    var body: some View {
        HStack(spacing: 0) {
            if numbered {
                gutter(row.oldNumber)
                gutter(row.newNumber)
            }
            Text(code).padding(.leading, 8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(hovering || selected ? Theme.cyan.opacity(0.2) : .clear)
        .background(tint?.opacity(row.kind == .hunk ? 0.12 : 0.15) ?? .clear)
        .overlay(alignment: .leading) { if pinned { Theme.gold.frame(width: 3) } }
        .overlay(alignment: .trailing) {
            if !hints.isEmpty {
                KeyHints(hints: hints, highlighted: armedKey)
                    .padding(.horizontal, 10)
                    .background(Slant(amount: 6).fill(Theme.deep.opacity(0.9)))
                    .padding(.trailing, 6)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(Theme.code)
            .foregroundStyle(Theme.dim)
            .frame(width: 52, alignment: .trailing)
            .padding(.trailing, 6)
            .background((tint ?? .clear).opacity(row.kind == .hunk ? 0 : 0.2))
    }
}
