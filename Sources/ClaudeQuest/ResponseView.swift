import SwiftUI

/// One line of a response body: a JSON node, or a plain line when the body isn't JSON.
struct ResponseRow: Identifiable {
    enum Kind { case object, array, string, number, bool, null, text }

    var path: [String]
    var key: String?
    var value: String
    var kind: Kind
    let id: String

    init(path: [String], key: String?, value: String, kind: Kind) {
        self.path = path
        self.key = key
        self.value = value
        self.kind = kind
        id = Self.id(of: path)
    }

    var depth: Int { kind == .text ? 0 : path.count }
    var isContainer: Bool { kind == .object || kind == .array }

    static func id(of path: some Sequence<String>) -> String { path.joined(separator: "\u{1F}") }

    func matches(_ query: String) -> Bool {
        key?.range(of: query, options: .caseInsensitive) != nil || (!isContainer && value.range(of: query, options: .caseInsensitive) != nil)
    }

    static func make(from body: String) -> [ResponseRow] {
        guard !body.isEmpty else { return [] }
        var reader = JSONReader(body)
        guard let json = reader.parse() else {
            return body.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map {
                ResponseRow(path: [String($0.offset)], key: nil, value: String($0.element), kind: .text)
            }
        }
        var rows: [ResponseRow] = []
        json.flatten(key: nil, path: [], into: &rows)
        return rows
    }
}

/// `JSONSerialization` returns dictionaries, which lose the order the API sent its keys in.
private indirect enum JSONValue {
    case object([(key: String, value: JSONValue)])
    case array([JSONValue])
    case scalar(String, ResponseRow.Kind)

    func flatten(key: String?, path: [String], into rows: inout [ResponseRow]) {
        switch self {
        case .object(let members):
            rows.append(ResponseRow(path: path, key: key, value: "{\(members.count)}", kind: .object))
            for member in members { member.value.flatten(key: member.key, path: path + [member.key], into: &rows) }
        case .array(let items):
            rows.append(ResponseRow(path: path, key: key, value: "[\(items.count)]", kind: .array))
            for (index, item) in items.enumerated() { item.flatten(key: String(index), path: path + [String(index)], into: &rows) }
        case .scalar(let text, let kind):
            rows.append(ResponseRow(path: path, key: key, value: text, kind: kind))
        }
    }
}

private struct JSONReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ text: String) { bytes = Array(text.utf8) }

    private var next: Character? { index < bytes.count ? Character(UnicodeScalar(bytes[index])) : nil }

    mutating func parse() -> JSONValue? {
        guard let value = value() else { return nil }
        skipSpace()
        return index == bytes.count ? value : nil
    }

    private mutating func value() -> JSONValue? {
        skipSpace()
        switch next {
        case "{": return members()
        case "[": return items()
        case "\"": return string().map { .scalar("\"\($0)\"", .string) }
        case nil: return nil
        default: return literal()
        }
    }

    private mutating func members() -> JSONValue? {
        index += 1
        var members: [(key: String, value: JSONValue)] = []
        skipSpace()
        if take("}") { return .object(members) }
        repeat {
            skipSpace()
            guard next == "\"", let key = string() else { return nil }
            skipSpace()
            guard take(":"), let value = value() else { return nil }
            members.append((key, value))
            skipSpace()
        } while take(",")
        return take("}") ? .object(members) : nil
    }

    private mutating func items() -> JSONValue? {
        index += 1
        var items: [JSONValue] = []
        skipSpace()
        if take("]") { return .array(items) }
        repeat {
            guard let item = value() else { return nil }
            items.append(item)
            skipSpace()
        } while take(",")
        return take("]") ? .array(items) : nil
    }

    /// Finds the closing quote and lets `JSONSerialization` decode the escapes.
    private mutating func string() -> String? {
        let start = index
        index += 1
        while let character = next, character != "\"" { index += character == "\\" ? 2 : 1 }
        guard index < bytes.count else { return nil }
        index += 1
        return (try? JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: .fragmentsAllowed)) as? String
    }

    private mutating func literal() -> JSONValue? {
        let start = index
        while let character = next, !",]} \n\r\t".contains(character) { index += 1 }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        switch text {
        case "true", "false": return .scalar(text, .bool)
        case "null": return .scalar(text, .null)
        default: return Double(text) == nil ? nil : .scalar(text, .number)
        }
    }

    private mutating func skipSpace() {
        while let character = next, " \n\r\t".contains(character) { index += 1 }
    }

    private mutating func take(_ character: Character) -> Bool {
        guard next == character else { return false }
        index += 1
        return true
    }
}

