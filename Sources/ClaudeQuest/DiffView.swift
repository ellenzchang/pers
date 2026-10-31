import SwiftUI

struct DiffView: View {
    @ObservedObject var session: Session
    @ObservedObject var scroller: LogScroller
    @ObservedObject var navigator: Navigator
    @ViewState private var viewportWidth: CGFloat = 0

    private var current: FileDiff? { navigator.file(in: session.diff) }
    private var cursor: Int? { navigator.active ? navigator.line(in: session.diff) : nil }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 230)
            Group {
                if let current {
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(current.lines.enumerated()), id: \.offset) { index, line in
                                DiffLine(row: line, selected: index == cursor) { session.quote($0) }
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
                } else {
                    Text("No changes").font(Theme.ui(14)).foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.codeBackground)
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
            }
            .frame(width: 150)
            .background(Theme.deep.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiffLine: View {
    var row: DiffRow
    var selected: Bool
    var onTap: (String) -> Void
    @ViewState private var hovering = false

    private static let hunkColor = Color(hex: 0x5C8DFF)

    private var tint: Color? {
        switch row.kind {
        case .added: Theme.green
        case .removed: Theme.red
        case .hunk: Self.hunkColor
        case .context: nil
        }
    }

    private var marker: String {
        switch row.kind {
        case .added: "+"
        case .removed: "-"
        case .hunk, .context: " "
        }
    }

    private var code: AttributedString {
        var text = AttributedString(row.text.isEmpty ? " " : row.text)
        text.font = Theme.code
        text.foregroundColor = row.kind == .hunk ? Theme.dim : Theme.text
        if let changed = row.changed, !changed.isEmpty, let tint {
            let start = text.index(text.startIndex, offsetByCharacters: changed.lowerBound)
            let end = text.index(start, offsetByCharacters: changed.count)
            text[start..<end].backgroundColor = tint.opacity(0.4)
        }
        return text
    }

    var body: some View {
        HStack(spacing: 0) {
            gutter(row.oldNumber)
            gutter(row.newNumber)
            Text(marker).font(Theme.code).foregroundStyle(tint ?? Theme.dim).frame(width: 18)
            Text(code).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(hovering || selected ? Theme.cyan.opacity(0.2) : .clear)
        .background(tint?.opacity(row.kind == .hunk ? 0.12 : 0.15) ?? .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onTap(row.text) }
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
