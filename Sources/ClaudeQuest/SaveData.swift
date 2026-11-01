import Foundation

struct SavedSession: Identifiable {
    var id: String
    var title: String
    var directory: String
    var updated: Date
    var url: URL
}

/// Reads the CLI's own transcripts in `~/.claude/projects`, so sessions from the terminal can be loaded too.
enum SaveData {
    static let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")

    /// Nil when the projects folder can't be read, so callers can tell "no sessions" from "unknown".
    static func transcripts() -> [URL]? {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else {
            return nil
        }
        return folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.pathExtension == "jsonl" }
        }
    }

    static func title(ofSession sessionId: String) -> String? {
        transcripts()?.first { $0.lastPathComponent == "\(sessionId).jsonl" }.flatMap { summary(of: $0, opened: [:])?.title }
    }

    static func list() -> [SavedSession] {
        let opened = UserDefaults.standard.dictionary(forKey: openedKey) as? [String: Date] ?? [:]
        return (transcripts() ?? []).compactMap { summary(of: $0, opened: opened) }.sorted { $0.updated > $1.updated }
    }

    /// Opening a session doesn't touch its transcript, so the app keeps its own record to sort by.
    static func markOpened(_ id: String) {
        var opened = UserDefaults.standard.dictionary(forKey: openedKey) as? [String: Date] ?? [:]
        opened[id] = Date()
        UserDefaults.standard.set(opened, forKey: openedKey)
    }

    private static let openedKey = "openedSessions"

    /// A name the user gave wins over the CLI's generated title, which wins over the first prompt.
    private static func summary(of url: URL, opened: [String: Date]) -> SavedSession? {
        var customTitle: String?, aiTitle: String?, firstPrompt: String?, directory: String?
        // Transcripts run to megabytes of tool output, so only lines that can hold a title or the first prompt are parsed.
        let lines = events(in: url) { line in
            line.range(of: titleMarker) != nil || line.range(of: customTitleMarker) != nil
                || ((directory == nil || firstPrompt == nil) && line.range(of: userMarker) != nil)
        }
        for event in lines {
            switch event["type"] as? String {
            case "custom-title": customTitle = event["customTitle"] as? String ?? customTitle
            case "ai-title": aiTitle = event["aiTitle"] as? String ?? aiTitle
            case "user":
                directory = directory ?? event["cwd"] as? String
                if firstPrompt == nil { firstPrompt = prompt(in: event) }
            default: break
            }
        }
        guard let directory, let title = customTitle ?? aiTitle ?? firstPrompt else { return nil }
        let id = url.deletingPathExtension().lastPathComponent
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        return SavedSession(id: id, title: title.trimmed, directory: directory,
                            updated: max(modified, opened[id] ?? .distantPast), url: url)
    }

    static func messages(in url: URL) -> [ChatMessage] {
        chatEntries(in: url).map(\.message)
    }

    /// The transcript event holding the `occurrence`th message with this speaker and text, which is where `--resume-session-at` cuts a fork.
    static func eventId(of message: ChatMessage, occurrence: Int, sessionId: String) -> String? {
        guard let url = transcripts()?.first(where: { $0.lastPathComponent == "\(sessionId).jsonl" }) else { return nil }
        let matches = chatEntries(in: url).filter { $0.message.speaker == message.speaker && $0.message.text == message.text }
        return matches.indices.contains(occurrence - 1) ? matches[occurrence - 1].id : nil
    }

    private static func chatEntries(in url: URL) -> [(id: String, message: ChatMessage)] {
        events(in: url).flatMap { event -> [(id: String, message: ChatMessage)] in
            guard event["isSidechain"] as? Bool != true, let id = event["uuid"] as? String else { return [] }
            let messages: [ChatMessage]
            switch event["type"] as? String {
            case "user":
                messages = prompt(in: event).map { [ChatMessage(speaker: .user, text: $0)] } ?? []
            case "assistant":
                let blocks = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
                messages = blocks.compactMap(Session.message(from:))
            default:
                messages = []
            }
            return messages.map { (id, $0) }
        }
    }

    /// Tool results, skill text, interruptions and `<bash-input>`-style command wrappers are also stored as user turns.
    /// Prompts sent with images or advisor notes are stored as blocks, with the typed text last.
    private static func prompt(in event: [String: Any]) -> String? {
        let content = (event["message"] as? [String: Any])?["content"]
        let blocks = content as? [[String: Any]] ?? []
        guard event["isMeta"] as? Bool != true,
              let text = (content as? String ?? blocks.last { $0["type"] as? String == "text" }?["text"] as? String)?.trimmed,
              !text.isEmpty, !text.hasPrefix("<"), !text.hasPrefix("[Request interrupted") else { return nil }
        return text
    }

    private static let titleMarker = Data(#""type":"ai-title""#.utf8)
    private static let customTitleMarker = Data(#""type":"custom-title""#.utf8)
    private static let userMarker = Data(#""type":"user""#.utf8)

    /// Lazy so `summary` can stop parsing user lines once it has what it needs.
    private static func events(in url: URL, where include: @escaping (Data) -> Bool = { _ in true }) -> some Sequence<[String: Any]> {
        let data = (try? Data(contentsOf: url)) ?? Data()
        return data.split(separator: 0x0A).lazy
            .filter(include)
            .compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}