/// The cursor, folds and search of the response on show, driven from the page's key handler.
@MainActor
final class ResponseBrowser: ObservableObject {
    @Published private(set) var visible: [ResponseRow] = []
    @Published private(set) var matches: [ResponseRow] = []
    @Published private(set) var matchIndex = 0
    @Published private(set) var collapsed: Set<String> = [] { didSet { updateVisible() } }
    @Published var cursor: String?
    @Published var showingHeaders = false
    @Published var query = "" { didSet { search() } }

    private var rows: [ResponseRow] = []
    private var shownId: UUID?

    var currentMatch: ResponseRow? { matches.indices.contains(matchIndex) ? matches[matchIndex] : nil }
    private var current: ResponseRow? { visible.first { $0.id == cursor } }

    func show(_ response: APIResponse?) {
        guard response?.id != shownId else { return }
        shownId = response?.id
        rows = response?.rows ?? []
        collapsed = []
        query = ""
        cursor = rows.first?.id
    }

    func move(by offset: Int) {
        guard !visible.isEmpty else { return }
        let index = visible.firstIndex { $0.id == cursor } ?? 0
        cursor = visible[min(max(index + offset, 0), visible.count - 1)].id
    }

    func moveToEdge(end: Bool) {
        cursor = (end ? visible.last : visible.first)?.id
    }

    func toggle() {
        guard let row = current, row.isContainer else { return }
        if collapsed.contains(row.id) { collapsed.remove(row.id) } else { collapsed.insert(row.id) }
    }

    func expand() {
        if let row = current { collapsed.remove(row.id) }
    }

    /// Folds an open node; on a closed node or a leaf it goes up to the parent instead.
    func collapse() {
        guard let row = current else { return }
        if row.isContainer && !collapsed.contains(row.id) {
            collapsed.insert(row.id)
        } else if row.kind != .text, !row.path.isEmpty {
            cursor = ResponseRow.id(of: row.path.dropLast())
        }
    }

    func expandAll() {
        collapsed = []
    }

    func collapseAll() {
        collapsed = Set(rows.filter { $0.isContainer && $0.depth > 0 }.map(\.id))
        cursor = visible.first?.id
    }

    func nextMatch(by offset: Int) {
        guard !matches.isEmpty else { return }
        reveal(at: (matchIndex + offset + matches.count) % matches.count)
    }

    private func search() {
        matches = query.isEmpty ? [] : rows.filter { $0.matches(query) }
        if !matches.isEmpty { reveal(at: 0) }
    }

    /// Opens the folds above a match so it can be seen.
    private func reveal(at index: Int) {
        matchIndex = index
        let row = matches[index]
        collapsed.subtract((0..<row.path.count).map { ResponseRow.id(of: row.path.prefix($0)) })
        cursor = row.id
    }

    private func updateVisible() {
        var hiddenBelow: Int?
        visible = rows.filter { row in
            if let depth = hiddenBelow {
                if row.depth > depth { return false }
                hiddenBelow = nil
            }
            if row.isContainer && collapsed.contains(row.id) { hiddenBelow = row.depth }
            return true
        }
    }
}

