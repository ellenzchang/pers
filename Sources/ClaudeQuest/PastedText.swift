import Foundation

/// Long pastes sit in the draft as `[Pasted text #1 +42 lines]` and are swapped back for the text when sent, like in Claude Code.
extension Session {
    static let pasteThreshold = 800
    static let placeholderPattern = try! NSRegularExpression(pattern: "\\[Pasted text #(\\d+)( \\+\\d+ lines)?\\]")

    func pasted(_ text: String) -> String {
        guard text.count > Self.pasteThreshold else { return text }
        let id = (pastes.keys.max() ?? 0) + 1
        pastes[id] = text
        let lines = text.filter { $0 == "\n" }.count
        return "[Pasted text #\(id)\(lines > 0 ? " +\(lines) lines" : "")]"
    }

    var expandedDraft: String {
        let source = draft as NSString
        var result = draft
        for match in Self.placeholderPattern.matches(in: draft, range: NSRange(location: 0, length: source.length)).reversed() {
            guard let text = pastes[Int(source.substring(with: match.range(at: 1))) ?? 0], let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: text)
        }
        return result
    }
}
