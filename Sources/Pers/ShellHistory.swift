import Foundation

/// The user's zsh history, oldest first, for zsh-autosuggestions-style completion in terminal mode.
/// Reloaded only when the file changes, since the user's own terminals keep appending to it.
@MainActor
enum ShellHistory {
    private static let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".zsh_history")
    private static var cache: (modified: Date, commands: [String])?

    static var commands: [String] {
        guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              let data = try? Data(contentsOf: url) else { return [] }
        if let cache, cache.modified == modified { return cache.commands }
        let commands = parse(String(decoding: unmetafy(data), as: UTF8.self))
        cache = (modified, commands)
        return commands
    }

    /// Lines look like `: <time>:<duration>;<command>`, with a trailing backslash continuing a multi-line command.
    private static func parse(_ text: String) -> [String] {
        var commands: [String] = []
        var pending: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(line)
            if pending == nil, line.hasPrefix(": "), let semicolon = line.firstIndex(of: ";") {
                line = String(line[line.index(after: semicolon)...])
            }
            let continues = line.hasSuffix("\\")
            if continues { line.removeLast() }
            let command = pending.map { $0 + "\n" + line } ?? line
            pending = continues ? command : nil
            if !continues, !command.trimmed.isEmpty { commands.append(command) }
        }
        return commands
    }

    /// zsh escapes bytes 0x83–0xA2 in its history file as 0x83 followed by the byte XOR 32,
    /// which would otherwise garble non-ASCII text such as æøå.
    private static func unmetafy(_ data: Data) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(data.count)
        var escaped = false
        for byte in data {
            if escaped {
                bytes.append(byte ^ 32)
                escaped = false
            } else if byte == 0x83 {
                escaped = true
            } else {
                bytes.append(byte)
            }
        }
        return Data(bytes)
    }
}
