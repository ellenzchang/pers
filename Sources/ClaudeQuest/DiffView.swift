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
                                DiffLine(text: AttributedString(ansi: line), selected: index == cursor) { session.quote($0) }
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
    var text: AttributedString
    var selected: Bool
    var onTap: (String) -> Void
    @ViewState private var hovering = false

    var body: some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering || selected ? Theme.cyan.opacity(0.2) : .clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { onTap(String(text.characters)) }
    }
}

private struct ANSIStyle {
    var foreground: Color?
    var background: Color?
    var bold = false
    var reverse = false

    private static let palette = [Theme.dim, Theme.red, Theme.green, Theme.gold,
                                  Color(hex: 0x5C8DFF), Theme.pink, Theme.aqua, Theme.text]

    mutating func apply(_ params: Substring) {
        let codes = params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var index = 0
        while index < codes.count {
            let code = codes[index]
            index += 1
            switch code {
            case 0: self = ANSIStyle()
            case 1: bold = true
            case 22: bold = false
            case 7: reverse = true
            case 27: reverse = false
            case 30...37: foreground = Self.palette[code - 30]
            case 90...97: foreground = Self.palette[code - 90]
            case 39: foreground = nil
            case 40...47: background = Self.palette[code - 40]
            case 100...107: background = Self.palette[code - 100]
            case 49: background = nil
            case 38, 48:
                let color = Self.extendedColor(codes, from: &index)
                if code == 38 { foreground = color } else { background = color }
            default: break
            }
        }
    }

    private static func extendedColor(_ codes: [Int], from index: inout Int) -> Color? {
        guard index < codes.count else { return nil }
        let mode = codes[index]
        index += 1
        if mode == 2, index + 2 < codes.count {
            defer { index += 3 }
            return Color(red: Double(codes[index]) / 255, green: Double(codes[index + 1]) / 255, blue: Double(codes[index + 2]) / 255)
        }
        guard mode == 5, index < codes.count else { return nil }
        let n = codes[index]
        index += 1
        switch n {
        case 0..<16: return palette[n % 8]
        case 16..<232:
            let level = { (v: Int) in v == 0 ? 0 : Double(55 + v * 40) / 255 }
            return Color(red: level((n - 16) / 36), green: level((n - 16) / 6 % 6), blue: level((n - 16) % 6))
        default:
            let gray = Double(8 + (n - 232) * 10) / 255
            return Color(red: gray, green: gray, blue: gray)
        }
    }

    func attributes() -> AttributeContainer {
        var container = AttributeContainer()
        let foreground = foreground ?? Theme.text
        container.font = bold ? Theme.code.bold() : Theme.code
        container.foregroundColor = reverse ? background ?? Theme.codeBackground : foreground
        container.backgroundColor = reverse ? foreground : background
        return container
    }
}

extension AttributedString {
    init(ansi line: Substring) {
        self.init()
        var style = ANSIStyle()
        var rest = line
        func append(_ text: Substring) {
            guard !text.isEmpty else { return }
            var chunk = AttributedString(text)
            chunk.setAttributes(style.attributes())
            self.append(chunk)
        }
        while let escape = rest.range(of: "\u{1B}[") {
            append(rest[..<escape.lowerBound])
            rest = rest[escape.upperBound...]
            let params = rest.prefix { $0.isNumber || $0 == ";" }
            rest = rest.dropFirst(params.count)
            guard let final = rest.first else { break }
            rest = rest.dropFirst()
            if final == "m" { style.apply(params) }
        }
        append(rest)
        if characters.isEmpty { append(" ") }
    }
}
