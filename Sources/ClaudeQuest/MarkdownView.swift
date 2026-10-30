import SwiftUI
import AppKit

struct MarkdownView: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.segments(of: text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .prose(let prose):
                    Text(Self.inline(prose))
                        .font(Theme.body)
                        .foregroundStyle(Theme.text)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let language, let code):
                    CodeBlock(language: language, code: code)
                }
            }
        }
        .textSelection(.enabled)
    }

    enum Segment {
        case prose(String)
        case code(language: String, code: String)
    }

    /// Splits on ``` fences; an unterminated fence (mid-typewriter) still renders as code.
    static func segments(of text: String) -> [Segment] {
        var result: [Segment] = []
        var prose: [Substring] = []
        var code: [Substring]?
        var language = ""

        func flushProse() {
            let joined = prose.joined(separator: "\n").trimmed
            if !joined.isEmpty { result.append(.prose(joined)) }
            prose = []
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let lines = code {
                    result.append(.code(language: language, code: lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flushProse()
                    language = line.trimmingCharacters(in: .whitespaces).dropFirst(3).trimmed
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else {
                prose.append(line)
            }
        }
        if let code { result.append(.code(language: language, code: code.joined(separator: "\n"))) }
        flushProse()
        return result
    }

    static func inline(_ prose: String) -> AttributedString {
        let headed = prose.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            guard line.hasPrefix("#") else { return String(line) }
            return "**\(line.drop { $0 == "#" }.trimmed)**"
        }.joined(separator: "\n")
        var attributed = (try? AttributedString(markdown: headed, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(prose)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].foregroundColor = Theme.cyan
            attributed[run.range].font = Theme.code
        }
        for run in attributed.runs where run.link != nil {
            attributed[run.range].foregroundColor = Theme.gold
        }
        return attributed
    }
}

struct CodeBlock: View {
    var language: String
    var code: String
    @ViewState private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "CODE" : language.uppercased())
                    .font(Theme.ui(10))
                    .foregroundStyle(Theme.dim)
                Spacer()
                Button(copied ? "COPIED!" : "COPY") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                .buttonStyle(.plain)
                .font(Theme.ui(10))
                .foregroundStyle(copied ? Theme.aqua : Theme.cyan)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.cyan.opacity(0.08))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code))
                    .font(Theme.code)
                    .lineSpacing(2)
                    .padding(10)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .background(Theme.codeBackground)
        .overlay(Rectangle().strokeBorder(Theme.cyan.opacity(0.35), lineWidth: 1.5))
    }
}

/// Language-agnostic highlighting: good enough for a chat log, not a parser.
enum SyntaxHighlighter {
    private static let keywords = Set("""
    func let var if else for while return import class struct enum case switch break continue in guard
    def elif try except finally with as from lambda yield async await const function new this self
    public private protected static final void int long bool boolean string fn mut pub use impl match
    interface type package extends implements throws throw true false nil null None True False do then fi
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    private static let pattern = try! NSRegularExpression(pattern: #"""
    (?<comment>//[^\n]*|#(?![!{])[^\n]*|/\*[\s\S]*?\*/)|(?<string>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`[^`]*`)|(?<number>\b\d+(?:\.\d+)?\b)|(?<word>\b[A-Za-z_][A-Za-z0-9_]*\b)
    """#)

    static func highlight(_ code: String) -> AttributedString {
        var result = AttributedString(code)
        result.foregroundColor = Color(hex: 0xD6E8FF)
        let ns = code as NSString
        for match in pattern.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
            let color: Color
            if match.range(withName: "comment").location != NSNotFound {
                color = Color(hex: 0x5B78A8)
            } else if match.range(withName: "string").location != NSNotFound {
                color = Theme.aqua
            } else if match.range(withName: "number").location != NSNotFound {
                color = Theme.gold
            } else {
                let word = ns.substring(with: match.range)
                if keywords.contains(word) { color = Theme.pink }
                else if word.first?.isUppercase == true { color = Theme.cyan }
                else { continue }
            }
            if let range = Range(match.range, in: code), let attributedRange = Range(range, in: result) {
                result[attributedRange].foregroundColor = color
            }
        }
        return result
    }
}