struct ResponseView: View {
    var response: APIResponse
    @ObservedObject var browser: ResponseBrowser
    var selected: Bool
    var focus: FocusState<RequestField?>.Binding
    var browse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summary
            search
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let error = response.error { Text(error).foregroundStyle(Theme.red) }
                        if browser.showingHeaders {
                            Text(response.headers.joined(separator: "\n"))
                                .foregroundStyle(Theme.dim)
                                .textSelection(.enabled)
                        }
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(browser.visible) { row in
                                ResponseRowView(row: row, collapsed: browser.collapsed.contains(row.id), query: browser.query,
                                                isCurrentMatch: browser.currentMatch?.id == row.id,
                                                isSelected: browser.cursor == row.id, isActive: selected)
                                    .id(row.id)
                                    .onTapGesture {
                                        browser.cursor = row.id
                                        browser.toggle()
                                        browse()
                                    }
                            }
                        }
                    }
                    .font(Theme.code)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .onChange(of: browser.cursor) {
                    if let id = browser.cursor { proxy.scrollTo(id) }
                }
            }
            .background(Theme.codeBackground)
        }
        .frame(maxHeight: .infinity)
        .panel(accent: response.color, padding: 18, selected: selected, opacity: 1)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            if let status = response.status {
                Chip(active: true, color: response.color) {
                    Text("\(status) \(HTTPURLResponse.localizedString(forStatusCode: status).uppercased())")
                }
            } else {
                Chip(color: Theme.red) { Text("FAILED") }
            }
            Text(response.duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))
            Text(ByteCountFormatter.string(fromByteCount: Int64(response.size), countStyle: .file))
            Spacer(minLength: 0)
            if !response.headers.isEmpty {
                Button { browser.showingHeaders.toggle() } label: {
                    Chip(active: browser.showingHeaders, color: Theme.ice) { Text("HEADERS \(response.headers.count)") }
                }
                .buttonStyle(.plain)
            }
        }
        .font(Theme.ui(12, weight: .bold))
        .foregroundStyle(Theme.dim)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Text("/").foregroundStyle(Theme.gold)
            TextField("search the response", text: $browser.query)
                .focused(focus, equals: .search)
                .onSubmit(browse)
            if !browser.query.isEmpty {
                Text(browser.matches.isEmpty ? "no matches" : "\(browser.matchIndex + 1)/\(browser.matches.count)")
                    .font(Theme.ui(12, weight: .bold))
                    .foregroundStyle(browser.matches.isEmpty ? Theme.red : Theme.dim)
            }
        }
        .fieldStyle()
    }
}

private struct ResponseRowView: View {
    var row: ResponseRow
    var collapsed: Bool
    var query: String
    var isCurrentMatch: Bool
    var isSelected: Bool
    var isActive: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Color.clear.frame(width: CGFloat(row.depth) * 16, height: 1)
            Text(row.isContainer ? (collapsed ? "▸" : "▾") : " ")
                .foregroundStyle(Theme.dim)
                .frame(width: 12)
            Text(line)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.cyan.opacity(isActive ? 0.25 : 0.1) : .clear)
        .contentShape(Rectangle())
    }

    private var line: AttributedString {
        var line = AttributedString()
        if let key = row.key {
            line += highlighted(key, color: Theme.cyan)
            line += highlighted(row.isContainer ? " " : ": ", color: Theme.dim, searching: false)
        }
        return line + highlighted(row.value, color: row.kind.color, searching: !row.isContainer)
    }

    private func highlighted(_ text: String, color: Color, searching: Bool = true) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = color
        guard searching, !query.isEmpty else { return result }
        var start = result.startIndex
        while let range = result[start...].range(of: query, options: .caseInsensitive) {
            result[range].backgroundColor = Theme.gold.opacity(isCurrentMatch ? 1 : 0.45)
            result[range].foregroundColor = Theme.navy
            start = range.upperBound
        }
        return result
    }
}

private extension ResponseRow.Kind {
    var color: Color {
        switch self {
        case .string: Theme.green
        case .number: Theme.gold
        case .bool, .null: Theme.pink
        case .object, .array: Theme.dim
        case .text: Theme.text
        }
    }
}
